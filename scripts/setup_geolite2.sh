#!/usr/bin/env bash
# @file setup_geolite2.sh
# @brief Install and refresh GeoLite2 databases for ntopng GeoIP enrichment.
# @details
#   1. Installs geoipupdate when it is missing.
#   2. Writes /etc/GeoIP.conf from environment variables.
#   3. Downloads MaxMind GeoLite2 databases.
#   4. Copies .mmdb files into the project geoip/ directory.
# @version 1.0.0
# @license MIT
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEOIP_DIR="${PROJECT_ROOT}/geoip"
MAXMIND_ACCOUNT_ID="${MAXMIND_ACCOUNT_ID:-}"
MAXMIND_LICENSE_KEY="${MAXMIND_LICENSE_KEY:-}"
MAXMIND_EDITION_IDS="${MAXMIND_EDITION_IDS:-GeoLite2-ASN GeoLite2-City GeoLite2-Country}"

log() {
    printf '\033[1;34m[geoip]\033[0m %s\n' "$*"
}

fail() {
    printf '\033[1;31m[geoip]\033[0m %s\n' "$*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fail "Run with sudo because geoipupdate writes to /etc and /var/lib/GeoIP."
    fi
}

validate_environment() {
    [[ -n "${MAXMIND_ACCOUNT_ID}" ]] || fail "MAXMIND_ACCOUNT_ID is required."
    [[ -n "${MAXMIND_LICENSE_KEY}" ]] || fail "MAXMIND_LICENSE_KEY is required."
}

install_geoipupdate() {
    if command -v geoipupdate >/dev/null 2>&1; then
        return
    fi

    log "Installing geoipupdate."
    apt-get update
    apt-get install -y geoipupdate
}

write_geoip_config() {
    log "Writing /etc/GeoIP.conf."
    if [[ -f /etc/GeoIP.conf ]]; then
        cp /etc/GeoIP.conf "/etc/GeoIP.conf.backup.$(date +%Y%m%d%H%M%S)"
    fi

    cat >/etc/GeoIP.conf <<EOF
AccountID ${MAXMIND_ACCOUNT_ID}
LicenseKey ${MAXMIND_LICENSE_KEY}
EditionIDs ${MAXMIND_EDITION_IDS}
DatabaseDirectory /var/lib/GeoIP
EOF
}

refresh_databases() {
    log "Refreshing GeoLite2 databases."
    install -d /var/lib/GeoIP "${GEOIP_DIR}"
    geoipupdate
}

copy_databases() {
    log "Copying databases to ${GEOIP_DIR}."
    find /var/lib/GeoIP -maxdepth 1 -type f -name 'GeoLite2-*.mmdb' -exec cp {} "${GEOIP_DIR}/" \;
    chmod 0644 "${GEOIP_DIR}"/*.mmdb
}

main() {
    require_root
    validate_environment
    install_geoipupdate
    write_geoip_config
    refresh_databases
    copy_databases
    log "GeoLite2 setup completed. Restart ntopng to reload databases."
}

main "$@"
