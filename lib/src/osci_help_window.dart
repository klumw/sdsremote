import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;

/// A help window that displays the user manual in markdown format
/// with a search bar to find and navigate between matching terms.
class HelpWindow extends StatefulWidget {
  const HelpWindow({super.key});

  @override
  State<HelpWindow> createState() => _HelpWindowState();
}

class _HelpWindowState extends State<HelpWindow> {
  String _manualContent = '';

  // Search state
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchTerm = '';
  List<int> _matchOffsets = [];
  int _currentMatchIndex = -1;
  int _pendingScrollMatchIndex = -1;

  /// Custom inline syntax that parses `@@term@@` into a `<mark>` AST element.
  /// This is used for search-highlighting instead of HTML tags (which the
  /// markdown parser treats as raw text).
  static final md.InlineSyntax _highlightSyntax = _HighlightSyntax();

  @override
  void initState() {
    super.initState();
    _loadManual();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadManual() async {
    try {
      _manualContent = await rootBundle.loadString('docs/manual.md');
    } catch (e) {
      _manualContent = 'Error loading manual: $e';
    }
    if (mounted) setState(() {});
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
        _currentMatchIndex = -1;
        _pendingScrollMatchIndex = -1;
      } else {
        try {
          final pattern = RegExp.escape(term);
          final regex = RegExp(pattern, caseSensitive: false);
          _matchOffsets = [];
          int searchStart = 0;
          while (searchStart < _manualContent.length) {
            final match =
                regex.firstMatch(_manualContent.substring(searchStart));
            if (match == null) break;
            _matchOffsets.add(searchStart + match.start);
            searchStart += match.end;
          }
          _currentMatchIndex = _matchOffsets.isNotEmpty ? 0 : -1;
          _pendingScrollMatchIndex = _matchOffsets.isNotEmpty ? 0 : -1;
        } catch (_) {
          _matchOffsets = [];
          _currentMatchIndex = -1;
          _pendingScrollMatchIndex = -1;
        }
      }
    });
  }

  /// Build a version of the manual with all matches delimited by `@@` markers
  /// that will be parsed into `<mark>` elements by [_highlightSyntax].
  String _buildHighlightedContent() {
    if (_searchTerm.isEmpty) return _manualContent;

    final buffer = StringBuffer();
    final pattern = RegExp.escape(_searchTerm);
    final regex = RegExp(pattern, caseSensitive: false);
    int lastEnd = 0;

    for (final match in regex.allMatches(_manualContent)) {
      buffer.write(_manualContent.substring(lastEnd, match.start));
      buffer.write('@@${match.group(0)}@@');
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

    // Use line-number-based estimation instead of character-offset-based.
    // Line count is a much better proxy for rendered scroll position than
    // character count because markdown elements (headings, code blocks, etc.)
    // render at roughly one visual "block" per line.
    final offset = _matchOffsets[index];
    final lineIndex =
        '\n'.allMatches(_manualContent.substring(0, offset)).length;
    final totalLines =
        _manualContent.isEmpty ? 1 : '\n'.allMatches(_manualContent).length + 1;
    final ratio = lineIndex / totalLines;

    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        ratio * maxScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNextMatch() {
    if (_matchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex + 1) % _matchOffsets.length;
    });
    _scheduleScrollToMatch(_currentMatchIndex);
  }

  void _goToPrevMatch() {
    if (_matchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchOffsets.length) %
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

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Ctrl+F / Cmd+F  → focus search field
          if (event.logicalKey == LogicalKeyboardKey.keyF &&
              (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed)) {
            _searchFocusNode.requestFocus();
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
            return KeyEventResult.handled;
          }
          // Escape → clear search and unfocus
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _clearSearch();
            return KeyEventResult.handled;
          }
          // F3 → next match
          if (event.logicalKey == LogicalKeyboardKey.f3 &&
              !HardwareKeyboard.instance.isShiftPressed) {
            _goToNextMatch();
            return KeyEventResult.handled;
          }
          // Shift+F3 → previous match
          if (event.logicalKey == LogicalKeyboardKey.f3 &&
              HardwareKeyboard.instance.isShiftPressed) {
            _goToPrevMatch();
            return KeyEventResult.handled;
          }
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
            // Search bar
            _buildSearchBar(),
            const SizedBox(height: 8),
            // Markdown content — using MarkdownBody (non-scrolling) inside a
            // SingleChildScrollView so WE control the ScrollController.
            Expanded(
              child: _manualContent.isEmpty
                  ? const Center(child: CircularProgressIndicator())
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
                            'mark': MarkHighlightBuilder(),
                          },
                          styleSheet: MarkdownStyleSheet.fromTheme(
                                  Theme.of(context))
                              .copyWith(
                            p: const TextStyle(
                                color: Colors.white, fontSize: 16),
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
                                'monospace'
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
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                              border: Border(
                                left: BorderSide(
                                  color: Colors.cyanAccent
                                      .withValues(alpha: 0.6),
                                  width: 3,
                                ),
                              ),
                            ),
                            horizontalRuleDecoration: const BoxDecoration(
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.search, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Expanded(
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  suffixIcon: hasSearch
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.white54,
                          onPressed: _clearSearch,
                        )
                      : null,
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
        if (matchLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                matchLabel,
                style: TextStyle(
                  color: hasMatches ? Colors.cyanAccent : Colors.white38,
                  fontSize: 12,
                  fontWeight: hasMatches ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Custom InlineSyntax for `@@term@@` → `<mark>` element
// -----------------------------------------------------------------------------

/// Parses `@@text@@` into a `md.Element` with tag `mark`.
class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax() : super(r'@@([^@]+)@@');

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
class MarkHighlightBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return SelectableText(
      element.textContent,
      style: (parentStyle ?? const TextStyle()).copyWith(
        color: Colors.black,
        background: Paint()..color = const Color(0xFFFFD700),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Existing custom builders (unchanged)
// -----------------------------------------------------------------------------

/// Builder for inline code (single backticks: `code`).
class InlineCodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        element.textContent,
        style: TextStyle(
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
    final text = element.textContent;
    return Builder(builder: (context) {
      return UnconstrainedBox(
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: Center(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: Colors.greenAccent[100],
                      fontFamily: 'Roboto Mono',
                      fontFamilyFallback: const [
                        'Consolas',
                        'Courier New',
                        'monospace'
                      ],
                      fontSize: 18,
                    ),
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
    });
  }
}
