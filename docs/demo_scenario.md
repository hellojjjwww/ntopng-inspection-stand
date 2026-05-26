# Practical Demonstration Scenario

## Назначение Сценария

Сценарий показывает работу стенда как пассивного NDR/IDS-сенсора: развертывание, сбор нормального трафика, генерация лабораторной аномалии, анализ в ntopng и подтверждение события по логам Zeek.

## Этап 1. Развертывание

```bash
sudo CAPTURE_INTERFACE=ens18 \
  bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

После установки открыть:

```text
http://<server-ip>:8088/
```

## Этап 2. Проверка Сервисов

```bash
cd /opt/ntopng-inspection-stand
docker compose -f deploy/docker-compose.yml ps
```

Ожидаемые сервисы:

- `ntopng-redis`
- `ntopng`
- `zeek-sensor`
- `ntopng-proxy`

## Этап 3. Проверка Доступа

```bash
NGINX_BASIC_USER=ntopadmin \
NGINX_BASIC_PASSWORD='<password>' \
deploy/scripts/tests/validate_stack.sh
```

Ожидаемый результат:

```text
Stack validation completed successfully.
```

## Этап 4. Нормальный Трафик

Сформировать обычную активность:

- открыть несколько HTTPS-сайтов;
- выполнить DNS-запросы;
- подключиться по SSH;
- скачать небольшой файл.

Проверить в ntopng:

- `Interfaces`;
- `Flows`;
- `Hosts`;
- `Applications`.

Проверить в Zeek:

```bash
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/conn.log
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/dns.log
```

## Этап 5. Генерация Аномалии

DNS burst:

```bash
sudo python3 scripts/generate_anomaly.py suspicious-dns \
  --resolver 1.1.1.1 \
  --domain lab.example \
  --count 100
```

SYN traffic:

```bash
sudo python3 scripts/generate_anomaly.py syn-flood \
  --target <lab-ip> \
  --port 80 \
  --count 500
```

## Этап 6. Анализ Результата

В ntopng:

- проверить `Alerts`;
- открыть `Flows`;
- найти источник тестового трафика;
- проверить приложение/протокол;
- зафиксировать график интерфейса.

В Zeek:

```bash
docker compose -f deploy/docker-compose.yml exec zeek tail -n 50 /var/log/zeek/conn.log
docker compose -f deploy/docker-compose.yml exec zeek tail -n 50 /var/log/zeek/dns.log
```

## Этап 7. Сбор Артефактов

```bash
deploy/scripts/tests/collect_evidence.sh
```

Собранные файлы сохраняются в:

```text
artifacts/evidence/<timestamp>/
```

Для отчета обычно достаточно:

- `compose-ps.txt`;
- `ntopng.log`;
- `zeek.log`;
- `zeek-conn.log`;
- `zeek-dns.log`;
- скриншоты ntopng `Interfaces`, `Flows`, `Alerts`.
