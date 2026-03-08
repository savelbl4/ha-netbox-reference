# Как полльзоваться

- Установить зависимости
    >pip install -r requirements.txt

- Определите основные переменные в `inventory/group_vars/netbox/main.yml`

- Определите секреты в `inventory/group_vars/netbox/secrets.yml`
    - Можно запустить скрипт `. ./gen_pass.sh` он создаст файл и сгенерирует случайные пароли
    - В файле секретов можно переопределить любые переменные

- Актуализируйте данные инвентаря
    - `inventory/hosts.ini` - адреса DHCP + static
    - `inventory/hosts_static.ini`

- Для первичной настройки сети нужно прокатить плейбук с тегом "network"
    > `ansible-playbook -i inventory/hosts.ini playbooks/bootstrap.yml -l netbox --tags network`
    - После этого перезапустите ноды
    > 'ansible -u root -m reboot -a 'reboot_timeout=300' netbox'

- Запустите первый плейбук
    > ansible-playbook playbooks/bootstrap.yml -l netbox
    - На этом этапе установятся и настроятся нужные приложения.
    - Mогут возникнуть проблемы со скриптом `/usr/local/bin/netbox_sync.sh` он синхронизирует плагины и картинки с живого мастера Netbox
    - **Важно чтобы файл сертификата был валидным, иначе Angie не поднимется**

- Восстановите базу данных последовательно на всех хостах
    ```bash
    # остановим patroni на всех нодах
    systemctl stop patroni
    # проверим наличие кластера и удалим его если есть
    patronictl -c /etc/patroni/patroni.yml list
    patronictl -c /etc/patroni/patroni.yml remove pgcluster
    # удалим старую директорию с базой
    rm -rf /var/lib/postgresql/17/patroni
    # скопируем базу, которую хотим восстановить (только на мастер)
    scp -3r 172.16.113.203:/var/lib/postgresql/17/patroni /var/lib/postgresql/17/
    # удалим лишний файлик
    rm -f /var/lib/postgresql/17/patroni/standby.signal
    # правим овнера и права на директорию
    chown -R postgres:postgres /var/lib/postgresql/17/patroni
    chmod -R 700 /var/lib/postgresql/17/patroni
    # проверим всё ли хорошо с сетевыми доступами у базы 
    grep -vE '^($|#)' /var/lib/postgresql/17/patroni/pg_hba.conf
    # запускаем с начала на мастере
    systemctl start patroni
    # и смотрим статус
    patronictl -c /etc/patroni/patroni.yml list
    ```
    > как только всё поднялось, можно поднять patroni на репликах
    - 'ansible -u root -m shell -a "systemctl start patroni" netbox'

- Запустите второй плейбук
    > ansible-playbook playbooks/site.yml -l netbox
    - На этом этапе применятся настройки Netbox и сервис запустится.
    - **Сработает только если кластер СУБД запущен**

- Смотрите за метриками тут
    > https://grafana.demo.example.ru/ (alloy_remote_host)
    - креды для входа `admin/grafana` 

[//]: # (ansible-playbook -i inventory/hosts_support.ini playbooks/vm_fusion.yml --tags stop)
[//]: # (ansible-playbook playbooks/vm_fusion.yml --tags stop)

---

# Инфраструктурный стек NetBox

(PostgreSQL, etcd, Patroni, HAProxy, Keepalived, PgBouncer, Redis, Angie)

---

## 1) etcd

### Итог
Собран рабочий 3‑узловой etcd‑кластер для Patroni на Debian 13 с кастомными портами `22379/22380`.

**Узлы**
- netbox-node-1 — 172.16.113.201
- netbox-node-2 — 172.16.113.202
- netbox-node-3 — 172.16.113.203

Кластер в кворуме, лидер — **netbox-node-2**, все endpoint’ы healthy.

### Что настроено
- Пакеты: `etcd-server`, `etcd-client`.
- Systemd: вместо штатного `etcd.service` — собственный юнит `etcd-patroni.service` в `/usr/lib/systemd/system/` (штатный замаскирован).
- Конфиг `/etc/etcd/etcd.conf.yml`:
  - `data-dir: /var/lib/etcd-patroni` (права 0700).
  - client:
    - `listen-client-urls: http://0.0.0.0:22379`
    - `advertise-client-urls: http://<IP>:22379`
  - peer:
    - `listen-peer-urls: http://0.0.0.0:22380`
    - `initial-advertise-peer-urls: http://<IP>:22380`
  - `initial-cluster: "netbox-node-1=http://172.16.113.201:22380,netbox-node-2=http://172.16.113.202:22380,netbox-node-3=http://172.16.113.203:22380"`
  - `initial-cluster-state: "new"`
  - Компакция: `auto-compaction-mode: "periodic"`, `auto-compaction-retention: "1h"`
  - Прочее: `snapshot-count: 10000`, `logger: zap`, `log-level: info`
- Авто-дефраг: единичный таймер `etcd-defrag.timer` на 1‑й ноде — раз в неделю запускает `/usr/local/sbin/etcd-defrag.sh`.

### Полезные команды / привычки
```bash
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=172.16.113.201:22379,172.16.113.202:22379,172.16.113.203:22379

etcdctl endpoint health
etcdctl endpoint status -w table
```

- Если менялся состав/инициализация — перед «чистым» запуском очищать `data-dir` узла.
- Много логов `election/pre-vote` на одиночной ноде — норма до появления кворума (2/3).

---

## 2) PostgreSQL 17 + Patroni

### Что строили
Кластер PostgreSQL 17 + Patroni на Debian 13 (3 узла):  
172.16.113.201 (netbox-node-1), 172.16.113.202 (netbox-node-2), 172.16.113.203 (netbox-node-3).  
etcd на тех же хостах (client 22379, peer 22380).  
RAM: 16 ГБ. Доступ клиентов: `172.16.0.128/25`.  
Python 3.13.5 установлен; важно, чтобы зависимости Patroni были в используемом интерпретаторе/виртуалке.

### Ключевые итоги и настройки Patroni (`/etc/patroni/patroni.yml`)
> Важно: `listen/port` и `connect_address` берутся **только** из локального `/etc/patroni/patroni.yml` и применяются **после рестарта** Postgres — из DCS они не подтягиваются.

```yaml
scope: "pgcluster"
namespace: "/service/pgcluster"
name: "{{ inventory_hostname }}"

restapi:
  listen: 0.0.0.0:8008
  connect_address: "{{ hostvars[inventory_hostname].node_ip }}:8008"

etcd3:
  hosts: "172.16.113.201:22379,172.16.113.202:22379,172.16.113.203:22379"

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    synchronous_mode: True
    synchronous_node_count: 1
    synchronous_mode_strict: True
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
        shared_buffers: "2GB"
        effective_cache_size: "6GB"
        maintenance_work_mem: "512MB"
        wal_level: "logical"
        max_replication_slots: 40
        max_wal_senders: 30
        max_logical_replication_workers: 8
        max_worker_processes: 16
        wal_compression: "on"
        max_slot_wal_keep_size: "32GB"
        wal_keep_size: "1024MB"
        hot_standby: "on"
  initdb:
    - encoding: "UTF8"
    - data-checksums
  users:
    replicator:
      password: "{{ patroni_replication_password }}"
      options:
        - replication
    postgres:
      password: "{{ patroni_superuser_password }}"
  pg_hba:
    - "local all all peer"
    - "host all all 127.0.0.1/32 md5"
    - "host all all ::1/128 md5"
    - "host replication replicator 127.0.0.1/32 md5"
    - "host replication replicator ::1/128 md5"
    - "host replication replicator 172.16.0.128/25 md5"
    - "host all all 127.0.0.1/32 md5"
    - "host all all ::1/128 md5"
    - "host all all 172.16.0.128/25 md5"

postgresql:
  listen: "{{ hostvars[inventory_hostname].node_ip }}:{{ pg_port }}"
  connect_address: "{{ hostvars[inventory_hostname].node_ip }}:{{ pg_port }}"
  data_dir: "{{ patroni_data_dir }}"
  bin_dir: "/usr/lib/postgresql/{{ pg_version }}/bin"
  authentication:
    superuser:
      username: "{{ pg_superuser }}"
      password: "{{ pg_superuser_password }}"
    replication:
      username: "{{ replication_user }}"
      password: "{{ replication_password }}"
  parameters:
    unix_socket_directories: "/var/run/postgresql"

tags:
  nofailover: False
  nosync: False
  noloadbalance: false
  clonefrom: false
```

### Динамический конфиг через DCS (неинтерактивно)
```bash
cat >/tmp/patroni-dynamic-config.yml <<'YAML'
synchronous_mode: true
synchronous_mode_strict: true
synchronous_node_count: 1
postgresql:
  pg_hba:
    - "local all postgres peer"
    - "local all all      peer"
    - "host  all all      127.0.0.1/32 md5"
    - "host  all all      ::1/128 md5"
    - "host  replication replicator 127.0.0.1/32 md5"
    - "host  replication replicator ::1/128 md5"
    - "host  replication replicator 172.16.0.128/25 md5"
    - "host  all all      172.16.0.128/25 md5"
  parameters:
    wal_level: logical
    wal_compression: on
    max_wal_senders: 30
    max_replication_slots: 40
    max_slot_wal_keep_size: 32GB
    max_logical_replication_workers: 8
    max_worker_processes: 16
    shared_buffers: 2GB
    effective_cache_size: 6GB
    maintenance_work_mem: 512MB
    wal_keep_size: 1024MB
    hot_standby: on
YAML

patronictl -c /etc/patroni/patroni.yml edit-config pgcluster --apply /tmp/patroni-dynamic-config.yml <<<"y"
patronictl -c /etc/patroni/patroni.yml reload pgcluster
```

> `listen/connect_address` в DCS — бессмысленны; меняются только в локальном файле + *restart* PostgreSQL.

### HAProxy (на тех же хостах)
- Отдаём клиентам `172.16.113.204:5432` (VIP).
- Бэкенды указывают `<node_ip>:5432`, health‑check через Patroni `/read-write` на `:8008`.

**Пример бэкенда**
```haproxy
backend pg_bkwrite
    mode tcp
    balance first
    option tcp-check
    tcp-check connect port 8008
    tcp-check send "GET /master HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    tcp-check expect rstring ^HTTP/1\.[01]\ 200\ OK
    tcp-check connect port 5432
    timeout connect 3s
    timeout server  30s

    default-server inter 1s fall 2 rise 2 maxconn 500
    server netbox-node-1 172.16.113.201:5432 check on-marked-down shutdown-sessions
    server netbox-node-2 172.16.113.202:5432 check on-marked-down shutdown-sessions
    server netbox-node-3 172.16.113.203:5432 check on-marked-down shutdown-sessions
```

### Частые грабли и решения
- *Can not find suitable configuration of DCS* — Patroni запущен с Python без модулей `etcd3gw/etcd3`. Запускать из окружения, где модули установлены; проверить `ExecStart` в systemd.
- `/health = 503`, `patronictl list → unknown` — нет HBA для `127.0.0.1/::1` → добавить в `pg_hba`, сделать `reload` (проверка через `pg_hba_file_rules`).
- Bootstrap: `no pg_hba.conf entry ... user "postgres"` — не хватает TCP‑разрешений для локального адреса/своего IP → добавить `127.0.0.1/32`, `::1/128`, `172.16.0.128/25` в `bootstrap.pg_hba`, при необходимости пересобрать.
- Switchover “no good candidates” — кандидат не готов (узел `starting`, проблемы с WAL/HBA) → чинить репликацию/HBA, при необходимости `reinit` реплики.

### Полезные команды (шпаргалка)
```bash
# состояние
patronictl -c /etc/patroni/patroni.yml list
patronictl -c /etc/patroni/patroni.yml topology
.
curl -s http://<node>:8008/patroni | jq .

# конфиг DCS
patronictl -c /etc/patroni/patroni.yml show-config
patronictl -c /etc/patroni/patroni.yml edit-config pgcluster --apply file.yml <<<"y"

# перезагрузки/рестарты
patronictl -c /etc/patroni/patroni.yml reload   pgcluster [member]
patronictl -c /etc/patroni/patroni.yml restart  pgcluster [member] --force
patronictl -c /etc/patroni/patroni.yml reinit   pgcluster [member]

# HBA на узле
psql -U postgres -Atc "SHOW hba_file;"
psql -U postgres -x -c "SELECT * FROM pg_hba_file_rules ORDER BY line_number;"
```

### Логическая репликация: заметки
- `DROP SUBSCRIPTION` выполняется **на подписчике** (в вашей БД `netbox` на 172.16.113.204).
- Если паблишер недоступен:
  ```sql
  ALTER SUBSCRIPTION netbox_sub DISABLE;
  ALTER SUBSCRIPTION netbox_sub SET (slot_name = NONE);
  DROP SUBSCRIPTION netbox_sub;
  -- или: DROP SUBSCRIPTION netbox_sub WITH (force); в новых версиях
  ```

---

## 3) Patroni + HAProxy + Keepalived (общая обвязка)

### Хосты кластера
- netbox-node-1 → 172.16.113.201
- netbox-node-2 → 172.16.113.202
- netbox-node-3 → 172.16.113.203

**VIP:** 172.16.113.204 (переезжает между нодами через Keepalived).

### HAProxy
- `frontend pg_write` → backend `/master`, ходит **только на лидера**.
- `frontend pg_read`  → backend `/replica`, ходит **на реплики**.
- Проверка здоровья через Patroni REST (`GET /master` / `GET /replica` на `:8008`) + TCP connect к `5432`.
- `on-marked-down shutdown-sessions` в `server`‑строках.

### Keepalived
- Две VRRP‑инстанции:
  - `VI_PG_VIP`: интерфейс `eth0`, VIP `172.16.113.204/24` (Postgres).
  - `VI_NB_VIP`: интерфейс `eth0`, VIP `172.16.113.205/25` (NetBox).

---

## 4) PgBouncer

### HAProxy
Слушает **только** VIP `172.16.113.204:6432`.

```haproxy
backend pgbouncer_nodes
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6432
    default-server inter 1s fall 2 rise 2 maxconn 500

    server netbox-node-1 172.16.113.201:6432 check
    server netbox-node-2 172.16.113.202:6432 check
    server netbox-node-3 172.16.113.203:6432 check

    acl dz_demo_srv_13_up  srv_is_up(pgbouncer_nodes/netbox-node-1)
    acl dz_demo_srv_14_up  srv_is_up(pgbouncer_nodes/netbox-node-2)
    acl dz_demo_srv_15_up  srv_is_up(pgbouncer_nodes/netbox-node-3)

    acl from_dz_demo_srv_13 src 172.16.113.201
    acl from_dz_demo_srv_14 src 172.16.113.202
    acl from_dz_demo_srv_15 src 172.16.113.203

    use-server netbox-node-1 if dz_demo_srv_13_up

    use-server netbox-node-1 if from_dz_demo_srv_13 dz_demo_srv_13_up
    use-server netbox-node-2 if from_dz_demo_srv_14 dz_demo_srv_14_up
    use-server netbox-node-3 if from_dz_demo_srv_15 dz_demo_srv_15_up
```

### Контекст и финальная конфигурация
1. План: PgBouncer на всех трёх узлах; клиенты приходят на VIP через HAProxy, затем на PgBouncer узлов.
2. Пользователь/права:
   - Service запускается под `postgres` (создавать отдельного системного пользователя не требуется).
   - `/etc/pgbouncer/` — `root:root 0755`
   - `pgbouncer.ini` — `postgres:postgres 0644`
   - `userlist.txt` — `postgres:postgres 0640`
3. PID/Runtime:
   - `pidfile = /run/pgbouncer/pgbouncer.pid`
   - systemd drop‑in: `/usr/lib/systemd/system/pgbouncer.service.d/override.conf`
     ```ini
     [Service]
     User=postgres
     Group=postgres
     RuntimeDirectory=pgbouncer
     RuntimeDirectoryMode=0750
     LimitNOFILE=8192
     ```
4. Сети:
   - PgBouncer слушает `<node_ip>:6432` на всех нодах.
   - **Нельзя** биндить PgBouncer на VIP — его публикует HAProxy.
   - HAProxy публикует `VIP:6432` → узлы `:6432` (приоритет: локальный сервер → хост клиента → roundrobin).
5. Конфиг Jinja:
   - Алиасы: `netbox_write`, `netbox_read`, `netbox_test_write`, `netbox_test_read` и/или прямые `netbox`, `netbox-test`.

### Отладка/ошибки
- `chown failed: failed to look up user pgbouncer` — не нужен отдельный пользователь; запускать под `postgres`.
- `Permission denied` для `auth_file` — права каталогов/файлов как выше.
- `no such database: netbox-test` — добавить алиас или прямую БД в `[databases]`.

---

## 5) Redis Sentinel + HAProxy + VIP

### Хосты
- netbox-node-1 → 172.16.113.201
- netbox-node-2 → 172.16.113.202
- netbox-node-3 → 172.16.113.203
- VIP (Keepalived) → 172.16.113.204

### Redis
- Запускается на всех трёх узлах (1 мастер, 2 реплики).
- Конфиг (базовый): `/etc/redis/redis.conf`
  ```conf
  port 6379
  bind 127.0.0.1 <node_ip>
  protected-mode yes
  requirepass "REDIS_PASS"
  masterauth "REDIS_PASS"
  dir /var/lib/redis

  # для реплик:
  replicaof 172.16.113.201 6379
  ```
- Данные/AOF — `/var/lib/redis`, права `redis:redis 0750`.

### Sentinel
- Поднят на всех трёх нодах (порт 26379). Конфиг `/etc/redis/sentinel.conf`:
  ```conf
  port 26379
  bind 0.0.0.0
  sentinel monitor myredis 172.16.113.201 6379 2
  sentinel auth-pass myredis REDIS_PASS
  sentinel down-after-milliseconds myredis 5000
  sentinel parallel-syncs myredis 1
  sentinel failover-timeout myredis 60000
  ```
- Юнит использует `redis-server --sentinel`.

### HAProxy
Слушает **только** VIP `172.16.113.204:6379`.

```haproxy
backend be_redis_master
    mode tcp
    option tcp-check
    timeout connect 3s
    timeout server  30s
    timeout check   1s

    default-server inter 1000ms fastinter 200ms downinter 500ms rise 1 fall 1
    tcp-check connect
    tcp-check send AUTH\ {{ redis_password }}\r\n
    tcp-check expect string +OK
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    tcp-check send ROLE\r\n
    tcp-check expect rstring \bmaster\b
    tcp-check send QUIT\r\n
    tcp-check expect string +OK

    server netbox-node-1 172.16.113.201:6379 check
    server netbox-node-2 172.16.113.202:6379 check
    server netbox-node-3 172.16.113.203:6379 check
```
Админ‑сокет: `stats socket /run/haproxy/admin.sock mode 660 level admin`. Это строка в конфиге `/etc/haproxy/haproxy.cfg`

### Проверки
```bash
# Кто мастер по мнению Sentinel
redis-cli -p 26379 SENTINEL get-master-addr-by-name {{ sentinel_name }}

# Через VIP (HAProxy)
redis-cli -h 172.16.113.204 -p 6379 -a '{{ redis_password }}' ROLE

# Статус бэкендов в HAProxy
echo "show servers state be_redis_master" | socat - UNIX-CONNECT:/run/haproxy/admin.sock
```

### Решённые проблемы
- Sentinel не стартовал → юнит на `redis-server --sentinel`.
- Redis падал с `appendonlydir: Read-only file system` → `dir /var/lib/redis`.
- Redis слушал только на 127.0.0.1 → добавлен `bind 127.0.0.1 <node_ip>`.
- HAProxy рвал соединение → порядок `tcp-check`: `AUTH → PING → ROLE`.
- После падения мастера не было переключения → `fastinter/downinter` + `restring master`.

### Частые грабли и решения
- Если собираетесь руками править конфиги redis/sentinel, то с начала стоит потушить sentinel → redis а после правок поднять в обратном порядке. 

---

## 6) Angie (reverse‑proxy для NetBox) + Keepalived (VIP 172.16.113.205)

### Архитектура и роли
- Узлы: **netbox-node-1** (172.16.113.201), **netbox-node-2** (172.16.113.202), **netbox-node-3** (172.16.113.203).
- Keepalived: на всех трёх узлах (VRRP), VIP: **172.16.113.205**.
- Angie: на всех трёх; реверс‑прокси на локальный gunicorn (**127.0.0.1:8001**).
- **Angie слушает VIP** `172.16.113.205` напрямую (TLS на 443, редирект с 80 на 443).

### Конфигурация Angie (`/etc/angie/http.d/netbox.conf`)
```nginx
server {
    listen 172.16.113.205:443 ssl;
    listen 127.0.0.1:80;
    server_name netbox.example.local 172.16.113.205;

    ssl_certificate /etc/ssl/private/netbox.crt;
    ssl_certificate_key /etc/ssl/private/netbox.key;

    client_max_body_size 25m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;


    location /static/ {
        alias /opt/netbox/netbox/static/;
    }

    location =/p8s {
        prometheus all;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;

        proxy_set_header Host               $host;
        proxy_set_header X-Forwarded-Host   $host;
        proxy_set_header X-Forwarded-Proto  https;
        proxy_set_header X-Forwarded-Port   443;
        proxy_set_header X-Real-IP          $remote_addr;
        proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Connection         "";
        proxy_redirect off;
    }
}

server {
    listen 172.16.113.205:80;
    server_name _;
    return 301 https://$host$request_uri;
}
```

### Важно/заметки
- Так как Angie слушает **VIP на всех узлах**, чтобы избежать ошибок старта на резервных нодах, включите:
  ```bash
  sysctl -w net.ipv4.ip_nonlocal_bind=1
  # и сделайте это постоянным в /etc/sysctl.d/60-vip-nonlocal.conf
  ```
- Убедитесь, что процесс Angie имеет доступ к приватному ключу:
  - `netbox.crt`/`netbox.key` читаемы пользователем/группой, под которой работает Angie (обычно `www-data` или `angie`). Рекомендуемые права: `0640`.
- `server_name` содержит домен и сам VIP — это упрощает обращения по IP.
- В /static/ раздаётся статика NetBox; основной трафик проксируется в gunicorn `127.0.0.1:8001`.
- Обновить сертификат
  положить новый сертификат в `playbooks/roles/angie/files/`
  `ansible-playbook playbooks/bootstrap.yml -l netbox --tags angie -e name_of_certs=<новое имя>`

---

## 7) HAProxy

Статистику можно будет посмотреть по адресу `172.16.113.204:7000/haproxy?stats`

### Конфигурация HAProxy (`/etc/haproxy/haproxy.cfg`)

```haproxy
global
    stats socket /run/haproxy/admin.sock mode 660 level admin
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 10000
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend pg_write
    bind 172.16.113.204:5432
    default_backend pg_bkwrite

backend pg_bkwrite
    mode tcp
    balance first
    option tcp-check
    tcp-check connect port 8008
    tcp-check send "GET /master HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    tcp-check expect rstring ^HTTP/1\.[01]\ 200\ OK
    tcp-check connect port 5432
    timeout connect 3s
    timeout server  30s

    default-server inter 1s fall 2 rise 2 maxconn 500
    server netbox-node-1 172.16.113.201:5432 check on-marked-down shutdown-sessions
    server netbox-node-2 172.16.113.202:5432 check on-marked-down shutdown-sessions
    server netbox-node-3 172.16.113.203:5432 check on-marked-down shutdown-sessions

frontend pg_read
    bind 172.16.113.204:5433
    default_backend pg_bkread

backend pg_bkread
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 8008
    tcp-check send "GET /replica HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    tcp-check expect rstring ^HTTP/1\.[01]\ 200\ OK
    tcp-check connect port 5432
    timeout connect 3s
    timeout server  30s

    default-server inter 1s fall 2 rise 2 maxconn 500
    server netbox-node-1 172.16.113.201:5432 check on-marked-down shutdown-sessions
    server netbox-node-2 172.16.113.202:5432 check on-marked-down shutdown-sessions
    server netbox-node-3 172.16.113.203:5432 check on-marked-down shutdown-sessions

frontend fe_redis
    bind 172.16.113.204:6379
    mode tcp
    default_backend be_redis_master

backend be_redis_master
    mode tcp
    option tcp-check
    timeout connect 3s
    timeout server  30s
    timeout check   1s

    default-server inter 1000ms fastinter 200ms downinter 500ms rise 1 fall 1
    tcp-check connect
    tcp-check send AUTH\ {{ redis_password }}\r\n
    tcp-check expect string +OK
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    tcp-check send ROLE\r\n
    tcp-check expect rstring \bmaster\b
    tcp-check send QUIT\r\n
    tcp-check expect string +OK

    server netbox-node-1 172.16.113.201:6379 check
    server netbox-node-2 172.16.113.202:6379 check
    server netbox-node-3 172.16.113.203:6379 check

frontend pgbouncer_vip
    bind 172.16.113.204:6432
    mode tcp
    option tcplog
    default_backend pgbouncer_nodes

backend pgbouncer_nodes
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 6432
    default-server inter 1s fall 2 rise 2 maxconn 500

    server netbox-node-1 172.16.113.201:6432 check
    server netbox-node-2 172.16.113.202:6432 check
    server netbox-node-3 172.16.113.203:6432 check

    acl netbox_node_1_up  srv_is_up(pgbouncer_nodes/netbox-node-1)
    acl netbox_node_2_up  srv_is_up(pgbouncer_nodes/netbox-node-2)
    acl netbox_node_3_up  srv_is_up(pgbouncer_nodes/netbox-node-3)

    acl from_netbox_node_1 src 172.16.113.201
    acl from_netbox_node_2 src 172.16.113.202
    acl from_netbox_node_3 src 172.16.113.203

    use-server netbox-node-1 if netbox_node_1_up

    use-server netbox-node-1 if from_netbox_node_1 netbox_node_1_up
    use-server netbox-node-2 if from_netbox_node_2 netbox_node_2_up
    use-server netbox-node-3 if from_netbox_node_3 netbox_node_3_up


listen stats
    bind 0.0.0.0:7000
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 5s
```
---

## 8) Keepalived
### Конфигурация Keepalived (`/etc/keepalived/keepalived.conf`)

```keepalived
vrrp_script chk_master {
    script "/usr/local/bin/patroni_is_master.sh"
    interval 1
    timeout 1
    fall 2
    rise 1
}

vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
    interval 1
    timeout 1
    fall 2
    rise 1
}

vrrp_script chk_netbox {
    script "/usr/local/bin/check_angie_netbox.sh"
    interval 1
    timeout 1
    fall 2
    rise 1
}

vrrp_instance VI_PG_VIP {
    state BACKUP
    interface eth0
    virtual_router_id 204
    priority 200
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass {{ vrrp_auth_pass }}
    }

    track_script {
        chk_master  weight -30
        chk_netbox  weight -30
        chk_haproxy weight -30
    }

    virtual_ipaddress {
        172.16.113.204/24 dev eth0 label eth0:vip204
    }
}

vrrp_instance VI_NB_VIP {
    state BACKUP
    interface eth0
    virtual_router_id 205
    priority 200
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass {{ vrrp_auth_pass }}
    }

    track_script {
        chk_master weight -50
        chk_netbox weight -100
    }

    virtual_ipaddress {
        172.16.113.205/24 dev eth0 label eth0:vip205
    }
}
```

---

## Приложение: Быстрые чек-листы

### etcd
- [ ] 3 узла в кворуме, лидер выбран
- [ ] `ETCDCTL_API=3`, `ETCDCTL_ENDPOINTS` выставлены
- [ ] `endpoint status -w table` → healthy
- [ ] auto‑compaction: periodic/1h, defrag‑таймер на 1‑й ноде

### Patroni/PostgreSQL
- [ ] Postgres слушает на `<node_ip>:5432`, HAProxy публикует `VIP:5432`
- [ ] HBA включает `127.0.0.1/32`, `::1/128`, `172.16.0.128/25`, `172.16.0.128/25`
- [ ] `patronictl list/topology` ок, `/health` возвращает 200

### HAProxy/Keepalived
- [ ] VIP(ы) назначаются на 1/2‑ю ноды, `ip_nonlocal_bind=1`
- [ ] Health‑checks корректны (Patroni REST, Redis ROLE, Angie /health)
- [ ] `on-marked-down shutdown-sessions` для graceful‑дампа
- [ ] GARP включён, VRID разнесены

### PgBouncer
- [ ] Слушает `<node_ip>:6432`, pid в `/run/pgbouncer/`
- [ ] Алиасы в `[databases]` соответствуют БД/сценариям

### Redis/Sentinel
- [ ] Глобальные `requirepass/masterauth` синхронизированы
- [ ] Sentinel monitor настроен на мастер
- [ ] HAProxy health‑checks (AUTH→PING→ROLE) проходят
- [ ] `ROLE` через VIP показывает `master` на активном узле
