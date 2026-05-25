#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ntopng-inspection-stand}"
NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-8088}"
NGINX_BASIC_USER="${NGINX_BASIC_USER:-ntopadmin}"
NGINX_BASIC_PASSWORD="${NGINX_BASIC_PASSWORD:-}"
CAPTURE_INTERFACE="${CAPTURE_INTERFACE:-}"
LOCAL_NETWORKS="${LOCAL_NETWORKS:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

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
  apt-get install -y ca-certificates curl gnupg openssl
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

fetch_project_files() {
  log "Installing project files into ${INSTALL_DIR}."
  install -d "${INSTALL_DIR}/ntopng" "${INSTALL_DIR}/redis" "${INSTALL_DIR}/nginx" \
    "${INSTALL_DIR}/geoip" "${INSTALL_DIR}/scripts" "${INSTALL_DIR}/tests" "${INSTALL_DIR}/docs"

  local files=(
    "docker-compose.yml"
    ".env.example"
    ".gitignore"
    "README.md"
    "ntopng/ntopng.conf"
    "redis/redis.conf"
    "nginx/default.conf.template"
    "scripts/generate_anomaly.py"
    "scripts/prepare_htpasswd.py"
    "tests/requirements.txt"
    "docs/OPERATIONS.md"
    "docs/ARCHITECTURE.md"
  )

  local file
  for file in "${files[@]}"; do
    curl -fsSL "${REPO_RAW}/${file}" -o "${INSTALL_DIR}/${file}"
  done
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
  printf '%s:%s\n' "${NGINX_BASIC_USER}" "${password_hash}" >"${INSTALL_DIR}/nginx/.htpasswd"
  chmod 600 "${INSTALL_DIR}/.env" "${INSTALL_DIR}/nginx/.htpasswd"
}

start_stack() {
  log "Starting containers."
  cd "${INSTALL_DIR}"
  docker compose up -d
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
  docker compose ps
  docker compose logs -f ntopng
  docker compose restart

Notes:
  ntopng's own login is disabled. Nginx Basic Auth is the access boundary.
  Capture interface: ${CAPTURE_INTERFACE}
EOF
}

main() {
  need_root
  detect_ubuntu
  install_docker
  detect_interface
  generate_password
  fetch_project_files
  write_runtime_config
  start_stack
  print_summary
}

main "$@"
