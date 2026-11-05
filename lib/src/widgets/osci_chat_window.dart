import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../voice/voice_input_binding.dart';
import '../voice/voice_input_service.dart';
import 'animated_sync_icon.dart';

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
    _opacity = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
        return Opacity(opacity: _opacity.value, child: child);
      },
      child: const Text(
        '▊',
        style: TextStyle(color: Colors.cyanAccent, fontSize: 15, height: 1.0),
      ),
    );
  }
}

/// A chat window widget for interacting with the AI assistant.
class ChatWindow extends StatefulWidget {
  final List<Map<String, String>> chatMessages;
  final bool isChatting;
  final bool isInitialized;
  final ValueChanged<String> onSendMessage;

  /// Optional controller for the input field. When provided, the caller owns
  /// the controller and may prefill it (for example with a variable name).
  final TextEditingController? inputController;

  /// Optional footer below a message bubble. The calculator uses it for copy
  /// actions, structured result cards and "Use in program".
  final Widget? Function(BuildContext context, int index)? messageFooterBuilder;

  /// Whether the input field should take focus when it appears. Panels that
  /// are built off-screen pass false and switch it on when they open.
  final bool autofocus;

  /// Optional custom builders for inline Markdown elements. The calculator
  /// uses this to render clickable footnote markers.
  final Map<String, MarkdownElementBuilder> markdownBuilders;

  /// Whether to wrap assistant messages in [SelectionArea].
  ///
  /// The calculator disables this so clickable inline footnote markers can
  /// keep their hand cursor; MarkdownBody already provides selectable text.
  final bool useSelectionArea;

  /// Placeholder shown in the input field.
  final String hintText;

  /// Optional hint shown in the message area while the chat is empty.
  final String? emptyStateText;

  /// Optional callback that stops the active AI response.
  ///
  /// When provided and [isChatting] is true, the send button is replaced by a
  /// square stop button. Chats without cancellation support keep the disabled
  /// send button while a response is running.
  final VoidCallback? onCancel;

  /// Recent user inputs offered in the expandable list above the input field.
  ///
  /// The list stays hidden until the user taps the history button. An empty
  /// list hides the button.
  final List<String> inputHistory;

  /// Called when the user selects an entry from [inputHistory].
  final ValueChanged<String>? onHistorySelected;

  /// Optional handler for taps on links inside AI answers.
  ///
  /// When null, links open in the external browser. The help window uses this
  /// to keep in-document links (`#heading-slug`) inside the help page instead
  /// of handing them to the browser.
  final void Function(String href)? onLinkTap;

  /// Optional microphone control shown next to the input field.
  ///
  /// The four AI assistants pass a binding for their own microphone; other
  /// chats leave it null and show no microphone button.
  final VoiceInputBinding? voiceInput;

  /// Optional widget shown directly above the input line.
  ///
  /// The waveform assistant uses it for the animated radio-button prompt, so
  /// the question appears at the bottom of the response panel while the input
  /// field stays visible below it.
  final Widget? inputBanner;

  const ChatWindow({
    super.key,
    required this.chatMessages,
    required this.isChatting,
    required this.isInitialized,
    required this.onSendMessage,
    this.inputController,
    this.messageFooterBuilder,
    this.autofocus = true,
    this.markdownBuilders = const {},
    this.useSelectionArea = true,
    this.hintText = 'Ask about the oscilloscope or give a command...',
    this.emptyStateText,
    this.onCancel,
    this.inputHistory = const [],
    this.onHistorySelected,
    this.onLinkTap,
    this.voiceInput,
    this.inputBanner,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  late final TextEditingController _chatController;
  late final bool _ownsChatController;
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  int _previousMessageCount = 0;
  int _previousLastMessageLength = 0;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _chatController = widget.inputController ?? TextEditingController();
    _ownsChatController = widget.inputController == null;
    _previousMessageCount = widget.chatMessages.length;
    _previousLastMessageLength = _lastMessageContentLength();
    if (widget.chatMessages.isNotEmpty) {
      // An existing conversation opens at its latest answer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomNow(animate: false);
      });
    }
    // Request focus on the chat input field when the chat window opens
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Capture the old scroll position before the new content is laid out.
    final wasNearBottom = _isNearBottom();
    final previousCount = _previousMessageCount;
    final previousLength = _previousLastMessageLength;
    final currentLength = _lastMessageContentLength();
    _previousMessageCount = widget.chatMessages.length;
    _previousLastMessageLength = currentLength;

    var shouldScroll = false;

    // Auto-scroll when a new message is added (either user or AI response)
    if (widget.chatMessages.length > previousCount) {
      shouldScroll = true;
    } else if (currentLength > previousLength) {
      // Auto-scroll during streaming when the last message content grows
      shouldScroll = true;
    }

    // The final Markdown layout and result cards can change the height after
    // the last text chunk arrived, so scroll again when streaming completes.
    if (oldWidget.isChatting && !widget.isChatting) {
      shouldScroll = true;
    }

    // A footer or result card may be added without changing the message text.
    // Follow it only when the user was already reading the end of the answer.
    if (wasNearBottom) shouldScroll = true;

    if (shouldScroll) _scrollToBottom();

    // Re-focus the chat input field when streaming finishes, so the user can
    // immediately type the next message without manually clicking the field.
    if (widget.autofocus &&
        ((oldWidget.isChatting && !widget.isChatting) ||
            (!oldWidget.autofocus && widget.autofocus))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatFocusNode.requestFocus();
      });
    }
  }

  /// Whether the message list is already at (or very close to) its end.
  bool _isNearBottom() {
    if (!_chatScrollController.hasClients) return true;
    final position = _chatScrollController.position;
    return position.maxScrollExtent - position.pixels <= 32;
  }

  /// Returns the content length of the last message, or 0 if no messages exist.
  int _lastMessageContentLength() {
    if (widget.chatMessages.isEmpty) return 0;
    return widget.chatMessages.last['content']?.length ?? 0;
  }

  @override
  void dispose() {
    if (_ownsChatController) _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  /// Dispatches a tap on a link inside a message.
  ///
  /// [ChatWindow.onLinkTap] takes precedence; without it the link opens in the
  /// external browser.
  void _handleLink(String? href) {
    if (href == null || href.isEmpty) return;
    final handler = widget.onLinkTap;
    if (handler != null) {
      handler(href);
      return;
    }
    launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || widget.isChatting || !widget.isInitialized) return;

    if (_showHistory) setState(() => _showHistory = false);
    _chatController.clear();
    widget.onSendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomNow(animate: animate);
    });
  }

  /// Scrolls to the latest content after the current frame has been laid out.
  ///
  /// Streaming uses a jump instead of an animation: text arrives much faster
  /// than an animation can finish, so repeated [ScrollController.animateTo]
  /// calls would keep restarting and never reach the end of the answer.
  void _scrollToBottomNow({required bool animate}) {
    if (!mounted || !_chatScrollController.hasClients) return;
    final position = _chatScrollController.position;
    final target = position.maxScrollExtent;
    if ((position.pixels - target).abs() < 0.5) return;
    if (!animate || widget.isChatting) {
      position.jumpTo(target);
      return;
    }
    _chatScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
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
            child: widget.chatMessages.isEmpty && widget.emptyStateText != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.emptyStateText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
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
                          child: _buildBubbleContent(
                            context,
                            msg,
                            index,
                            isUser,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_showHistory && widget.inputHistory.isNotEmpty)
            _buildInputHistory(),
          // Optional banner directly above the input line (for example the
          // radio-button prompt of the waveform assistant).
          if (widget.inputBanner != null) widget.inputBanner!,
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
                        hintText: widget.hintText,
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
                if (widget.voiceInput != null)
                  ValueListenableBuilder<VoiceInputStatus>(
                    valueListenable: widget.voiceInput!.status,
                    builder: (context, voice, _) =>
                        _buildMicrophoneButton(voice),
                  ),
                if (widget.inputHistory.isNotEmpty)
                  IconButton(
                    tooltip: _showHistory
                        ? 'Hide input history'
                        : 'Show input history',
                    icon: const Icon(Icons.history, color: Colors.white70),
                    onPressed: widget.isChatting || !widget.isInitialized
                        ? null
                        : () => setState(() => _showHistory = !_showHistory),
                  ),
                const SizedBox(width: 8),
                if (widget.isChatting && widget.onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.redAccent),
                    tooltip: 'Stop AI response',
                    onPressed: widget.onCancel,
                  )
                else
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

  /// Microphone button of an AI assistant.
  ///
  /// The button starts switched off whenever the assistant opens. Activating
  /// it keeps the microphone listening until the user switches it off again
  /// or the assistant closes.
  Widget _buildMicrophoneButton(VoiceInputStatus voice) {
    final binding = widget.voiceInput!;
    final active = voice.isActiveFor(binding.ownerId);
    final answering = active && voice.isResponding;
    final preparing = active && voice.isPreparing;
    // The microphone cannot be switched off while the model is prepared or an
    // utterance is transcribed; stopping then would cut into whisper.cpp.
    final locked = active && (voice.isPreparing || voice.isTranscribing);
    final color = active && (voice.isTranscribing || answering)
        ? Colors.greenAccent
        : (active ? Colors.cyanAccent : Colors.white70);
    final tooltip = active
        ? (answering ? voice.message : 'Turn off the assistant microphone')
        : 'Turn on the assistant microphone';
    return IconButton(
      tooltip: tooltip,
      icon: preparing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                value: voice.downloadProgress,
                color: color,
              ),
            )
          : Icon(active ? Icons.mic : Icons.mic_off),
      color: color,
      onPressed: widget.isInitialized && !locked
          ? () => unawaited(binding.toggle())
          : null,
    );
  }

  /// Expandable list of recent user inputs above the input field.
  Widget _buildInputHistory() {
    final enabled = !widget.isChatting && widget.isInitialized;
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: const BoxDecoration(
        color: Color(0xFF10263D),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: widget.inputHistory.length,
        itemBuilder: (context, index) {
          final entry = widget.inputHistory[index];
          return InkWell(
            onTap: enabled
                ? () {
                    setState(() => _showHistory = false);
                    widget.onHistorySelected?.call(entry);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.north_west,
                    size: 14,
                    color: enabled ? Colors.white38 : Colors.white24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? Colors.white70 : Colors.white30,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext context,
    Map<String, String> message,
    int index,
    bool isUser,
  ) {
    final content = _buildMessageContent(message, index, isUser);
    final footer = isUser
        ? null
        : widget.messageFooterBuilder?.call(context, index);
    if (footer == null) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [content, footer],
    );
  }

  Widget _wrapSelection(Widget child) =>
      widget.useSelectionArea ? SelectionArea(child: child) : child;

  /// Builds the content for a single chat message bubble.
  ///
  /// Shows a "Thinking..." spinner when the AI message is empty and streaming
  /// is in progress. Shows the message content with an animated streaming
  /// indicator at the end when content has started arriving but the agent is
  /// still generating. Otherwise renders the content as markdown.
  Widget _buildMessageContent(Map<String, String> msg, int index, bool isUser) {
    // Streaming state belongs to the last assistant message even when a
    // non-assistant message (for example an upload notice) was added while
    // the answer is still being generated.
    final lastAiIndex = widget.chatMessages.lastIndexWhere(
      (message) => message['role'] != 'user',
    );
    final isLastAiMessage = !isUser && index == lastAiIndex;

    // Case 1: Empty content while streaming → "Thinking..." spinner
    if (isLastAiMessage && msg['content']!.isEmpty && widget.isChatting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AnimatedSyncIcon(size: 14, color: Colors.cyanAccent),
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
          _wrapSelection(
            MarkdownBody(
              selectable: true,
              data: _convertBareUrlsToMarkdownLinks(msg['content']!),
              builders: widget.markdownBuilders,
              onTapLink: (text, href, title) => _handleLink(href),
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: const TextStyle(color: Colors.white, fontSize: 15),
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
                    listBullet: const TextStyle(color: Colors.cyanAccent),
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
                    blockquote: const TextStyle(color: Colors.yellow),
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
    return _wrapSelection(
      MarkdownBody(
        selectable: true,
        data: _convertBareUrlsToMarkdownLinks(msg['content']!),
        builders: widget.markdownBuilders,
        onTapLink: (text, href, title) => _handleLink(href),
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(color: Colors.white, fontSize: 15),
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
          listBullet: const TextStyle(color: Colors.cyanAccent),
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
          blockquote: const TextStyle(color: Colors.yellow),
          blockquoteDecoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
