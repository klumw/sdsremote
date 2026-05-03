import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;

/// A help window that displays the user manual in markdown format.
class HelpWindow extends StatefulWidget {
  const HelpWindow({super.key});

  @override
  State<HelpWindow> createState() => _HelpWindowState();
}

class _HelpWindowState extends State<HelpWindow> {
  String _manualContent = '';

  @override
  void initState() {
    super.initState();
    _loadManual();
  }

  Future<void> _loadManual() async {
    try {
      _manualContent = await rootBundle.loadString('docs/manual.md');
    } catch (e) {
      _manualContent = 'Error loading manual: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: _manualContent.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Markdown(
                    data: _manualContent,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        _launchUrl(href);
                      }
                    },
                    builders: {
                      'code': InlineCodeElementBuilder(),
                      'pre': CodeBlockElementBuilder(),
                    },
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
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
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          code: TextStyle(
                            backgroundColor: Colors.black54,
                            color: Colors.greenAccent[100],
                            fontFamily: 'Roboto Mono',
                            fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
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
                                color: Colors.cyanAccent.withValues(alpha: 0.6),
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
                        ),
                  ),
          ),
        ],
      ),
    );
  }
}

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
                      fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
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
