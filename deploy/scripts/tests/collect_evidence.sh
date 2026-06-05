#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
DESKTOP_COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.desktop.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/artifacts/evidence/$(date +%Y%m%d-%H%M%S)}"

compose() {
    local args=()
    if [[ -f "${ENV_FILE}" ]]; then
        args+=(--env-file "${ENV_FILE}")
    fi
    args+=(-f "${COMPOSE_FILE}")
    if [[ "${USE_DESKTOP_OVERRIDE:-0}" == "1" ]]; then
        args+=(-f "${DESKTOP_COMPOSE_FILE}")
    fi
    docker compose "${args[@]}" "$@"
}

collect_service_state() {
    compose ps >"${OUTPUT_DIR}/compose-ps.txt"
}

collect_container_logs() {
    compose logs --tail 200 ntopng >"${OUTPUT_DIR}/ntopng.log" 2>&1 || true
    compose logs --tail 200 zeek >"${OUTPUT_DIR}/zeek.log" 2>&1 || true
    compose logs --tail 200 nginx >"${OUTPUT_DIR}/nginx.log" 2>&1 || true
}

collect_zeek_samples() {
    local log_name
    for log_name in conn.log dns.log http.log ssl.log notice.log; do
        compose exec -T zeek sh -c "test -f /var/log/zeek/${log_name} && tail -n 40 /var/log/zeek/${log_name}" \
            >"${OUTPUT_DIR}/zeek-${log_name}" 2>/dev/null || true
    done
}

main() {
    mkdir -p "${OUTPUT_DIR}"
    collect_service_state
    collect_container_logs
    collect_zeek_samples
    printf 'Evidence collected in %s\n' "${OUTPUT_DIR}"
}

main "$@"
