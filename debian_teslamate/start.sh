#!/bin/bash

# --- TeslaMate Samsung A6 Engine v57 (Stability Fix) ---
# Changes vs v56:
#   - Services only started if not already running (idempotent)
#   - TeslaMate runs in auto-restart loop — recovers from crashes automatically
#   - Mosquitto is NOT killed on TeslaMate restart
#   - Symlink /opt/teslamate/dashboards created if missing (Grafana provisioning)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export DATABASE_HOST=127.0.0.1
LOG_FILE="/opt/teslamate/teslamate_full.log"

echo "=== START: $(date) ===" | tee -a "$LOG_FILE"

# Fix: symlink pentru Grafana provisioning
if [ ! -e /opt/teslamate/dashboards ]; then
    echo "[fix] Creating missing dashboards symlink..."
    ln -s /opt/teslamate/grafana/dashboards /opt/teslamate/dashboards
    echo "[OK] Symlink created."
fi

# 1. Mosquitto (MQTT)
if pgrep -x mosquitto > /dev/null; then
    echo "[1/4] Mosquitto already running."
else
    echo "[1/4] Starting Mosquitto..."
    pkill -9 mosquitto 2>/dev/null
    sleep 1
    mosquitto -d
    sleep 2
    if pgrep -x mosquitto > /dev/null; then
        echo "[OK] Mosquitto started."
    else
        echo "[!] FATAL: Mosquitto failed. Aborting."
        exit 1
    fi
fi

# 1.1 Cron
service cron start 2>/dev/null

# 1.2 Tunel Acvariu (Proxy)
pkill -f "socat TCP-LISTEN:8080" 2>/dev/null
nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:192.168.1.32:80 > /dev/null 2>&1 &

# 2. PostgreSQL
if sudo -u postgres /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 > /dev/null 2>&1; then
    echo "[2/4] PostgreSQL already running."
else
    echo "[2/4] Starting PostgreSQL..."
    pkill -9 postgres 2>/dev/null
    rm -f /var/lib/postgresql/17/main/postmaster.pid 2>/dev/null
    rm -rf /tmp/.s.PGSQL.* 2>/dev/null
    mkdir -p /var/run/postgresql
    chown -R postgres:postgres /var/run/postgresql
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

    sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl \
        -D /var/lib/postgresql/17/main \
        -l /var/lib/postgresql/17/main/logfile \
        -o "-c shared_memory_type=mmap -c shared_buffers=12MB -c max_connections=25 -c fsync=off" \
        start

    for i in {1..15}; do
        sudo -u postgres /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 > /dev/null 2>&1 \
            && echo "[OK] DB ready." && break
        [ $i -eq 15 ] && echo "[!] DB timeout." && exit 1
        sleep 2
    done
fi

# 3. Grafana
if pgrep grafana-server > /dev/null; then
    echo "[3/4] Grafana already running."
else
    echo "[3/4] Starting Grafana..."
    nohup /usr/share/grafana/bin/grafana-server \
        --config=/etc/grafana/grafana.ini \
        --homepath=/usr/share/grafana \
        cfg:default.paths.logs=/var/log/grafana \
        cfg:default.paths.data=/var/lib/grafana >> "$LOG_FILE" 2>&1 &
    echo "[OK] Grafana started."
fi

# 4. TeslaMate cu restart automat
echo "[4/4] Starting TeslaMate (auto-restart loop)..."
cd /opt/teslamate
export $(grep -v '^#' .env | xargs)
export DATABASE_HOST=127.0.0.1

echo "Running DB migrations..."
mix ecto.migrate 2>&1 | tee -a "$LOG_FILE"

echo "[!] Cinderella se trezeste..."
while true; do
    echo "=== TeslaMate START: $(date) ===" >> "$LOG_FILE"
    mix phx.server >> "$LOG_FILE" 2>&1
    echo "=== TeslaMate EXIT: $(date) ===" >> "$LOG_FILE"

    # Reporneste Mosquitto daca a cazut
    if ! pgrep -x mosquitto > /dev/null; then
        echo "[!] Mosquitto died! Restarting..." | tee -a "$LOG_FILE"
        mosquitto -d
        sleep 3
    fi

    echo "[!] TeslaMate reporneste in 15 secunde..." | tee -a "$LOG_FILE"
    sleep 15
done
