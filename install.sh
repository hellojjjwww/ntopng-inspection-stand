#!/usr/bin/env bash
# @file install.sh
# @brief Bootstrap script for deploying the ntopng traffic inspection stand on Ubuntu LTS.
# @details
#   1. Validates the target operating system.
#   2. Installs Docker Engine and Docker Compose plugin when missing.
#   3. Downloads project configuration from the Git repository.
#   4. Generates local runtime secrets outside Git.
#   5. Enables a restrictive UFW policy and starts the container stack.
# @version 1.1.0
# @license MIT
set -Eeuo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ntopng-inspection-stand}"
NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-8088}"
NGINX_BASIC_USER="${NGINX_BASIC_USER:-ntopadmin}"
NGINX_BASIC_PASSWORD="${NGINX_BASIC_PASSWORD:-}"
CAPTURE_INTERFACE="${CAPTURE_INTERFACE:-}"
LOCAL_NETWORKS="${LOCAL_NETWORKS:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
ALLOW_WEAK_PASSWORD="${ALLOW_WEAK_PASSWORD:-0}"
INSTALL_SYSTEMD_SERVICE="${INSTALL_SYSTEMD_SERVICE:-1}"

log() {
  printf '\033[1;34m[ntopng-stand]\033[0m %s\n' "$*"
}

fail() {
  printf '\033[1;31m[ntopng-stand]\033[0m %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root: sudo bash <(curl -Ls ${REPO_RAW}/install.sh)"
  fi
}

detect_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    fail "Cannot detect OS. Ubuntu 24.04 LTS is expected."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Unsupported OS '${ID:-unknown}'. Use Ubuntu LTS, preferably 24.04."
  fi

  case "${VERSION_ID:-}" in
    22.04|24.04|26.04) ;;
    *) log "Warning: Ubuntu ${VERSION_ID:-unknown} is not explicitly tested. Continuing." ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Compose plugin already installed."
    return
  fi

  log "Installing Docker Engine from the official Docker apt repository."
  apt-get update
  apt-get install -y ca-certificates curl gnupg openssl iproute2
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  # shellcheck disable=SC1091
  . /etc/os-release
  codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  [[ -n "${codename}" ]] || fail "Cannot detect Ubuntu codename."

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

configure_firewall() {
  log "Configuring UFW firewall policy."
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH || true
  ufw allow "${NGINX_LISTEN_PORT}/tcp"
  ufw --force enable
}

check_host_resources() {
  local mem_kb disk_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
  disk_kb="$(df -Pk "${INSTALL_DIR%/*}" 2>/dev/null | awk 'NR == 2 {print $4}')"

  if [[ "${mem_kb:-0}" -lt 1900000 ]]; then
    log "Warning: less than 2 GB RAM detected. Use conservative retention settings."
  fi

  if [[ "${disk_kb:-0}" -lt 5242880 ]]; then
    log "Warning: less than 5 GB free disk space detected. Zeek and ntopng logs may fill the disk quickly."
  fi
}

check_port_available() {
  if command -v ss >/dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -Eq "[:.]${NGINX_LISTEN_PORT}$"; then
    fail "TCP port ${NGINX_LISTEN_PORT} is already in use. Set NGINX_LISTEN_PORT=<port> and rerun."
  fi
}

detect_interface() {
  if [[ -n "${CAPTURE_INTERFACE}" ]]; then
    return
  fi

  CAPTURE_INTERFACE="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
  if [[ -z "${CAPTURE_INTERFACE}" ]]; then
    CAPTURE_INTERFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')"
  fi
  [[ -n "${CAPTURE_INTERFACE}" ]] || fail "Cannot detect capture interface. Set CAPTURE_INTERFACE=eth0 and rerun."
}

generate_password() {
  if [[ -z "${NGINX_BASIC_PASSWORD}" ]]; then
    NGINX_BASIC_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-18)"
  fi
}

validate_password_strength() {
  if [[ "${ALLOW_WEAK_PASSWORD}" == "1" ]]; then
    log "Weak password check is disabled by ALLOW_WEAK_PASSWORD=1."
    return
  fi

  if [[ "${#NGINX_BASIC_PASSWORD}" -lt 12 ]]; then
    fail "NGINX_BASIC_PASSWORD must be at least 12 characters. Set ALLOW_WEAK_PASSWORD=1 only for isolated lab tests."
  fi

  case "${NGINX_BASIC_PASSWORD}" in
    change-me-now|password|admin|ntoplab|ntopng|123456789012)
      fail "NGINX_BASIC_PASSWORD is too common. Use a stronger value."
      ;;
  esac
}

fetch_project_files() {
  log "Installing project files into ${INSTALL_DIR}."
  install -d "${INSTALL_DIR}/config/ntopng" "${INSTALL_DIR}/config/redis" \
    "${INSTALL_DIR}/config/nginx" "${INSTALL_DIR}/config/zeek" \
    "${INSTALL_DIR}/deploy/scripts/tests" "${INSTALL_DIR}/geoip" "${INSTALL_DIR}/scripts" \
    "${INSTALL_DIR}/tests" "${INSTALL_DIR}/docs" "${INSTALL_DIR}/.github/workflows"

  local files=(
    "deploy/docker-compose.yml"
    ".env.example"
    ".gitignore"
    "Makefile"
    "README.md"
    "LICENSE.txt"
    "install.sh"
    "config/ntopng/ntopng.conf"
    "config/ntopng/locales/ru.lua"
    "config/redis/redis.conf"
    "config/nginx/default.conf.template"
    "config/zeek/local.zeek"
    "scripts/generate_anomaly.py"
    "scripts/prepare_htpasswd.py"
    "scripts/setup_geolite2.sh"
    "scripts/doctor.sh"
    "scripts/backup.sh"
    "scripts/enable_russian_ui.sh"
    "tests/requirements.txt"
    "deploy/scripts/tests/validate_stack.sh"
    "deploy/scripts/tests/collect_evidence.sh"
    ".github/workflows/pr-validation.yml"
    "docs/operations.md"
    "docs/architecture.md"
    "docs/deployment.md"
    "docs/testing.md"
    "docs/alerts.md"
    "docs/demo_scenario.md"
  )

  local file
  for file in "${files[@]}"; do
    curl -fsSL "${REPO_RAW}/${file}" -o "${INSTALL_DIR}/${file}"
  done

  chmod +x "${INSTALL_DIR}/install.sh" 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/scripts/"*.sh
  chmod +x "${INSTALL_DIR}/deploy/scripts/tests/"*.sh
}

write_runtime_config() {
  log "Writing runtime configuration."
  cat >"${INSTALL_DIR}/.env" <<EOF
CAPTURE_INTERFACE=${CAPTURE_INTERFACE}
LOCAL_NETWORKS=${LOCAL_NETWORKS}
NGINX_LISTEN_PORT=${NGINX_LISTEN_PORT}
NGINX_BASIC_USER=${NGINX_BASIC_USER}
NGINX_BASIC_PASSWORD=${NGINX_BASIC_PASSWORD}
NTOPNG_MAX_NUM_FLOWS=200000
NTOPNG_MAX_NUM_HOSTS=25000
EOF

  local password_hash
  password_hash="$(openssl passwd -apr1 "${NGINX_BASIC_PASSWORD}")"
  printf '%s:%s\n' "${NGINX_BASIC_USER}" "${password_hash}" >"${INSTALL_DIR}/config/nginx/.htpasswd"
  chmod 600 "${INSTALL_DIR}/.env" "${INSTALL_DIR}/config/nginx/.htpasswd"
}

start_stack() {
  log "Starting containers."
  cd "${INSTALL_DIR}"
  docker compose -f deploy/docker-compose.yml up -d
}

write_systemd_unit() {
  if [[ "${INSTALL_SYSTEMD_SERVICE}" != "1" ]]; then
    return
  fi

  log "Writing systemd unit."
  cat >/etc/systemd/system/ntopng-inspection-stand.service <<EOF
[Unit]
Description=ntopng inspection stand
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose -f deploy/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f deploy/docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ntopng-inspection-stand.service
}

print_summary() {
  local host_ip
  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "${host_ip}" ]] || host_ip="<server-ip>"

  cat <<EOF

Installation complete.

URL:
  http://${host_ip}:${NGINX_LISTEN_PORT}/

Basic Auth:
  username: ${NGINX_BASIC_USER}
  password: ${NGINX_BASIC_PASSWORD}

Useful commands:
  cd ${INSTALL_DIR}
  docker compose -f deploy/docker-compose.yml ps
  scripts/doctor.sh
  scripts/backup.sh
  docker compose -f deploy/docker-compose.yml logs -f ntopng
  docker compose -f deploy/docker-compose.yml logs -f zeek
  docker compose -f deploy/docker-compose.yml restart

Notes:
  ntopng's own login is disabled. Nginx Basic Auth is the access boundary.
  Zeek writes JSON logs to the zeek-logs Docker volume.
  Capture interface: ${CAPTURE_INTERFACE}
EOF
}

main() {
  need_root
  detect_ubuntu
  install_docker
  check_host_resources
  detect_interface
  generate_password
  validate_password_strength
  check_port_available
  fetch_project_files
  write_runtime_config
  configure_firewall
  write_systemd_unit
  start_stack
  print_summary
}

main "$@"
