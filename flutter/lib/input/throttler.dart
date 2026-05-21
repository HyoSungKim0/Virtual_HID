import 'dart:async';

typedef MouseMoveSender = void Function(int dx, int dy);

class MouseMoveThrottler {
  MouseMoveThrottler({
    required MouseMoveSender sender,
    Duration window = const Duration(milliseconds: 16),
  })  : _sender = sender,
        _window = window;

  final MouseMoveSender _sender;
  final Duration _window;
  Timer? _flushTimer;
  int _accDx = 0;
  int _accDy = 0;

  void add(double dx, double dy) {
    _accDx += dx.round();
    _accDy += dy.round();
    _flushTimer ??= Timer(_window, _flush);
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void _flush() {
    final int dx = _accDx.clamp(-127, 127);
    final int dy = _accDy.clamp(-127, 127);
    _accDx = 0;
    _accDy = 0;
    _flushTimer = null;

    if (dx != 0 || dy != 0) {
      _sender(dx, dy);
    }
  }
}
