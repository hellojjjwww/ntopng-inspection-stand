# Стенд глубокого мониторинга сетевого трафика: ntopng / Redis / Nginx

Проект поднимает лабораторный стенд сетевой инспекции на базе `ntopng` с DPI через nDPI, Redis для кэша и настроек, reverse-proxy Nginx с Basic Auth, подготовкой GeoLite2 и Python-тестом на `scapy` для генерации аномального трафика.

> Практическое замечание: захват реального трафика из контейнера через `network_mode: host` корректно работает на Linux-хосте. В Docker Desktop на Windows/macOS контейнер видит сеть VM, а не физические интерфейсы машины.

## Состав

- `docker-compose.yml` - Redis, ntopng, Nginx reverse-proxy.
- `ntopng/ntopng.conf` - базовая конфигурация ntopng для захвата, DPI и локального web-интерфейса.
- `nginx/default.conf.template` - закрытие ntopng за Basic Auth.
- `scripts/generate_anomaly.py` - генератор SYN-flood, DNS-туннельных запросов и oversized ICMP через scapy.
- `scripts/prepare_htpasswd.py` - создание файла Basic Auth без внешних утилит.
- `docs/OPERATIONS.md` - порядок настройки алертов, GeoIP, хранения flows и проверки стенда.

## Быстрый запуск

1. Скопируйте пример переменных окружения:

   ```powershell
   Copy-Item .env.example .env
   ```

   На Linux:

   ```bash
   cp .env.example .env
   ```

2. Отредактируйте `.env`:

   - `CAPTURE_INTERFACE` - интерфейс для захвата (`ip link`, `ip addr`, `tcpdump -D`).
   - `LOCAL_NETWORKS` - локальные сети через запятую.
   - `NGINX_BASIC_USER` и `NGINX_BASIC_PASSWORD` - логин и пароль reverse-proxy.

3. Создайте файл Basic Auth:

   ```bash
   python3 scripts/prepare_htpasswd.py
   ```

4. Запустите стенд:

   ```bash
   docker compose up -d
   ```

   В Docker Desktop на Windows используйте override, который пробрасывает Nginx на `localhost:8088`:

   ```powershell
   docker-compose -f docker-compose.yml -f docker-compose.desktop.yml up -d
   ```

5. Откройте ntopng через proxy:

   - URL: `http://<linux-host>:8088/`
   - Basic Auth: значения из `.env`
   - Первый вход ntopng: `admin` / `admin`, затем ntopng попросит сменить пароль.

## GeoLite2

Для визуализации внешних IP на карте положите базы MaxMind в каталог `geoip/`:

- `GeoLite2-City.mmdb`
- `GeoLite2-ASN.mmdb`
- `GeoLite2-Country.mmdb`

Если у вас есть MaxMind license key, можно использовать `geoipupdate` на хосте или добавить отдельный контейнер обновления. Подробнее: [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Проверка аномалий

Установите зависимости теста на машине-генераторе:

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

Запускайте генератор только в своей лабораторной сети или на адресах, которыми вы управляете.

## Источники

Решения в проекте опираются на актуальную документацию ntopng:

- Redis используется ntopng для кэша, настроек и preferences: <https://ntop.org/guides/ntopng/user_interface/system_interface/health/redis.html>
- Конфигурационный файл и изоляция Redis/портов/data dir для daemon-режима: <https://www.ntop.org/guides/ntopng/how_to_start/running_as_a_daemon.html>
- Захват трафика через libpcap/PF_RING, включая SPAN/TAP-сценарии: <https://www.ntop.org/ntopng/>
- Alert engine и threshold-алерты: <https://www.ntop.org/guides/ntopng/basic_concepts/alerts.html>
