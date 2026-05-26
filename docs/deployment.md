# Deployment Guide

## Target Platform

The deployment target is Ubuntu LTS. Ubuntu 24.04 LTS is the primary tested environment.

Required host capabilities:

- Docker Engine with Docker Compose plugin.
- Linux network namespace access to the capture interface.
- `sudo` access for installation tasks.
- UFW enabled with a default-deny incoming policy.

## One-command Installation

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

Optional variables:

```bash
sudo CAPTURE_INTERFACE=ens18 \
  LOCAL_NETWORKS=192.168.0.0/16,10.0.0.0/8 \
  NGINX_LISTEN_PORT=8088 \
  NGINX_BASIC_USER=ntopadmin \
  bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

If `NGINX_BASIC_PASSWORD` is not set, the installer generates a random password and prints it after deployment.

## Manual Deployment

```bash
cp .env.example .env
python3 scripts/prepare_htpasswd.py
docker compose -f deploy/docker-compose.yml up -d
```

Docker Desktop on Windows uses an override:

```powershell
docker-compose -f deploy/docker-compose.yml -f deploy/docker-compose.desktop.yml up -d
```

## Service Status

```bash
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs -f ntopng
```

Expected services:

- `ntopng-redis`
- `ntopng`
- `zeek-sensor`
- `ntopng-proxy`

## Access

```text
http://<host-ip>:8088/
```

The web interface is protected by Nginx Basic Auth. The built-in ntopng login is disabled because authentication is delegated to the reverse proxy.

## Zeek Logs

Zeek writes JSON logs to the `zeek-logs` Docker volume:

```bash
docker compose -f deploy/docker-compose.yml exec zeek ls -lah /var/log/zeek
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/conn.log
```

## Firewall Policy

The installer configures UFW:

- default incoming policy: deny;
- default outgoing policy: allow;
- SSH allowed through `OpenSSH` profile when available;
- Nginx UI port allowed through `NGINX_LISTEN_PORT`.

## Shutdown

```bash
docker compose -f deploy/docker-compose.yml down
```

Persistent state remains in named Docker volumes.
