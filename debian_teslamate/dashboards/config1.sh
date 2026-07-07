# 1. Creează folderul de configurare pentru Grafana
mkdir -p /etc/grafana/provisioning/dashboards

# 2. Creează fișierul de "instrucțiuni" pentru Grafana
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

echo "[OK] Grafana a fost instruită să citească folderul /opt/teslamate/dashboards"

# 3. Asigură-te că fișierele JSON sunt în folderul corect
mkdir -p /opt/teslamate/dashboards
cd /opt/teslamate/dashboards
for dashboard in "overview" "drive_details" "efficiency" "charge_details" "charging_stats" "visit_stats" "vitals" "updates" "timeline" "trip_stats" "locations" "states"; do
  wget -q -N https://raw.githubusercontent.com/teslamate-org/teslamate/master/grafana/dashboards/\${dashboard}.json
done

echo "[OK] Fișierele JSON sunt pregătite."

# 4. Restart Grafana cu pauză pentru eliberarea portului
echo "[!] Repornire Grafana..."
# Omorâm orice proces care folosește portul 3000
fuser -k 3000/tcp 2>/dev/null
pkill -f grafana-server 2>/dev/null

# Așteptăm 2 secunde (critic pentru Samsung A6)
sleep 2

# Pornim Grafana în fundal
/usr/share/grafana/bin/grafana-server \
  --config=/etc/grafana/grafana.ini \
  --homepath=/usr/share/grafana \
  cfg:default.paths.logs=/var/log/grafana \
  cfg:default.paths.data=/var/lib/grafana &

echo "----------------------------------------------------------"
echo "Gata! Portul 3000 a fost eliberat și Grafana a repornit."
echo "Intră în Grafana și mergi la 'Dashboards' -> 'Browse'."
echo "Ar trebui să vezi un folder numit 'TeslaMate'."
echo "----------------------------------------------------------"
