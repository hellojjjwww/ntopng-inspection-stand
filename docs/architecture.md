# Архитектура стенда NDR/DPI

Проект реализует NDR/IDS-стенд для контролируемой сети: наблюдение, классификация, алерты, расследование инцидентов и проверка гипотез по трафику.

## Как работает текущий стенд

Поток данных:

```text
network interface / mirror port
        |
        v
ntopng container -> nDPI protocol classification -> flows, hosts, applications, alerts
        |
        +-> Redis: cache, preferences, runtime state
        |
        +-> ntopng-data volume: persistent state and time-series

user browser -> Nginx Basic Auth -> ntopng web UI
```

Компоненты:

- `ntopng` читает пакеты с интерфейса хоста через `libpcap`. Если PF_RING есть на хосте, ntopng пытается использовать его, иначе откатывается на pcap.
- `nDPI` внутри ntopng определяет L7-протоколы: HTTP, TLS, DNS, QUIC, SSH и другие.
- `Redis` хранит кэш, preferences и runtime-состояние ntopng.
- `Nginx` закрывает UI через Basic Auth. Встроенный логин ntopng отключён параметром `--disable-login 1`, чтобы не ловить lockout при тестах.
- `GeoIP` подключается через базы в каталоге `geoip/`.
- `scripts/generate_anomaly.py` генерирует лабораторные аномалии: SYN flood, аномальные DNS-запросы, oversized ICMP.

## Что уже обнаруживается

Текущая версия даёт:

- карту flows: кто с кем общается, по каким портам и протоколам;
- L7-классификацию через nDPI;
- статистику полосы и top talkers;
- host/application/protocol dashboards;
- threshold alerts в ntopng;
- threat intelligence lists, загружаемые ntopng при старте;
- GeoIP/ASN, если положить MaxMind/DB-IP базы;
- лабораторную проверку аномалий через scapy.

## Целевая модель NDR/DPI

Архитектура строится как pipeline обнаружения и анализа:

1. Passive packet capture
   - SPAN/TAP/mirror port.
   - `network_mode: host` на Linux.
   - Возможный PF_RING для высокой скорости.

2. Flow analytics
   - объём трафика;
   - new flows rate;
   - top hosts / top ASNs;
   - long-lived connections;
   - data exfiltration thresholds.

3. DPI и application classification
   - nDPI в ntopng;
   - L7-протоколы поверх нестандартных портов;
   - QUIC/TLS/DNS/HTTP visibility по metadata.

4. TLS/QUIC/DNS fingerprinting
   - SNI, ALPN, JA3/JA4 где доступно;
   - DoH/DoT detection по destination, TLS metadata и flow behavior;
   - NXDOMAIN bursts, high-entropy DNS labels, DNS tunneling indicators.

5. IDS signatures
   - следующий слой проекта: Suricata в IDS-only режиме;
   - EVE JSON output для alert/dns/tls/http/flow событий;
   - Emerging Threats или локальные правила.

6. Network security monitoring
   - следующий слой проекта: Zeek;
   - `conn.log`, `dns.log`, `ssl.log`, `http.log`, `notice.log`;
   - расследование инцидентов через структурированные логи.

7. Long-term storage
   - минимально: Docker volumes ntopng/Redis;
   - production-like: ClickHouse/OpenSearch/Loki для EVE/Zeek/flows;
   - алерты через webhook/syslog/SIEM.

## Как тестировать сейчас

1. Откройте UI:

   ```text
   http://127.0.0.1:8088/
   ```

2. Введите только Basic Auth:

   ```text
   ntopadmin / ntoplab
   ```

3. В ntopng смотрите:

   - `Interfaces`;
   - `Hosts`;
   - `Flows`;
   - `Applications`;
   - `Alerts`.

4. Создайте тестовый трафик:

   ```bash
   sudo python3 scripts/generate_anomaly.py suspicious-dns --resolver 1.1.1.1 --domain lab.example --count 100
   sudo python3 scripts/generate_anomaly.py syn-flood --target <lab-ip> --port 80 --count 500
   ```

5. Проверьте, появились ли flows и alerts.

## Источники по технологиям

- Docker Engine для Ubuntu: <https://docs.docker.com/engine/install/ubuntu/>
- ntopng Redis: <https://ntop.org/guides/ntopng/user_interface/system_interface/health/redis.html>
- ntopng daemon/config: <https://www.ntop.org/guides/ntopng/how_to_start/running_as_a_daemon.html>
- Zeek logs: <https://docs.zeek.org/en/v8.1.1/script-reference/log-files.html>
- Suricata EVE JSON: <https://docs.suricata.io/en/suricata-8.0.4/output/eve/eve-json-output.html>
- Suricata JA3/JA4 metadata: <https://docs.suricata.io/en/suricata-8.0.0/output/eve/eve-json-format.html>
