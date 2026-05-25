# Testing Guide

## Static Validation

Validate Compose syntax:

```bash
docker compose -f deploy/docker-compose.yml config --quiet
```

Validate Bash syntax:

```bash
bash -n install.sh
bash -n deploy/scripts/tests/validate_stack.sh
```

Validate Python syntax:

```bash
python3 -m py_compile scripts/generate_anomaly.py scripts/prepare_htpasswd.py
```

## Stack Validation

After deployment:

```bash
NGINX_BASIC_USER=ntopadmin \
NGINX_BASIC_PASSWORD=<password> \
deploy/scripts/tests/validate_stack.sh
```

Expected results:

- unauthenticated request returns HTTP `401`;
- authenticated request returns HTTP `200` or `302`;
- Docker Compose can list the service state.

## Traffic Anomaly Tests

Install test dependency:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r tests/requirements.txt
```

Generate high-entropy DNS requests:

```bash
sudo python3 scripts/generate_anomaly.py suspicious-dns \
  --resolver 1.1.1.1 \
  --domain lab.example \
  --count 100
```

Generate TCP SYN packets toward a controlled lab target:

```bash
sudo python3 scripts/generate_anomaly.py syn-flood \
  --target <lab-ip> \
  --port 80 \
  --count 500
```

Generate oversized ICMP packets:

```bash
sudo python3 scripts/generate_anomaly.py oversized-icmp \
  --target <lab-ip> \
  --size 3000 \
  --count 5
```

All packet-generation tests must be executed only in a controlled lab network.

## Evidence Collection

Collect service state:

```bash
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs --tail 200 ntopng
docker compose -f deploy/docker-compose.yml logs --tail 200 nginx
```

Collect ntopng evidence:

- interface traffic graph;
- flow list;
- application/protocol classification;
- alert list;
- GeoIP/ASN view for external hosts.
