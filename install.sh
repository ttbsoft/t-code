#!/usr/bin/env bash
# T-Code 바이너리 인스톨러
#
# 미리 빌드된 tcode 바이너리를 GitHub Releases 에서 받아 설치합니다.
# 로컬 빌드는 수행하지 않습니다.
#
# 분리 아키텍처:
#   - 개발 저장소(소스): 별도 GitLab — 일반 사용자에겐 노출되지 않음
#   - 배포 저장소(install): github.com/ttbsoft/t-code — 본 install.sh 와
#     release 바이너리만 호스팅. 메인테이너가 scripts/release.sh 로 동기화.
#
# 한 줄 설치 (최신):
#   curl -fsSL https://raw.githubusercontent.com/ttbsoft/t-code/main/install.sh | bash
#
# 특정 버전:
#   curl -fsSL ... | bash -s -- --version v0.1.0
#
# 업데이트:
#   tcode-update
#   (또는 위 한 줄 설치 명령을 다시 실행)
#
# 업데이트 가능 여부만 확인:
#   tcode-update --check
#   bash install.sh --check-update
#
# 제거:
#   bash install.sh --uninstall
#
# 환경 변수:
#   TCODE_REPO           GitHub owner/repo (기본: ttbsoft/t-code)
#   TCODE_RELEASE_BASE   릴리스 베이스 URL (기본: https://github.com/${TCODE_REPO})
#   TCODE_VERSION        설치할 버전 (latest | vX.Y.Z), 기본 latest
#   TCODE_PREFIX         설치 prefix, 기본 $HOME/.local
#                        (바이너리는 $TCODE_PREFIX/bin/tcode 에 저장)

set -euo pipefail

# ---------------------------------------------------------------------------
# 기본값
# ---------------------------------------------------------------------------

TCODE_REPO="${TCODE_REPO:-ttbsoft/t-code}"
TCODE_RELEASE_BASE="${TCODE_RELEASE_BASE:-https://github.com/${TCODE_REPO}}"
TCODE_VERSION="${TCODE_VERSION:-latest}"
TCODE_PREFIX="${TCODE_PREFIX:-$HOME/.local}"

INSTALL_BIN_DIR="${TCODE_PREFIX}/bin"
INSTALL_BIN="${INSTALL_BIN_DIR}/tcode"
UPDATER_BIN="${INSTALL_BIN_DIR}/tcode-update"
META_DIR="${HOME}/.tcode"
META_FILE="${META_DIR}/install.json"
INSTALLER_URL_DEFAULT="https://raw.githubusercontent.com/${TCODE_REPO}/main/install.sh"

# ---------------------------------------------------------------------------
# 출력 포맷
# ---------------------------------------------------------------------------

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"
    C_BOLD="$(tput bold)"
    C_DIM="$(tput dim)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

info()  { printf '%s->%s %s\n' "${C_BLUE}" "${C_RESET}" "$1"; }
ok()    { printf '%sok%s %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn()  { printf '%swarn%s %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
error() { printf '%serror%s %s\n' "${C_RED}" "${C_RESET}" "$1" 1>&2; }

print_usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# 인자 파싱
# ---------------------------------------------------------------------------

ACTION="install"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            shift
            TCODE_VERSION="${1:-latest}"
            ;;
        --prefix)
            shift
            TCODE_PREFIX="${1:-$HOME/.local}"
            INSTALL_BIN_DIR="${TCODE_PREFIX}/bin"
            INSTALL_BIN="${INSTALL_BIN_DIR}/tcode"
            UPDATER_BIN="${INSTALL_BIN_DIR}/tcode-update"
            ;;
        --check-update)
            ACTION="check"
            ;;
        --uninstall)
            ACTION="uninstall"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            error "알 수 없는 인자: $1"
            print_usage
            exit 2
            ;;
    esac
    shift || true
done

# ---------------------------------------------------------------------------
# 플랫폼 감지
# ---------------------------------------------------------------------------

detect_asset() {
    local kernel arch os
    kernel="$(uname -s 2>/dev/null || echo unknown)"
    arch="$(uname -m 2>/dev/null || echo unknown)"

    case "${kernel}" in
        Darwin) os="macos" ;;
        Linux)
            error "Linux 바이너리는 아직 배포되지 않았습니다. 현재는 macOS 만 지원."
            error "소스 빌드 가이드: ${TCODE_RELEASE_BASE}/blob/main/USAGE.md"
            exit 1
            ;;
        *)
            error "지원하지 않는 OS: ${kernel}. 현재 macOS 만 지원."
            exit 1
            ;;
    esac

    case "${arch}" in
        arm64|aarch64) printf 'tcode-%s-arm64\n' "${os}" ;;
        x86_64|amd64)  printf 'tcode-%s-x64\n'   "${os}" ;;
        *)
            error "지원하지 않는 아키텍처: ${arch}"
            exit 1
            ;;
    esac
}

asset_download_url() {
    local asset="$1"
    local version="$2"
    if [ "${version}" = "latest" ]; then
        # GitHub Releases: /releases/latest/download/<asset> redirects to the
        # current latest release's asset URL.
        printf '%s/releases/latest/download/%s\n' "${TCODE_RELEASE_BASE}" "${asset}"
    else
        printf '%s/releases/download/%s/%s\n' "${TCODE_RELEASE_BASE}" "${version}" "${asset}"
    fi
}

resolve_remote_version() {
    # GitHub /releases/latest 은 /releases/tag/<TAG> 로 리다이렉트.
    # 헤더만 받고 effective URL 의 마지막 세그먼트(=tag)를 사용.
    local url effective tag
    url="${TCODE_RELEASE_BASE}/releases/latest"
    if ! effective="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${url}" 2>/dev/null)"; then
        printf 'unknown\n'
        return
    fi
    tag="${effective##*/}"
    if [ -z "${tag}" ] || [ "${tag}" = "latest" ]; then
        printf 'unknown\n'
        return
    fi
    printf '%s\n' "${tag}"
}

current_version() {
    if [ -x "${INSTALL_BIN}" ]; then
        "${INSTALL_BIN}" --version 2>/dev/null | awk 'NF{print $NF; exit}' || printf 'unknown\n'
    else
        printf 'none\n'
    fi
}

# ---------------------------------------------------------------------------
# 액션: check-update
# ---------------------------------------------------------------------------

action_check_update() {
    local current remote
    current="$(current_version)"
    if [ "${current}" = "none" ]; then
        info "tcode 가 설치되어 있지 않습니다. 설치:"
        info "  curl -fsSL ${INSTALLER_URL_DEFAULT} | bash"
        exit 0
    fi
    info "현재 설치: ${current}"
    info "원격 최신 버전 확인 중 ..."
    remote="$(resolve_remote_version)"
    if [ "${remote}" = "unknown" ]; then
        warn "원격 버전을 확인할 수 없습니다 (releases 없음 또는 네트워크 오류)"
        exit 1
    fi
    info "원격 최신: ${remote}"
    if [ "${current}" = "${remote}" ] || [ "v${current}" = "${remote}" ]; then
        ok "최신 버전입니다."
    else
        warn "업데이트 가능: ${remote} (현재: ${current})"
        info "업데이트: tcode-update"
    fi
}

# ---------------------------------------------------------------------------
# 액션: uninstall
# ---------------------------------------------------------------------------

action_uninstall() {
    local removed=0
    if [ -e "${INSTALL_BIN}" ]; then
        rm -f "${INSTALL_BIN}"
        ok "제거: ${INSTALL_BIN}"
        removed=1
    fi
    if [ -e "${UPDATER_BIN}" ]; then
        rm -f "${UPDATER_BIN}"
        ok "제거: ${UPDATER_BIN}"
        removed=1
    fi
    if [ -e "${META_FILE}" ]; then
        rm -f "${META_FILE}"
        ok "제거: ${META_FILE}"
        removed=1
    fi
    if [ "${removed}" = "0" ]; then
        warn "제거할 항목이 없습니다."
    fi
    info "사용자 데이터(${META_DIR}/plugins, settings.json 등) 는 보존됩니다."
    info "전체 삭제는 직접 실행: rm -rf ${META_DIR}"
}

# ---------------------------------------------------------------------------
# 액션: install (= update)
# ---------------------------------------------------------------------------

action_install() {
    local asset url tmpfile installed_ver previous_ver

    asset="$(detect_asset)"
    url="$(asset_download_url "${asset}" "${TCODE_VERSION}")"
    previous_ver="$(current_version)"

    info "플랫폼:    ${asset}"
    info "버전:      ${TCODE_VERSION}"
    info "다운로드:  ${url}"

    mkdir -p "${INSTALL_BIN_DIR}" "${META_DIR}"

    tmpfile="$(mktemp "${TMPDIR:-/tmp}/tcode-install.XXXXXX")"
    cleanup_tmp() { rm -f "${tmpfile}"; }
    trap cleanup_tmp EXIT INT TERM

    if ! curl -fSL --progress-bar --output "${tmpfile}" "${url}"; then
        error "다운로드 실패: ${url}"
        error "릴리스가 존재하는지 (TCODE_VERSION) 와 ${TCODE_RELEASE_BASE} 접근 가능 여부 확인."
        exit 1
    fi

    # 다운로드된 파일이 실제 바이너리인지 검증 (404 HTML 등 차단)
    if command -v file >/dev/null 2>&1; then
        if ! file "${tmpfile}" | grep -qE 'Mach-O|ELF|executable'; then
            error "다운로드 파일이 실행 가능한 바이너리가 아닙니다."
            error "응답 내용 (앞 300바이트):"
            head -c 300 "${tmpfile}" 1>&2
            printf '\n' 1>&2
            exit 1
        fi
    fi

    chmod +x "${tmpfile}"

    # macOS Gatekeeper quarantine 비트 제거 (curl 다운로드는 보통 없지만 안전망)
    if [ "$(uname -s)" = "Darwin" ] && command -v xattr >/dev/null 2>&1; then
        xattr -d com.apple.quarantine "${tmpfile}" 2>/dev/null || true
    fi

    # 원자적 교체 (mv 가 같은 파일시스템 내에서 atomic)
    mv -f "${tmpfile}" "${INSTALL_BIN}"
    trap - EXIT INT TERM

    # 설치된 버전 확인
    if installed_ver="$("${INSTALL_BIN}" --version 2>/dev/null | awk 'NF{print $NF; exit}')"; then
        :
    else
        installed_ver="unknown"
        warn "tcode --version 호출 실패 — 바이너리는 설치되었지만 실행 검증 안 됨"
    fi

    # 메타데이터 기록
    cat > "${META_FILE}" <<EOF
{
  "version": "${installed_ver}",
  "asset": "${asset}",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "release_base": "${TCODE_RELEASE_BASE}",
  "requested_version": "${TCODE_VERSION}",
  "binary": "${INSTALL_BIN}"
}
EOF

    # 업데이트 래퍼 설치
    cat > "${UPDATER_BIN}" <<UPDATER_EOF
#!/usr/bin/env bash
# tcode-update — 최신 install.sh 를 다시 받아 실행합니다.
# 사용법:
#   tcode-update            # 최신 버전으로 업데이트
#   tcode-update --check    # 업데이트 가능 여부만 확인
#   tcode-update --version v0.2.0   # 특정 버전으로 변경
set -e
INSTALLER_URL="\${TCODE_INSTALLER_URL:-${INSTALLER_URL_DEFAULT}}"
ARGS=()
if [ "\${1:-}" = "--check" ]; then
    ARGS+=("--check-update")
    shift
fi
ARGS+=("\$@")
exec env \\
    TCODE_PREFIX="${TCODE_PREFIX}" \\
    TCODE_RELEASE_BASE="${TCODE_RELEASE_BASE}" \\
    bash -c "curl -fsSL \"\${INSTALLER_URL}\" | bash -s -- \${ARGS[*]+\"\${ARGS[@]}\"}"
UPDATER_EOF
    chmod +x "${UPDATER_BIN}"

    printf '\n'
    if [ "${previous_ver}" = "none" ]; then
        ok "설치 완료: ${INSTALL_BIN} (${installed_ver})"
    else
        ok "업데이트 완료: ${previous_ver} → ${installed_ver}"
    fi
    info "업데이트 명령: ${UPDATER_BIN}"

    if ! printf ':%s:' "${PATH}" | grep -q ":${INSTALL_BIN_DIR}:"; then
        printf '\n'
        warn "${INSTALL_BIN_DIR} 가 PATH 에 없습니다."
        info "다음 한 줄을 ~/.zshrc 또는 ~/.bashrc 에 추가:"
        printf '\n  %sexport PATH="%s:$PATH"%s\n\n' "${C_BOLD}" "${INSTALL_BIN_DIR}" "${C_RESET}"
    fi

    cat <<EOF

${C_BOLD}빠른 시작${C_RESET}
  ${C_DIM}# 헬스 체크${C_RESET}
  tcode doctor

  ${C_DIM}# 인터랙티브 REPL${C_RESET}
  tcode

  ${C_DIM}# 업데이트${C_RESET}
  tcode-update

자세한 사용법: ${TCODE_RELEASE_BASE}/blob/main/USAGE.md
EOF
}

# ---------------------------------------------------------------------------
# 디스패치
# ---------------------------------------------------------------------------

case "${ACTION}" in
    install)   action_install ;;
    check)     action_check_update ;;
    uninstall) action_uninstall ;;
    *)
        error "내부 오류: 알 수 없는 액션 ${ACTION}"
        exit 2
        ;;
esac
