# 1. Creează folderul de configurare pentru Grafana
mkdir -p /etc/grafana/provisioning/dashboards

# 2. Creează fișierul de "instrucțiuni" pentru Grafana
# Acest fișier spune Grafanei să încarce automat graficele TeslaMate
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

echo "[OK] Grafana a fost configurată pentru folderul /opt/teslamate/dashboards"

# 3. Descarcă Dashboard-urile (graficele)
mkdir -p /opt/teslamate/dashboards
cd /opt/teslamate/dashboards
echo "[!] Se descarcă graficele de pe GitHub..."
for dashboard in "overview" "drive_details" "efficiency" "charge_details" "charging_stats" "visit_stats" "vitals" "updates" "timeline" "trip_stats" "locations" "states"; do
  wget -q -N https://raw.githubusercontent.com/teslamate-org/teslamate/master/grafana/dashboards/\${dashboard}.json
done

echo "[OK] Fișierele JSON (graficele) sunt pregătite."

# 4. Repornire Grafana pentru a aplica noile setări
echo "[!] Se aplică setările în Grafana..."
fuser -k 3000/tcp 2>/dev/null
pkill -f grafana-server 2>/dev/null

# Pauză pentru a lăsa procesorul de A6 să elibereze portul
sleep 2

# Pornire Grafana
/usr/share/grafana/bin/grafana-server \
  --config=/etc/grafana/grafana.ini \
  --homepath=/usr/share/grafana \
  cfg:default.paths.logs=/var/log/grafana \
  cfg:default.paths.data=/var/lib/grafana &

echo "----------------------------------------------------------"
echo "CONFIGURARE FINALIZATĂ!"
echo "1. Accesează http://192.168.1.28:3000"
echo "2. Mergi la 'Dashboards' -> 'Browse' -> folderul 'TeslaMate'"
echo "3. NU UITA: Adaugă Data Source PostgreSQL (127.0.0.1) dacă e prima dată."
echo "----------------------------------------------------------"
