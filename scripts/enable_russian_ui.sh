#!/usr/bin/env bash
# @file enable_russian_ui.sh
# @brief Enable the optional Russian ntopng UI locale.
# @version 1.0.0
# @license MIT
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
DESKTOP_COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.desktop.yml"
USE_DESKTOP_OVERRIDE="${USE_DESKTOP_OVERRIDE:-0}"

compose() {
  if [[ "${USE_DESKTOP_OVERRIDE}" == "1" ]]; then
    docker compose -f "${COMPOSE_FILE}" -f "${DESKTOP_COMPOSE_FILE}" "$@"
  else
    docker compose -f "${COMPOSE_FILE}" "$@"
  fi
}

main() {
  # ntopng exposes only a fixed list of language codes in the UI. The project
  # mounts the Russian dictionary over one supported locale slot and keeps all
  # missing strings covered by ntopng's standard English fallback.
  compose exec -T redis redis-cli set ntopng.user.admin.language it >/dev/null
  compose exec -T redis redis-cli set ntopng.user.nologin.language it >/dev/null
  compose restart ntopng >/dev/null
  printf 'Russian UI locale enabled. Refresh the browser page after ntopng starts.\n'
}

main "$@"
