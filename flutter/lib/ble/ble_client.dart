import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'packet_codec.dart';
import 'uuid.dart';

const int _uint32Mask = 0xFFFFFFFF;
const Duration _reconnectDelay = Duration(seconds: 2);
const Duration _heartbeatInterval = Duration(seconds: 2);
const Duration _heartbeatTimeout = Duration(seconds: 5);

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  verifying,
  connected,
  error,
}

class RttStats {
  const RttStats({required this.samples});

  final List<int> samples;

  int get count => samples.length;

  double get averageMs {
    if (samples.isEmpty) {
      return 0;
    }
    return samples.reduce((int a, int b) => a + b) / samples.length;
  }

  int get maxMs =>
      samples.isEmpty ? 0 : samples.reduce((int a, int b) => a > b ? a : b);
}

class BleClient extends ChangeNotifier {
  BleConnectionState state = BleConnectionState.disconnected;
  String statusMessage = '연결 안됨';
  RttStats rttStats = const RttStats(samples: <int>[]);
  int? negotiatedMtu;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _inputCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _manualDisconnect = false;
  bool _connecting = false;
  bool _mouseMoveWriteInFlight = false;
  bool _leftButtonPressed = false;
  int _pendingMouseDx = 0;
  int _pendingMouseDy = 0;
  int? _lastHeartbeatSentAt;
  DateTime? _lastEchoAt;
  final List<int> _rttSamples = <int>[];

  Future<void> connect() async {
    if (_disposed ||
        _connecting ||
        state == BleConnectionState.connected ||
        state == BleConnectionState.verifying) {
      return;
    }
    _connecting = true;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      final bool granted = await _requestPermissions();
      if (!granted) {
        _setState(BleConnectionState.error, '오류 - 블루투스 권한 필요');
        return;
      }
      await _disconnectCurrent(updateState: false);
      _manualDisconnect = false;
      _setState(BleConnectionState.scanning, '탐색 중...');

      final Guid serviceGuid = Guid(VhidUuids.service);
      _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
      await FlutterBluePlus.startScan(
        withServices: <Guid>[serviceGuid],
        timeout: const Duration(seconds: 5),
      );
      if (!_disposed && state == BleConnectionState.scanning) {
        _scheduleReconnect('연결 안됨 - 재시도 중');
      }
    } catch (error) {
      _manualDisconnect = false;
      _setState(BleConnectionState.error, '오류 - $error');
      _scheduleReconnect('오류 - 재시도 중');
    } finally {
      _connecting = false;
    }
  }

  Future<void> disposeClient() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer = null;
    await _disconnectCurrent(updateState: false);
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _disconnectCurrent(updateState: true);
    _manualDisconnect = false;
  }

  Future<void> _disconnectCurrent({required bool updateState}) async {
    await _scanSub?.cancel();
    await _notifySub?.cancel();
    await _connectionSub?.cancel();
    _scanSub = null;
    _notifySub = null;
    _connectionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inputCharacteristic = null;
    _statusCharacteristic = null;
    negotiatedMtu = null;
    _lastHeartbeatSentAt = null;
    _lastEchoAt = null;

    final BluetoothDevice? device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (error) {
        debugPrint('BLE disconnect failed after OS teardown: $error');
      }
    }
    if (updateState && !_disposed) {
      _setState(BleConnectionState.disconnected, '연결 안됨');
    }
  }

  Future<void> sendMouseMove(int dx, int dy) async {
    if (_mouseMoveWriteInFlight) {
      _pendingMouseDx = (_pendingMouseDx + dx).clamp(-127, 127);
      _pendingMouseDy = (_pendingMouseDy + dy).clamp(-127, 127);
      return;
    }

    _mouseMoveWriteInFlight = true;
    try {
      await _write(PacketCodec.encodeMouseMove(dx, dy));
      while (_pendingMouseDx != 0 || _pendingMouseDy != 0) {
        final int pendingDx = _pendingMouseDx;
        final int pendingDy = _pendingMouseDy;
        _pendingMouseDx = 0;
        _pendingMouseDy = 0;
        await _write(PacketCodec.encodeMouseMove(pendingDx, pendingDy));
      }
    } finally {
      _mouseMoveWriteInFlight = false;
    }
  }

  Future<void> sendMouseButton(int button, bool pressed) async {
    if (button == 1) {
      _leftButtonPressed = pressed;
    }
    await _write(PacketCodec.encodeMouseButton(button, pressed));
  }

  Future<void> clickMouseButton(int button) async {
    await sendMouseButton(button, true);
    await sendMouseButton(button, false);
  }

  Future<void> releaseLeftButton() async {
    _leftButtonPressed = false;
    await _write(PacketCodec.encodeMouseButton(1, false));
  }

  Future<void> sendMouseScroll(int axis, int ticks) async {
    await _write(PacketCodec.encodeMouseScroll(axis, ticks));
  }

  Future<void> sendKeyEvent(int hidKeycode, bool pressed) async {
    await _write(PacketCodec.encodeKeyEvent(hidKeycode, pressed));
  }

  Future<void> sendModifier(int mask, bool pressed) async {
    await _write(PacketCodec.encodeModifier(mask, pressed));
  }

  Future<void> sendShortcut(int modifierMask, int hidKeycode) async {
    await sendModifier(modifierMask, true);
    await sendKeyEvent(hidKeycode, true);
    await sendKeyEvent(hidKeycode, false);
    await sendModifier(modifierMask, false);
  }

  Future<void> sendReset() async {
    if (_leftButtonPressed) {
      await releaseLeftButton();
    }
    await _write(PacketCodec.encodeReset());
  }

  Future<void> reconnect() async {
    await sendReset();
    await disconnect();
    await Future<void>.delayed(const Duration(seconds: 1));
    await connect();
  }

  Future<void> measureRtt() async {
    _rttSamples.clear();
    rttStats = const RttStats(samples: <int>[]);
    notifyListeners();

    // Phase 1 explicitly sends 10 pings at 50ms spacing for RTT sampling.
    for (int i = 0; i < 10; i += 1) {
      await _write(PacketCodec.encodePing(_nowMillis32()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    if (state != BleConnectionState.scanning) {
      return;
    }
    for (final ScanResult result in results) {
      if (result.advertisementData.serviceUuids
          .map((Guid uuid) => uuid.str.toLowerCase())
          .contains(VhidUuids.service)) {
        await FlutterBluePlus.stopScan();
        await _scanSub?.cancel();
        _scanSub = null;
        await _connectDevice(result.device);
        return;
      }
    }
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    if (_disposed ||
        state == BleConnectionState.connected ||
        state == BleConnectionState.verifying ||
        state == BleConnectionState.connecting) {
      return;
    }
    _setState(BleConnectionState.connecting, '연결 중...');
    _device = device;
    try {
      await device.connect(autoConnect: false);
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen(_onDeviceConnectionState);
      try {
        negotiatedMtu = await device.requestMtu(247);
      } catch (error) {
        negotiatedMtu = null;
        debugPrint('BLE MTU request failed: $error');
      }
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (error) {
        debugPrint('BLE connection priority request failed: $error');
      }

      final List<BluetoothService> services = await device.discoverServices();
      for (final BluetoothService service in services) {
        if (service.uuid.str.toLowerCase() != VhidUuids.service) {
          continue;
        }
        for (final BluetoothCharacteristic characteristic
            in service.characteristics) {
          final String uuid = characteristic.uuid.str.toLowerCase();
          if (uuid == VhidUuids.input) {
            _inputCharacteristic = characteristic;
          } else if (uuid == VhidUuids.status) {
            _statusCharacteristic = characteristic;
          }
        }
      }

      if (_inputCharacteristic == null || _statusCharacteristic == null) {
        throw StateError('Required GATT characteristics not found');
      }

      await _statusCharacteristic!.setNotifyValue(true);
      _notifySub =
          _statusCharacteristic!.onValueReceived.listen(_onStatusNotify);
      _setState(BleConnectionState.verifying, '연동 확인 중...');
      _startHeartbeat();
    } catch (error) {
      _setState(BleConnectionState.error, '오류 - $error');
      _scheduleReconnect('오류 - 재시도 중');
    }
  }

  void _onDeviceConnectionState(BluetoothConnectionState nextState) {
    if (_disposed || _manualDisconnect) {
      return;
    }
    if (nextState == BluetoothConnectionState.disconnected &&
        (state == BleConnectionState.connected ||
            state == BleConnectionState.verifying)) {
      _handleLinkLost();
    }
  }

  void _handleLinkLost() {
    if (_disposed || _manualDisconnect) {
      return;
    }
    _inputCharacteristic = null;
    _statusCharacteristic = null;
    negotiatedMtu = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeatSentAt = null;
    _lastEchoAt = null;
    _setState(BleConnectionState.disconnected, '연동 끊김');
    _scheduleReconnect('재연결 중...');
  }

  void _onStatusNotify(List<int> data) {
    final int? sentAtMs = PacketCodec.decodePingEcho(data);
    if (sentAtMs == null) {
      return;
    }
    final int rtt = (_nowMillis32() - sentAtMs) & _uint32Mask;
    _lastEchoAt = DateTime.now();
    if (sentAtMs == _lastHeartbeatSentAt) {
      if (state != BleConnectionState.connected) {
        _setState(BleConnectionState.connected, '연동됨');
      }
      return;
    }

    _rttSamples.add(rtt);
    rttStats = RttStats(samples: List<int>.unmodifiable(_rttSamples));
    if (state == BleConnectionState.verifying) {
      _setState(BleConnectionState.connected, '연동됨');
    } else {
      notifyListeners();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final DateTime? lastEcho = _lastEchoAt;
      if (lastEcho != null &&
          DateTime.now().difference(lastEcho) > _heartbeatTimeout) {
        _handleLinkLost();
        return;
      }
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    if (_disposed || _inputCharacteristic == null) {
      return;
    }
    _lastHeartbeatSentAt = _nowMillis32();
    unawaited(_write(PacketCodec.encodePing(_lastHeartbeatSentAt!)));
  }

  Future<void> _write(List<int> data) async {
    final BluetoothCharacteristic? input = _inputCharacteristic;
    if (input == null ||
        (state != BleConnectionState.connected &&
            state != BleConnectionState.verifying)) {
      return;
    }
    try {
      await input.write(data, withoutResponse: true);
    } catch (error) {
      debugPrint('BLE write failed: $error');
      _handleLinkLost();
    }
  }

  Future<bool> _requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    return statuses.values.every((PermissionStatus status) => status.isGranted);
  }

  void _setState(BleConnectionState nextState, String message) {
    state = nextState;
    statusMessage = message;
    notifyListeners();
  }

  void _scheduleReconnect(String message) {
    if (_disposed || _reconnectTimer?.isActive == true) {
      return;
    }
    _setState(BleConnectionState.scanning, message);
    _reconnectTimer = Timer(_reconnectDelay, connect);
  }

  int _nowMillis32() {
    return DateTime.now().millisecondsSinceEpoch & _uint32Mask;
  }
}
