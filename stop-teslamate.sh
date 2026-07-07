#!/data/data/com.termux/files/usr/bin/bash

# Proiect Cinderella - Shutdown Sequence
# Scop: Inchiderea sigura a proceselor pentru a preveni coruperea bazei de date.

echo "=========================================="
echo "   SHUTDOWN SEQUENCE: PROJECT CINDERELLA  "
echo "=========================================="

# 1. Oprire TeslaMate (Stratul Logic)
# Trimitem SIGTERM (semnal de inchidere curata)
echo "[1/4] Se opreste TeslaMate (beam.smp)..."
pkill -15 -f beam.smp
pkill -15 -f esbuild
sleep 3

# 2. Oprire Grafana (Vizualizare)
echo "[2/4] Se opreste Grafana..."
pkill -15 -f grafana
sleep 2

# 3. Oprire Mosquitto (MQTT Broker)
echo "[3/4] Se opreste Mosquitto..."
pkill -15 -f mosquitto
sleep 2

# 4. Oprire PostgreSQL (Baza de date - Ultima, pentru a salva datele din cache)
echo "[4/4] Se opreste PostgreSQL..."
# Folosim SIGTERM pentru a-i permite sa faca flush la date pe disk
pkill -15 -f postgres
echo "Asteptam sincronizarea bazei de date cu stocarea..."
sleep 5

# Verificare Finala
echo "------------------------------------------"
echo "Verificare procese ramase active:"
CHECK=$(ps -ef | grep -E "postgres|beam|grafana|mosquitto" | grep -v grep)

if [ -z "$CHECK" ]; then
    echo "[SUCCESS] Toate serviciile Cinderella sunt offline."
else
    # Aici era eroarea: am inchis ghilimeaua si am completat fraza
    echo "[WARNING] Unele procese sunt incapatanate. Se forteaza inchiderea..."
    pkill -9 -f "postgres|beam|grafana|mosquitto"
    sleep 1
    echo "[DONE] Inchidere fortata executata."
fi

# La final, omoram si sesiunea de Tmux ca sa fie curat
tmux kill-session -t teslamate 2>/dev/null
echo "[INFO] Sesiunea TMUX a fost inchisa."

echo "=========================================="
