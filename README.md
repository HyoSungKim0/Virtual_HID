# Virtual_HID

스마트폰을 Windows PC의 무선 터치패드 + 키보드처럼 쓰는 실험용 앱입니다.  
폰 앱은 Flutter로 만들고, PC 쪽은 Python BLE Peripheral 서버가 입력 패킷을 받아 Windows `SendInput`으로 마우스/키보드 입력을 주입합니다.

## 현재 지원 기능

- 1손가락 드래그: 마우스 이동
- 1손가락 더블탭: 좌클릭
- 더블탭 후 누른 채 드래그: 좌클릭 드래그
- 2손가락 탭: 우클릭
- 2손가락 드래그: 세로/가로 스크롤
- 3손가락 드래그: 휠 클릭(Middle Mouse Button) 누른 채 이동, Blender 같은 3D 뷰 회전용
- 키보드 모드: 영문/숫자/기호/F1~F12/방향키/한영/한자/Modifier
- 키 길게 누름 반복 입력
- 설정 팝업: 감도, 3D 뷰 감도, PING RTT, 재연결, 기본값 복원

## 개발 환경 버전

현재 프로젝트에서 확인한 버전입니다.

### Flutter

- FVM Flutter: `3.44.0`
- Dart SDK constraint: `>=3.4.0 <4.0.0`
- `flutter/.fvmrc`: `3.44.0`

주요 Flutter 패키지:

| 패키지 | pubspec 제약 | lock 버전 |
|---|---:|---:|
| `flutter_blue_plus` | `^1.32.0` | `1.36.8` |
| `permission_handler` | `^11.3.1` | `11.4.0` |
| `shared_preferences` | `^2.2.3` | `2.5.5` |
| `wakelock_plus` | `^1.2.5` | `1.6.1` |

### Python

- Python: `3.11.9`
- `pip`: `26.1.1`

주요 Python 패키지:

| 패키지 | 버전 |
|---|---:|
| `bless` | `0.3.0` |
| `bleak` | `3.0.2` |
| `bleak-winrt` | `1.2.0` |
| `pywin32` | `311` |
| `pysetupdi` | `2018.10.22` |
| `winrt-*` | `3.2.1` |

`pysetupdi`는 PyPI 이름 설치가 안 되어 GitHub zip URL로 설치합니다. `python/requirements.txt`에 포함되어 있습니다.

## 사전 준비

### 1. Windows 개발자 모드

Flutter 플러그인 빌드에는 symlink가 필요합니다. Windows 설정에서 개발자 모드를 켜야 합니다.

```cmd
start ms-settings:developers
```

열린 설정 화면에서 **개발자 모드**를 켭니다.

### 2. FVM 설치

`fvm`이 없다면:

```cmd
dart pub global activate fvm
```

`fvm` 명령이 안 잡히면 아래 경로가 PATH에 있어야 합니다.

```text
%USERPROFILE%\AppData\Local\Pub\Cache\bin
```

직접 실행할 수도 있습니다.

```cmd
%LOCALAPPDATA%\Pub\Cache\bin\fvm.bat --version
```

## 설치

### 1. 저장소 위치로 이동

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID
```

### 2. Python 가상환경 준비

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID
python -m venv python\.venv
python\.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r python\requirements.txt
```

설치 확인:

```cmd
python -c "import bless; from pysetupdi import devices; print('python deps ok')"
```

### 3. Flutter 의존성 준비

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\flutter
fvm install 3.44.0
fvm use 3.44.0
fvm flutter pub get
```

FVM이 PATH에 없다면:

```cmd
%LOCALAPPDATA%\Pub\Cache\bin\fvm.bat flutter pub get
```

## 실행 방법

반드시 **PC Python 서버를 먼저 켠 뒤** 폰 앱을 실행합니다.

### 1. PC 서버 실행

새 터미널에서:

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

서버 종료:

```text
Ctrl+C
```

### 2. Flutter 앱 실행

다른 터미널에서:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\flutter
fvm flutter run
```

기기를 고르고 실행합니다. Android 실기기 사용을 권장합니다.

### 3. 실행 후 확인

앱 상단 상태가 다음 순서로 바뀌어야 합니다.

```text
탐색 중... -> 연결 중... -> 연동 확인 중... -> 연동됨
```

`연동됨`은 단순 Bluetooth 연결이 아니라, Flutter가 Python 서버의 Ping echo를 실제로 받은 상태입니다.

## 빌드

Android debug APK:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\flutter
fvm flutter build apk --debug
```

산출물:

```text
flutter\build\app\outputs\flutter-apk\app-debug.apk
```

## 사용법

### 터치패드 모드

| 제스처 | 동작 |
|---|---|
| 1손가락 드래그 | 커서 이동 |
| 1손가락 더블탭 | 좌클릭 |
| 더블탭 후 누른 채 드래그 | 좌클릭 드래그 |
| 2손가락 탭 | 우클릭 |
| 2손가락 위/아래 드래그 | 세로 스크롤 |
| 2손가락 좌/우 드래그 | 가로 스크롤 |
| 3손가락 드래그 | 휠 클릭 누른 채 이동, 3D 뷰 회전용 |

상단 버튼:

| 버튼 | 동작 |
|---|---|
| 왼쪽 화살표 | 이전 페이지 (`Alt + Left`) |
| 오른쪽 화살표 | 다음 페이지 (`Alt + Right`) |
| 톱니바퀴 | 설정 팝업 |
| 전환 아이콘 | 터치패드/키보드 모드 전환 |

### 키보드 모드

- 키를 짧게 누르면 일반 입력
- 키를 길게 누르면 앱이 반복 `KeyDown`을 보내 연속 입력
- Shift/Ctrl/Alt/Win은 Sticky/Lock 방식
  - 짧게 탭: 다음 키 입력 후 자동 해제
  - 길게 누름: Lock
  - 다시 탭: 해제

## 설정 팝업

설정에서 조절할 수 있는 값:

- 마우스 감도
- 스크롤 감도
- 3D 뷰 감도
- PING 10회 RTT 측정
- 재연결
- 기본값 복원

감도 값은 `shared_preferences`에 저장되어 앱 재시작 후에도 유지됩니다.

## 문제 해결

### `fvm` 명령을 찾을 수 없음

```cmd
dart pub global activate fvm
```

그래도 안 되면:

```cmd
%LOCALAPPDATA%\Pub\Cache\bin\fvm.bat --version
```

### `Building with plugins requires symlink support`

Windows 개발자 모드를 켭니다.

```cmd
start ms-settings:developers
```

### Python에서 `ModuleNotFoundError: pysetupdi`

가상환경을 켠 뒤 requirements를 다시 설치합니다.

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\python
.venv\Scripts\activate
python -m pip install -r requirements.txt
```

### Python 서버가 종료되지 않음

우선 `Ctrl+C`를 누릅니다. 그래도 남아 있으면 프로젝트 venv Python 프로세스를 찾아 종료합니다.

```powershell
Get-Process python | Select-Object Id,Path
Stop-Process -Id <PID> -Force
```

### 좌클릭/휠 클릭/Modifier가 눌린 채로 남은 느낌

앱 설정에서 **재연결**을 누르거나 Python 서버를 껐다 켭니다.  
그래도 남으면 실제 키보드/마우스에서 `Ctrl`, `Alt`, `Shift`, `Win`, 좌클릭, 우클릭, 휠클릭을 한 번씩 눌렀다 떼면 대부분 풀립니다.

### 앱 상태가 `연동 확인 중...`에서 멈춤

Python 서버가 Ping echo를 못 보내는 상태입니다.

1. PC 터미널에 `advertising as VHID-PC`가 떠 있는지 확인
2. Python 서버 재시작
3. 앱 설정에서 재연결
4. Windows Bluetooth가 켜져 있는지 확인

## 개발 검증 명령

Python 문법 확인:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID
python\.venv\Scripts\python.exe -m compileall python\ble python\hid python\main.py
```

Dart format/analyze:

```cmd
cd C:\Users\{사용자}\flutter\Virtual_HID\flutter
fvm dart format lib
fvm dart analyze lib
```

만약 Dart가 AppData 권한 문제를 내면 임시 경로를 지정해서 실행합니다.

```powershell
$env:APPDATA='C:\tmp\dart_appdata'
$env:LOCALAPPDATA='C:\tmp\dart_localappdata'
C:\Users\{사용자}\fvm\versions\3.44.0\bin\cache\dart-sdk\bin\dart.exe analyze lib
```

## 문서

- Python 서버 실행 문서: `python/README.md`
- Flutter 앱 문서: `flutter/README.md`
- 프로젝트 개요: `docs/00_project_overview.md`
- 기술 스택: `docs/01_tech_stack.md`
- 아키텍처: `docs/02_architecture.md`
- UX 명세: `docs/03_ux_spec.md`
- 프로토콜 명세: `docs/04_protocol_spec.md`
- Phase 1 보고서: `docs/dev_instructions/001_phase1_report.md`
- Phase 2 보고서: `docs/dev_instructions/002_phase2_report.md`
