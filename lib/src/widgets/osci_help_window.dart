import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;

import '../ai/ai_settings.dart';
import '../ai/help_chat_controller.dart';
import '../core/logger.dart';
import '../help/help_link_history.dart';
import '../help/help_sections.dart';
import '../voice/voice_input_binding.dart';
import '../voice/voice_input_service.dart';
import 'animated_sync_icon.dart';
import 'markdown_table_width.dart';
import 'osci_chat_window.dart';

/// The slug helpers live in `help_sections.dart` because the AI help
/// assistant needs the same link targets; they are re-exported here for the
/// existing imports and tests.
export '../help/help_sections.dart'
    show markdownHeadingSlug, resolveHeadingAnchor;

/// One entry of the table of contents: the title of a main chapter and the
/// anchor slug that scrolls to its heading.
typedef HelpChapter = ({String title, String slug});

/// One rendered slice of the manual.
///
/// The manual is split at heading boundaries so the markdown parser and the
/// widget builder only ever handle a few kilobytes per frame; [data] already
/// contains the search markers when a search is active.
class _ManualChunk {
  const _ManualChunk(this.data, this.firstMatchIndex);

  /// Markdown source of this chunk.
  final String data;

  /// Index into the global match list of the first match in this chunk.
  final int firstMatchIndex;
}

/// Everything the help window derives from the raw manual: the code spans that
/// keep search matches out of code, the main chapters for the table of
/// contents and the heading offsets used to split the rendered page.
typedef _ManualIndex = ({
  List<(int, int)> fencedCodeBlockSpans,
  List<(int, int)> inlineCodeSpans,
  List<HelpChapter> chapters,
  List<int> headingStarts,
});

/// Parses fenced code block spans, inline code spans, the table of contents
/// and the heading offsets from [content] in a background isolate so the UI
/// thread stays responsive during loading.
_ManualIndex _indexManualInIsolate(String content) {
  // Parse fenced code block spans
  final fencedCodeBlockSpans = <(int, int)>[];
  final fenceRe = RegExp(r'^(`{3,}|~{3,})[^`~\n]*$', multiLine: true);
  final fences = fenceRe.allMatches(content).toList();

  for (int i = 0; i < fences.length - 1; i += 2) {
    final start = fences[i].start; // opening fence (beginning of line)
    final end = fences[i + 1].start + fences[i + 1].group(0)!.length + 1;
    fencedCodeBlockSpans.add((start, end));
  }

  // Parse inline code spans
  final inlineCodeSpans = <(int, int)>[];
  final re = RegExp(r'(`+)([^`\n]+?)\1');
  for (final m in re.allMatches(content)) {
    inlineCodeSpans.add((m.start, m.end));
  }

  return (
    fencedCodeBlockSpans: fencedCodeBlockSpans,
    inlineCodeSpans: inlineCodeSpans,
    chapters: extractMainChapters(content),
    headingStarts: _headingOffsets(content),
  );
}

/// Source offsets of every level-2 and level-3 heading in [content].
///
/// The help page splits the manual at these boundaries so the markdown parser
/// and widget builder only handle a few kilobytes per frame. Fenced code
/// blocks are skipped, and indented code never matches because the heading
/// markers must start at the beginning of a line.
List<int> _headingOffsets(String content) {
  final offsets = <int>[];
  var offset = 0;
  var inFence = false;
  for (final line in content.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
    } else if (!inFence &&
        (line.startsWith('## ') || line.startsWith('### '))) {
      offsets.add(offset);
    }
    offset += line.length + 1;
  }
  return offsets;
}

/// A help window that displays the user manual in markdown format
/// with a search bar to find and navigate between matching terms.
///
/// In-document links in the manual — e.g.
/// `[section 4.1](#41-ai-model-configuration)` — scroll to the heading they
/// point at instead of being handed to the browser.
class HelpWindow extends StatefulWidget {
  const HelpWindow({super.key, this.aiSettings, this.voiceInput});

  /// AI provider/token/model settings for the help assistant; null (or an
  /// unconfigured value) disables the ai button in the header.
  final AiSettings? aiSettings;

  /// Shared microphone service; null hides the assistant microphone.
  final VoiceInputService? voiceInput;

  @override
  State<HelpWindow> createState() => _HelpWindowState();
}

class _HelpWindowState extends State<HelpWindow>
    with SingleTickerProviderStateMixin {
  String _manualContent = '';
  bool _isLoading = true;

  /// Target source size of one rendered chunk. Large enough to keep the
  /// number of frames low, small enough that a chunk parses quickly.
  static const int _chunkTargetChars = 8000;

  /// Source offsets of the level-2/3 headings in [_manualContent].
  List<int> _headingStarts = const [];

  /// Chunks of the current display content; see [_ManualChunk].
  List<_ManualChunk> _chunks = const [];

  /// Number of chunks currently mounted in the scroll view.
  int _mountedChunks = 0;

  /// True while [_chunks] are being mounted one frame at a time.
  bool _isRenderingChunks = false;

  /// Guards against two post-frame chains mounting chunks in parallel.
  bool _nextChunkScheduled = false;

  /// Heading scroll request that arrived while chunks were still mounting.
  String? _deferredHeadingFragment;
  bool _deferredHeadingRecordHistory = true;

  /// Owns the AI help conversation. Created with the window, so closing and
  /// reopening the chat panel keeps the transcript; leaving the help page
  /// disposes it and discards the chat.
  late final HelpChatController _helpChatController;

  /// Microphone binding of this assistant; null when voice input is disabled.
  VoiceInputBinding? _voice;

  /// Drives the chat panel's slide-in from the right and its slide-out.
  late final AnimationController _helpChatAnimation;

  /// S-curve slide of the panel across the right half of the window.
  late final Animation<Offset> _helpSlideAnimation;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchTerm = '';
  List<int> _matchOffsets = [];
  int _currentMatchIndex = -1;
  int _pendingScrollMatchIndex = -1;

  /// GlobalKeys attached to each highlighted <mark> element so we can use
  /// [Scrollable.ensureVisible] to reliably scroll matches into view.
  final List<GlobalKey> _matchKeys = [];

  /// GlobalKeys of the invisible heading anchors, keyed by heading slug.
  /// In-document links (`#41-ai-model-configuration`) are scrolled into view
  /// through these.  The map lives in the state so the keys survive the
  /// rebuilds that every search triggers.
  final Map<String, GlobalKey> _headingAnchorKeys = {};

  /// Stable keys for every heading occurrence, keyed by chunk and slug.
  ///
  /// The manual is rendered as several lazily mounted [MarkdownBody] chunks,
  /// each with its own [HeadingAnchorBuilder]. A duplicate heading slug that
  /// ends up in two different chunks must not share a [GlobalKey], so every
  /// occurrence gets its own key; [_headingAnchorKeys] keeps the first
  /// occurrence as the link target.
  final Map<String, GlobalKey> _headingOccurrenceKeys = {};

  /// The manual's main chapters, shown as the table of contents above it.
  final List<HelpChapter> _chapters = [];

  /// Targets visited through in-document links and table-of-contents entries.
  final HelpLinkHistory _linkHistory = HelpLinkHistory();

  /// Custom inline syntax that parses `@@term@@` into a `<mark>` AST element.
  /// This is used for search-highlighting instead of HTML tags (which the
  /// markdown parser treats as raw text).
  static final md.InlineSyntax _highlightSyntax = _HighlightSyntax();

  /// Byte-offset spans [start, end) of fenced code blocks in the raw
  /// markdown source.  Computed once when the manual loads so that matches
  /// inside code blocks can be excluded — the markdown parser treats code
  /// block content as literal text, so our highlight markers (\x02/\x03)
  /// would never be processed there, causing a mismatch between
  /// _matchOffsets and rendered <mark> elements.
  final List<(int, int)> _fencedCodeBlockSpans = [];

  /// Byte-offset spans [start, end) of inline code spans (`` `...` ``) in
  /// the raw markdown source.  Like fenced code blocks, the markdown parser
  /// treats inline code content as literal text and never applies our
  /// highlight syntax there, so matches inside inline code must also be
  /// excluded to keep _matchOffsets and <mark> elements aligned.
  final List<(int, int)> _inlineCodeSpans = [];

  @override
  void initState() {
    super.initState();
    // Deliberately slow, S-curve motion: the panel slides in from the right
    // edge and glides back out the same way.
    _helpChatAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
      reverseDuration: const Duration(milliseconds: 1600),
    );
    _helpSlideAnimation =
        Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _helpChatAnimation,
            curve: Curves.easeInOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          ),
        );
    _helpChatController = HelpChatController();
    _initVoiceInput();
    _helpChatController.addListener(_syncHelpChatPanel);
    // The agent itself is created once the manual has loaded; with valid
    // settings the panel can already be opened until then.
    _helpChatController.configure(widget.aiSettings, manual: '');
    // Defer loading until after the first frame is rendered so the
    // loading indicator is visible and its animation has started ticking
    // before the async I/O and isolate work begin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadManual();
    });
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
  }

  @override
  void didUpdateWidget(covariant HelpWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiSettings != widget.aiSettings) {
      _helpChatController.configure(
        widget.aiSettings,
        manual: _isLoading ? '' : _manualContent,
      );
    }
    if (oldWidget.voiceInput != widget.voiceInput) {
      unawaited(_voice?.detach());
      _initVoiceInput();
    }
  }

  /// Creates the microphone binding for the shared voice input service.
  void _initVoiceInput() {
    final service = widget.voiceInput;
    _voice = service == null
        ? null
        : VoiceInputBinding(
            ownerId: 'help_ai',
            service: service,
            onTranscript: _helpChatController.send,
          );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    unawaited(_voice?.detach());
    _voice = null;
    _helpChatController.removeListener(_syncHelpChatPanel);
    _helpChatController.dispose();
    _helpChatAnimation.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadManual() async {
    final log = AppLogger(agentName: 'HelpWindow', toolName: '_loadManual');
    // Ensure the loading indicator stays visible for at least 400ms
    // so the user always sees visual feedback when opening Help.
    final minLoadTime = Future.delayed(const Duration(milliseconds: 400));
    final sw = Stopwatch()..start();
    try {
      _manualContent = wrapMarkdownLines(
        await rootBundle.loadString('assets/manuals/sds_manual.md'),
        maxLineLength: kMarkdownMaxLineLength,
      );
      log.log(
        'Manual asset loaded: ${_manualContent.length} chars in '
        '${sw.elapsedMilliseconds} ms',
      );
      // Derive code spans and chapters in a background isolate so the
      // loading indicator animation keeps spinning while loading.
      // compute() passes the top-level function and argument directly to
      // Isolate.spawn — no closure, no captured `this`.
      final index = await compute(_indexManualInIsolate, _manualContent);
      _fencedCodeBlockSpans.clear();
      _fencedCodeBlockSpans.addAll(index.fencedCodeBlockSpans);
      _inlineCodeSpans.clear();
      _inlineCodeSpans.addAll(index.inlineCodeSpans);
      _chapters.clear();
      _chapters.addAll(index.chapters);
      _headingStarts = index.headingStarts;
      // Anchors of a previously loaded manual are stale: the new content may
      // have a different set of headings.
      _headingAnchorKeys.clear();
      _linkHistory.clear();
      // The help assistant answers from the manual, so its agent is created
      // once the text is available.
      _helpChatController.configure(widget.aiSettings, manual: _manualContent);
      log.log(
        'Manual indexed: ${index.fencedCodeBlockSpans.length} fenced code '
        'blocks, ${index.inlineCodeSpans.length} inline code spans, '
        '${index.chapters.length} chapters in ${sw.elapsedMilliseconds} ms',
      );
      await minLoadTime;
    } catch (e) {
      log.error('Manual load FAILED after ${sw.elapsedMilliseconds} ms: $e');
      _manualContent = 'Error loading manual: $e';
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _rebuildChunks();
      });
      _scheduleNextChunk();
    }
    log.log('Loading flag cleared after ${sw.elapsedMilliseconds} ms');
  }

  /// Returns `true` if [offset] falls inside any fenced code block span
  /// or inline code span.
  bool _isInsideCodeBlock(int offset) {
    for (final (start, end) in _fencedCodeBlockSpans) {
      if (offset >= start && offset < end) return true;
    }
    for (final (start, end) in _inlineCodeSpans) {
      if (offset >= start && offset < end) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Search logic — only triggered by pressing Enter in the search bar
  // ---------------------------------------------------------------------------

  void _onSearchSubmitted() {
    _performSearch(_searchController.text);
  }

  void _performSearch(String term) {
    setState(() {
      _searchTerm = term;
      if (term.isEmpty) {
        _matchOffsets = [];
        _matchKeys.clear();
        _currentMatchIndex = -1;
        _pendingScrollMatchIndex = -1;
      } else {
        try {
          final regex = _searchPattern(term);
          _matchOffsets = [];
          int searchStart = 0;
          while (searchStart < _manualContent.length) {
            final match = regex.firstMatch(
              _manualContent.substring(searchStart),
            );
            if (match == null) break;
            final offset = searchStart + match.start;
            // Exclude matches inside fenced code blocks or inline code
            // spans — the markdown parser treats code content as literal
            // text and never applies our inline highlight syntax there.
            if (!_isInsideCodeBlock(offset)) {
              _matchOffsets.add(offset);
            }
            searchStart += match.end;
          }
          // Regenerate keys so each match has a stable [GlobalKey] for
          // [Scrollable.ensureVisible] scrolling.
          _matchKeys.clear();
          for (var i = 0; i < _matchOffsets.length; i++) {
            _matchKeys.add(GlobalKey());
          }
          _currentMatchIndex = _matchOffsets.isNotEmpty ? 0 : -1;
          _pendingScrollMatchIndex = _matchOffsets.isNotEmpty ? 0 : -1;
        } catch (_) {
          _matchOffsets = [];
          _matchKeys.clear();
          _currentMatchIndex = -1;
          _pendingScrollMatchIndex = -1;
        }
      }
      // Re-chunk the highlighted content. The chunks mount progressively so
      // a search stays responsive instead of re-laying out the whole manual
      // in a single frame.
      _rebuildChunks();
    });
    _scheduleNextChunk();
  }

  /// Builds the markdown shown in the help page for the current search and
  /// maps [sourceOffsets] — positions in [_manualContent] — into that string.
  ///
  /// Matches are wrapped in ASCII STX / ETX control bytes that
  /// [_highlightSyntax] turns into `<mark>` elements. These characters never
  /// appear in the manual and cannot collide with any markdown syntax.
  ({String content, List<int> renderedOffsets}) _buildDisplayContent(
    List<int> sourceOffsets,
  ) {
    if (_searchTerm.isEmpty) {
      return (
        content: _manualContent,
        renderedOffsets: List<int>.of(sourceOffsets),
      );
    }

    final buffer = StringBuffer();
    final renderedOffsets = List<int>.filled(sourceOffsets.length, 0);
    final regex = _searchPattern(_searchTerm);
    var boundary = 0;
    var lastEnd = 0;

    for (final match in regex.allMatches(_manualContent)) {
      // Map boundaries that lie before this match. `buffer.length - lastEnd`
      // is the number of marker characters inserted so far; the source text
      // up to this match has not been written yet, so only that shift counts.
      while (boundary < sourceOffsets.length &&
          sourceOffsets[boundary] <= match.start) {
        renderedOffsets[boundary] =
            sourceOffsets[boundary] + (buffer.length - lastEnd);
        boundary++;
      }
      buffer.write(_manualContent.substring(lastEnd, match.start));
      if (_isInsideCodeBlock(match.start)) {
        // Inside a fenced code block or inline code span: write the
        // matched text as-is (the markdown parser treats code content
        // as literal text and would never apply _highlightSyntax here).
        buffer.write(match.group(0)!);
      } else {
        buffer.write('\x02${match.group(0)}\x03');
      }
      lastEnd = match.end;
    }
    while (boundary < sourceOffsets.length) {
      renderedOffsets[boundary] =
          sourceOffsets[boundary] + (buffer.length - lastEnd);
      boundary++;
    }
    buffer.write(_manualContent.substring(lastEnd));
    return (content: buffer.toString(), renderedOffsets: renderedOffsets);
  }

  /// Splits the current display content into chunks and resets the
  /// progressive mount state.
  ///
  /// Chunks end at heading boundaries and grow to roughly
  /// [_chunkTargetChars] characters. Mounting them over several frames keeps
  /// the loading indicator animating instead of blocking the UI thread on
  /// one full-document parse and layout pass.
  void _rebuildChunks() {
    if (_manualContent.isEmpty) {
      _chunks = const [];
      _mountedChunks = 0;
      _isRenderingChunks = false;
      return;
    }

    final boundaries = <int>[
      0,
      for (final start in _headingStarts)
        if (start > 0 && start < _manualContent.length) start,
      _manualContent.length,
    ];
    final display = _buildDisplayContent(boundaries);

    final chunks = <_ManualChunk>[];
    var sourceStart = 0;
    var renderedStart = 0;
    var matchCursor = 0;
    for (var i = 1; i < boundaries.length; i++) {
      final sourceEnd = boundaries[i];
      final isLast = i == boundaries.length - 1;
      if (!isLast && sourceEnd - sourceStart < _chunkTargetChars) continue;

      final renderedEnd = display.renderedOffsets[i];
      if (renderedEnd <= renderedStart) continue;
      var cursor = matchCursor;
      while (cursor < _matchOffsets.length &&
          _matchOffsets[cursor] < sourceStart) {
        cursor++;
      }
      chunks.add(
        _ManualChunk(
          display.content.substring(renderedStart, renderedEnd),
          cursor,
        ),
      );
      matchCursor = cursor;
      sourceStart = sourceEnd;
      renderedStart = renderedEnd;
    }

    _chunks = chunks;
    _mountedChunks = chunks.isEmpty ? 0 : 1;
    _isRenderingChunks = _mountedChunks < chunks.length;
    if (!_isRenderingChunks) {
      _scrollToDeferredHeading();
    }
  }

  /// Mounts the next chunk after the current frame.
  ///
  /// One chunk per frame keeps every layout pass short, so the loading
  /// indicator and the rest of the page stay responsive while the manual
  /// fills in.
  void _scheduleNextChunk() {
    if (!_isRenderingChunks || _nextChunkScheduled) return;
    _nextChunkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nextChunkScheduled = false;
      if (!mounted || !_isRenderingChunks) return;
      setState(() {
        _mountedChunks++;
        if (_mountedChunks >= _chunks.length) {
          _mountedChunks = _chunks.length;
          _isRenderingChunks = false;
        }
      });
      if (_isRenderingChunks) {
        _scheduleNextChunk();
      } else {
        _scrollToDeferredHeading();
      }
    });
  }

  /// Retries a heading scroll that was requested while chunks were mounting.
  void _scrollToDeferredHeading() {
    final fragment = _deferredHeadingFragment;
    if (fragment == null) return;
    _deferredHeadingFragment = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToHeading(fragment, recordHistory: _deferredHeadingRecordHistory);
    });
  }

  /// Schedules the scroll for the match at [index].
  /// The actual scroll is performed in a post-frame callback triggered from
  /// [build], ensuring the newly rebuilt MarkdownBody is laid out.
  void _scheduleScrollToMatch(int index) {
    if (index < 0 || index >= _matchOffsets.length) return;
    _pendingScrollMatchIndex = index;
    if (mounted) setState(() {});
  }

  void _performScrollToMatch(int index) {
    if (index < 0 || index >= _matchOffsets.length) return;

    // Try the exact match first.
    if (index < _matchKeys.length) {
      final ctx = _matchKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    }

    // Fallback: the target key has no attached context (e.g. the match
    // lives inside a markdown construct that prevented rendering a <mark>).
    // Search forward, then backward, for the nearest match that *does* have
    // a valid context so the user still sees something scroll into view.
    for (int i = index + 1; i < _matchKeys.length; i++) {
      final ctx = _matchKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    }
    for (int i = index - 1; i >= 0; i--) {
      final ctx = _matchKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    }
  }

  /// Global hardware keyboard handler registered via
  /// [HardwareKeyboard.instance.addHandler].  This receives key events
  /// *before* they enter the focus system, so F3 / Shift+F3 work reliably
  /// regardless of which child widget (TextField, SelectableText in the
  /// MarkdownBody, or code blocks) currently holds focus.
  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f3) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _goToPrevMatch();
      } else {
        _goToNextMatch();
      }
      return true; // event handled — do not propagate further
    }
    return false; // not handled — let the focus system process it
  }

  void _goToNextMatch() {
    if (_matchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchOffsets.length;
    });
    _scheduleScrollToMatch(_currentMatchIndex);
  }

  void _goToPrevMatch() {
    if (_matchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _matchOffsets.length) %
          _matchOffsets.length;
    });
    _scheduleScrollToMatch(_currentMatchIndex);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _performSearch('');
  }

  // ---------------------------------------------------------------------------
  // Link handling
  // ---------------------------------------------------------------------------

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Dispatches a tap on a link inside the manual.
  ///
  /// The manual cross-references its own sections with fragments such as
  /// `[section 4.1](#41-ai-model-configuration)`; those scroll to the heading
  /// they point at.  Everything else is a real URL and goes to the browser.
  void _handleLinkTap(String? href) {
    if (href == null || href.isEmpty) return;
    if (href.startsWith('#')) {
      _scrollToHeading(href.substring(1));
    } else {
      _launchUrl(href);
    }
  }

  /// Scrolls the manual to the heading that the link fragment [fragment]
  /// points at, e.g. `41-ai-model-configuration` for
  /// "4.1 AI Model Configuration".
  void _scrollToHeading(String fragment, {bool recordHistory = true}) {
    final log = AppLogger(
      agentName: 'HelpWindow',
      toolName: '_scrollToHeading',
    );
    // While chunks are still mounting, the target heading is neither in the
    // tree nor registered yet. Retry once rendering has finished.
    if (_isRenderingChunks) {
      _deferredHeadingFragment = fragment;
      _deferredHeadingRecordHistory = recordHistory;
      return;
    }
    final slug = resolveHeadingAnchor(fragment, _headingAnchorKeys.keys);
    if (slug == null) {
      log.log('No heading found for link target "#$fragment"');
      return;
    }
    final ctx = _headingAnchorKeys[slug]?.currentContext;
    if (ctx == null) {
      log.log('No heading found for link target "#$fragment"');
      return;
    }
    if (recordHistory && _linkHistory.visit(slug)) {
      setState(() {});
    }
    log.log('Scrolling to heading "#$slug"');
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.05,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBackInLinkHistory() {
    final target = _linkHistory.back();
    if (target == null) return;
    setState(() {});
    _scrollToHeading(target, recordHistory: false);
  }

  void _goForwardInLinkHistory() {
    final target = _linkHistory.forward();
    if (target == null) return;
    setState(() {});
    _scrollToHeading(target, recordHistory: false);
  }

  /// Scrolls the manual back to the top, past the table of contents.
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// Starts the slide-in or slide-out animation for the chat panel.
  void _syncHelpChatPanel() {
    if (_helpChatController.isOpen && _helpChatController.isAvailable) {
      _helpChatAnimation.forward();
    } else {
      unawaited(_voice?.detach());
      _helpChatAnimation.reverse();
    }
  }

  /// Handles a link clicked in an answer of the help assistant.
  ///
  /// Section links (`#heading-slug`) slide the chat out and scroll the manual
  /// to the heading; everything else is a real URL and goes to the browser.
  void _handleHelpChatLink(String href) {
    if (href.startsWith('#')) {
      _helpChatController.close();
      // The panel overlays the manual, so the scroll position is stable while
      // it slides out.
      _scrollToHeading(href.substring(1));
    } else {
      _launchUrl(href);
    }
  }

  /// AI button next to the title that opens and closes the AI help
  /// assistant. It is only active while valid AI settings are configured.
  ///
  /// The colors match the Macro Editor's assistant button: a cyan border and
  /// a white icon while the assistant is closed, a cyan icon while it is open.
  Widget _buildHelpAssistantButton() {
    final enabled = widget.aiSettings?.isConfigured == true;
    final borderColor = enabled ? Colors.cyanAccent : Colors.white24;
    // The frame makes the icon read as a button rather than a decoration.
    return ListenableBuilder(
      listenable: _helpChatController,
      builder: (context, _) {
        final open = enabled && _helpChatController.isOpen;
        return Container(
          key: const ValueKey('help-ai-button-frame'),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            icon: Icon(
              Icons.auto_awesome,
              size: 20,
              color: enabled
                  ? (open ? Colors.cyanAccent : Colors.white70)
                  : Colors.white24,
            ),
            tooltip: enabled
                ? (open ? 'Close AI Help Assistant' : 'AI Help Assistant')
                : 'AI Help Assistant (configure the AI settings first)',
            onPressed: enabled ? _helpChatController.toggleOpen : null,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
          ),
        );
      },
    );
  }

  /// Chat panel that fills the right half of the help window.
  Widget _buildHelpChatPanel() {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.cyanAccent,
                ),
                const Spacer(),
                ListenableBuilder(
                  listenable: _helpChatController,
                  builder: (context, _) => IconButton(
                    tooltip: 'Clear session',
                    onPressed:
                        _helpChatController.messages.isEmpty ||
                            _helpChatController.isChatting
                        ? null
                        : _helpChatController.clearSession,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    color: Colors.white70,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 18,
                  ),
                  tooltip: 'Close AI Help Assistant',
                  onPressed: _helpChatController.close,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: ListenableBuilder(
                listenable: _helpChatController,
                builder: (context, _) => ChatWindow(
                  chatMessages: _helpChatController.messages,
                  isChatting: _helpChatController.isChatting,
                  isInitialized: _helpChatController.isInitialized,
                  onSendMessage: _helpChatController.send,
                  onCancel: _helpChatController.cancel,
                  voiceInput: _voice,
                  inputHistory: _helpChatController.inputHistory,
                  onHistorySelected: _helpChatController.send,
                  onLinkTap: _handleHelpChatLink,
                  hintText: 'Ask about SDS-Remote...',
                  emptyStateText:
                      'Ask me anything about SDS-Remote. I answer from the '
                      'manual and link the matching sections.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating button in the bottom-right corner that jumps back to the top
  /// of the manual.
  ///
  /// It fades in once the reader has scrolled a little way down, so it is
  /// always at hand while reading but never covers the start of the text.
  Widget _buildBackToTopButton() {
    return ListenableBuilder(
      listenable: _scrollController,
      builder: (context, _) {
        final visible =
            _scrollController.hasClients && _scrollController.offset > 200;
        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !visible,
            // A hidden button must not be announced by screen readers.
            child: ExcludeSemantics(
              excluding: !visible,
              child: Tooltip(
                message: 'Back to top',
                child: Material(
                  color: const Color(0xFF0A192F),
                  elevation: 6,
                  shadowColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: Colors.cyanAccent.withValues(alpha: 0.6),
                    ),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _scrollToTop,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.vertical_align_top,
                        size: 22,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Trigger the pending scroll via post-frame callback so the newly rebuilt
    // MarkdownBody is laid out and the ScrollController has clients. While
    // chunks are still mounting, the target may not be built yet, so the
    // request stays pending until the last chunk is mounted.
    if (_pendingScrollMatchIndex >= 0 && !_isRenderingChunks) {
      final idx = _pendingScrollMatchIndex;
      _pendingScrollMatchIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performScrollToMatch(idx);
      });
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        _HelpClearSearchIntent: CallbackAction<_HelpClearSearchIntent>(
          onInvoke: (_) => _clearSearch(),
        ),
        _HelpFocusSearchIntent: CallbackAction<_HelpFocusSearchIntent>(
          onInvoke: (_) {
            _searchFocusNode.requestFocus();
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.escape):
              _HelpClearSearchIntent(),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _HelpFocusSearchIntent(),
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _HelpFocusSearchIntent(),
        },
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              // Arrow keys → when search field is focused, navigate matches
              if (_searchFocusNode.hasFocus) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _goToNextMatch();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _goToPrevMatch();
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Headline, AI assistant button and search bar row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SDS-Remote Help',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_isRenderingChunks) ...[
                              const SizedBox(width: 10),
                              // Keeps the busy feedback visible and
                              // animating while the manual's chunks fill in.
                              const AnimatedSyncIcon(
                                size: 16,
                                color: Colors.cyanAccent,
                              ),
                            ],
                          ],
                        ),
                        _buildSearchBar(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Black blurred line with 3D depth effect
                    Container(
                      height: 2,
                      decoration: BoxDecoration(
                        border: const Border(
                          top: BorderSide(color: Colors.black, width: 1),
                          bottom: BorderSide(color: Colors.white10, width: 1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.95),
                            blurRadius: 6,
                            spreadRadius: 2,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    // Markdown content — using MarkdownBody (non-scrolling) inside a
                    // SingleChildScrollView so WE control the ScrollController.
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedSyncIcon(
                                    size: 36,
                                    color: Colors.cyanAccent,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Loading...',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Table of contents first, so a chapter can be
                                    // picked right away; it scrolls away with the
                                    // manual like any other content.
                                    if (_chapters.isNotEmpty) ...[
                                      _buildContents(),
                                      const SizedBox(height: 24),
                                    ],
                                    for (
                                      var index = 0;
                                      index < _mountedChunks &&
                                          index < _chunks.length;
                                      index++
                                    )
                                      _buildManualChunk(index),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              // Floating jump-to-top control, above the manual but below the
              // chat panel, which slides over it.
              Positioned(right: 24, bottom: 24, child: _buildBackToTopButton()),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1,
                    child: AnimatedBuilder(
                      animation: _helpChatAnimation,
                      builder: (context, child) {
                        // A fully collapsed panel is removed from the tree so
                        // the chat field cannot take focus while it is hidden.
                        if (_helpChatAnimation.value == 0) {
                          return const SizedBox.shrink();
                        }
                        return ClipRect(
                          child: SlideTransition(
                            position: _helpSlideAnimation,
                            child: child,
                          ),
                        );
                      },
                      child: _buildHelpChatPanel(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds one chunk of the manual.
  Widget _buildManualChunk(int index) {
    final chunk = _chunks[index];
    return MarkdownBody(
      key: ValueKey('help-chunk-$index'),
      data: chunk.data,
      // Keep the source line breaks: the manual is preprocessed to at most
      // 200 characters per line, and Markdown must not join those lines into
      // one long paragraph again.
      softLineBreak: true,
      // Selection is OFF for the manual as a whole. `selectable: true` wraps
      // every text node in its own SelectableText plus selection bookkeeping,
      // which measured 4767 ms to lay out versus 577 ms without — an 8x cost
      // that blocked the UI thread for seconds. Code blocks stay selectable
      // and copyable on their own (see CodeBlockElementBuilder).
      selectable: false,
      onTapLink: (text, href, title) {
        _handleLinkTap(href);
      },
      // Custom block syntaxes are consulted before the GitHub-flavored
      // extension set, so the stock heading syntax is shadowed by this one —
      // which only adds the invisible anchors and renders headings exactly
      // as before.
      blockSyntaxes: const [AnchorHeadingSyntax()],
      inlineSyntaxes: [_highlightSyntax],
      builders: {
        'code': InlineCodeElementBuilder(),
        'pre': CodeBlockElementBuilder(),
        // Each chunk starts at its own offset in the global match list;
        // otherwise every chunk would claim the first highlight keys.
        'mark': MarkHighlightBuilder(_matchKeys, start: chunk.firstMatchIndex),
        _kAnchorTag: HeadingAnchorBuilder(
          _headingAnchorKeys,
          _headingOccurrenceKeys,
          index,
        ),
      },
      styleSheet: _buildMarkdownStyleSheet(context),
    );
  }

  /// Style sheet shared by all manual chunks.
  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      p: const TextStyle(color: Colors.white, fontSize: 16),
      h1: const TextStyle(
        color: Colors.cyanAccent,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
      h2: const TextStyle(
        color: Colors.cyanAccent,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      h3: const TextStyle(
        color: Colors.greenAccent,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      h4:
          base.h4?.copyWith(color: Colors.yellow) ??
          const TextStyle(
            color: Colors.yellow,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
      code: TextStyle(
        backgroundColor: Colors.black54,
        color: Colors.greenAccent[100],
        fontFamily: 'Roboto Mono',
        fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
      ),
      codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      blockquote: const TextStyle(
        color: Colors.white70,
        fontSize: 15,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: Colors.cyanAccent.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white38, width: 1.3),
          bottom: BorderSide(color: Colors.black38, width: 1.3),
        ),
      ),
      tablePadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      // Content-sized columns keep short tables narrow. The table still
      // receives the available width, so wide tables shrink their columns
      // down to the longest word and wrap the remaining text.
      tableColumnWidth: const ContentColumnWidth(),
    );
  }

  // ---------------------------------------------------------------------------
  // Table of contents
  // ---------------------------------------------------------------------------

  /// Builds the table of contents shown above the manual: one entry per main
  /// chapter, laid out in as many columns as the window has room for.
  Widget _buildContents() {
    return Container(
      key: const ValueKey('help-contents'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contents',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              // Spread the chapters over up to three columns. Fill each column
              // from top to bottom before moving to the next one, so chapter 2
              // appears directly under chapter 1 instead of beside it.
              const spacing = 24.0;
              final maxColumns = (constraints.maxWidth / 300)
                  .floor()
                  .clamp(1, 3)
                  .toInt();
              final columns = chaptersByColumn(_chapters, maxColumns);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns.length; column++) ...[
                    if (column > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final chapter in columns[column])
                            _buildContentsEntry(chapter),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Builds a single tappable entry of the table of contents.
  Widget _buildContentsEntry(HelpChapter chapter) {
    return InkWell(
      // An InkWell shows the plain arrow on desktop by default, whereas the
      // manual's links — text spans carrying a tap recognizer — show the
      // pointing hand.  An entry has to look like the links it stands for.
      mouseCursor: SystemMouseCursors.click,
      onTap: () => _scrollToHeading(chapter.slug),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          chapter.title,
          style: const TextStyle(color: Colors.cyanAccent, fontSize: 14),
        ),
      ),
    );
  }

  /// Build the search bar row with text field, match counter, and navigation
  /// arrows.
  Widget _buildSearchBar() {
    final hasMatches = _matchOffsets.isNotEmpty;
    final hasSearch = _searchTerm.isNotEmpty;

    String matchLabel;
    if (!hasSearch) {
      matchLabel = '';
    } else if (!hasMatches) {
      matchLabel = 'No matches';
    } else {
      matchLabel =
          '${_currentMatchIndex + 1} of ${_matchOffsets.length} matches';
    }

    // Show the clear button whenever the TextField has content,
    // regardless of whether search has been submitted — this prevents
    // a layout shift when pressing Enter.
    final hasText = _searchController.text.isNotEmpty;

    return SizedBox(
      height: 60,
      // IntrinsicWidth constrains the Column to the width of its widest
      // child (the Row), so the match label sits directly beneath the
      // search box rather than stretching to the screen edge.
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Opens the AI help assistant; sits directly left of the
                // magnifier so both controls form one group.
                _buildHelpAssistantButton(),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: Icons.undo,
                  tooltip: 'Back to previous link',
                  onPressed: _linkHistory.canGoBack
                      ? _goBackInLinkHistory
                      : null,
                ),
                const SizedBox(width: 2),
                _SmallIconButton(
                  icon: Icons.redo,
                  tooltip: 'Forward to next link',
                  onPressed: _linkHistory.canGoForward
                      ? _goForwardInLinkHistory
                      : null,
                ),
                const SizedBox(width: 8),
                const Icon(Icons.search, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search manual…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      isDense: true,
                      // Always render the clear button so the TextField's
                      // internal layout never changes — use opacity to hide
                      // it when there is no text.
                      suffixIcon: Opacity(
                        opacity: hasText ? 1.0 : 0.0,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.white54,
                          onPressed: _clearSearch,
                        ),
                      ),
                    ),
                    // Search is only triggered on Enter/Return
                    onSubmitted: (_) => _onSearchSubmitted(),
                  ),
                ),
                const SizedBox(width: 4),
                _SmallIconButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Previous match (Shift+F3)',
                  onPressed: hasMatches ? _goToPrevMatch : null,
                ),
                const SizedBox(width: 2),
                _SmallIconButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Next match (F3)',
                  onPressed: hasMatches ? _goToNextMatch : null,
                ),
              ],
            ),
            // Fixed-height container for match label — aligned to the
            // right edge of the search box (same width as Row above).
            SizedBox(
              height: 20,
              child: matchLabel.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          matchLabel,
                          style: TextStyle(
                            color: hasMatches
                                ? Colors.cyanAccent
                                : Colors.white38,
                            fontSize: 12,
                            fontWeight: hasMatches
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Intents for keyboard shortcuts handled via [Actions] / [Shortcuts]
// -----------------------------------------------------------------------------

class _HelpClearSearchIntent extends Intent {
  const _HelpClearSearchIntent();
}

class _HelpFocusSearchIntent extends Intent {
  const _HelpFocusSearchIntent();
}

// -----------------------------------------------------------------------------
// Custom InlineSyntax for `@@term@@` → `<mark>` element
// -----------------------------------------------------------------------------

/// Parses text delimited by ASCII STX / ETX (\x02 … \x03) into a
/// `md.Element` with tag `mark`.  These control characters cannot
/// collide with manual content or markdown syntax.
/// Search pattern for [term] that treats every whitespace run as a wildcard.
///
/// The manual is preprocessed with hard line breaks, so a phrase can span a
/// line break. Matching the words with `\s+` keeps the search working there.
RegExp _searchPattern(String term) {
  final words = term.trim().split(RegExp(r'\s+'));
  if (words.length <= 1) {
    return RegExp(RegExp.escape(term), caseSensitive: false);
  }
  return RegExp(words.map(RegExp.escape).join(r'\s+'), caseSensitive: false);
}

class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax() : super('\x02([^\x02\x03]+)\x03');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mark', match[1]!));
    return true;
  }
}

// -----------------------------------------------------------------------------
// Small icon button helper
// -----------------------------------------------------------------------------

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 20,
              color: onPressed != null ? Colors.white70 : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Custom builder for <mark> search-highlight tags
// -----------------------------------------------------------------------------

/// Renders inline `<mark>` text with a gold background and black text so
/// search matches are clearly visible against the dark theme.
///
/// Each rendered element is wrapped in a [SizedBox] with a [GlobalKey] from
/// the caller-supplied list so that [Scrollable.ensureVisible] can reliably
/// scroll any match into view.
///
/// Returning a [Text] widget with [TextStyle.backgroundColor] allows the
/// parent builder to extract its [TextSpan] and merge it directly into the
/// main [TextSpan] tree. This avoids wrapping the highlighted text in a
/// [WidgetSpan] (which a [Container] would require), preserving perfect
/// baseline alignment with the surrounding text and preventing layout breakage.
class MarkHighlightBuilder extends MarkdownElementBuilder {
  MarkHighlightBuilder(this.keys, {int start = 0}) : _cursor = start;

  /// [GlobalKey]s, one per match, assigned in document order.
  final List<GlobalKey> keys;

  /// Index of the first key this builder may claim.
  int _cursor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final key = _cursor < keys.length ? keys[_cursor++] : null;
    final text = Text.rich(
      TextSpan(
        text: element.textContent,
        style: (parentStyle ?? const TextStyle()).copyWith(
          backgroundColor: const Color(0xFFFFD700),
          color: Colors.black,
        ),
      ),
    );
    if (key == null) return text;
    return SizedBox(key: key, child: text);
  }
}

// -----------------------------------------------------------------------------
// Existing custom builders (unchanged)
// -----------------------------------------------------------------------------

/// Builder for inline code (single backticks: `code`).
class InlineCodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      TextSpan(
        text: element.textContent,
        style: (preferredStyle ?? parentStyle ?? const TextStyle()).copyWith(
          backgroundColor: Colors.black54,
          color: Colors.greenAccent[100],
          fontFamily: 'Roboto Mono',
          fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
        ),
      ),
    );
  }
}

/// Builder for fenced code blocks (```bash ... ```).
class CodeBlockElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Strip the trailing newline that the markdown parser includes in the
    // text content of fenced code blocks, otherwise an extra blank line is
    // rendered at the bottom of the code block.
    final text = element.textContent.replaceAll(RegExp(r'\n$'), '');
    return Builder(
      builder: (context) {
        // The block hugs its longest line (plus the copy button) instead of
        // spanning the whole manual width; longer lines still wrap at the
        // available width.
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              // Centre the copy button on the text; with `start` its 8 px
              // padding pushed the icon visibly below the first code line.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      color: Colors.greenAccent[100],
                      fontFamily: 'Roboto Mono',
                      fontFamilyFallback: const [
                        'Consolas',
                        'Courier New',
                        'monospace',
                      ],
                      fontSize: 14,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.copy, size: 16, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Heading anchors — the targets of in-document links
// -----------------------------------------------------------------------------

/// Tag of the invisible element that [AnchorHeadingSyntax] adds to every
/// heading.  It is not an HTML tag — it only exists so that
/// [HeadingAnchorBuilder] has a node to attach a [GlobalKey] to.
const String _kAnchorTag = 'anchor';

/// Attribute of an [_kAnchorTag] element holding its heading slug.
const String _kAnchorSlugAttribute = 'data-slug';

/// Parses ATX headings (`### 4.1 AI Model Configuration`) exactly like the
/// stock markdown heading syntax and additionally injects an invisible
/// [_kAnchorTag] element as the first child of every heading.
///
/// The heading itself is left untouched — level, padding, styles and any
/// inline markup inside it are still rendered by flutter_markdown_plus; the
/// anchor is one extra zero-sized child marking where the heading starts.
class AnchorHeadingSyntax extends md.HeaderSyntax {
  const AnchorHeadingSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final element = super.parse(parser) as md.Element;
    final children = element.children;
    final slug = markdownHeadingSlug(element.textContent);
    if (children != null && slug.isNotEmpty) {
      children.insert(
        0,
        md.Element.empty(_kAnchorTag)..attributes[_kAnchorSlugAttribute] = slug,
      );
    }
    return element;
  }
}

/// Extracts the main chapters of [content] — every `## …` heading, with the
/// anchor slug of its heading — in document order.
///
/// Runs the very same heading syntax as the rendering pipeline, and reads the
/// slug off the anchor that syntax created, so a table-of-contents entry always
/// points at the heading it was built from.
List<HelpChapter> extractMainChapters(String content) {
  final nodes = md.Document(
    blockSyntaxes: const [AnchorHeadingSyntax()],
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(content);

  final chapters = <HelpChapter>[];
  for (final node in nodes) {
    if (node is! md.Element || node.tag != 'h2') continue;
    final children = node.children;
    if (children == null || children.isEmpty) continue;
    // AnchorHeadingSyntax put the anchor in front of the heading text.
    final anchor = children.first;
    final slug = anchor is md.Element
        ? anchor.attributes[_kAnchorSlugAttribute]
        : null;
    final title = node.textContent.trim();
    if (slug != null && title.isNotEmpty) {
      chapters.add((title: title, slug: slug));
    }
  }
  return chapters;
}

/// Distributes [chapters] over at most [columns] columns in reading order.
///
/// Each column is filled from top to bottom before the next one starts, so
/// chapter 2 lands directly under chapter 1. The column count is capped at the
/// number of chapters, which keeps a short list from leaving empty columns.
List<List<HelpChapter>> chaptersByColumn(
  List<HelpChapter> chapters,
  int columns,
) {
  if (chapters.isEmpty) return <List<HelpChapter>>[];
  final count = columns.clamp(1, chapters.length).toInt();
  final rows = (chapters.length + count - 1) ~/ count;
  return <List<HelpChapter>>[
    for (var column = 0; column < count; column++)
      <HelpChapter>[
        for (var row = 0; row < rows; row++)
          if (column * rows + row < chapters.length)
            chapters[column * rows + row],
      ],
  ];
}

/// Renders the anchors injected by [AnchorHeadingSyntax] as zero-sized widgets
/// carrying a [GlobalKey], which gives [Scrollable.ensureVisible] the scroll
/// target for an in-document link.
///
/// The keys are owned by the help window state and only handed out here: they
/// have to survive the rebuilds that every search triggers, and no two live
/// widgets may ever share one.
class HeadingAnchorBuilder extends MarkdownElementBuilder {
  HeadingAnchorBuilder(this.keys, this.occurrenceKeys, this.chunkIndex);

  /// Slug → [GlobalKey] of the first heading occurrence (link target).
  final Map<String, GlobalKey> keys;

  /// `chunkIndex|slug|occurrence` → stable key of that heading occurrence.
  ///
  /// Every occurrence gets its own key, so a duplicate heading slug that spans
  /// two chunks cannot assign the same [GlobalKey] twice. The first occurrence
  /// also registers in [keys] as the link target.
  final Map<String, GlobalKey> occurrenceKeys;

  final int chunkIndex;

  /// Number of times a slug has been seen inside this chunk.
  final Map<String, int> _occurrencesInChunk = <String, int>{};

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final slug = element.attributes[_kAnchorSlugAttribute];
    if (slug == null || slug.isEmpty) {
      return const SizedBox.shrink();
    }
    final occurrence = _occurrencesInChunk.update(
      slug,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final occurrenceKey = occurrenceKeys.putIfAbsent(
      '$chunkIndex|$slug|$occurrence',
      () => GlobalKey(),
    );
    keys.putIfAbsent(slug, () => occurrenceKey);
    return SizedBox.shrink(key: occurrenceKey);
  }
}
