# t-code (배포 저장소)

`tcode` CLI 바이너리 배포 채널입니다. **소스 코드는 여기에 없으며**, 개발은 별도 저장소에서 진행됩니다.

## 한 줄 설치 (macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/ttbsoft/t-code/main/install.sh | bash
```

설치 후:

```bash
tcode --help
tcode doctor
tcode-update          # 다음 release 가 나오면 갱신
tcode-update --check  # 업데이트 가능 여부만 확인
```

## 지원 플랫폼

| OS / Arch | 자산 이름 | 상태 |
|---|---|---|
| macOS arm64 (Apple Silicon) | `tcode-macos-arm64` | ✅ |
| macOS x64 (Intel) | `tcode-macos-x64` | ✅ |
| Linux x64 | `tcode-linux-x64` | ⏳ 예정 |
| Windows | — | ⏳ 예정 |

## 옵션

```bash
# 특정 버전
curl -fsSL https://raw.githubusercontent.com/ttbsoft/t-code/main/install.sh | bash -s -- --version v0.1.0

# 다른 prefix
TCODE_PREFIX=/usr/local curl -fsSL https://raw.githubusercontent.com/ttbsoft/t-code/main/install.sh | bash

# 제거
bash install.sh --uninstall
```

## 소스 / 이슈 리포팅

소스 코드, 이슈, PR 은 별도 개발 저장소에서 관리됩니다.

본 저장소는 install.sh 와 release 바이너리만 호스팅합니다.

---

마지막 release: [`v0.1.4`](https://github.com/ttbsoft/t-code/releases/tag/v0.1.4)
