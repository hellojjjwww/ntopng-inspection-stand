# Стенд глубокого мониторинга сетевого трафика: ntopng / Redis / Nginx

Проект разворачивает стенд сетевой инспекции на базе `ntopng` с DPI через nDPI, Redis для кэша и настроек, reverse-proxy Nginx с Basic Auth, подготовкой GeoLite2 и Python-тестом на `scapy` для генерации аномального трафика.

Захват реального трафика из контейнера через `network_mode: host` корректно работает на Linux-хосте. В Docker Desktop на Windows/macOS контейнер видит сеть виртуальной машины Docker Desktop, а не физические интерфейсы хоста.

## Состав

- `deploy/docker-compose.yml` - Redis, ntopng, Nginx reverse-proxy.
- `config/ntopng/ntopng.conf` - базовая конфигурация ntopng.
- `config/nginx/default.conf.template` - reverse-proxy с Basic Auth.
- `config/redis/redis.conf` - конфигурация Redis.
- `install.sh` - установка стенда на Ubuntu LTS одной командой.
- `scripts/generate_anomaly.py` - генератор SYN-flood, DNS-туннельных запросов и oversized ICMP.
- `scripts/prepare_htpasswd.py` - создание файла Basic Auth.
- `deploy/scripts/tests/validate_stack.sh` - интеграционная проверка запущенного стенда.
- `docs/architecture.md` - архитектура NDR/DPI.
- `docs/deployment.md` - инструкция развертывания.
- `docs/testing.md` - методика проверки.
- `docs/operations.md` - эксплуатационные процедуры.

## Роли

| Роль | Зона ответственности |
| --- | --- |
| DevOps/IaC Engineer | Docker Compose, установщик, структура репозитория, автоматизация развертывания |
| System Administrator / SRE | Nginx, Redis, healthcheck-и, эксплуатационные процедуры |
| Observability and Security Engineer | ntopng, DPI, алерты, тесты аномального трафика, документация мониторинга |

## Установка одной командой

На чистой Ubuntu LTS:

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

С параметрами:

```bash
sudo CAPTURE_INTERFACE=ens18 \
  NGINX_LISTEN_PORT=8088 \
  NGINX_BASIC_USER=admin \
  bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

Если `NGINX_BASIC_PASSWORD` не задан, установщик сгенерирует пароль и покажет его после запуска.

## Ручной запуск

1. Скопировать пример переменных окружения:

   ```bash
   cp .env.example .env
   ```

2. Отредактировать `.env`:

   - `CAPTURE_INTERFACE` - интерфейс для захвата (`ip link`, `ip addr`, `tcpdump -D`).
   - `LOCAL_NETWORKS` - локальные сети через запятую.
   - `NGINX_BASIC_USER` и `NGINX_BASIC_PASSWORD` - логин и пароль reverse-proxy.

3. Создать файл Basic Auth:

   ```bash
   python3 scripts/prepare_htpasswd.py
   ```

4. Запустить стенд:

   ```bash
   docker compose -f deploy/docker-compose.yml up -d
   ```

   Docker Desktop на Windows:

   ```powershell
   docker-compose -f deploy/docker-compose.yml -f deploy/docker-compose.desktop.yml up -d
   ```

5. Открыть ntopng через proxy:

   - URL: `http://<linux-host>:8088/`
   - Basic Auth: значения из `.env`
   - встроенный логин ntopng отключен, доступ контролируется Nginx Basic Auth.

## Проверка статуса

```bash
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs -f ntopng
```

Интеграционный тест:

```bash
NGINX_BASIC_USER=ntopadmin \
NGINX_BASIC_PASSWORD=<password> \
deploy/scripts/tests/validate_stack.sh
```

## GeoLite2

Для визуализации внешних IP на карте положите базы MaxMind в каталог `geoip/`:

- `GeoLite2-City.mmdb`
- `GeoLite2-ASN.mmdb`
- `GeoLite2-Country.mmdb`

Подробности приведены в `docs/operations.md`.

## Проверка аномалий

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r tests/requirements.txt
```

Примеры:

```bash
sudo python3 scripts/generate_anomaly.py syn-flood --target 192.0.2.10 --port 80 --count 500
sudo python3 scripts/generate_anomaly.py suspicious-dns --resolver 1.1.1.1 --domain lab.example --count 100
sudo python3 scripts/generate_anomaly.py oversized-icmp --target 192.0.2.10 --size 3000 --count 5
```

Генерация пакетов должна выполняться только в контролируемой лабораторной сети.

## Лицензирование

Исходный код автоматизации и конфигурации распространяются под лицензией MIT. Полный текст указан в `LICENSE.txt`.

## Источники

- ntopng Redis: <https://ntop.org/guides/ntopng/user_interface/system_interface/health/redis.html>
- ntopng daemon/config: <https://www.ntop.org/guides/ntopng/how_to_start/running_as_a_daemon.html>
- ntopng capture: <https://www.ntop.org/ntopng/>
- ntopng alerts: <https://www.ntop.org/guides/ntopng/basic_concepts/alerts.html>
