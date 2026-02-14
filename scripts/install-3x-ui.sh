#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="MHSanaei"
REPO_NAME="3x-ui"
XUI_DIR="/usr/local/x-ui"
XUI_SERVICE_FILE="/etc/systemd/system/x-ui.service"

USERNAME=""
PASSWORD=""
PANEL_PATH=""
PANEL_PORT="2053"
VERSION=""
DRY_RUN=0
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  install-3x-ui.sh --username <username> --password <password> [options]

Required:
  --username <value>       Panel username
                           Also used for Linux system user creation
  --password <value>       Panel password
                           Also used for Linux system user password

Optional:
  --path <value>           Panel URL path (e.g. panel or admin/panel)
                           Default: root path (no custom path)
  --port <value>           Panel port
                           Default: 2053
  --version <value>        3x-ui release tag (e.g. v2.6.5)
                           Default: latest release
  --dry-run                Print commands without executing them
  -h, --help               Show help
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" && "${DRY_RUN}" -eq 0 ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --username)
        [[ $# -ge 2 ]] || die "Missing value for --username"
        USERNAME="$2"
        shift 2
        ;;
      --username=*)
        USERNAME="${1#*=}"
        shift
        ;;
      --password)
        [[ $# -ge 2 ]] || die "Missing value for --password"
        PASSWORD="$2"
        shift 2
        ;;
      --password=*)
        PASSWORD="${1#*=}"
        shift
        ;;
      --path)
        [[ $# -ge 2 ]] || die "Missing value for --path"
        PANEL_PATH="$2"
        shift 2
        ;;
      --path=*)
        PANEL_PATH="${1#*=}"
        shift
        ;;
      --port)
        [[ $# -ge 2 ]] || die "Missing value for --port"
        PANEL_PORT="$2"
        shift 2
        ;;
      --port=*)
        PANEL_PORT="${1#*=}"
        shift
        ;;
      --version)
        [[ $# -ge 2 ]] || die "Missing value for --version"
        VERSION="$2"
        shift 2
        ;;
      --version=*)
        VERSION="${1#*=}"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

validate_system_username() {
  local username="$1"
  [[ "${username}" != "root" ]] || die "Invalid --username: 'root' is not allowed"
  [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid --username for Linux user. Use lowercase letters, numbers, _ or -, start with a letter/_ and max 32 chars"
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "Invalid --port value: must be a number"
  (( port >= 1 && port <= 65535 )) || die "Invalid --port value: must be between 1 and 65535"
}

normalize_panel_path() {
  local raw="$1"
  local path="${raw#/}"
  path="${path%/}"

  if [[ -z "${path}" ]]; then
    echo "/"
    return 0
  fi

  if [[ "${path}" == *".."* ]]; then
    die "Invalid --path value: '..' is not allowed"
  fi

  if [[ "${path}" == *"//"* ]]; then
    die "Invalid --path value: repeated '/' is not allowed"
  fi

  if [[ ! "${path}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    die "Invalid --path value. Allowed characters: letters, numbers, ., _, -, /"
  fi

  echo "${path}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|x64|amd64) echo "amd64" ;;
    i386|i486|i586|i686) echo "386" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7|armhf|arm) echo "armv7" ;;
    armv6l|armv6) echo "armv6" ;;
    armv5tel|armv5) echo "armv5" ;;
    s390x) echo "s390x" ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

latest_version() {
  local response tag
  response="$(curl -fsSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest")"
  tag="$(printf '%s\n' "${response}" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "${tag}" ]] || die "Failed to resolve latest 3x-ui release tag"
  echo "${tag}"
}

ensure_root_and_platform() {
  [[ "${EUID}" -eq 0 ]] || die "This script must run as root"
  command -v apt-get >/dev/null 2>&1 || die "This installer currently supports Debian/Ubuntu only (apt-get is required)"
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required"
}

install_dependencies() {
  log "Running apt update and installing dependencies"
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update
  run apt-get install -y --no-install-recommends curl tar ca-certificates sudo nload fzf figlet
}

create_or_update_system_user() {
  local sudoers_file="/etc/sudoers.d/90-${USERNAME}"

  log "Creating/updating Linux user '${USERNAME}' with root-like sudo access"
  if id -u "${USERNAME}" >/dev/null 2>&1; then
    log "Linux user '${USERNAME}' already exists, updating password and privileges"
  else
    run useradd -m -s /bin/bash "${USERNAME}"
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: would set Linux password for user '${USERNAME}'"
  else
    chpasswd <<<"${USERNAME}:${PASSWORD}"
  fi

  run usermod -aG sudo "${USERNAME}"
  run mkdir -p /etc/sudoers.d

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: would create '${sudoers_file}' with NOPASSWD sudo rule"
  else
    printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${USERNAME}" > "${sudoers_file}"
    chmod 440 "${sudoers_file}"
    visudo -cf "${sudoers_file}" >/dev/null
  fi
}

download_and_unpack() {
  local arch="$1"
  local version="$2"
  local archive_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${version}/x-ui-linux-${arch}.tar.gz"
  local archive_file="${TMP_DIR}/x-ui-linux-${arch}.tar.gz"

  log "Downloading 3x-ui ${version} (${arch})"
  run curl -fL -o "${archive_file}" "${archive_url}"

  log "Extracting package"
  run tar -xzf "${archive_file}" -C "${TMP_DIR}"

  if [[ "${DRY_RUN}" -eq 0 && ! -d "${TMP_DIR}/x-ui" ]]; then
    die "Unexpected archive structure: ${TMP_DIR}/x-ui not found"
  fi
}

install_files() {
  local arch="$1"

  log "Installing files to ${XUI_DIR}"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    systemctl stop x-ui >/dev/null 2>&1 || true
  else
    run systemctl stop x-ui
  fi

  run rm -rf "${XUI_DIR}"
  run mkdir -p "${XUI_DIR}"
  run cp -a "${TMP_DIR}/x-ui/." "${XUI_DIR}/"

  run chmod +x "${XUI_DIR}/x-ui" "${XUI_DIR}/x-ui.sh"

  if [[ "${arch}" == "armv5" || "${arch}" == "armv6" || "${arch}" == "armv7" ]]; then
    if [[ "${DRY_RUN}" -eq 1 || -f "${XUI_DIR}/bin/xray-linux-${arch}" ]]; then
      run mv -f "${XUI_DIR}/bin/xray-linux-${arch}" "${XUI_DIR}/bin/xray-linux-arm"
      run chmod +x "${XUI_DIR}/bin/xray-linux-arm"
    fi
  else
    run chmod +x "${XUI_DIR}/bin/xray-linux-${arch}"
  fi

  run curl -fL -o /usr/bin/x-ui "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/x-ui.sh"
  run chmod +x /usr/bin/x-ui
  run mkdir -p /var/log/x-ui
}

install_service_file() {
  local candidate=""
  if [[ -f "${XUI_DIR}/x-ui.service" ]]; then
    candidate="${XUI_DIR}/x-ui.service"
  elif [[ -f "${XUI_DIR}/x-ui.service.debian" ]]; then
    candidate="${XUI_DIR}/x-ui.service.debian"
  elif [[ -f "${XUI_DIR}/x-ui.service.rhel" ]]; then
    candidate="${XUI_DIR}/x-ui.service.rhel"
  fi

  if [[ -n "${candidate}" ]]; then
    run cp -f "${candidate}" "${XUI_SERVICE_FILE}"
  else
    warn "Service file not found in extracted package, downloading Debian unit file"
    run curl -fL -o "${XUI_SERVICE_FILE}" "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/x-ui.service.debian"
  fi

  run chown root:root "${XUI_SERVICE_FILE}"
  run chmod 644 "${XUI_SERVICE_FILE}"
  run systemctl daemon-reload
  run systemctl enable x-ui
}

configure_panel() {
  local effective_path="$1"
  local panel_port="$2"

  log "Configuring panel credentials, path, and port"
  run "${XUI_DIR}/x-ui" setting -username "${USERNAME}" -password "${PASSWORD}" -port "${panel_port}" -webBasePath "${effective_path}" -resetTwoFactor true

  log "Disabling panel SSL certificate configuration (HTTP-only by default)"
  run "${XUI_DIR}/x-ui" cert -reset

  log "Running 3x-ui database migration"
  run "${XUI_DIR}/x-ui" migrate
}

start_panel() {
  run systemctl start x-ui

  if [[ "${DRY_RUN}" -eq 0 ]]; then
    systemctl is-active --quiet x-ui || die "x-ui service is not active after start"
  fi
}

print_summary() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry run complete"
    return
  fi

  local port base_path host
  port="$("${XUI_DIR}/x-ui" setting -show true | awk '/port:/{print $2; exit}')"
  base_path="$("${XUI_DIR}/x-ui" setting -show true | awk '/webBasePath:/{print $2; exit}')"
  host="$(hostname -I 2>/dev/null | awk '{print $1}')"

  [[ -n "${port}" ]] || port="<panel-port>"
  [[ -n "${base_path}" ]] || base_path="/"
  [[ -n "${host}" ]] || host="<server-ip>"

  printf '\n'
  printf '3x-ui installation completed.\n'
  printf 'Username: %s\n' "${USERNAME}"
  printf 'Password: %s\n' "${PASSWORD}"
  printf 'SSL: disabled by default\n'
  printf 'Panel URL: http://%s:%s%s\n' "${host}" "${port}" "${base_path}"
}

main() {
  trap cleanup EXIT

  parse_args "$@"
  ensure_root_and_platform

  [[ -n "${USERNAME}" ]] || die "--username is required"
  [[ -n "${PASSWORD}" ]] || die "--password is required"
  validate_system_username "${USERNAME}"
  validate_port "${PANEL_PORT}"

  local effective_path="/"
  if [[ -n "${PANEL_PATH}" ]]; then
    effective_path="$(normalize_panel_path "${PANEL_PATH}")"
  fi

  install_dependencies
  create_or_update_system_user

  if [[ -z "${VERSION}" ]]; then
    VERSION="$(latest_version)"
  fi

  local arch
  arch="$(detect_arch)"

  if [[ "${DRY_RUN}" -eq 0 ]]; then
    TMP_DIR="$(mktemp -d)"
  else
    TMP_DIR="/tmp/3x-ui-dry-run"
  fi

  log "Installing 3x-ui version: ${VERSION}"
  log "Using panel path: ${effective_path}"
  log "Using panel port: ${PANEL_PORT}"

  download_and_unpack "${arch}" "${VERSION}"
  install_files "${arch}"
  install_service_file
  configure_panel "${effective_path}" "${PANEL_PORT}"
  start_panel
  print_summary
}

main "$@"
