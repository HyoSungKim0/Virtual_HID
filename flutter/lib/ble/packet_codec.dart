import 'dart:typed_data';

const int _protocolVersion = 0x01;
const int _opMouseMove = 0x01;
const int _opMouseButton = 0x02;
const int _opMouseScroll = 0x03;
const int _opKeyEvent = 0x10;
const int _opModifier = 0x11;
const int _opPing = 0xF0;
const int _opReset = 0xFE;

class PacketCodec {
  const PacketCodec._();

  static Uint8List encodeMouseMove(int dx, int dy) {
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opMouseMove,
      0x02,
      _toInt8(dx),
      _toInt8(dy),
    ]);
  }

  static Uint8List encodeMouseButton(int button, bool pressed) {
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opMouseButton,
      0x02,
      button,
      pressed ? 1 : 0,
    ]);
  }

  static Uint8List encodeMouseScroll(int axis, int ticks) {
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opMouseScroll,
      0x02,
      axis,
      _toInt8(ticks),
    ]);
  }

  static Uint8List encodeKeyEvent(int hidKeycode, bool pressed) {
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opKeyEvent,
      0x02,
      hidKeycode,
      pressed ? 1 : 0,
    ]);
  }

  static Uint8List encodeModifier(int mask, bool pressed) {
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opModifier,
      0x02,
      mask,
      pressed ? 1 : 0,
    ]);
  }

  static Uint8List encodePing(int timestampMs) {
    final ByteData payload = ByteData(4)
      ..setUint32(0, timestampMs, Endian.little);
    return Uint8List.fromList(<int>[
      _protocolVersion,
      _opPing,
      0x04,
      ...payload.buffer.asUint8List(),
    ]);
  }

  static Uint8List encodeReset() {
    return Uint8List.fromList(<int>[_protocolVersion, _opReset, 0x00]);
  }

  static int? decodePingEcho(List<int> data) {
    if (data.length != 7 || data[0] != _protocolVersion || data[1] != _opPing) {
      return null;
    }
    if (data[2] != 0x04) {
      return null;
    }
    return ByteData.sublistView(Uint8List.fromList(data), 3, 7)
        .getUint32(0, Endian.little);
  }

  static int _toInt8(int value) {
    final int clamped = value.clamp(-127, 127);
    return clamped < 0 ? clamped + 256 : clamped;
  }
}
