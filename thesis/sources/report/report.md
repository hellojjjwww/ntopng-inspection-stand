# Технический отчет

## 1. Введение

Тема проекта: анализ и глубокий мониторинг сетевого трафика на базе ntopng и Zeek.

Цель работы: разработать воспроизводимый стенд сетевой инспекции, обеспечивающий захват трафика, классификацию протоколов, фиксацию сетевых потоков, выявление аномалий и сохранение структурированных логов.

## 2. Постановка Задачи

Основные задачи:

- развернуть ntopng и Redis в Docker;
- настроить захват пакетов с интерфейса хоста;
- включить DPI-классификацию на базе nDPI;
- добавить политики выявления аномалий;
- обеспечить хранение статистики flows и логов;
- закрыть административный интерфейс через Nginx Basic Auth;
- добавить проверочные сценарии на базе scapy.

## 3. Анализ Существующих Решений

Сравниваемые подходы:

- ntopng как визуальный анализатор flows и DPI;
- Zeek как источник структурированных сетевых логов;
- Suricata как перспективный IDS-сенсор для сигнатурного анализа.

Итоговый стек выбран как комбинация ntopng и Zeek: ntopng обеспечивает удобную визуализацию и алерты, Zeek формирует доказательные JSON-логи для дальнейшего анализа.

## 4. Архитектура

Компоненты стенда:

- ntopng;
- Redis;
- Zeek;
- Nginx;
- Docker Compose;
- scapy-тесты.

Сетевая схема: пассивный захват трафика с интерфейса Linux-хоста через `network_mode: host`.

## 5. Развертывание

Быстрый запуск:

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

Ручной запуск:

```bash
cp .env.example .env
python3 scripts/prepare_htpasswd.py
docker compose -f deploy/docker-compose.yml up -d
```

## 6. Тестирование

Статическая проверка:

```bash
docker compose -f deploy/docker-compose.yml config --quiet
bash -n install.sh
python3 -m py_compile scripts/generate_anomaly.py scripts/prepare_htpasswd.py
```

Интеграционная проверка:

```bash
deploy/scripts/tests/validate_stack.sh
```

Генерация аномального трафика:

```bash
sudo python3 scripts/generate_anomaly.py suspicious-dns --resolver 1.1.1.1 --domain lab.example --count 100
```

## 7. Результаты

Ожидаемые результаты:

- ntopng отображает flows, hosts, protocols и bandwidth;
- Zeek формирует `conn.log`, `dns.log`, `ssl.log`, `http.log`;
- Nginx ограничивает доступ к web-интерфейсу;
- scapy-тесты создают наблюдаемые сетевые события;
- GeoIP-базы позволяют обогащать внешние IP-адреса.

## 8. Заключение

Разработанный стенд обеспечивает воспроизводимое развертывание системы сетевой инспекции и может использоваться для анализа сетевых потоков, проверки политик обнаружения и подготовки материалов по мониторингу Linux-инфраструктуры.
