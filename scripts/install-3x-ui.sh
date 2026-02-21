#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="MHSanaei"
REPO_NAME="3x-ui"
XUI_DIR="/usr/local/x-ui"
XUI_SERVICE_FILE="/etc/systemd/system/x-ui.service"

COMMON_USERNAME=""
COMMON_PASSWORD=""
PANEL_USERNAME=""
PANEL_PASSWORD=""
SYSTEM_USERNAME=""
SYSTEM_PASSWORD=""
PANEL_PATH=""
PANEL_PORT="2053"
VERSION=""
DRY_RUN=0
FORCE_REINSTALL=0
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage:
  install-3x-ui.sh [credential options] [other options]

Credential options:
  --username <value>       Shared username for both panel and Linux user
  --password <value>       Shared password for both panel and Linux user
  --panel-username <value> Panel username (can differ from Linux user)
  --panel-password <value> Panel password (can differ from Linux user)
  --server-username <value> Linux username with sudo privileges
  --server-password <value> Linux user password

Notes:
  - You can use shared credentials via --username/--password.
  - Or set panel and Linux credentials separately.

Optional:
  --path <value>           Panel URL path (e.g. panel or admin/panel)
                           Default: root path (no custom path)
  --port <value>           Panel port
                           Default: 2053
  --version <value>        3x-ui release tag (e.g. v2.6.5)
                           Default: latest release
  --force                  Force reinstall even if 3x-ui is already healthy
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
        COMMON_USERNAME="$2"
        shift 2
        ;;
      --username=*)
        COMMON_USERNAME="${1#*=}"
        shift
        ;;
      --password)
        [[ $# -ge 2 ]] || die "Missing value for --password"
        COMMON_PASSWORD="$2"
        shift 2
        ;;
      --password=*)
        COMMON_PASSWORD="${1#*=}"
        shift
        ;;
      --panel-username)
        [[ $# -ge 2 ]] || die "Missing value for --panel-username"
        PANEL_USERNAME="$2"
        shift 2
        ;;
      --panel-username=*)
        PANEL_USERNAME="${1#*=}"
        shift
        ;;
      --panel-password)
        [[ $# -ge 2 ]] || die "Missing value for --panel-password"
        PANEL_PASSWORD="$2"
        shift 2
        ;;
      --panel-password=*)
        PANEL_PASSWORD="${1#*=}"
        shift
        ;;
      --server-username)
        [[ $# -ge 2 ]] || die "Missing value for --server-username"
        SYSTEM_USERNAME="$2"
        shift 2
        ;;
      --server-username=*)
        SYSTEM_USERNAME="${1#*=}"
        shift
        ;;
      --server-password)
        [[ $# -ge 2 ]] || die "Missing value for --server-password"
        SYSTEM_PASSWORD="$2"
        shift 2
        ;;
      --server-password=*)
        SYSTEM_PASSWORD="${1#*=}"
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
      --force)
        FORCE_REINSTALL=1
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

resolve_credentials() {
  if [[ -n "${COMMON_USERNAME}" ]]; then
    [[ -n "${PANEL_USERNAME}" ]] || PANEL_USERNAME="${COMMON_USERNAME}"
    [[ -n "${SYSTEM_USERNAME}" ]] || SYSTEM_USERNAME="${COMMON_USERNAME}"
  fi

  if [[ -n "${COMMON_PASSWORD}" ]]; then
    [[ -n "${PANEL_PASSWORD}" ]] || PANEL_PASSWORD="${COMMON_PASSWORD}"
    [[ -n "${SYSTEM_PASSWORD}" ]] || SYSTEM_PASSWORD="${COMMON_PASSWORD}"
  fi

  [[ -n "${PANEL_USERNAME}" ]] || die "Missing panel username. Use --panel-username or --username"
  [[ -n "${PANEL_PASSWORD}" ]] || die "Missing panel password. Use --panel-password or --password"
  [[ -n "${SYSTEM_USERNAME}" ]] || die "Missing server username. Use --server-username or --username"
  [[ -n "${SYSTEM_PASSWORD}" ]] || die "Missing server password. Use --server-password or --password"
}

validate_system_username() {
  local username="$1"
  [[ "${username}" != "root" ]] || die "Invalid --server-username: 'root' is not allowed"
  [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid --server-username for Linux user. Use lowercase letters, numbers, _ or -, start with a letter/_ and max 32 chars"
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

is_panel_healthy() {
  [[ -x "${XUI_DIR}/x-ui" ]] || return 1
  systemctl is-active --quiet x-ui >/dev/null 2>&1 || return 1
  "${XUI_DIR}/x-ui" setting -show true >/dev/null 2>&1 || return 1
  return 0
}

ensure_ssh_password_auth_enabled() {
  local files=()
  local file=""
  local found_yes=0
  local changed=0
  local dropin_file="/etc/ssh/sshd_config.d/99-enable-password-auth.conf"

  [[ -f /etc/ssh/sshd_config ]] && files+=("/etc/ssh/sshd_config")
  if [[ -d /etc/ssh/sshd_config.d ]]; then
    while IFS= read -r -d '' file; do
      files+=("${file}")
    done < <(find /etc/ssh/sshd_config.d -maxdepth 1 -type f -name "*.conf" -print0 | sort -z)
  fi

  log "Ensuring SSH password authentication is enabled"

  for file in "${files[@]}"; do
    if grep -Eiq '^[[:space:]]*PasswordAuthentication[[:space:]]+yes([[:space:]]|$)' "${file}"; then
      found_yes=1
    fi

    if grep -Eiq '^[[:space:]]*PasswordAuthentication[[:space:]]+no([[:space:]]|$)' "${file}"; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "DRY-RUN: would update '${file}' to set PasswordAuthentication yes"
      else
        cp -a "${file}" "${file}.bak.codex"
        sed -Ei 's/^[[:space:]]*PasswordAuthentication[[:space:]]+no([[:space:]]*(#.*)?)?$/PasswordAuthentication yes\1/I' "${file}"
      fi
      changed=1
      found_yes=1
    fi
  done

  if [[ "${found_yes}" -eq 0 ]]; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "DRY-RUN: would create '${dropin_file}' with PasswordAuthentication yes"
    else
      mkdir -p /etc/ssh/sshd_config.d
      printf 'PasswordAuthentication yes\n' > "${dropin_file}"
      chmod 644 "${dropin_file}"
    fi
    changed=1
  fi

  if [[ "${changed}" -eq 0 ]]; then
    log "SSH password authentication is already enabled; no SSH config changes needed"
    return 0
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: would validate SSH config and reload SSH service"
    return 0
  fi

  if command -v sshd >/dev/null 2>&1; then
    sshd -t || die "sshd config validation failed after updating PasswordAuthentication"
  fi

  if systemctl reload ssh >/dev/null 2>&1; then
    log "Reloaded ssh service"
  elif systemctl restart ssh >/dev/null 2>&1; then
    log "Restarted ssh service"
  elif systemctl reload sshd >/dev/null 2>&1; then
    log "Reloaded sshd service"
  elif systemctl restart sshd >/dev/null 2>&1; then
    log "Restarted sshd service"
  else
    warn "Could not reload/restart SSH service automatically; please run: systemctl restart ssh"
  fi
}

install_dependencies() {
  log "Running apt update and installing dependencies"
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update
  run apt-get install -y --no-install-recommends curl tar ca-certificates sudo nload fzf figlet
}

create_or_update_system_user() {
  local username="$1"
  local password="$2"
  local sudoers_file="/etc/sudoers.d/90-${username}"

  log "Creating/updating Linux user '${username}' with root-like sudo access"
  if id -u "${username}" >/dev/null 2>&1; then
    log "Linux user '${username}' already exists, updating password and privileges"
  else
    run useradd -m -s /bin/bash "${username}"
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: would set Linux password for user '${username}'"
  else
    chpasswd <<<"${username}:${password}"
  fi

  run usermod -aG sudo "${username}"
  run mkdir -p /etc/sudoers.d

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: would create '${sudoers_file}' with NOPASSWD sudo rule"
  else
    printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${username}" > "${sudoers_file}"
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
  local panel_username="$1"
  local panel_password="$2"
  local effective_path="$3"
  local panel_port="$4"

  log "Configuring panel credentials, path, and port"
  run "${XUI_DIR}/x-ui" setting -username "${panel_username}" -password "${panel_password}" -port "${panel_port}" -webBasePath "${effective_path}" -resetTwoFactor true

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

  local settings port base_path host
  settings="$("${XUI_DIR}/x-ui" setting -show true 2>/dev/null || true)"
  port="$(printf '%s\n' "${settings}" | awk '/^port:[[:space:]]/{print $2}')"
  base_path="$(printf '%s\n' "${settings}" | awk '/^webBasePath:[[:space:]]/{print $2}')"
  host="$(hostname -I 2>/dev/null || true)"
  host="${host%% *}"

  [[ -n "${port}" ]] || port="<panel-port>"
  [[ -n "${base_path}" ]] || base_path="/"
  [[ -n "${host}" ]] || host="<server-ip>"

  printf '\n'
  printf '3x-ui installation completed.\n'
  printf 'Panel Username: %s\n' "${PANEL_USERNAME}"
  printf 'Panel Password: %s\n' "${PANEL_PASSWORD}"
  printf 'Server Username: %s\n' "${SYSTEM_USERNAME}"
  printf 'Server Password: %s\n' "${SYSTEM_PASSWORD}"
  printf 'SSL: disabled by default\n'
  printf 'Panel URL: http://%s:%s%s\n' "${host}" "${port}" "${base_path}"
}

main() {
  trap cleanup EXIT

  parse_args "$@"
  ensure_root_and_platform

  resolve_credentials
  validate_system_username "${SYSTEM_USERNAME}"
  validate_port "${PANEL_PORT}"

  local effective_path="/"
  if [[ -n "${PANEL_PATH}" ]]; then
    effective_path="$(normalize_panel_path "${PANEL_PATH}")"
  fi

  install_dependencies
  create_or_update_system_user "${SYSTEM_USERNAME}" "${SYSTEM_PASSWORD}"
  ensure_ssh_password_auth_enabled

  if [[ "${FORCE_REINSTALL}" -eq 0 ]] && is_panel_healthy; then
    log "3x-ui is already installed and running healthy; skipping reinstall."
    log "Use --force if you want to reinstall anyway."
    exit 0
  fi

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
  log "Using panel username: ${PANEL_USERNAME}"
  log "Using server username: ${SYSTEM_USERNAME}"

  download_and_unpack "${arch}" "${VERSION}"
  install_files "${arch}"
  install_service_file
  configure_panel "${PANEL_USERNAME}" "${PANEL_PASSWORD}" "${effective_path}" "${PANEL_PORT}"
  start_panel
  print_summary
}

main "$@"
