#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/artifacts/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${OUTPUT_DIR}/${STAMP}"

compose() {
  local args=()
  if [[ -f "${ENV_FILE}" ]]; then
    args+=(--env-file "${ENV_FILE}")
  fi
  args+=(-f "${COMPOSE_FILE}")
  docker compose "${args[@]}" "$@"
}

backup_config() {
  local paths=(config deploy docs scripts tests README.md LICENSE.txt)
  [[ -f "${PROJECT_ROOT}/.env" ]] && paths=(.env "${paths[@]}")
  [[ -f "${PROJECT_ROOT}/Makefile" ]] && paths=(Makefile "${paths[@]}")

  mkdir -p "${BACKUP_DIR}/project"
  tar -czf "${BACKUP_DIR}/project/config.tar.gz" \
    -C "${PROJECT_ROOT}" \
    "${paths[@]}"
}

backup_volume() {
  local volume_name="$1"
  local archive_name="$2"

  docker run --rm \
    -v "${volume_name}:/volume:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.22 \
    sh -c "cd /volume && tar -czf /backup/${archive_name}.tar.gz ."
}

backup_volumes() {
  local project_name
  project_name="$(awk -F': *' '/^name:/ {gsub(/"/, "", $2); print $2; exit}' "${COMPOSE_FILE}")"
  project_name="${project_name:-ntopng-inspection-stand}"

  backup_volume "${project_name}_redis-data" "redis-data"
  backup_volume "${project_name}_ntopng-data" "ntopng-data"
  backup_volume "${project_name}_zeek-logs" "zeek-logs"
}

main() {
  mkdir -p "${BACKUP_DIR}"
  backup_config
  backup_volumes
  printf 'Backup created in %s\n' "${BACKUP_DIR}"
}

main "$@"
