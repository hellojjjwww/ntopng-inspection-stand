#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
DESKTOP_COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.desktop.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
USE_DESKTOP_OVERRIDE="${USE_DESKTOP_OVERRIDE:-0}"

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

main() {
  compose exec -T redis redis-cli set ntopng.user.admin.language it >/dev/null
  compose exec -T redis redis-cli set ntopng.user.nologin.language it >/dev/null
  compose restart ntopng >/dev/null
  printf 'Russian UI locale enabled. Refresh the browser page after ntopng starts.\n'
}

main "$@"
