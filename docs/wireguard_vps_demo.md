# WireGuard VPS Demo

Этот режим нужен для демонстрации работы стенда без SPAN/TAP и без изменения локальной сети. Тестовый клиент подключается к VPS по WireGuard, а ntopng и Zeek анализируют трафик на интерфейсе `wg0`.

## Топология

```text
Test client
    |
    | WireGuard full tunnel
    v
VPS / VDS
    |
    +-- WireGuard wg0
    +-- ntopng
    +-- Redis
    +-- Zeek
    +-- Nginx Basic Auth
    |
 Internet
```

## Установка одной командой

Публичный репозиторий позволяет развернуть стенд одной командой без дополнительных токенов:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install-vps-wireguard.sh)
```

Во время установки скрипт спросит, нужно ли задать собственный логин и пароль для панели. Если ответить `N`, будет создан случайный пароль для пользователя `ntopadmin`.

С параметрами без интерактивного ввода:

```bash
sudo SERVER_PUBLIC_IP=<vps-public-ip> \
  WG_PORT=51820 \
  NGINX_LISTEN_PORT=8088 \
  NGINX_EXTRA_LISTEN_PORT=8080 \
  NGINX_BASIC_USER=admin \
  NGINX_BASIC_PASSWORD=<strong-password> \
  bash <(curl -fsSL https://raw.githubusercontent.com/hellojjjwww/ntopng-inspection-stand/main/install-vps-wireguard.sh)
```

## После установки

На VPS:

```bash
cd /opt/ntopng-wireguard-demo
docker compose -f deploy/docker-compose.yml ps
scripts/doctor.sh
systemctl status wg-quick@wg0
```

Клиентский конфиг:

```text
/opt/ntopng-wireguard-demo/wireguard/client.conf
```

Для удобного скачивания установщик дополнительно копирует файл в домашнюю директорию пользователя, от имени которого был запущен `sudo`:

```text
/home/<user>/ntopng-wireguard-client.conf
```

В Termius этот файл можно скачать через SFTP file browser. В обычном терминале:

```bash
scp <user>@<vps-public-ip>:/home/<user>/ntopng-wireguard-client.conf ./ntopng-wireguard-client.conf
```

В конце установки скрипт также печатает тестовый WireGuard client config в терминал, чтобы его можно было сразу скопировать и импортировать в WireGuard.

Панель ntopng:

```text
http://<vps-public-ip>:8088/
http://<vps-public-ip>:8080/
```

## Что показывать на демонстрации

1. Подключить тестовый клиент к WireGuard.
2. Открыть несколько сайтов, выполнить DNS-запросы, скачать небольшой файл.
3. В ntopng открыть интерфейс `wg0`.
4. Показать live flows, hosts, protocols/applications, throughput.
5. В Zeek проверить логи:

```bash
docker compose -f deploy/docker-compose.yml exec zeek ls -lah /var/log/zeek
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/conn.log
docker compose -f deploy/docker-compose.yml exec zeek tail -n 20 /var/log/zeek/dns.log
```

## Ограничения

- Виден трафик клиентов, которые подключены к WireGuard и используют full tunnel.
- HTTPS-содержимое не расшифровывается, но видны направления, SNI/метаданные, DNS, объемы и поведение потоков.
- Для панели ntopng порт `8088/tcp` лучше ограничить по IP в firewall/security group VPS.
