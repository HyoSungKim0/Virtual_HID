from collections.abc import Callable

from hid.sender import key, modifier, mouse_button, move_mouse, scroll_mouse

PROTOCOL_VERSION = 0x01
OP_MOUSE_MOVE = 0x01
OP_MOUSE_BUTTON = 0x02
OP_MOUSE_SCROLL = 0x03
OP_KEY_EVENT = 0x10
OP_MODIFIER = 0x11
OP_PING = 0xF0
OP_RESET = 0xFE

NotifyEcho = Callable[[bytes], None]


class InputHandler:
    def __init__(self, notify_echo: NotifyEcho) -> None:
        self._notify_echo = notify_echo
        self._pressed_buttons: set[int] = set()
        self._pressed_keys: set[int] = set()
        self._pressed_modifier_mask = 0

    def handle_write(self, data: bytes) -> None:
        event = self._parse(data)
        if event is None:
            return

        op, payload = event
        if op == OP_MOUSE_MOVE:
            dx = int.from_bytes(payload[0:1], "little", signed=True)
            dy = int.from_bytes(payload[1:2], "little", signed=True)
            move_mouse(dx, dy)
        elif op == OP_MOUSE_BUTTON:
            button = payload[0]
            pressed = payload[1] == 1
            mouse_button(button, pressed)
            if pressed:
                self._pressed_buttons.add(button)
            else:
                self._pressed_buttons.discard(button)
        elif op == OP_MOUSE_SCROLL:
            ticks = int.from_bytes(payload[1:2], "little", signed=True)
            scroll_mouse(payload[0], ticks)
        elif op == OP_KEY_EVENT:
            hid_usage = payload[0]
            pressed = payload[1] == 1
            key(hid_usage, pressed)
            if pressed:
                self._pressed_keys.add(hid_usage)
            else:
                self._pressed_keys.discard(hid_usage)
        elif op == OP_MODIFIER:
            mask = payload[0]
            pressed = payload[1] == 1
            modifier(mask, pressed)
            if pressed:
                self._pressed_modifier_mask |= mask
            else:
                self._pressed_modifier_mask &= ~mask
        elif op == OP_PING:
            self._notify_echo(data)
        elif op == OP_RESET:
            self._reset_pressed_inputs()

    def _parse(self, data: bytes) -> tuple[int, bytes] | None:
        if len(data) < 3:
            return None
        version, op, length = data[0], data[1], data[2]
        if version != PROTOCOL_VERSION:
            return None
        payload = data[3 : 3 + length]
        if len(payload) != length:
            return None
        if op == OP_MOUSE_MOVE and length != 2:
            return None
        if op == OP_MOUSE_BUTTON and length != 2:
            return None
        if op == OP_MOUSE_SCROLL and length != 2:
            return None
        if op == OP_KEY_EVENT and length != 2:
            return None
        if op == OP_MODIFIER and length != 2:
            return None
        if op == OP_PING and length not in (0, 4):
            return None
        if op == OP_RESET and length != 0:
            return None
        return op, payload

    def _reset_pressed_inputs(self) -> None:
        for button in tuple(self._pressed_buttons):
            mouse_button(button, False)
        for hid_usage in tuple(self._pressed_keys):
            key(hid_usage, False)
        if self._pressed_modifier_mask:
            modifier(self._pressed_modifier_mask, False)
        self._pressed_buttons.clear()
        self._pressed_keys.clear()
        self._pressed_modifier_mask = 0
