
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai_chat_service.dart';

/// Regular expression to match bare URLs (http, https, ftp).
///
/// Uses a negative lookbehind `(?<!...)` to skip URLs already wrapped in
/// Markdown link syntax `[text](url)`.
final RegExp _urlRegExp = RegExp(
  r'(?<!\]\()\bhttps?:\/\/[^\s<>"(){}|\\^`\[\]]+',
);

/// Converts bare URLs in [text] to Markdown link syntax `[url](url)`.
///
/// This ensures that URLs not already wrapped in Markdown link syntax
/// (e.g., `[text](url)`) are rendered as clickable links.
String _convertBareUrlsToMarkdownLinks(String text) {
  return text.replaceAllMapped(_urlRegExp, (match) {
    final url = match.group(0)!;
    return '[$url]($url)';
  });
}

/// A small animated streaming indicator shown at the end of AI message content
/// while the frontend agent is still generating a response.
///
/// Displays a pulsing vertical bar character `▊` that fades in and out to
/// signal that more content is on its way.
class _StreamingIndicator extends StatefulWidget {
  @override
  State<_StreamingIndicator> createState() => _StreamingIndicatorState();
}

class _StreamingIndicatorState extends State<_StreamingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    // Smooth pulsing: 0.3 → 1.0 → 0.3 using easeInOut sine-like curve
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: child,
        );
      },
      child: const Text(
        '▊',
        style: TextStyle(
          color: Colors.cyanAccent,
          fontSize: 15,
          height: 1.0,
        ),
      ),
    );
  }
}

/// A chat window widget for interacting with the AI assistant.
class ChatWindow extends StatefulWidget {
  final AiChatService aiChatService;
  final List<Map<String, String>> chatMessages;
  final bool isChatting;
  final bool isInitialized;
  final ValueChanged<String> onSendMessage;

  const ChatWindow({
    super.key,
    required this.aiChatService,
    required this.chatMessages,
    required this.isChatting,
    required this.isInitialized,
    required this.onSendMessage,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  int _previousMessageCount = 0;
  int _previousLastMessageLength = 0;

  @override
  void initState() {
    super.initState();
    _previousMessageCount = widget.chatMessages.length;
    _previousLastMessageLength = _lastMessageContentLength();
    // Request focus on the chat input field when the chat window opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatFocusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll when a new message is added (either user or AI response)
    if (widget.chatMessages.length > _previousMessageCount) {
      _previousMessageCount = widget.chatMessages.length;
      _previousLastMessageLength = _lastMessageContentLength();
      _scrollToBottom();
      return;
    }
    // Auto-scroll during streaming when the last message content grows
    final currentLength = _lastMessageContentLength();
    if (currentLength > _previousLastMessageLength) {
      _previousLastMessageLength = currentLength;
      _scrollToBottom();
    }

    // Re-focus the chat input field when streaming finishes, so the user can
    // immediately type the next message without manually clicking the field.
    if (oldWidget.isChatting && !widget.isChatting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatFocusNode.requestFocus();
      });
    }
  }

  /// Returns the content length of the last message, or 0 if no messages exist.
  int _lastMessageContentLength() {
    if (widget.chatMessages.isEmpty) return 0;
    return widget.chatMessages.last['content']?.length ?? 0;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || widget.isChatting || !widget.isInitialized) return;

    _chatController.clear();
    widget.onSendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Chat history
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.all(16),
              itemCount: widget.chatMessages.length,
              itemBuilder: (context, index) {
                final msg = widget.chatMessages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.cyan[800] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildMessageContent(msg, index, isUser),
                  ),
                );
              },
            ),
          ),
          // Input area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2A4A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF475569),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          offset: const Offset(2, 3),
                          blurRadius: 6,
                        ),
                        BoxShadow(
                          color: const Color(0xFF2A4A7A).withValues(alpha: 0.2),
                          offset: const Offset(-1, -1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _chatController,
                      focusNode: _chatFocusNode,
                      decoration: InputDecoration(
                        hintText:
                            'Ask about the oscilloscope or give a command...',
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.send,
                    color: widget.isInitialized
                        ? Colors.cyanAccent
                        : Colors.grey[700],
                  ),
                  onPressed: widget.isInitialized ? _sendChatMessage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the content for a single chat message bubble.
  ///
  /// Shows a "Thinking..." spinner when the AI message is empty and streaming
  /// is in progress. Shows the message content with an animated streaming
  /// indicator at the end when content has started arriving but the agent is
  /// still generating. Otherwise renders the content as markdown.
  Widget _buildMessageContent(
    Map<String, String> msg,
    int index,
    bool isUser,
  ) {
    final isLastAiMessage =
        !isUser && index == widget.chatMessages.length - 1;

    // Case 1: Empty content while streaming → "Thinking..." spinner
    if (isLastAiMessage &&
        msg['content']!.isEmpty &&
        widget.isChatting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.cyanAccent,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            "Thinking...",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    // Case 2: Non-empty content while streaming → content + blinking indicator
    if (isLastAiMessage && widget.isChatting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectionArea(
            child: MarkdownBody(
              selectable: true,
              data: _convertBareUrlsToMarkdownLinks(
                msg['content']!,
              ),
              onTapLink: (text, href, title) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              styleSheet: MarkdownStyleSheet.fromTheme(
                Theme.of(context),
              ).copyWith(
                p: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
                h1: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                h2: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                h3: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                listBullet: const TextStyle(
                  color: Colors.cyanAccent,
                ),
                code: TextStyle(
                  backgroundColor: Colors.black26,
                  color: Colors.cyanAccent[100],
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                codeblockDecoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
                blockquote: const TextStyle(
                  color: Colors.yellow,
                ),
                blockquoteDecoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          _StreamingIndicator(),
        ],
      );
    }

    // Case 3: Not streaming → plain markdown content
    return SelectionArea(
      child: MarkdownBody(
        selectable: true,
        data: _convertBareUrlsToMarkdownLinks(
          msg['content']!,
        ),
        onTapLink: (text, href, title) {
          if (href != null) {
            launchUrl(
              Uri.parse(href),
              mode: LaunchMode.externalApplication,
            );
          }
        },
        styleSheet: MarkdownStyleSheet.fromTheme(
          Theme.of(context),
        ).copyWith(
          p: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
          h1: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          h2: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          h3: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          listBullet: const TextStyle(
            color: Colors.cyanAccent,
          ),
          code: TextStyle(
            backgroundColor: Colors.black26,
            color: Colors.cyanAccent[100],
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          codeblockDecoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(4),
          ),
          blockquote: const TextStyle(
            color: Colors.yellow,
          ),
          blockquoteDecoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
