#!/usr/bin/env bash
# @file collect_evidence.sh
# @brief Collect runtime evidence for documentation and validation.
# @details
#   1. Stores Docker Compose service state.
#   2. Stores recent ntopng, Zeek and Nginx logs.
#   3. Stores short Zeek log samples when files are available.
# @version 1.0.0
# @license MIT
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/docker-compose.yml"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/artifacts/evidence/$(date +%Y%m%d-%H%M%S)}"

compose() {
    docker compose -f "${COMPOSE_FILE}" "$@"
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
