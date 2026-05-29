# Эксплуатация и проверка стенда

## 1. Выбор интерфейса захвата

На Linux-хосте найдите интерфейс:

```bash
ip -br addr
sudo tcpdump -D
```

Укажите его в `.env`:

```env
CAPTURE_INTERFACE=eth0
```

Если трафик приходит с SPAN/TAP-порта или виртуального mirror-интерфейса, укажите именно mirror-интерфейс. Для высоких скоростей можно заменить libpcap-захват на PF_RING, но это требует установки PF_RING-модуля на хост и совместимого образа/пакетов ntop.

## 2. DPI и классификация протоколов

ntopng использует nDPI для L7-классификации. После запуска проверьте:

1. `Interfaces` -> выбранный интерфейс.
2. `Applications` / `Protocols`.
3. Наличие HTTP, TLS, DNS, QUIC, SSH и других L7-протоколов.

Если вместо приложений виден только L3/L4-трафик, проверьте, что контейнер запущен с `network_mode: host`, `NET_RAW`, `NET_ADMIN`, а интерфейс в `.env` существует на Linux-хосте.

## 3. GeoLite2

Создайте бесплатный MaxMind аккаунт, получите license key и обновите базы на хосте:

```bash
sudo apt-get install geoipupdate
sudo geoipupdate
```

Затем скопируйте базы в проект:

```bash
mkdir -p geoip
cp /var/lib/GeoIP/GeoLite2-City.mmdb geoip/
cp /var/lib/GeoIP/GeoLite2-ASN.mmdb geoip/
cp /var/lib/GeoIP/GeoLite2-Country.mmdb geoip/
docker compose restart ntopng
```

Проверка в ntopng: `Hosts` -> внешний IP -> геолокация/ASN.

## 4. Алерты аномалий

В ntopng включите и настройте проверки:

- Port scan / TCP SYN scan: `Settings` -> `Checks` -> `Host Checks`.
- DoS / flow flood: `Settings` -> `Checks` -> `Flow Checks` и `Host Checks`.
- Suspicious DNS: `Settings` -> `Checks` -> `Flow Checks`, включите DNS-related проверки.
- Threshold traffic: `Settings` -> `Checks` -> `Interface Checks` или `Host Checks`.

Рекомендуемые лабораторные пороги:

- Traffic volume для контейнера/host IP: `50 MB / 5 min`.
- SYN packets: `100-300 / min`.
- New flows: `500 / min`.
- DNS queries: `100 / min`.

После генерации тестового трафика смотрите `Alerts` -> `Engaged` и `Alerts` -> `Past`.

## 5. Алертинг на превышение трафика контейнером

Для контейнеров Docker самый надежный способ в лабораторном стенде:

1. Назначить контейнерам фиксированные IP в user-defined bridge-сети или контролировать их IP через `docker inspect`.
2. Добавить Docker subnet в `LOCAL_NETWORKS`.
3. В ntopng открыть `Hosts`, выбрать IP контейнера.
4. Создать host threshold на bytes/traffic или flow count.
5. Настроить endpoint уведомлений: webhook, email, Slack/Discord, syslog.

Если контейнер работает через NAT и виден как хост Docker, зеркалируйте bridge-трафик на отдельный интерфейс или используйте nProbe/NetFlow/IPFIX экспорт.

## 6. Долгосрочное хранение статистики и flows

Минимальный вариант уже включен:

- `ntopng-data` хранит состояние ntopng и time-series.
- `redis-data` хранит Redis AOF/RDB.

Для production-like хранения flows используйте один из вариантов:

- ntopng Enterprise/Pro с ClickHouse backend для flows.
- nProbe как сенсор NetFlow/IPFIX и отдельное долговременное хранилище.
- Экспорт алертов через webhook/syslog в SIEM.

Бэкап конфигурации и volume:

```bash
scripts/backup.sh
```

Архивы сохраняются в `artifacts/backups/<timestamp>/`.

## 7. Диагностика и управление

Быстрая проверка состояния:

```bash
scripts/doctor.sh
```

Команды управления:

```bash
make up
make ps
make logs SERVICE=ntopng
make logs SERVICE=zeek
make russian-ui
make evidence
make backup
make down
```

После установки одной командой на Ubuntu создается unit:

```bash
systemctl status ntopng-inspection-stand.service
systemctl restart ntopng-inspection-stand.service
```

## 8. Русская локаль ntopng

В проекте подключен дополнительный файл `config/ntopng/locales/ru.lua`. Он переводит основные пункты интерфейса. Полная локализация зависит от количества строк в словаре ntopng; отсутствующие строки остаются на английском. Для совместимости с фиксированным списком языков ntopng словарь подключается через поддерживаемый языковой слот.

Включение:

```bash
scripts/enable_russian_ui.sh
```

Для Docker Desktop:

```bash
USE_DESKTOP_OVERRIDE=1 scripts/enable_russian_ui.sh
```

## 9. Проверка reverse-proxy

Проверьте, что прямой web-порт ntopng не доступен извне:

```bash
curl -I http://127.0.0.1:3000/
curl -I http://<linux-host>:3000/
```

Ожидаемо: локально ntopng отвечает, с другой машины порт не должен быть доступен. Пользователи заходят только через:

```text
http://<linux-host>:8088/
```

## 10. Контрольный сценарий проверки

1. `docker compose ps` показывает `redis`, `ntopng`, `zeek`, `nginx`.
2. В ntopng виден live-трафик на выбранном интерфейсе.
3. На вкладке protocols/applications есть L7-классификация nDPI.
4. Для внешних IP видны ASN/country/city после установки GeoLite2.
5. Python-тест генерирует SYN/DNS/MTU anomaly.
6. В `Alerts` появляется событие после превышения порога.
7. Вход в UI ntopng возможен только через Nginx Basic Auth.
