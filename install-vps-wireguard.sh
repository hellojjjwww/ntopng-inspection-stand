#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ntopng-wireguard-demo}"
CAPTURE_INTERFACE="${CAPTURE_INTERFACE:-wg0}"
LOCAL_NETWORKS="${LOCAL_NETWORKS:-10.66.66.0/24,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-8088}"
NGINX_EXTRA_LISTEN_PORT="${NGINX_EXTRA_LISTEN_PORT:-8080}"
NGINX_BASIC_USER="${NGINX_BASIC_USER:-ntopadmin}"
NGINX_BASIC_PASSWORD="${NGINX_BASIC_PASSWORD:-}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_SERVER_ADDRESS="${WG_SERVER_ADDRESS:-10.66.66.1/24}"
WG_CLIENT_ADDRESS="${WG_CLIENT_ADDRESS:-10.66.66.2/32}"
WG_DNS="${WG_DNS:-1.1.1.1}"
WG_ALLOWED_IPS="${WG_ALLOWED_IPS:-0.0.0.0/0}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
CLIENT_DOWNLOAD_PATH=""

log() {
  printf '\033[1;34m[vps-demo]\033[0m %s\n' "$*"
}

fail() {
  printf '\033[1;31m[vps-demo]\033[0m %s\n' "$*" >&2
  exit 1
}

is_yes() {
  case "$1" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

read_secret() {
  local prompt="$1"
  local value=""
  read -r -s -p "${prompt}" value
  printf '\n' >&2
  printf '%s' "${value}"
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run as root."
}

detect_ubuntu() {
  [[ -r /etc/os-release ]] || fail "Cannot detect OS."
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || fail "Ubuntu LTS is expected."
}

curl_fetch() {
  local url="$1"
  local output="$2"

  if [[ -n "${GITHUB_TOKEN}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "${url}" -o "${output}"
  else
    curl -fsSL "${url}" -o "${output}"
  fi
}

install_packages() {
  log "Installing required packages."
  apt-get update
  apt-get install -y ca-certificates curl gnupg openssl iproute2 iptables ufw wireguard wireguard-tools

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker already installed."
    return
  fi

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release
  local codename
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

detect_public_interface() {
  PUBLIC_INTERFACE="${PUBLIC_INTERFACE:-$(ip route show default 2>/dev/null | awk '{print $5; exit}')}"
  [[ -n "${PUBLIC_INTERFACE}" ]] || fail "Cannot detect public network interface."
}

detect_public_ip() {
  if [[ -n "${SERVER_PUBLIC_IP}" ]]; then
    return
  fi

  SERVER_PUBLIC_IP="$(curl -fsS4 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
    SERVER_PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -n "${SERVER_PUBLIC_IP}" ]] || fail "Cannot detect public IP. Set SERVER_PUBLIC_IP and rerun."
}

generate_password() {
  if [[ -z "${NGINX_BASIC_PASSWORD}" ]]; then
    NGINX_BASIC_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/[:space:]' | cut -c1-18)"
  fi
}

configure_panel_credentials() {
  if [[ -n "${NGINX_BASIC_PASSWORD}" ]]; then
    return
  fi

  if [[ ! -t 0 || "${NTOPNG_NONINTERACTIVE:-0}" == "1" ]]; then
    return
  fi

  printf '\n'
  printf 'Panel credentials\n'
  printf 'Default mode creates a random password for user "%s".\n' "${NGINX_BASIC_USER}"

  local answer=""
  read -r -p "Set custom panel login and password? [y/N]: " answer
  if ! is_yes "${answer}"; then
    return
  fi

  local input_user=""
  while true; do
    read -r -p "Panel username [${NGINX_BASIC_USER}]: " input_user
    input_user="${input_user:-${NGINX_BASIC_USER}}"
    if [[ "${input_user}" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
      NGINX_BASIC_USER="${input_user}"
      break
    fi
    printf 'Use 3-32 characters: letters, digits, dot, underscore or dash.\n'
  done

  local pass1="" pass2=""
  while true; do
    pass1="$(read_secret "Panel password: ")"
    if [[ -z "${pass1}" ]]; then
      printf 'Password cannot be empty.\n'
      continue
    fi
    if [[ ! "${pass1}" =~ ^[A-Za-z0-9._~!@#%+=,-]{8,64}$ ]]; then
      printf 'Use 8-64 characters without spaces or quotes.\n'
      continue
    fi
    pass2="$(read_secret "Repeat password: ")"
    if [[ "${pass1}" == "${pass2}" ]]; then
      NGINX_BASIC_PASSWORD="${pass1}"
      break
    fi
    printf 'Passwords do not match. Try again.\n'
  done
}

fetch_project_files() {
  log "Installing project files into ${INSTALL_DIR}."
  install -d \
    "${INSTALL_DIR}/config/ntopng/locales" \
    "${INSTALL_DIR}/config/redis" \
    "${INSTALL_DIR}/config/nginx" \
    "${INSTALL_DIR}/config/zeek" \
    "${INSTALL_DIR}/deploy/scripts/tests" \
    "${INSTALL_DIR}/geoip" \
    "${INSTALL_DIR}/scripts" \
    "${INSTALL_DIR}/tests" \
    "${INSTALL_DIR}/docs"

  local files=(
    ".env.example"
    ".gitignore"
    "Makefile"
    "README.md"
    "LICENSE.txt"
    "install.sh"
    "install-vps-wireguard.sh"
    "deploy/docker-compose.yml"
    "deploy/docker-compose.desktop.yml"
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
    "docs/operations.md"
    "docs/architecture.md"
    "docs/deployment.md"
    "docs/testing.md"
    "docs/alerts.md"
    "docs/demo_scenario.md"
    "docs/wireguard_vps_demo.md"
  )

  local file
  for file in "${files[@]}"; do
    curl_fetch "${REPO_RAW}/${file}" "${INSTALL_DIR}/${file}"
  done

  chmod +x "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/install-vps-wireguard.sh"
  chmod +x "${INSTALL_DIR}/scripts/"*.sh
  chmod +x "${INSTALL_DIR}/deploy/scripts/tests/"*.sh
}

write_env() {
  cat >"${INSTALL_DIR}/.env" <<EOF
CAPTURE_INTERFACE=${CAPTURE_INTERFACE}
LOCAL_NETWORKS=${LOCAL_NETWORKS}
NGINX_LISTEN_PORT=${NGINX_LISTEN_PORT}
NGINX_EXTRA_LISTEN_PORT=${NGINX_EXTRA_LISTEN_PORT}
NGINX_BASIC_USER=${NGINX_BASIC_USER}
NGINX_BASIC_PASSWORD=${NGINX_BASIC_PASSWORD}
NTOPNG_MAX_NUM_FLOWS=200000
NTOPNG_MAX_NUM_HOSTS=25000
EOF

  local password_hash
  password_hash="$(openssl passwd -apr1 "${NGINX_BASIC_PASSWORD}")"
  printf '%s:%s\n' "${NGINX_BASIC_USER}" "${password_hash}" >"${INSTALL_DIR}/config/nginx/.htpasswd"
  chmod 600 "${INSTALL_DIR}/.env"
  chmod 644 "${INSTALL_DIR}/config/nginx/.htpasswd"
}

configure_wireguard() {
  log "Configuring WireGuard."
  install -d -m 700 /etc/wireguard "${INSTALL_DIR}/wireguard"

  local server_private server_public client_private client_public
  server_private="$(wg genkey)"
  server_public="$(printf '%s' "${server_private}" | wg pubkey)"
  client_private="$(wg genkey)"
  client_public="$(printf '%s' "${client_private}" | wg pubkey)"

  cat >/etc/wireguard/${WG_INTERFACE}.conf <<EOF
[Interface]
Address = ${WG_SERVER_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${server_private}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUBLIC_INTERFACE} -j MASQUERADE

[Peer]
PublicKey = ${client_public}
AllowedIPs = ${WG_CLIENT_ADDRESS}
EOF

  cat >"${INSTALL_DIR}/wireguard/client.conf" <<EOF
[Interface]
PrivateKey = ${client_private}
Address = ${WG_CLIENT_ADDRESS}
DNS = ${WG_DNS}

[Peer]
PublicKey = ${server_public}
Endpoint = ${SERVER_PUBLIC_IP}:${WG_PORT}
AllowedIPs = ${WG_ALLOWED_IPS}
PersistentKeepalive = 25
EOF

  chmod 600 /etc/wireguard/${WG_INTERFACE}.conf "${INSTALL_DIR}/wireguard/client.conf"
}

publish_client_config() {
  local target_user="${SUDO_USER:-root}"
  local target_home=""

  if [[ "${target_user}" != "root" ]]; then
    target_home="$(getent passwd "${target_user}" | cut -d: -f6 || true)"
  fi
  target_home="${target_home:-/root}"

  CLIENT_DOWNLOAD_PATH="${target_home}/ntopng-wireguard-client.conf"
  cp "${INSTALL_DIR}/wireguard/client.conf" "${CLIENT_DOWNLOAD_PATH}"
  chmod 600 "${CLIENT_DOWNLOAD_PATH}"
  if [[ "${target_user}" != "root" ]]; then
    chown "${target_user}:${target_user}" "${CLIENT_DOWNLOAD_PATH}" 2>/dev/null || true
  fi
}

configure_network() {
  log "Enabling routing and firewall rules."
  cat >/etc/sysctl.d/99-ntopng-wireguard-demo.conf <<EOF
net.ipv4.ip_forward=1
EOF
  sysctl --system >/dev/null

  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH || true
  ufw allow "${WG_PORT}/udp"
  ufw allow "${NGINX_LISTEN_PORT}/tcp"
  if [[ -n "${NGINX_EXTRA_LISTEN_PORT}" ]]; then
    ufw allow "${NGINX_EXTRA_LISTEN_PORT}/tcp"
  fi
  ufw --force enable
}

start_services() {
  log "Starting WireGuard and Docker stack."
  systemctl enable --now "wg-quick@${WG_INTERFACE}"
  cd "${INSTALL_DIR}"
  docker compose --env-file .env -f deploy/docker-compose.yml up -d
}

print_summary() {
  local extra_url=""
  if [[ -n "${NGINX_EXTRA_LISTEN_PORT}" ]]; then
    extra_url="  http://${SERVER_PUBLIC_IP}:${NGINX_EXTRA_LISTEN_PORT}/"
  fi

  cat <<EOF

VPS demo deployment completed.

ntopng URLs:
  http://${SERVER_PUBLIC_IP}:${NGINX_LISTEN_PORT}/
${extra_url}

Basic Auth:
  username: ${NGINX_BASIC_USER}
  password: ${NGINX_BASIC_PASSWORD}

WireGuard client config:
  ${INSTALL_DIR}/wireguard/client.conf
  ${CLIENT_DOWNLOAD_PATH}

Termius:
  Open SFTP file browser and download:
  ${CLIENT_DOWNLOAD_PATH}

scp:
  scp ${SUDO_USER:-root}@${SERVER_PUBLIC_IP}:${CLIENT_DOWNLOAD_PATH} ./ntopng-wireguard-client.conf

Useful commands:
  cd ${INSTALL_DIR}
  docker compose --env-file .env -f deploy/docker-compose.yml ps
  scripts/doctor.sh
  systemctl status wg-quick@${WG_INTERFACE}

Traffic capture interface:
  ${CAPTURE_INTERFACE}

WireGuard test client config:
-----BEGIN WG CLIENT CONFIG-----
$(cat "${INSTALL_DIR}/wireguard/client.conf")
-----END WG CLIENT CONFIG-----
EOF
}

main() {
  need_root
  detect_ubuntu
  install_packages
  detect_public_interface
  detect_public_ip
  configure_panel_credentials
  generate_password
  fetch_project_files
  write_env
  configure_wireguard
  publish_client_config
  configure_network
  start_services
  print_summary
}

main "$@"
