# G80SH_RemoteDisplaySwitch

Odyssey G80SH 모니터를 쓰는 PC에서 원격 접속할 때만 DP 더미 동글로 화면을 옮기고, 원격이 끝나면 평소 모니터 구성으로 바로 되돌리는 Windows 감시 스크립트입니다.

원격이 끝난 뒤 화면이 절전에 들어갈 때 G80SH가 약 42초마다 다시 인식되는 문제를 피하려고 만들었습니다. 원인 분석은 [docs/G80SH_장치인식_문제분석보고서.md](docs/G80SH_장치인식_문제분석보고서.md)에 있습니다.

## 구성

| 파일 | 역할 |
|---|---|
| `RemoteDisplaySwitch.ps1` | 감시자. 로그온 작업으로 관리자 권한으로 실행되고, 스크립트가 바뀌면 스스로 다시 시작 |
| `SwitchLib.ps1`, `DispCfg.ps1` | 원격 여부 판정, 디스플레이 구성 적용(CCD API) |
| `Restore.ps1` / `Restore.bat` | 평소 구성으로 복원. 로그온 작업(`-Auto`)과 수동 비상 복구 겸용 |
| `Setup.bat` / `Setup.ps1` | 처음 설치: 구성 저장, 작업 스케줄러 등록 |
| `Uninstall.bat` | 작업 삭제, 감시자 종료, 복원 |
| `reset_mode.txt` | 원격 종료 뒤 리셋 방식: `rewake` \| `restartdev` \| `gpureset` \| `off` |
| `tools/Set-HdrCertification.ps1` | Windows "HDR 인증" 표시 채우기 (`-Undo`로 되돌림) |

## 준비

- [NirSoft MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) `MultiMonitorTool.exe`를 이 폴더에 둡니다(저장소에는 없음). 없으면 감시자가 시작하지 않습니다.
- `RemoteDisplaySwitch.ps1` 위쪽의 모니터 장치 경로는 설치한 PC에 맞게 고칩니다.
- `home.cfg`, `remote.cfg`는 `Setup.bat`이 만듭니다.

로그: `C:\ProgramData\RemoteDisplaySwitch.log`
