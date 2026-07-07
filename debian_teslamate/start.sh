#!/bin/bash

# --- TeslaMate Samsung A6 Engine v56 (Connection & MQTT Fix) ---
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export DATABASE_HOST=127.0.0.1
LOG_FILE="/opt/teslamate/teslamate_full.log"

echo "=== LOG RESTART: $(date) ===" > "$LOG_FILE"

cleanup() {
    echo -e "\n\n[!] CRASH SAU OPRIRE DETECTATĂ." >> "$LOG_FILE"
    tail -n 20 "$LOG_FILE"
    echo "------------------------------------------------"
    echo "Apasă ENTER pentru a ieși..."
    read
}
trap cleanup EXIT

{
    # 1. Curățare procese și erori silențioase
    echo "[1/5] Eliberare memorie și porturi..."
    pkill -9 postgres 2>/dev/null
    pkill -9 beam.smp 2>/dev/null
    pkill -9 grafana-server 2>/dev/null
    pkill -9 mosquitto 2>/dev/null
    fuser -k 4000/tcp 3000/tcp 5432/tcp 1883/tcp 2>/dev/null
    
    # Curățăm lock-urile de memorie
    rm -f /var/lib/postgresql/17/main/postmaster.pid 2>/dev/null
    rm -rf /tmp/.s.PGSQL.* 2>/dev/null
    mkdir -p /var/run/postgresql
    chown -R postgres:postgres /var/run/postgresql
    
    # Încercăm curățarea cache-ului fără să afișăm eroarea de permisiuni
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

    # 2. Pornire Mosquitto (CRITIC: TeslaMate moare fără MQTT)
    echo "[2/5] Pornire Serviciu Mesagerie (MQTT)..."
    service mosquitto start || mosquitto -d

    #2.1 Pornire backup service - chron
    service cron start

    # --- 2.2 Pornire Tunel Acvariu (Proxy) ---
    echo "[2.2/5] Pornire Proxy Acvariu pe portul 8080..."
    pkill -f "socat TCP-LISTEN:8080" 2>/dev/null
    nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:192.168.1.32:80 > /dev/null 2>&1 &

    # 3. Pornire PostgreSQL (Fix: Creștem conexiunile la 20)
    echo "[3/5] Pornire Bază de Date (Fix Connections)..."
    sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/17/main -l /var/lib/postgresql/17/main/logfile -o "-c shared_memory_type=mmap -c shared_buffers=12MB -c max_connections=25 -c fsync=off" start
    
    for i in {1..15}; do
        if sudo -u postgres /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 > /dev/null 2>&1; then
            echo "[OK] DB Gata."
            break
        fi
        [ $i -eq 15 ] && echo "[!] DB Timeout." && exit 1
        sleep 2
    done

    # 4. Pornire Grafana
    echo "[4/5] Pornire Grafana..."
    /usr/share/grafana/bin/grafana-server \
      --config=/etc/grafana/grafana.ini \
      --homepath=/usr/share/grafana \
      cfg:default.paths.logs=/var/log/grafana \
      cfg:default.paths.data=/var/lib/grafana &

    # 5. Pornire TeslaMate
    echo "[5/5] Pornire TeslaMate Core..."
    cd /opt/teslamate
    export $(grep -v '^#' .env | xargs)
    export DATABASE_HOST=127.0.0.1
    
    # Repară tabelele dacă e cazul
    mix ecto.migrate
    
    echo "[!] Cinderella se trezește..."
    mix phx.server

} 2>&1 | tee -a "$LOG_FILE"
