#!/data/data/com.termux/files/usr/bin/bash

proot-distro login debian -- /bin/bash -c '
START_SCRIPT="/opt/teslamate/start.sh"

if grep -q "socat TCP-LISTEN" "$START_SCRIPT"; then
    echo "[INFO] Tunelul pentru acvariu există deja în $START_SCRIPT"
    exit 0
fi

# Creăm un fișier temporar cu liniile pe care vrem să le injectăm
cat << "INJECT" > /tmp/acvariu_patch.txt

    # --- 2.2 Pornire Tunel Acvariu (Proxy) ---
    echo "[2.2/5] Pornire Proxy Acvariu pe portul 8080..."
    pkill -f "socat TCP-LISTEN:8080" 2>/dev/null
    nohup socat TCP-LISTEN:8080,fork,reuseaddr TCP:192.168.1.32:80 > /dev/null 2>&1 &
INJECT

# Inserăm codul inteligent, exact după pornirea serviciului cron
sed -i "/service cron start/r /tmp/acvariu_patch.txt" "$START_SCRIPT"
rm /tmp/acvariu_patch.txt

echo "[OK] Tunelul pentru acvariu a fost integrat permanent în secvența de boot Cinderella!"
'
