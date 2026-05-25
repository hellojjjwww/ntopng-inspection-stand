#!/usr/bin/env python3
"""Create config/nginx/.htpasswd from .env without external utilities.

File: prepare_htpasswd.py
Version: 1.1.0
License: MIT
"""

from __future__ import annotations

import base64
import hashlib
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
HTPASSWD_FILE = ROOT / "config" / "nginx" / ".htpasswd"


def load_env() -> dict[str, str]:
    values: dict[str, str] = {}
    if ENV_FILE.exists():
        for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def apr1_hash(password: str, salt: str = "ntoplab1") -> str:
    # Nginx accepts Apache MD5 "$apr1$" hashes in htpasswd files.
    magic = "$apr1$"
    salt = salt[:8]
    password_bytes = password.encode()
    salt_bytes = salt.encode()

    ctx = hashlib.md5()
    ctx.update(password_bytes + magic.encode() + salt_bytes)

    alt = hashlib.md5(password_bytes + salt_bytes + password_bytes).digest()
    for i in range(len(password_bytes)):
        ctx.update(alt[i % 16 : i % 16 + 1])

    length = len(password_bytes)
    while length:
        ctx.update(b"\x00" if length & 1 else password_bytes[:1])
        length >>= 1

    final = ctx.digest()
    for i in range(1000):
        loop = hashlib.md5()
        loop.update(password_bytes if i & 1 else final)
        if i % 3:
            loop.update(salt_bytes)
        if i % 7:
            loop.update(password_bytes)
        loop.update(final if i & 1 else password_bytes)
        final = loop.digest()

    alphabet = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    def to64(value: int, count: int) -> str:
        result = ""
        for _ in range(count):
            result += alphabet[value & 0x3F]
            value >>= 6
        return result

    encoded = (
        to64((final[0] << 16) | (final[6] << 8) | final[12], 4)
        + to64((final[1] << 16) | (final[7] << 8) | final[13], 4)
        + to64((final[2] << 16) | (final[8] << 8) | final[14], 4)
        + to64((final[3] << 16) | (final[9] << 8) | final[15], 4)
        + to64((final[4] << 16) | (final[10] << 8) | final[5], 4)
        + to64(final[11], 2)
    )
    return f"{magic}{salt}${encoded}"


def main() -> None:
    values = load_env()
    user = values.get("NGINX_BASIC_USER") or os.environ.get("NGINX_BASIC_USER") or "ntopadmin"
    password = values.get("NGINX_BASIC_PASSWORD") or os.environ.get("NGINX_BASIC_PASSWORD") or "change-me-now"

    if password == "change-me-now":
        raise SystemExit("Change NGINX_BASIC_PASSWORD in .env before creating config/nginx/.htpasswd")

    HTPASSWD_FILE.parent.mkdir(parents=True, exist_ok=True)
    HTPASSWD_FILE.write_text(f"{user}:{apr1_hash(password)}\n", encoding="utf-8")
    print(f"Created {HTPASSWD_FILE}")


if __name__ == "__main__":
    main()
