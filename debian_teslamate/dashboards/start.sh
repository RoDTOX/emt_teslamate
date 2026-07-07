#!/bin/bash

echo "--- TeslaMate Samsung A6 - UNIFIED MASTER START v11 ---"

# 1. Configurare Mediu
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export DATABASE_HOST=127.0.0.1

# 2. Curățare nucleară (Reset total procese)
echo "[1/6] Eliberare memorie și porturi..."
pkill -9 -u postgres 2>/dev/null
pkill -9 postgres 2>/dev/null
pkill -9 beam.smp 2>/dev/null
pkill -9 grafana-server 2>/dev/null
pkill -9 grafana 2>/dev/null
fuser -k 4000/tcp 2>/dev/null
fuser -k 3000/tcp 2>/dev/null
fuser -k 5432/tcp 2>/dev/null

# Eliminare lock-uri și socket-uri reziduale
rm -f /var/lib/postgresql/17/main/postmaster.pid 2>/dev/null
rm -f /var/lib/postgresql/17/main/postmaster.opts 2>/dev/null
rm -rf /tmp/.s.PGSQL.* 2>/dev/null
rm -rf /var/run/postgresql/.s.PGSQL.* 2>/dev/null

# 3. FIX Bază de Date (Configurație de Avarie pentru proot)
CONF_FILE="/var/lib/postgresql/17/main/postgresql.conf"
if [ -f "$CONF_FILE" ]; then
    echo "[!] Aplicăm configurația de stabilitate v11 (No-IPC Mode)..."
    # Forțăm mmap și dezactivăm memoria dinamică care cauzează bucla în log
    sed -i "s/^#*shared_memory_type =.*/shared_memory_type = mmap/" $CONF_FILE
    sed -i "s/^#*dynamic_shared_memory_type =.*/dynamic_shared_memory_type = none/" $CONF_FILE
    sed -i "s/^#*huge_pages =.*/huge_pages = off/" $CONF_FILE
    
    # Reducem consumul la minimul absolut
    sed -i "s/^#*shared_buffers =.*/shared_buffers = 4MB/" $CONF_FILE
    sed -i "s/^#*max_connections =.*/max_connections = 5/" $CONF_FILE
    
    # Dezactivăm sincronizarea forțată (ajută enorm pe Samsung A6 / stocare lentă)
    sed -i "s/^#*fsync =.*/fsync = off/" $CONF_FILE
    sed -i "s/^#*full_page_writes =.*/full_page_writes = off/" $CONF_FILE
    
    # Dezactivăm statisticile
    sed -i "s/^#*track_activities =.*/track_activities = off/" $CONF_FILE
    sed -i "s/^#*track_counts =.*/track_counts = off/" $CONF_FILE
fi

# 4. Pornire PostgreSQL
echo "[2/6] Pornire PostgreSQL (Mod Fail-Safe)..."
# Încercăm o oprire forțată înainte de start
sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/17/main stop -m immediate 2>/dev/null

# Pornire cu setări injectate direct pentru a ignora orice eroare din fișier
sudo -u postgres /usr/lib/postgresql/17/bin/pg_ctl -D /var/lib/postgresql/17/main -l /var/lib/postgresql/17/main/logfile -o "-c shared_memory_type=mmap -c dynamic_shared_memory_type=none -c huge_pages=off -c shared_buffers=4MB -c max_connections=5 -c fsync=off" -W start

echo -n "[...] Se așteaptă baza de date"
MAX_RETRIES=15
COUNT=0
until sudo -u postgres /usr/lib/postgresql/17/bin/pg_isready -h 127.0.0.1 > /dev/null 2>&1 || [ $COUNT -eq $MAX_RETRIES ]; do
    sleep 2
    COUNT=$((COUNT + 1))
    echo -n "."
done
echo ""

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "[EROARE] PostgreSQL a rămas blocat în buclă. Încearcă un restart la telefon."
    exit 1
fi
echo "[OK] PostgreSQL este ACTIV."

# 5. CONFIGURARE AUTOMATĂ GRAFANA
echo "[3/6] Automatizare conexiuni Grafana..."
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards

cat <<EOF > /etc/grafana/provisioning/datasources/teslamate.yaml
apiVersion: 1
datasources:
  - name: PostgreSQL
    type: postgres
    access: proxy
    url: 127.0.0.1:5432
    database: teslamate
    user: teslamate
    secureJsonData:
      password: teslamate
    jsonData:
      sslmode: 'disable'
      postgresVersion: 1500
EOF

cat <<EOF > /etc/grafana/provisioning/dashboards/teslamate.yaml
apiVersion: 1
providers:
  - name: 'TeslaMate'
    orgId: 1
    folder: 'TeslaMate'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /opt/teslamate/dashboards
EOF

# 6. Pornire Mosquitto și Grafana
echo "[4/6] Pornire Mosquitto & Grafana..."
service mosquitto restart
sleep 5 # Timp pentru eliberarea portului 3000
/usr/share/grafana/bin/grafana-server \
  --config=/etc/grafana/grafana.ini \
  --homepath=/usr/share/grafana \
  cfg:default.paths.logs=/var/log/grafana \
  cfg:default.paths.data=/var/lib/grafana &

# 7. Pornire TeslaMate
echo "[5/6] Pornire TeslaMate..."
cd /opt/teslamate
export $(grep -v '^#' .env | xargs)
export DATABASE_HOST=127.0.0.1
mix ecto.migrate

echo "[6/6] SISTEMUL ESTE ONLINE!"
echo "----------------------------------------------------------"
echo "TeslaMate: http://192.168.1.28:4000"
echo "Grafana:   http://192.168.1.28:3000"
echo "----------------------------------------------------------"
mix phx.server
