# Чек-лист соответствия требованиям проекта

Документ фиксирует текущее соответствие репозитория требованиям по проекту 25: анализ и глубокий мониторинг сетевого трафика.

## Организация репозитория

| Требование | Статус | Подтверждение |
| --- | --- | --- |
| Публичный Git-репозиторий | Выполнено | `origin` указывает на публичный репозиторий GitHub |
| Основная ветка `main` | Выполнено | рабочая ветка проекта - `main` |
| Ветка `gh-pages` | Выполнено | ветка присутствует на удаленном репозитории |
| README с описанием проекта | Выполнено | `README.md` |
| Лицензия | Выполнено | `LICENSE.txt` |
| `.env` не публикуется | Выполнено | `.gitignore`, `.env.example` |
| Структура `.github`, `config`, `deploy`, `scripts`, `docs`, `tests`, `thesis` | Выполнено | каталоги присутствуют в репозитории |
| Автоматизированная проверка | Выполнено | `.github/workflows/pr-validation.yml` |

## Функциональные требования проекта 25

| Требование | Статус | Реализация |
| --- | --- | --- |
| ntopng + Redis в Docker | Выполнено | `deploy/docker-compose.yml` |
| Захват трафика с интерфейса хоста | Выполнено | `network_mode: host`, `CAPTURE_INTERFACE`, libpcap/PF_RING fallback |
| DPI-классификация | Выполнено | nDPI внутри ntopng |
| Политики аномалий | Выполнено | ntopng alerts, behavioural checks, scapy-генератор |
| Долгосрочное хранение статистики и flows | Выполнено | Docker volumes `ntopng-data`, `redis-data`, `zeek-logs` |
| Zeek-логи потоков | Выполнено | `zeek/zeek`, `config/zeek/local.zeek`, JSON-логи |
| Reverse-proxy с Basic Auth | Выполнено | `nginxinc/nginx-unprivileged`, `.htpasswd`, `--disable-login 1` |
| GeoLite2/GeoIP | Выполнено | каталог `geoip/`, `scripts/setup_geolite2.sh` |
| Алертинг по превышению трафика | Выполнено | `docs/alerts.md`, ntopng threshold policies |
| Python/scapy тест | Выполнено | `scripts/generate_anomaly.py`, `tests/requirements.txt` |

## Требования по развертыванию

| Требование | Статус | Реализация |
| --- | --- | --- |
| Ubuntu LTS | Выполнено | `install.sh`, `install-vps-wireguard.sh` проверяют Ubuntu |
| Установка одной командой | Выполнено | `sudo bash <(curl -Ls ...)` |
| Контейнеризация | Выполнено | Docker Compose |
| UFW deny-by-default | Выполнено | installer включает UFW и открывает только нужные порты |
| Запуск после перезагрузки | Выполнено | `systemd` unit для основного стенда, `wg-quick@wg0` для VPS demo |
| Демонстрация без SPAN/TAP | Выполнено | режим WireGuard VPS demo |

## Проверки перед сдачей

Рекомендуемый минимальный набор:

```bash
docker compose -f deploy/docker-compose.yml config --quiet
bash -n install.sh
bash -n install-vps-wireguard.sh
bash -n scripts/doctor.sh
python3 -m py_compile scripts/generate_anomaly.py scripts/prepare_htpasswd.py
```

На развернутом стенде:

```bash
cd /opt/ntopng-wireguard-demo
docker compose --env-file .env -f deploy/docker-compose.yml ps
scripts/doctor.sh
deploy/scripts/tests/validate_stack.sh
```
