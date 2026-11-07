import 'package:flutter/material.dart';

/// Scrollable container that signals when more content is below the fold.
///
/// The hint is a bottom fade plus a downward arrow; both disappear once the
/// user reaches the end. A visible scrollbar is always shown while the content
/// overflows. Dialog panels use this wrapper so long questions never look
/// complete when further fields are hidden below the visible area.
class ScrollHint extends StatefulWidget {
  const ScrollHint({
    super.key,
    required this.child,
    this.maxHeight = 360,
    this.background = const Color(0xFF10263D),
    this.controller,
  });

  /// Scrollable content, usually a [Column].
  final Widget child;

  /// Maximum height before the content scrolls.
  final double maxHeight;

  /// Background color the bottom fade blends into.
  final Color background;

  /// Optional external controller; the widget owns one when omitted.
  final ScrollController? controller;

  @override
  State<ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<ScrollHint> {
  late final ScrollController _controller;
  late final bool _ownsController;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_update);
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final hasMore = position.maxScrollExtent - position.pixels > 2;
    if (hasMore == _hasMore) return;
    setState(() => _hasMore = hasMore);
  }

  @override
  Widget build(BuildContext context) {
    // Content can grow after a validation message appears, so re-check after
    // every layout instead of only on scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Stack(
        children: <Widget>[
          Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _controller,
              child: widget.child,
            ),
          ),
          if (_hasMore)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: 30,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          widget.background.withValues(alpha: 0),
                          widget.background,
                        ],
                      ),
                    ),
                    child: const Align(
                      alignment: Alignment.bottomCenter,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.lightBlueAccent,
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
