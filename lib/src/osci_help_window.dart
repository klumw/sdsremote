import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;

/// Result of parsing code spans from the manual content.
typedef _CodeSpansResult = (List<(int, int)>, List<(int, int)>);

/// Parses fenced code block spans and inline code spans from [content]
/// in a background isolate so the UI thread stays responsive during loading.
_CodeSpansResult _parseCodeSpansInIsolate(String content) {
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

  return (fencedCodeBlockSpans, inlineCodeSpans);
}

/// A help window that displays the user manual in markdown format
/// with a search bar to find and navigate between matching terms.
class HelpWindow extends StatefulWidget {
  const HelpWindow({super.key});

  @override
  State<HelpWindow> createState() => _HelpWindowState();
}

class _HelpWindowState extends State<HelpWindow> {
  String _manualContent = '';
  bool _isLoading = true;

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
    // Defer loading until after the first frame is rendered so the
    // CircularProgressIndicator is visible and its animation has started
    // ticking before the async I/O and isolate work begin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadManual();
    });
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadManual() async {
    // Ensure the loading indicator stays visible for at least 400ms
    // so the user always sees visual feedback when opening Help.
    final minLoadTime = Future.delayed(const Duration(milliseconds: 400));
    try {
      _manualContent = await rootBundle.loadString('docs/manual.md');
      // Run the regex-based span parsing in a background isolate so the
      // CircularProgressIndicator animation keeps spinning while loading.
      // compute() passes the top-level function and argument directly to
      // Isolate.spawn — no closure, no captured `this`.
      final spans = await compute(_parseCodeSpansInIsolate, _manualContent);
      _fencedCodeBlockSpans.clear();
      _fencedCodeBlockSpans.addAll(spans.$1);
      _inlineCodeSpans.clear();
      _inlineCodeSpans.addAll(spans.$2);
      await minLoadTime;
    } catch (e) {
      _manualContent = 'Error loading manual: $e';
    }
    if (mounted) setState(() => _isLoading = false);
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
          final pattern = RegExp.escape(term);
          final regex = RegExp(pattern, caseSensitive: false);
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
    });
  }

  /// Build a version of the manual with all matches delimited by ASCII
  /// STX / ETX control bytes that will be parsed into `<mark>` elements
  /// by [_highlightSyntax].  These characters (\x02 / \x03) never appear
  /// in the manual and cannot collide with any markdown syntax.
  String _buildHighlightedContent() {
    if (_searchTerm.isEmpty) return _manualContent;

    final buffer = StringBuffer();
    final pattern = RegExp.escape(_searchTerm);
    final regex = RegExp(pattern, caseSensitive: false);
    int lastEnd = 0;

    for (final match in regex.allMatches(_manualContent)) {
      buffer.write(_manualContent.substring(lastEnd, match.start));
      if (_isInsideCodeBlock(match.start)) {
        // Inside a fenced code block or inline code span: write the
        // matched text as-is (the markdown parser treats code content
        // as literal text and would never apply _HighlightSyntax here).
        buffer.write(match.group(0)!);
      } else {
        buffer.write('\x02${match.group(0)}\x03');
      }
      lastEnd = match.end;
    }
    buffer.write(_manualContent.substring(lastEnd));
    return buffer.toString();
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final displayContent = _buildHighlightedContent();

    // Trigger the pending scroll via post-frame callback so the newly rebuilt
    // MarkdownBody is laid out and the ScrollController has clients.
    if (_pendingScrollMatchIndex >= 0) {
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
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Headline and search bar row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'SDS-Remote Help',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
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
                              CircularProgressIndicator(
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
                            child: MarkdownBody(
                              data: displayContent,
                              selectable: true,
                              onTapLink: (text, href, title) {
                                if (href != null) {
                                  _launchUrl(href);
                                }
                              },
                              inlineSyntaxes: [_highlightSyntax],
                              builders: {
                                'code': InlineCodeElementBuilder(),
                                'pre': CodeBlockElementBuilder(),
                                'mark': MarkHighlightBuilder(_matchKeys),
                              },
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    p: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
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
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    code: TextStyle(
                                      backgroundColor: Colors.black54,
                                      color: Colors.greenAccent[100],
                                      fontFamily: 'Roboto Mono',
                                      fontFamilyFallback: const [
                                        'Consolas',
                                        'Courier New',
                                        'monospace',
                                      ],
                                    ),
                                    codeblockDecoration: const BoxDecoration(
                                      color: Colors.transparent,
                                    ),
                                    blockquote: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.cyanAccent.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    horizontalRuleDecoration:
                                        const BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.white38,
                                              width: 1.3,
                                            ),
                                            bottom: BorderSide(
                                              color: Colors.black38,
                                              width: 1.3,
                                            ),
                                          ),
                                        ),
                                    tableColumnWidth:
                                        const IntrinsicColumnWidth(),
                                  ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
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
  MarkHighlightBuilder(this.keys);

  /// [GlobalKey]s, one per match, assigned in document order.
  final List<GlobalKey> keys;
  int _cursor = 0;

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
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
        );
      },
    );
  }
}
