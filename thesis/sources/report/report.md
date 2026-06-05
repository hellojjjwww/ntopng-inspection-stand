# Технический отчет

## Стенд глубокого мониторинга сетевого трафика: ntopng / Zeek

**Проект 25.** Анализ и глубокий мониторинг сетевого трафика.

**Участники:** Якушенко Илья Дмитриевич; Бокова Елизавета Игоревна; Пикуза Софья Романовна.

## 1. Введение

Современная сеть генерирует большое количество событий, которые невозможно надежно анализировать только по журналам конечных узлов. Для контроля инцидентов требуется наблюдение за сетевыми потоками, классификация прикладных протоколов, фиксация DNS- и TLS-метаданных, а также понятный интерфейс для оперативного просмотра состояния канала.

Цель проекта - разработать воспроизводимый стенд сетевой инспекции, который разворачивается на Ubuntu LTS, работает в Docker, захватывает трафик с реального или виртуального интерфейса, показывает карту сетевых потоков в ntopng и сохраняет доказательные логи Zeek.

## 2. Постановка задачи

Проект реализует требования варианта 25: ntopng и Redis в Docker; packet capture через интерфейс хоста; DPI на базе nDPI; политики выявления аномалий; хранение flows и логов; GeoLite2; Nginx Basic Auth; Python/scapy-тесты.

| Требование | Реализация |
| --- | --- |
| ntopng + Redis в Docker | `deploy/docker-compose.yml`, сервисы `ntopng` и `redis` |
| Захват пакетов | `network_mode: host`, `CAPTURE_INTERFACE`, libpcap/PF_RING fallback |
| DPI | nDPI внутри ntopng |
| Аномалии | ntopng alerts, behavioural checks, Scapy tests |
| Flows и логи | Docker volumes `ntopng-data`, `redis-data`, `zeek-logs` |
| GeoIP | каталог `geoip/`, helper `scripts/setup_geolite2.sh` |
| Reverse-proxy | Nginx Basic Auth, `--disable-login 1` |
| Установка одной командой | `install.sh`, `install-vps-wireguard.sh` |

## 3. Анализ существующих решений

Рассмотрены tcpdump/Wireshark, ntopng, Zeek, Suricata и системы долгосрочного хранения. Итоговый стек выбран как комбинация ntopng и Zeek: ntopng дает визуализацию и DPI, Zeek формирует структурированные журналы для расследования.

tcpdump и Wireshark полезны для ручного анализа отдельных дампов, однако они не дают постоянной web-панели и не решают задачу автоматического накопления статистики. Suricata эффективна как IDS-сенсор с сигнатурными правилами, но в рамках проекта важна не только сигнатурная фиксация, а еще и визуализация сетевых потоков. Поэтому Suricata оставлена как перспективное расширение.

| Решение | Сильная сторона | Ограничение | Использование |
| --- | --- | --- | --- |
| tcpdump/Wireshark | точный packet analysis | ручная работа | дополнительная диагностика |
| ntopng | flows, DPI, dashboards, alerts | часть функций зависит от редакции | основная панель |
| Zeek | структурированные сетевые логи | нужен отдельный анализ | доказательная база |
| Suricata | IDS-сигнатуры, EVE JSON | усложняет минимальный стенд | развитие проекта |
| OpenSearch/ClickHouse/Loki | долгосрочный поиск | требует отдельной инфраструктуры | развитие проекта |

## 4. Архитектура

```text
network interface / mirror port / wg0
        |
        +--> ntopng --> nDPI --> flows, hosts, protocols, alerts
        |       |
        |       +--> Redis and ntopng-data volume
        |
        +--> Zeek --> conn/dns/http/ssl logs --> zeek-logs volume

user browser --> Nginx Basic Auth --> ntopng UI
```

Архитектура построена как пассивный pipeline. ntopng отвечает за оперативное наблюдение: интерфейсы, hosts, live flows, applications, bandwidth, alerts и GeoIP. Redis используется как оперативное хранилище ntopng. Zeek параллельно пишет журналы `conn.log`, `dns.log`, `ssl.log`, `http.log`, которые можно использовать для проверки выводов из панели.

В обычной локальной сети стенд подключается к mirror/SPAN-порту либо к интерфейсу Linux-хоста. В демонстрационном режиме без SPAN/TAP используется WireGuard full tunnel: тестовый клиент подключается к VPS, а его трафик проходит через `wg0`.

## 5. Реализация

Сервисы описаны в Docker Compose. Для анализаторов используется `network_mode: host`, capabilities `NET_ADMIN` и `NET_RAW`, healthcheck и Docker volumes. Nginx закрывает панель Basic Auth, а встроенная форма ntopng отключена параметром `--disable-login 1`.

Основные файлы:

- `deploy/docker-compose.yml` - Redis, ntopng, Zeek, Nginx;
- `config/ntopng/ntopng.conf` - параметры ntopng;
- `config/nginx/default.conf.template` - reverse-proxy;
- `config/zeek/local.zeek` - политика Zeek для JSON-логов;
- `scripts/generate_anomaly.py` - генерация тестовых аномалий;
- `scripts/doctor.sh` - диагностика типовых проблем;
- `docs/compliance_checklist.md` - проверка соответствия требованиям.

## 6. Развертывание

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install-vps-wireguard.sh)
```

После установки проверяются контейнеры, WireGuard при необходимости, Nginx Basic Auth и доступность ntopng. Установщик VPS demo дополнительно выводит путь к клиентскому WireGuard config и команду `scp` для скачивания.

## 7. Тестирование

Проверяются Docker Compose, Bash/Python syntax, доступность Nginx/Basic Auth, наличие логов Zeek и появление flows в ntopng. Для лабораторной генерации аномалий используется `scripts/generate_anomaly.py`.

```bash
docker compose -f deploy/docker-compose.yml config --quiet
bash -n install.sh
bash -n install-vps-wireguard.sh
python3 -m py_compile scripts/generate_anomaly.py scripts/prepare_htpasswd.py
deploy/scripts/tests/validate_stack.sh
sudo python3 scripts/generate_anomaly.py suspicious-dns --resolver 1.1.1.1 --domain lab.example --count 100
```

## 8. Результаты

Стенд показывает live flows, hosts, applications, bandwidth, alerts, behavioural checks и GeoIP-карту. Скриншоты интерфейса находятся в `assets/screenshots/`.

Демонстрационный сценарий:

1. Развернуть стенд на Ubuntu LTS или VPS.
2. Подключить клиент через WireGuard.
3. Открыть несколько сайтов и выполнить DNS-запросы.
4. Открыть ntopng и показать dashboard, flows, hosts, interface, alerts.
5. Подтвердить события через Zeek logs.

## 9. Роли

- Якушенко Илья Дмитриевич - архитектура, Docker Compose, установщики, WireGuard demo, ntopng/Zeek, тестирование аномалий.
- Бокова Елизавета Игоревна - Nginx, Basic Auth, Redis, healthcheck, эксплуатационные процедуры.
- Пикуза Софья Романовна - документация, сценарий демонстрации, чек-листы, презентационные материалы.

## 10. Развитие

Перспективы: Suricata IDS, ClickHouse/OpenSearch/Loki, webhook/syslog-алерты, Prometheus/Grafana, несколько WireGuard-клиентов, nProbe/NetFlow.

## 11. Заключение

Проект реализует воспроизводимый стенд сетевой инспекции и может использоваться для демонстрации анализа flows, DPI, алертинга и журналирования сетевых событий.
