# Virtual_HID Python Server

Windows PC에서 BLE Peripheral로 광고하고, Flutter 앱에서 받은 입력 패킷을 Windows `SendInput`으로 전달하는 서버입니다.

루트의 `README.md`는 전체 프로젝트 실행 순서이고, 이 문서는 Python PC 서버만 따로 실행하거나 문제를 확인할 때 보는 문서입니다.

## 역할

- BLE 장치 이름 `VHID-PC`로 광고
- Flutter 앱의 GATT write 패킷 수신
- 마우스 이동, 좌/우/휠 클릭, 스크롤, 키보드 입력을 Windows에 주입
- Flutter 앱의 Ping 패킷을 notify로 echo해서 앱 상단의 `연동됨` 상태 확인
- 연결이 끊기거나 재연결될 때 눌린 입력을 해제할 수 있도록 reset 패킷 처리

## 확인된 버전

현재 개발 환경에서 확인한 버전입니다.

| 항목 | 버전 |
|---|---:|
| Python | `3.11.9` |
| pip | `26.1.1` |
| bless | `0.3.0` |
| bleak | `3.0.2` |
| bleak-winrt | `1.2.0` |
| pywin32 | `311` |
| pysetupdi | `2018.10.22` |
| winrt-* | `3.2.1` |

`pysetupdi`는 PyPI에서 `pip install pysetupdi`로 설치되지 않습니다. `requirements.txt`에 GitHub zip URL로 고정해 두었습니다.

## 파일 구조

```text
python/
  main.py                  # 서버 엔트리포인트
  requirements.txt         # Python 의존성
  ble/
    peripheral.py          # bless 기반 BLE GATT 서버
    handlers.py            # 입력 프로토콜 파싱/분기
    uuid.py                # BLE 이름, service/characteristic UUID
  hid/
    sender.py              # Windows SendInput 래퍼
    hid_to_scancode.py     # HID usage -> Windows scancode 매핑
```

## 설치

프로젝트 루트에서 실행합니다.

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID
python -m venv python\.venv
python\.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r python\requirements.txt
```

이미 가상환경이 있다면:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\python
.venv\Scripts\activate
python -m pip install -r requirements.txt
```

설치 확인:

```cmd
python -c "import bless; from pysetupdi import devices; import win32api; print('python deps ok')"
```

## 실행

Flutter 앱보다 먼저 Python 서버를 실행합니다.

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\python
.venv\Scripts\activate
python main.py
```

정상 출력:

```text
advertising as VHID-PC
Press Ctrl+C to stop.
```

이 상태에서 Android 앱을 실행하고 BLE 연결을 시도합니다. 앱 상단이 `연동됨`으로 바뀌면 Bluetooth 연결뿐 아니라 Flutter와 Python 사이의 Ping echo까지 정상입니다.

## 종료

터미널에서:

```text
Ctrl+C
```

정상 종료 시:

```text
stopped
```

서버가 남아 있는지 확인하려면:

```powershell
Get-Process python | Select-Object Id,Path
```

프로젝트 venv의 Python 프로세스만 골라 종료합니다.

```powershell
Stop-Process -Id <PID> -Force
```

## 환경 변수

콘솔 로그를 줄이고 싶으면 `VHID_QUIET=1`을 줄 수 있습니다.

```cmd
set VHID_QUIET=1
python main.py
```

## 입력 프로토콜

패킷 기본 형식:

```text
[version, op, length, payload...]
```

현재 `version`은 `0x01`입니다.

| op | 이름 | payload |
|---:|---|---|
| `0x01` | Mouse move | `dx:int8, dy:int8` |
| `0x02` | Mouse button | `button:uint8, pressed:uint8` |
| `0x03` | Mouse scroll | `axis:uint8, ticks:int8` |
| `0x10` | Key event | `hid_usage:uint8, pressed:uint8` |
| `0x11` | Modifier | `mask:uint8, pressed:uint8` |
| `0xF0` | Ping | empty 또는 4 bytes |
| `0xFE` | Reset | empty |

마우스 버튼 값:

| 값 | 버튼 |
|---:|---|
| `1` | 좌클릭 |
| `2` | 우클릭 |
| `3` | 휠 클릭 / Middle Mouse Button |

## 문제 해결

### `ModuleNotFoundError: No module named 'pysetupdi'`

가상환경이 켜진 상태에서 `requirements.txt`로 다시 설치합니다.

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\python
.venv\Scripts\activate
python -m pip install -r requirements.txt
```

`pip install pysetupdi`는 실패하는 것이 정상입니다. 이 프로젝트는 GitHub zip URL로 설치합니다.

### `ImportError: cannot import name 'GATTAttributePermissions'`

예전 코드나 잘못된 bless import 경로를 쓰면 발생합니다. 현재 코드는 아래 경로를 사용합니다.

```python
from bless.backends.attribute import GATTAttributePermissions
from bless.backends.characteristic import GATTCharacteristicProperties
```

코드를 최신 상태로 맞춘 뒤 다시 실행합니다.

### `pywintypes.error: (2, 'CreateFile', ...)`

Windows BLE/WinRT 어댑터 탐색 중 발생할 수 있는 bless 쪽 문제입니다. 현재 서버는 사용하지 않는 adapter probe를 우회하도록 패치되어 있습니다. 그래도 발생하면 다음을 확인합니다.

- Windows Bluetooth가 켜져 있는지
- PC에 BLE를 지원하는 Bluetooth 어댑터가 있는지
- 기존에 떠 있는 `python main.py` 프로세스가 남아 있지 않은지
- 가상환경 의존성이 현재 `requirements.txt` 기준인지

### 앱은 연결됨처럼 보이는데 Python을 다시 켜도 연결이 꼬임

Flutter 앱의 실제 정상 상태는 `연동됨`입니다. 단순 Bluetooth 연결 표시와 다릅니다.

1. 앱 설정에서 재연결
2. Python 서버 `Ctrl+C` 종료 후 재실행
3. Android Bluetooth 화면에서 `VHID-PC` 연결 상태 정리
4. 필요하면 Windows Bluetooth를 껐다 켬

### 클릭이나 modifier가 눌린 채로 남은 느낌

Flutter 앱이 reset 패킷을 보낼 수 있고 Python 서버도 reset을 처리합니다. 앱 설정에서 재연결을 먼저 시도합니다.

그래도 남으면 실제 키보드/마우스에서 `Ctrl`, `Alt`, `Shift`, `Win`, 좌클릭, 우클릭, 휠클릭을 한 번씩 눌렀다 떼면 Windows 입력 상태가 풀립니다.

## 개발 확인

문법 확인:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID
python\.venv\Scripts\python.exe -m compileall python\ble python\hid python\main.py
```

의존성 목록 확인:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\python
.venv\Scripts\activate
python -m pip list
```
