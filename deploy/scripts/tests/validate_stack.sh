#!/usr/bin/env bash
# @file validate_stack.sh
# @brief Validate the local Docker Compose stack and HTTP access path.
# @details
#   1. Checks Docker Compose service state.
#   2. Verifies that Nginx protects the UI with Basic Auth.
#   3. Verifies that authenticated access reaches ntopng.
# @version 1.0.0
# @license MIT
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
DESKTOP_COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.desktop.yml"
BASE_URL="${BASE_URL:-http://127.0.0.1:8088/}"
NGINX_BASIC_USER="${NGINX_BASIC_USER:-ntopadmin}"
NGINX_BASIC_PASSWORD="${NGINX_BASIC_PASSWORD:-ntoplab}"

compose() {
    if [[ "${USE_DESKTOP_OVERRIDE:-0}" == "1" ]]; then
        docker compose -f "${COMPOSE_FILE}" -f "${DESKTOP_COMPOSE_FILE}" "$@"
    else
        docker compose -f "${COMPOSE_FILE}" "$@"
    fi
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'Required command is missing: %s\n' "${command_name}" >&2
        return 1
    fi
}

validate_containers() {
    local service
    for service in redis ntopng zeek nginx; do
        compose ps --status running --services | grep -qx "${service}"
    done
}

validate_zeek_service() {
    compose ps --status running --services | grep -qx zeek
}

validate_unauthenticated_access() {
    local status_code
    status_code="$(curl -sS -o /dev/null -w '%{http_code}' "${BASE_URL}")"
    [[ "${status_code}" == "401" ]]
}

validate_authenticated_access() {
    local status_code
    status_code="$(curl -sS -o /dev/null -w '%{http_code}' \
        -u "${NGINX_BASIC_USER}:${NGINX_BASIC_PASSWORD}" "${BASE_URL}")"
    [[ "${status_code}" =~ ^(200|302)$ ]]
}

main() {
    require_command docker
    require_command curl
    validate_containers
    validate_zeek_service
    validate_unauthenticated_access
    validate_authenticated_access
    printf 'Stack validation completed successfully.\n'
}

main "$@"
