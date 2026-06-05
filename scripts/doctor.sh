#!/usr/bin/env bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
DESKTOP_COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.desktop.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
USE_DESKTOP_OVERRIDE="${USE_DESKTOP_OVERRIDE:-0}"

CHECKS_FAILED=0
CHECKS_WARNED=0

info() {
  printf '[INFO] %s\n' "$*"
}

pass() {
  printf '[ OK ] %s\n' "$*"
}

warn() {
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  printf '[FAIL] %s\n' "$*"
}

compose() {
  local args=()
  if [[ -f "${ENV_FILE}" ]]; then
    args+=(--env-file "${ENV_FILE}")
  fi
  args+=(-f "${COMPOSE_FILE}")
  if [[ "${USE_DESKTOP_OVERRIDE}" == "1" ]]; then
    args+=(-f "${DESKTOP_COMPOSE_FILE}")
  fi
  docker compose "${args[@]}" "$@"
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a && . "${ENV_FILE}" && set +a
    pass ".env loaded"
  else
    warn ".env is missing; copy .env.example to .env before manual deployment"
  fi

  NGINX_LISTEN_PORT="${NGINX_LISTEN_PORT:-8088}"
  NGINX_BASIC_USER="${NGINX_BASIC_USER:-ntopadmin}"
  NGINX_BASIC_PASSWORD="${NGINX_BASIC_PASSWORD:-}"
  CAPTURE_INTERFACE="${CAPTURE_INTERFACE:-eth0}"
}

check_command() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    pass "command found: ${name}"
  else
    fail "command missing: ${name}"
  fi
}

check_docker() {
  if docker version >/dev/null 2>&1; then
    pass "Docker daemon is reachable"
  else
    fail "Docker daemon is not reachable"
    return
  fi

  if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose plugin is available"
  else
    fail "Docker Compose plugin is missing"
  fi
}

check_compose_config() {
  if compose config --quiet >/dev/null 2>&1; then
    pass "Compose configuration is valid"
  else
    fail "Compose configuration is invalid"
  fi
}

check_runtime_files() {
  [[ -f "${PROJECT_ROOT}/config/nginx/.htpasswd" ]] \
    && pass "Nginx Basic Auth file exists" \
    || fail "Nginx Basic Auth file is missing"

  [[ -d "${PROJECT_ROOT}/geoip" ]] \
    && pass "GeoIP directory exists" \
    || warn "GeoIP directory is missing"
}

check_interface() {
  if command -v ip >/dev/null 2>&1; then
    if ip link show "${CAPTURE_INTERFACE}" >/dev/null 2>&1; then
      pass "capture interface exists: ${CAPTURE_INTERFACE}"
    else
      warn "capture interface is not visible on this host: ${CAPTURE_INTERFACE}"
    fi
  else
    warn "ip command is unavailable; interface check skipped"
  fi
}

check_port() {
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -Eq "[:.]${NGINX_LISTEN_PORT}$"; then
      pass "port ${NGINX_LISTEN_PORT}/tcp is listening"
    else
      warn "port ${NGINX_LISTEN_PORT}/tcp is not listening"
    fi
  else
    warn "ss command is unavailable; port check skipped"
  fi
}

check_containers() {
  if ! compose ps >/dev/null 2>&1; then
    fail "Compose services are not available"
    return
  fi

  local service
  for service in redis ntopng zeek nginx; do
    if compose ps --status running --services 2>/dev/null | grep -qx "${service}"; then
      pass "service is running: ${service}"
    else
      fail "service is not running: ${service}"
    fi
  done
}

check_http_path() {
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl is unavailable; HTTP checks skipped"
    return
  fi

  local base_url status_code
  base_url="${BASE_URL:-http://127.0.0.1:${NGINX_LISTEN_PORT}/}"
  status_code="$(curl -sS -o /dev/null -w '%{http_code}' "${base_url}" 2>/dev/null || true)"

  if [[ "${status_code}" == "401" ]]; then
    pass "unauthenticated access is blocked by Nginx"
  else
    warn "expected HTTP 401 without credentials, got ${status_code:-no response}"
  fi

  if [[ -n "${NGINX_BASIC_PASSWORD}" ]]; then
    status_code="$(curl -sS -o /dev/null -w '%{http_code}' \
      -u "${NGINX_BASIC_USER}:${NGINX_BASIC_PASSWORD}" "${base_url}" 2>/dev/null || true)"
    if [[ "${status_code}" =~ ^(200|302)$ ]]; then
      pass "authenticated access reaches ntopng"
    else
      warn "authenticated HTTP check returned ${status_code:-no response}"
    fi
  else
    warn "NGINX_BASIC_PASSWORD is not set; authenticated HTTP check skipped"
  fi
}

print_summary() {
  printf '\nDoctor summary: %s failed, %s warnings.\n' "${CHECKS_FAILED}" "${CHECKS_WARNED}"
  [[ "${CHECKS_FAILED}" -eq 0 ]]
}

main() {
  info "Project root: ${PROJECT_ROOT}"
  load_env
  check_command docker
  check_command curl
  check_docker
  check_compose_config
  check_runtime_files
  check_interface
  check_port
  check_containers
  check_http_path
  print_summary
}

main "$@"
