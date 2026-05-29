# Инструкция по установке и эксплуатации стенда ntopng / Zeek

## 1. Назначение

Стенд предназначен для анализа и глубокого мониторинга сетевого трафика в контролируемой лабораторной или корпоративной сети. Решение позволяет собирать сетевые потоки, классифицировать протоколы, отслеживать утилизацию полосы, фиксировать аномалии и сохранять структурированные сетевые логи.

## 2. Состав стенда

- ntopng: веб-интерфейс, DPI-классификация через nDPI, flows, hosts, applications, alerts.
- Redis: кэш, runtime-состояние и настройки ntopng.
- Zeek: пассивный сетевой сенсор, JSON-логи `conn.log`, `dns.log`, `http.log`, `ssl.log`, `ssh.log`, `notice.log`.
- Nginx: reverse-proxy перед ntopng с Basic Auth.
- GeoIP: каталог для баз GeoLite2 / MaxMind.
- Scapy-тесты: генерация SYN-flood, аномальных DNS-запросов и oversized ICMP.

## 3. Требования к серверу

- Ubuntu LTS, рекомендуемая версия: Ubuntu 24.04 LTS.
- Доступ пользователя с `sudo`.
- Сетевой интерфейс для захвата трафика.
- Доступ в интернет для загрузки Docker-образов и файлов проекта.
- Открытый порт панели, по умолчанию `8088/tcp`.

## 4. Быстрая установка

Выполнить на чистом Ubuntu-сервере:

```bash
sudo bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

Скрипт выполняет следующие действия:

1. Проверяет ОС.
2. Устанавливает Docker Engine и Docker Compose plugin.
3. Определяет сетевой интерфейс.
4. Скачивает проект в `/opt/ntopng-inspection-stand`.
5. Создает `.env` и файл Basic Auth.
6. Включает UFW с политикой default deny incoming.
7. Запускает контейнеры.

Если пароль не задан заранее, установщик создаст его и выведет в конце.

## 5. Установка с параметрами

Пример с явным интерфейсом:

```bash
sudo CAPTURE_INTERFACE=ens18 bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

Пример с заданным логином и паролем:

```bash
sudo CAPTURE_INTERFACE=ens18 \
  NGINX_BASIC_USER=admin \
  NGINX_BASIC_PASSWORD='StrongPasswordHere' \
  bash <(curl -Ls https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install.sh)
```

## 6. Доступ к веб-интерфейсу

Открыть в браузере:

```text
http://<ip-сервера>:8088/
```

Ввести логин и пароль Basic Auth. Встроенный логин ntopng отключен, потому что доступ контролируется Nginx.

## 7. Проверка контейнеров

Перейти в каталог проекта:

```bash
cd /opt/ntopng-inspection-stand
```

Проверить состояние:

```bash
docker compose -f deploy/docker-compose.yml ps
```

Ожидаемые сервисы:

- `ntopng-redis`
- `ntopng`
- `zeek-sensor`
- `ntopng-proxy`

## 8. Просмотр логов

Логи ntopng:

```bash
docker compose -f deploy/docker-compose.yml logs -f ntopng
```

Логи Zeek:

```bash
docker compose -f deploy/docker-compose.yml logs -f zeek
```

Список файлов Zeek:

```bash
docker compose -f deploy/docker-compose.yml exec zeek ls -lah /var/log/zeek
```

Пример просмотра `conn.log`:

```bash
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/conn.log
```

## 9. Автоматическая проверка стенда

Запустить интеграционную проверку:

```bash
NGINX_BASIC_USER=ntopadmin \
NGINX_BASIC_PASSWORD='<пароль>' \
deploy/scripts/tests/validate_stack.sh
```

Успешный результат:

```text
Stack validation completed successfully.
```

Проверка подтверждает:

- доступ без Basic Auth закрыт HTTP-кодом `401`;
- доступ с Basic Auth проходит до ntopng;
- сервис Zeek присутствует в Docker Compose;
- Docker Compose корректно возвращает состояние стенда.

## 10. Тестирование аномального трафика

Установить зависимости:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r tests/requirements.txt
```

SYN-flood в лабораторный адрес:

```bash
sudo python3 scripts/generate_anomaly.py syn-flood --target <lab-ip> --port 80 --count 500
```

Аномальные DNS-запросы:

```bash
sudo python3 scripts/generate_anomaly.py suspicious-dns --resolver 1.1.1.1 --domain lab.example --count 100
```

Oversized ICMP:

```bash
sudo python3 scripts/generate_anomaly.py oversized-icmp --target <lab-ip> --size 3000 --count 5
```

Генерация пакетов должна выполняться только в контролируемой лабораторной сети.

## 11. Что смотреть после тестов

В ntopng:

- `Interfaces`: наличие трафика на выбранном интерфейсе.
- `Flows`: сетевые соединения.
- `Hosts`: активные узлы.
- `Applications`: DPI-классификация протоколов.
- `Alerts`: события и превышения порогов.

В Zeek:

- `conn.log`: сетевые соединения.
- `dns.log`: DNS-запросы.
- `http.log`: HTTP-события.
- `ssl.log`: TLS/SSL metadata.
- `notice.log`: события безопасности.

## 12. GeoIP

Для GeoIP-визуализации положить базы в каталог `geoip/`:

- `GeoLite2-City.mmdb`
- `GeoLite2-ASN.mmdb`
- `GeoLite2-Country.mmdb`

После добавления баз перезапустить ntopng:

```bash
docker compose -f deploy/docker-compose.yml restart ntopng
```

## 13. Остановка и перезапуск

Остановить стенд:

```bash
docker compose -f deploy/docker-compose.yml down
```

Перезапустить:

```bash
docker compose -f deploy/docker-compose.yml restart
```

Обновить после изменений в репозитории:

```bash
cd /opt/ntopng-inspection-stand
git pull
docker compose -f deploy/docker-compose.yml up -d
```

## 14. Docker Desktop на Windows

Для локальной проверки в Docker Desktop:

```powershell
docker-compose -f deploy/docker-compose.yml -f deploy/docker-compose.desktop.yml up -d
```

Открыть:

```text
http://127.0.0.1:8088/
```

Ограничение: Docker Desktop видит сеть Linux VM, а не физический интерфейс Windows. Для полноценного packet capture рекомендуется Ubuntu-сервер или Ubuntu VM.

## 15. Типовые проблемы

Панель не открывается:

```bash
docker compose -f deploy/docker-compose.yml ps
docker compose -f deploy/docker-compose.yml logs --tail 100 nginx
```

Нет трафика:

```bash
ip -br addr
sudo tcpdump -D
```

Затем проверить `CAPTURE_INTERFACE` в `.env`.

Zeek не пишет логи:

```bash
docker compose -f deploy/docker-compose.yml logs --tail 100 zeek
docker compose -f deploy/docker-compose.yml exec zeek ls -lah /var/log/zeek
```

Basic Auth не принимает пароль:

```bash
python3 scripts/prepare_htpasswd.py
docker compose -f deploy/docker-compose.yml restart nginx
```

## 16. Контрольный список готовности

- Контейнеры запущены и имеют статус `running` / `healthy`.
- ntopng открывается через Nginx Basic Auth.
- На выбранном интерфейсе видны flows.
- В `Applications` отображаются протоколы.
- Zeek создает JSON-логи.
- Scapy-тест генерирует события.
- GeoIP-базы добавлены при необходимости.
- UFW включен и разрешает только необходимые входящие порты.
