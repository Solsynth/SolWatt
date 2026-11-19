import 'package:flutter/widgets.dart';

/// Reports a double click without competing for the tap.
///
/// A [GestureDetector] with `onDoubleTap` enters the gesture arena: the
/// recognizer holds the first pointer until its double-tap window closes, so a
/// row's own single-tap handler either lags or loses outright. This listens to
/// raw pointer ups instead — the child keeps every tap it always had, and a
/// second click inside [window] is reported on top.
class DoubleClickDetector extends StatefulWidget {
  final VoidCallback onDoubleClick;
  final Widget child;

  const DoubleClickDetector({
    super.key,
    required this.onDoubleClick,
    required this.child,
  });

  static const window = Duration(milliseconds: 280);

  @override
  State<DoubleClickDetector> createState() => _DoubleClickDetectorState();
}

class _DoubleClickDetectorState extends State<DoubleClickDetector> {
  DateTime? _lastClick;

  void _handlePointerUp(PointerUpEvent event) {
    final now = DateTime.now();
    final last = _lastClick;
    _lastClick = now;
    if (last != null && now.difference(last) <= DoubleClickDetector.window) {
      _lastClick = null;
      widget.onDoubleClick();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerUp: _handlePointerUp, child: widget.child);
}
