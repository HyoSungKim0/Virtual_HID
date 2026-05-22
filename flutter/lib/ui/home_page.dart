import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_client.dart';
import '../input/throttler.dart';

const double _defaultMouseSensitivity = 1.5;
const double _defaultScrollSensitivity = 1.0;
const double _defaultOrbitSensitivity = 1.0;
const int _leftButton = 1;
const int _rightButton = 2;
const int _verticalScroll = 0;
const int _horizontalScroll = 1;

enum _InputMode { touchpad, keyboard }

enum _ModifierMode { off, sticky, locked }

const Duration _keyRepeatDelay = Duration(milliseconds: 450);
const Duration _keyRepeatInterval = Duration(milliseconds: 45);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final BleClient _bleClient;
  late MouseMoveThrottler _throttler;
  _InputMode _mode = _InputMode.touchpad;
  double _mouseSensitivity = _defaultMouseSensitivity;
  double _scrollSensitivity = _defaultScrollSensitivity;
  double _orbitSensitivity = _defaultOrbitSensitivity;

  @override
  void initState() {
    super.initState();
    _bleClient = BleClient()..addListener(_onBleChanged);
    _throttler = _createThrottler();
    _loadSettings();
    _bleClient.connect();
  }

  @override
  void dispose() {
    _throttler.dispose();
    _bleClient.removeListener(_onBleChanged);
    unawaited(_bleClient.disposeClient());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool touchpad = _mode == _InputMode.touchpad;
    return Scaffold(
      backgroundColor:
          touchpad ? const Color(0xFF2A2A2A) : const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              mode: _mode,
              state: _bleClient.state,
              statusText: _bleClient.statusMessage,
              onReconnect: () => unawaited(_bleClient.reconnect()),
              onSettings: _showSettings,
              onBack: () => unawaited(_bleClient.sendShortcut(0x04, 0x50)),
              onForward: () => unawaited(_bleClient.sendShortcut(0x04, 0x4F)),
              onToggleMode: _toggleMode,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: touchpad
                    ? _TouchpadView(
                        key: const ValueKey<_InputMode>(_InputMode.touchpad),
                        mouseSensitivity: _mouseSensitivity,
                        scrollSensitivity: _scrollSensitivity,
                        orbitSensitivity: _orbitSensitivity,
                        onMove: (Offset delta) =>
                            _throttler.add(delta.dx, delta.dy),
                        onLeftClick: () =>
                            unawaited(_bleClient.clickMouseButton(_leftButton)),
                        onRightClick: () => unawaited(
                          _bleClient.clickMouseButton(_rightButton),
                        ),
                        onLeftPressed: (bool pressed) => unawaited(
                          _bleClient.sendMouseButton(_leftButton, pressed),
                        ),
                        onLeftRelease: () =>
                            unawaited(_bleClient.releaseLeftButton()),
                        onMiddlePressed: (bool pressed) =>
                            unawaited(_bleClient.sendMouseButton(3, pressed)),
                        onScroll: (int axis, int ticks) =>
                            unawaited(_bleClient.sendMouseScroll(axis, ticks)),
                      )
                    : _KeyboardView(
                        key: const ValueKey<_InputMode>(_InputMode.keyboard),
                        onKeyDown: (int hidUsage) =>
                            _bleClient.sendKeyEvent(hidUsage, true),
                        onKeyUp: (int hidUsage) =>
                            _bleClient.sendKeyEvent(hidUsage, false),
                        onModifier: _bleClient.sendModifier,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  MouseMoveThrottler _createThrottler() {
    return MouseMoveThrottler(
      sender: (int dx, int dy) => _bleClient.sendMouseMove(dx, dy),
    );
  }

  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _mouseSensitivity =
          prefs.getDouble('mouse_sensitivity') ?? _defaultMouseSensitivity;
      _scrollSensitivity =
          prefs.getDouble('scroll_sensitivity') ?? _defaultScrollSensitivity;
      _orbitSensitivity =
          prefs.getDouble('orbit_sensitivity') ?? _defaultOrbitSensitivity;
    });
  }

  Future<void> _setMouseSensitivity(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mouse_sensitivity', value);
    if (mounted) {
      setState(() => _mouseSensitivity = value);
    }
  }

  Future<void> _setScrollSensitivity(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('scroll_sensitivity', value);
    if (mounted) {
      setState(() => _scrollSensitivity = value);
    }
  }

  Future<void> _setOrbitSensitivity(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('orbit_sensitivity', value);
    if (mounted) {
      setState(() => _orbitSensitivity = value);
    }
  }

  Future<void> _resetSettings() async {
    await _setMouseSensitivity(_defaultMouseSensitivity);
    await _setScrollSensitivity(_defaultScrollSensitivity);
    await _setOrbitSensitivity(_defaultOrbitSensitivity);
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return _SettingsSheet(
              client: _bleClient,
              mouseSensitivity: _mouseSensitivity,
              scrollSensitivity: _scrollSensitivity,
              orbitSensitivity: _orbitSensitivity,
              onMouseSensitivityChanged: (double value) {
                setDialogState(() => _mouseSensitivity = value);
                unawaited(_setMouseSensitivity(value));
              },
              onScrollSensitivityChanged: (double value) {
                setDialogState(() => _scrollSensitivity = value);
                unawaited(_setScrollSensitivity(value));
              },
              onOrbitSensitivityChanged: (double value) {
                setDialogState(() => _orbitSensitivity = value);
                unawaited(_setOrbitSensitivity(value));
              },
              onReconnect: () => unawaited(_bleClient.reconnect()),
              onPing: () => unawaited(_bleClient.measureRtt()),
              onReset: () => unawaited(_resetSettings()),
            );
          },
        );
      },
    );
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _InputMode.touchpad
          ? _InputMode.keyboard
          : _InputMode.touchpad;
    });
  }

  void _onBleChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mode,
    required this.state,
    required this.statusText,
    required this.onReconnect,
    required this.onSettings,
    required this.onBack,
    required this.onForward,
    required this.onToggleMode,
  });

  final _InputMode mode;
  final BleConnectionState state;
  final String statusText;
  final VoidCallback onReconnect;
  final VoidCallback onSettings;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            _StatusBadge(state: state, text: statusText, onTap: onReconnect),
            const Spacer(),
            _RoundIconButton(
              icon: Icons.arrow_back,
              tooltip: '이전 페이지',
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.arrow_forward,
              tooltip: '다음 페이지',
              onPressed: onForward,
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.settings,
              tooltip: '설정',
              onPressed: onSettings,
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.swap_horiz,
              tooltip: mode == _InputMode.touchpad ? '키보드 모드' : '터치패드 모드',
              onPressed: onToggleMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _TouchpadView extends StatefulWidget {
  const _TouchpadView({
    super.key,
    required this.mouseSensitivity,
    required this.scrollSensitivity,
    required this.orbitSensitivity,
    required this.onMove,
    required this.onLeftClick,
    required this.onRightClick,
    required this.onLeftPressed,
    required this.onLeftRelease,
    required this.onMiddlePressed,
    required this.onScroll,
  });

  final double mouseSensitivity;
  final double scrollSensitivity;
  final double orbitSensitivity;
  final ValueChanged<Offset> onMove;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;
  final ValueChanged<bool> onLeftPressed;
  final VoidCallback onLeftRelease;
  final ValueChanged<bool> onMiddlePressed;
  final void Function(int axis, int ticks) onScroll;

  @override
  State<_TouchpadView> createState() => _TouchpadViewState();
}

class _TouchpadViewState extends State<_TouchpadView> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 250);
  static const Duration _holdClassifyWindow = Duration(milliseconds: 150);
  static const Duration _twoFingerTapWindow = Duration(milliseconds: 170);
  static const double _tapSlop = 20;
  static const double _dragStartSlop = 5;
  static const double _scrollPixelsPerTick = 30;

  final Map<int, Offset> _positions = <int, Offset>{};
  final Map<int, Offset> _startPositions = <int, Offset>{};
  DateTime? _lastTapAt;
  Offset? _lastTapPosition;
  Timer? _dragClassifyTimer;
  bool _doubleTapSecondDown = false;
  bool _draggingWithButton = false;
  bool _threeFingerGesture = false;
  bool _middleDragging = false;
  bool _twoFingerGesture = false;
  bool _scrolling = false;
  int? _scrollAxis;
  double _scrollAccumulator = 0;
  DateTime? _twoFingerStartedAt;

  @override
  void dispose() {
    _dragClassifyTimer?.cancel();
    if (_draggingWithButton) {
      widget.onLeftRelease();
    }
    if (_middleDragging) {
      widget.onMiddlePressed(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: const Center(
        child: Text(
          '터치패드 모드',
          style: TextStyle(color: Color(0x22FFFFFF), fontSize: 24),
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _positions[event.pointer] = event.localPosition;
    _startPositions[event.pointer] = event.localPosition;

    if (_positions.length >= 3) {
      _startThreeFingerGesture();
    } else if (_positions.length == 1) {
      _prepareDoubleTapDrag(event.localPosition);
    } else if (_positions.length == 2) {
      _dragClassifyTimer?.cancel();
      _doubleTapSecondDown = false;
      _twoFingerGesture = true;
      _scrolling = false;
      _scrollAxis = null;
      _scrollAccumulator = 0;
      _twoFingerStartedAt = DateTime.now();
    }
  }

  void _startThreeFingerGesture() {
    _dragClassifyTimer?.cancel();
    if (_draggingWithButton) {
      _finishButtonDrag();
    }
    _doubleTapSecondDown = false;
    _twoFingerGesture = false;
    _scrolling = false;
    _scrollAxis = null;
    _scrollAccumulator = 0;
    _threeFingerGesture = true;
  }

  void _prepareDoubleTapDrag(Offset position) {
    final DateTime now = DateTime.now();
    final bool secondTap = _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow &&
        _lastTapPosition != null &&
        (position - _lastTapPosition!).distance <= _tapSlop;
    _doubleTapSecondDown = secondTap;
    if (!secondTap) {
      return;
    }
    _dragClassifyTimer?.cancel();
    _dragClassifyTimer = Timer(_holdClassifyWindow, () {});
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final Offset? previous = _positions[event.pointer];
    if (previous == null) {
      return;
    }
    _positions[event.pointer] = event.localPosition;

    if (_threeFingerGesture) {
      if (_positions.length >= 3) {
        _handleThreeFingerMove(event.localPosition - previous);
      }
      return;
    }

    if (_positions.length == 1 && !_twoFingerGesture) {
      final Offset delta = event.localPosition - previous;
      if (_doubleTapSecondDown && !_draggingWithButton) {
        final Offset start =
            _startPositions[event.pointer] ?? event.localPosition;
        if ((event.localPosition - start).distance > _dragStartSlop) {
          _dragClassifyTimer?.cancel();
          _draggingWithButton = true;
          widget.onLeftPressed(true);
        }
      }
      widget.onMove(delta * widget.mouseSensitivity);
      return;
    }

    if (_positions.length == 2) {
      _handleTwoFingerMove(event.localPosition - previous);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final Offset? start = _startPositions[event.pointer];
    final Offset end = event.localPosition;
    final bool wasThreeFinger = _threeFingerGesture;
    final bool wasTwoFinger = _twoFingerGesture;
    final bool wasButtonDrag = _draggingWithButton;

    _positions.remove(event.pointer);
    _startPositions.remove(event.pointer);

    if (wasThreeFinger) {
      if (_middleDragging) {
        widget.onMiddlePressed(false);
        _middleDragging = false;
      }
      if (_positions.isEmpty) {
        _threeFingerGesture = false;
      }
      return;
    }

    if (wasButtonDrag) {
      _finishButtonDrag();
      return;
    }

    if (wasTwoFinger) {
      _finishTwoFingerGesture();
      return;
    }

    if (start != null && (end - start).distance <= _tapSlop) {
      if (_doubleTapSecondDown) {
        _dragClassifyTimer?.cancel();
        widget.onLeftClick();
        _doubleTapSecondDown = false;
        _lastTapAt = null;
        _lastTapPosition = null;
        return;
      }
      _handleSingleTap(end);
    } else {
      _doubleTapSecondDown = false;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _positions.remove(event.pointer);
    _startPositions.remove(event.pointer);
    if (_draggingWithButton) {
      _finishButtonDrag();
    }
    if (_middleDragging) {
      widget.onMiddlePressed(false);
      _middleDragging = false;
    }
    if (_positions.isEmpty) {
      _resetTwoFingerState();
      _threeFingerGesture = false;
      _doubleTapSecondDown = false;
    }
  }

  void _handleSingleTap(Offset position) {
    if (_doubleTapSecondDown) {
      return;
    }
    _lastTapAt = DateTime.now();
    _lastTapPosition = position;
  }

  void _finishButtonDrag() {
    widget.onLeftRelease();
    _draggingWithButton = false;
    _doubleTapSecondDown = false;
    _lastTapAt = null;
    _lastTapPosition = null;
    _positions.clear();
    _startPositions.clear();
  }

  void _handleTwoFingerMove(Offset delta) {
    final double maxDistance = _startPositions.entries.fold<double>(
      0,
      (double current, MapEntry<int, Offset> entry) {
        final Offset? position = _positions[entry.key];
        return position == null
            ? current
            : math.max(current, (position - entry.value).distance);
      },
    );

    if (!_scrolling && maxDistance > _dragStartSlop) {
      _scrolling = true;
      _scrollAxis = delta.dy.abs() >= delta.dx.abs()
          ? _verticalScroll
          : _horizontalScroll;
    }
    if (!_scrolling || _scrollAxis == null) {
      return;
    }

    final double axisDelta =
        _scrollAxis == _verticalScroll ? -delta.dy : delta.dx;
    _scrollAccumulator += axisDelta * widget.scrollSensitivity;
    final int ticks = (_scrollAccumulator / _scrollPixelsPerTick).truncate();
    if (ticks == 0) {
      return;
    }
    _scrollAccumulator -= ticks * _scrollPixelsPerTick;
    widget.onScroll(_scrollAxis!, ticks.clamp(-127, 127));
  }

  void _handleThreeFingerMove(Offset delta) {
    final double maxDistance = _startPositions.entries.fold<double>(
      0,
      (double current, MapEntry<int, Offset> entry) {
        final Offset? position = _positions[entry.key];
        return position == null
            ? current
            : math.max(current, (position - entry.value).distance);
      },
    );
    if (!_middleDragging && maxDistance > _dragStartSlop) {
      _middleDragging = true;
      widget.onMiddlePressed(true);
    }
    if (_middleDragging) {
      widget.onMove(
        delta * widget.mouseSensitivity * widget.orbitSensitivity,
      );
    }
  }

  void _finishTwoFingerGesture() {
    if (_positions.isNotEmpty) {
      return;
    }
    final bool isTap = !_scrolling &&
        _twoFingerStartedAt != null &&
        DateTime.now().difference(_twoFingerStartedAt!) <= _twoFingerTapWindow;
    _resetTwoFingerState();
    if (isTap) {
      widget.onRightClick();
    }
  }

  void _resetTwoFingerState() {
    _twoFingerGesture = false;
    _scrolling = false;
    _scrollAxis = null;
    _scrollAccumulator = 0;
    _twoFingerStartedAt = null;
  }
}

class _KeyboardView extends StatefulWidget {
  const _KeyboardView({
    super.key,
    required this.onKeyDown,
    required this.onKeyUp,
    required this.onModifier,
  });

  final Future<void> Function(int hidUsage) onKeyDown;
  final Future<void> Function(int hidUsage) onKeyUp;
  final Future<void> Function(int mask, bool pressed) onModifier;

  @override
  State<_KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<_KeyboardView> {
  final Map<int, _ModifierMode> _modifiers = <int, _ModifierMode>{};
  final Set<int> _pressedKeys = <int>{};
  final Map<int, Timer> _repeatTimers = <int, Timer>{};
  Timer? _longPressTimer;
  int? _longPressMask;

  bool get _shiftActive =>
      (_modifiers[0x02] ?? _ModifierMode.off) != _ModifierMode.off ||
      (_modifiers[0x20] ?? _ModifierMode.off) != _ModifierMode.off;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    for (final Timer timer in _repeatTimers.values) {
      timer.cancel();
    }
    _repeatTimers.clear();
    for (final int hidUsage in _pressedKeys.toList()) {
      unawaited(widget.onKeyUp(hidUsage));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<List<_KeySpec>> rows = _keyboardRows(_shiftActive);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        children: rows
            .map(
              (List<_KeySpec> row) => Expanded(
                child: Row(
                  children: row
                      .map(
                        (_KeySpec spec) => Expanded(
                          flex: spec.flex,
                          child: _KeyboardKey(
                            spec: spec,
                            modifierMode: spec.modifierMask == null
                                ? _ModifierMode.off
                                : _modifiers[spec.modifierMask!] ??
                                    _ModifierMode.off,
                            onTapDown: () => _handleKeyDown(spec),
                            onTapUp: () => _handleKeyUp(spec),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _handleKeyDown(_KeySpec spec) {
    HapticFeedback.selectionClick();
    final int? modifierMask = spec.modifierMask;
    if (modifierMask == null) {
      final int hidUsage = spec.hidUsage!;
      if (_pressedKeys.add(hidUsage)) {
        unawaited(widget.onKeyDown(hidUsage));
        _startKeyRepeat(hidUsage);
      }
      return;
    }
    final int mask = modifierMask;
    _longPressMask = mask;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (_longPressMask == mask) {
        _setModifier(mask, _ModifierMode.locked);
      }
    });
  }

  void _handleKeyUp(_KeySpec spec) {
    _longPressTimer?.cancel();
    _longPressMask = null;
    final int? modifierMask = spec.modifierMask;
    if (modifierMask != null) {
      final _ModifierMode current =
          _modifiers[modifierMask] ?? _ModifierMode.off;
      if (current == _ModifierMode.locked) {
        _setModifier(modifierMask, _ModifierMode.off);
      } else if (current == _ModifierMode.sticky) {
        _setModifier(modifierMask, _ModifierMode.off);
      } else {
        _setModifier(modifierMask, _ModifierMode.sticky);
      }
      return;
    }

    final int hidUsage = spec.hidUsage!;
    if (_pressedKeys.remove(hidUsage)) {
      _stopKeyRepeat(hidUsage);
      unawaited(widget.onKeyUp(hidUsage));
    }
    _releaseStickyModifiers();
  }

  void _startKeyRepeat(int hidUsage) {
    _repeatTimers[hidUsage]?.cancel();
    _repeatTimers[hidUsage] = Timer(_keyRepeatDelay, () {
      if (!_pressedKeys.contains(hidUsage)) {
        return;
      }
      unawaited(widget.onKeyDown(hidUsage));
      _repeatTimers[hidUsage] = Timer.periodic(_keyRepeatInterval, (_) {
        if (_pressedKeys.contains(hidUsage)) {
          unawaited(widget.onKeyDown(hidUsage));
        }
      });
    });
  }

  void _stopKeyRepeat(int hidUsage) {
    _repeatTimers.remove(hidUsage)?.cancel();
  }

  void _setModifier(int mask, _ModifierMode mode) {
    final _ModifierMode previous = _modifiers[mask] ?? _ModifierMode.off;
    if (previous == mode) {
      return;
    }
    if (previous == _ModifierMode.off && mode != _ModifierMode.off) {
      unawaited(widget.onModifier(mask, true));
    } else if (previous != _ModifierMode.off && mode == _ModifierMode.off) {
      unawaited(widget.onModifier(mask, false));
    }
    setState(() => _modifiers[mask] = mode);
  }

  void _releaseStickyModifiers() {
    final List<int> sticky = _modifiers.entries
        .where((MapEntry<int, _ModifierMode> entry) =>
            entry.value == _ModifierMode.sticky)
        .map((MapEntry<int, _ModifierMode> entry) => entry.key)
        .toList();
    for (final int mask in sticky) {
      _setModifier(mask, _ModifierMode.off);
    }
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.spec,
    required this.modifierMode,
    required this.onTapDown,
    required this.onTapUp,
  });

  final _KeySpec spec;
  final _ModifierMode modifierMode;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  @override
  Widget build(BuildContext context) {
    final bool active = modifierMode != _ModifierMode.off;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onTapDown(),
        onTapUp: (_) => onTapUp(),
        onTapCancel: onTapUp,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active
                ? modifierMode == _ModifierMode.locked
                    ? const Color(0xFF1565C0)
                    : const Color(0xFFBBDEFB)
                : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCCCCCC)),
          ),
          child: Center(
            child: _KeyLabel(
              label: modifierMode == _ModifierMode.locked
                  ? '${spec.label} lock'
                  : spec.label,
              subLabel: spec.subLabel,
              color: active && modifierMode == _ModifierMode.locked
                  ? Colors.white
                  : const Color(0xFF111111),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyLabel extends StatelessWidget {
  const _KeyLabel({
    required this.label,
    required this.subLabel,
    required this.color,
  });

  final String label;
  final String? subLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String? secondary = subLabel;
    if (secondary == null) {
      return Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: label.length > 5 ? 12 : 15,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          secondary,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _KeySpec {
  const _KeySpec(
    this.label, {
    this.subLabel,
    this.hidUsage,
    this.modifierMask,
    this.flex = 1,
  });

  final String label;
  final String? subLabel;
  final int? hidUsage;
  final int? modifierMask;
  final int flex;
}

List<List<_KeySpec>> _keyboardRows(bool shifted) {
  _KeySpec letterKey(String english, String korean, String shiftedKorean) {
    return _KeySpec(
      shifted ? english : english.toLowerCase(),
      subLabel: shifted ? shiftedKorean : korean,
      hidUsage: 0x04 + 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.indexOf(english),
    );
  }

  _KeySpec symbolKey(String normal, String shiftedLabel, int hidUsage) {
    return _KeySpec(normal, subLabel: shiftedLabel, hidUsage: hidUsage);
  }

  return <List<_KeySpec>>[
    <_KeySpec>[
      const _KeySpec('Esc', hidUsage: 0x29),
      for (int i = 0; i < 12; i++) _KeySpec('F${i + 1}', hidUsage: 0x3A + i),
    ],
    <_KeySpec>[
      symbolKey('`', '~', 0x35),
      symbolKey('1', '!', 0x1E),
      symbolKey('2', '@', 0x1F),
      symbolKey('3', '#', 0x20),
      symbolKey('4', r'$', 0x21),
      symbolKey('5', '%', 0x22),
      symbolKey('6', '^', 0x23),
      symbolKey('7', '&', 0x24),
      symbolKey('8', '*', 0x25),
      symbolKey('9', '(', 0x26),
      symbolKey('0', ')', 0x27),
      symbolKey('-', '_', 0x2D),
      symbolKey('=', '+', 0x2E),
      const _KeySpec('Backspace', hidUsage: 0x2A, flex: 2),
    ],
    <_KeySpec>[
      const _KeySpec('Tab', hidUsage: 0x2B, flex: 2),
      letterKey('Q', 'ㅂ', 'ㅃ'),
      letterKey('W', 'ㅈ', 'ㅉ'),
      letterKey('E', 'ㄷ', 'ㄸ'),
      letterKey('R', 'ㄱ', 'ㄲ'),
      letterKey('T', 'ㅅ', 'ㅆ'),
      letterKey('Y', 'ㅛ', 'ㅛ'),
      letterKey('U', 'ㅕ', 'ㅕ'),
      letterKey('I', 'ㅑ', 'ㅑ'),
      letterKey('O', 'ㅐ', 'ㅒ'),
      letterKey('P', 'ㅔ', 'ㅖ'),
      symbolKey('[', '{', 0x2F),
      symbolKey(']', '}', 0x30),
      symbolKey(r'\', '|', 0x31),
    ],
    <_KeySpec>[
      const _KeySpec('Caps', hidUsage: 0x39, flex: 2),
      letterKey('A', 'ㅁ', 'ㅁ'),
      letterKey('S', 'ㄴ', 'ㄴ'),
      letterKey('D', 'ㅇ', 'ㅇ'),
      letterKey('F', 'ㄹ', 'ㄹ'),
      letterKey('G', 'ㅎ', 'ㅎ'),
      letterKey('H', 'ㅗ', 'ㅗ'),
      letterKey('J', 'ㅓ', 'ㅓ'),
      letterKey('K', 'ㅏ', 'ㅏ'),
      letterKey('L', 'ㅣ', 'ㅣ'),
      symbolKey(';', ':', 0x33),
      symbolKey("'", '"', 0x34),
      const _KeySpec('Enter', hidUsage: 0x28, flex: 2),
    ],
    <_KeySpec>[
      const _KeySpec('Shift', modifierMask: 0x02, flex: 2),
      letterKey('Z', 'ㅋ', 'ㅋ'),
      letterKey('X', 'ㅌ', 'ㅌ'),
      letterKey('C', 'ㅊ', 'ㅊ'),
      letterKey('V', 'ㅍ', 'ㅍ'),
      letterKey('B', 'ㅠ', 'ㅠ'),
      letterKey('N', 'ㅜ', 'ㅜ'),
      letterKey('M', 'ㅡ', 'ㅡ'),
      symbolKey(',', '<', 0x36),
      symbolKey('.', '>', 0x37),
      symbolKey('/', '?', 0x38),
      const _KeySpec('Shift', modifierMask: 0x20, flex: 2),
    ],
    <_KeySpec>[
      const _KeySpec('Ctrl', modifierMask: 0x01),
      const _KeySpec('Win', modifierMask: 0x08),
      const _KeySpec('Alt', modifierMask: 0x04),
      const _KeySpec('한/영', hidUsage: 0x90),
      const _KeySpec('한자', hidUsage: 0x91),
      const _KeySpec('Space', hidUsage: 0x2C, flex: 6),
      const _KeySpec('←', hidUsage: 0x50),
      const _KeySpec('↑', hidUsage: 0x52),
      const _KeySpec('↓', hidUsage: 0x51),
      const _KeySpec('→', hidUsage: 0x4F),
      const _KeySpec('Ctrl', modifierMask: 0x10),
    ],
  ];
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.client,
    required this.mouseSensitivity,
    required this.scrollSensitivity,
    required this.orbitSensitivity,
    required this.onMouseSensitivityChanged,
    required this.onScrollSensitivityChanged,
    required this.onOrbitSensitivityChanged,
    required this.onReconnect,
    required this.onPing,
    required this.onReset,
  });

  final BleClient client;
  final double mouseSensitivity;
  final double scrollSensitivity;
  final double orbitSensitivity;
  final ValueChanged<double> onMouseSensitivityChanged;
  final ValueChanged<double> onScrollSensitivityChanged;
  final ValueChanged<double> onOrbitSensitivityChanged;
  final VoidCallback onReconnect;
  final VoidCallback onPing;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(context).height - 32,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool narrow = constraints.maxWidth < 560;
                final List<Widget> panels = <Widget>[
                  _SettingsPanel(title: '상태', children: <Widget>[
                    Text('연동: ${client.statusMessage}'),
                    Text('MTU: ${client.negotiatedMtu ?? '-'}'),
                    const Text('Interval: 측정 불가'),
                    const Text('PHY: 측정 불가'),
                    const Divider(height: 24),
                    FilledButton(
                      onPressed: onPing,
                      child: const Text('PING 10회'),
                    ),
                    const SizedBox(height: 8),
                    Text('샘플: ${client.rttStats.count}/10'),
                    Text(
                      '평균 RTT: ${client.rttStats.averageMs.toStringAsFixed(1)} ms',
                    ),
                    Text('최대 RTT: ${client.rttStats.maxMs} ms'),
                  ]),
                  _SettingsPanel(title: '입력', children: <Widget>[
                    Text('마우스 감도 ${mouseSensitivity.toStringAsFixed(1)}'),
                    Slider(
                      min: 0.5,
                      max: 3.0,
                      value: mouseSensitivity,
                      onChanged: onMouseSensitivityChanged,
                    ),
                    Text('스크롤 감도 ${scrollSensitivity.toStringAsFixed(1)}'),
                    Slider(
                      min: 0.5,
                      max: 3.0,
                      value: scrollSensitivity,
                      onChanged: onScrollSensitivityChanged,
                    ),
                    Text('3D 뷰 감도 ${orbitSensitivity.toStringAsFixed(1)}'),
                    Slider(
                      min: 0.5,
                      max: 3.0,
                      value: orbitSensitivity,
                      onChanged: onOrbitSensitivityChanged,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: onReconnect,
                          child: const Text('재연결'),
                        ),
                        OutlinedButton(
                          onPressed: onReset,
                          child: const Text('기본값 복원'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('닫기'),
                        ),
                      ],
                    ),
                  ]),
                ];

                if (narrow) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      panels[0],
                      const SizedBox(height: 16),
                      panels[1],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: panels[0]),
                    const SizedBox(width: 24),
                    Expanded(child: panels[1]),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC111111),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        tooltip: tooltip,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.state,
    required this.text,
    required this.onTap,
  });

  final BleConnectionState state;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      BleConnectionState.connected => const Color(0xFF2E7D32),
      BleConnectionState.scanning ||
      BleConnectionState.verifying ||
      BleConnectionState.connecting =>
        const Color(0xFFFFB300),
      BleConnectionState.error => const Color(0xFFC62828),
      BleConnectionState.disconnected => const Color(0xFF888888),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC111111),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
