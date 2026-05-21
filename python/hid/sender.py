import ctypes
from ctypes import wintypes

from hid.hid_to_scancode import HID_TO_SCANCODE

INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x01000
WHEEL_DELTA = 120
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
VK_HANGUL = 0x15
VK_HANJA = 0x19

_BUTTON_FLAGS: dict[int, tuple[int, int]] = {
    1: (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
    2: (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
    3: (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
}


class MouseInput(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", wintypes.WPARAM),
    ]


class KeyboardInput(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", wintypes.WPARAM),
    ]


class InputUnion(ctypes.Union):
    _fields_ = [("mi", MouseInput), ("ki", KeyboardInput)]


class Input(ctypes.Structure):
    _fields_ = [
        ("type", wintypes.DWORD),
        ("union", InputUnion),
    ]


SendInput = ctypes.windll.user32.SendInput
SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(Input), ctypes.c_int)
SendInput.restype = wintypes.UINT


def move_mouse(dx: int, dy: int) -> None:
    _send_mouse(dx=dx, dy=dy, mouse_data=0, flags=MOUSEEVENTF_MOVE)


def mouse_button(button: int, pressed: bool) -> None:
    flags_pair = _BUTTON_FLAGS.get(button)
    if flags_pair is None:
        raise ValueError(f"unknown mouse button: {button}")
    down_flag, up_flag = flags_pair
    _send_mouse(dx=0, dy=0, mouse_data=0, flags=down_flag if pressed else up_flag)


def scroll_mouse(axis: int, ticks: int) -> None:
    flags = MOUSEEVENTF_WHEEL if axis == 0 else MOUSEEVENTF_HWHEEL
    _send_mouse(dx=0, dy=0, mouse_data=ticks * WHEEL_DELTA, flags=flags)


def key(hid_usage: int, pressed: bool) -> None:
    if hid_usage == 0x90:
        _send_vk(VK_HANGUL, pressed)
        return
    if hid_usage == 0x91:
        _send_vk(VK_HANJA, pressed)
        return

    mapping = HID_TO_SCANCODE.get(hid_usage)
    if mapping is None:
        print(f"unknown HID usage: 0x{hid_usage:02X}", flush=True)
        return
    scancode, extended = mapping
    _send_scancode(scancode, pressed, extended)


def modifier(mask: int, pressed: bool) -> None:
    modifier_map: dict[int, tuple[int, bool]] = {
        0x01: (0x1D, False),  # LeftCtrl
        0x02: (0x2A, False),  # LeftShift
        0x04: (0x38, False),  # LeftAlt
        0x08: (0x5B, True),  # LeftWin
        0x10: (0x1D, True),  # RightCtrl
        0x20: (0x36, False),  # RightShift
        0x40: (0x38, True),  # RightAlt
        0x80: (0x5C, True),  # RightWin
    }
    for bit, (scancode, extended) in modifier_map.items():
        if mask & bit:
            _send_scancode(scancode, pressed, extended)


def _send_mouse(dx: int, dy: int, mouse_data: int, flags: int) -> None:
    event = Input(
        type=INPUT_MOUSE,
        union=InputUnion(
            mi=MouseInput(
                dx=dx,
                dy=dy,
                mouseData=mouse_data,
                dwFlags=flags,
                time=0,
                dwExtraInfo=0,
            )
        ),
    )
    sent = SendInput(1, ctypes.byref(event), ctypes.sizeof(event))
    if sent != 1:
        raise ctypes.WinError()


def _send_scancode(scancode: int, pressed: bool, extended: bool) -> None:
    flags = KEYEVENTF_SCANCODE
    if extended:
        flags |= KEYEVENTF_EXTENDEDKEY
    if not pressed:
        flags |= KEYEVENTF_KEYUP
    _send_keyboard(vk=0, scancode=scancode, flags=flags)


def _send_vk(vk: int, pressed: bool) -> None:
    flags = 0 if pressed else KEYEVENTF_KEYUP
    _send_keyboard(vk=vk, scancode=0, flags=flags)


def _send_keyboard(vk: int, scancode: int, flags: int) -> None:
    event = Input(
        type=INPUT_KEYBOARD,
        union=InputUnion(
            ki=KeyboardInput(
                wVk=vk,
                wScan=scancode,
                dwFlags=flags,
                time=0,
                dwExtraInfo=0,
            )
        ),
    )
    sent = SendInput(1, ctypes.byref(event), ctypes.sizeof(event))
    if sent != 1:
        raise ctypes.WinError()
