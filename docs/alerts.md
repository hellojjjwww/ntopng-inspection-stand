# Alert Policy Baseline

## Цель

Документ описывает базовый набор политик обнаружения для стенда ntopng / Zeek. Пороговые значения рассчитаны на лабораторную среду и должны корректироваться под реальную нагрузку сети.

## Объекты Контроля

- интерфейс захвата;
- локальные хосты;
- контейнерные подсети Docker;
- внешние IP-адреса;
- DNS-активность;
- новые TCP/UDP flows;
- объем исходящего трафика.

## Базовые Пороги

| Сценарий | Метрика | Стартовый порог | Назначение |
| --- | --- | --- | --- |
| Port scan | new flows per host | 500/min | Выявление перебора портов |
| SYN flood | TCP SYN packets | 100-300/min | Проверка всплесков TCP SYN |
| DNS anomaly | DNS queries | 100/min | Поиск DNS burst и туннелирования |
| Data exfiltration | outbound bytes per host | 50 MB / 5 min | Выявление нетипичного исходящего объема |
| Container abuse | traffic per container IP | 50 MB / 5 min | Контроль контейнеров |

## Настройка В ntopng

1. Открыть веб-интерфейс через Nginx Basic Auth.
2. Перейти в `Settings` -> `Checks`.
3. Включить проверки для `Host Checks`, `Flow Checks`, `Interface Checks`.
4. Для локальных хостов задать thresholds по traffic volume, new flows и DNS activity.
5. Для контейнерной подсети добавить Docker subnet в `LOCAL_NETWORKS`.
6. Проверить события в `Alerts` -> `Engaged` и `Alerts` -> `Past`.

## Проверка Scapy-Трафиком

DNS burst:

```bash
sudo python3 scripts/generate_anomaly.py suspicious-dns \
  --resolver 1.1.1.1 \
  --domain lab.example \
  --count 100
```

SYN packets:

```bash
sudo python3 scripts/generate_anomaly.py syn-flood \
  --target <lab-ip> \
  --port 80 \
  --count 500
```

Oversized ICMP:

```bash
sudo python3 scripts/generate_anomaly.py oversized-icmp \
  --target <lab-ip> \
  --size 3000 \
  --count 5
```

## Проверка В Zeek

```bash
docker compose -f deploy/docker-compose.yml exec zeek tail -n 40 /var/log/zeek/conn.log
docker compose -f deploy/docker-compose.yml exec zeek tail -n 40 /var/log/zeek/dns.log
```

## Сбор Материалов Проверки

```bash
deploy/scripts/tests/collect_evidence.sh
```

Скрипт сохраняет состояние сервисов, последние логи контейнеров и фрагменты Zeek-логов в `artifacts/evidence/`.
