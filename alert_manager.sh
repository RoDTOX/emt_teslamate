#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# PROJECT CINDERELLA - UNIFIED SYSTEM & BATTERY GUARDIAN v4.0
# Target: Samsung Galaxy A6 (Termux + Debian proot)
# Supervised: 
#   1. Battery Level & Charging Status (Power Loss & Recovery)
#   2. Low Available RAM (< 350MB) & Memory Pressure
#   3. High Swap/ZRAM Usage (> 75% / > 1150MB - LMK Early Warning)
#   4. High CPU Load Average (5-min Load > 7.5)
#   5. High Battery / Hardware Temperature (> 43°C)
#   6. Low Storage Space (< 1.5GB Free)
#   7. Core Services Health (PostgreSQL, Grafana, TeslaMate, Mosquitto)
# ==============================================================================

RECIPIENT="${ALERT_RECIPIENT:-dtoxpk@gmail.com}"
LAST_ALERT_FILE="$HOME/.last_alert_level"
LAST_ANOMALY_FILE="$HOME/.last_anomaly_state"
LAST_ANOMALY_TIME_FILE="$HOME/.last_anomaly_time"
CHECK_INTERVAL=120 # Verificare la fiecare 2 minute (120s)
COOLDOWN_INTERVAL=1800 # 30 minute între alerte repetate pentru aceeași anomalie

# Praguri de alertare la descărcare baterie:
THRESHOLDS=(90 80 60 40 30 20 10 5 1)

# Inițializare memorie stare alertă
[ ! -f "$LAST_ALERT_FILE" ] && echo "100" > "$LAST_ALERT_FILE"
[ ! -f "$LAST_ANOMALY_FILE" ] && echo "NORMAL" > "$LAST_ANOMALY_FILE"
[ ! -f "$LAST_ANOMALY_TIME_FILE" ] && echo "0" > "$LAST_ANOMALY_TIME_FILE"

# --- FUNCȚIE TRIMITERE EMAIL GENERAL ---
send_raw_email() {
    local subject="$1"
    local body="$2"

    echo -e "Subject: ${subject}\n\n${body}" | msmtp "$RECIPIENT" 2>/dev/null
}

# --- FUNCȚIE EMAIL BATERIE ---
send_battery_email() {
    local subject="$1"
    local level="$2"
    local offgrid="$3"
    local temp="$4"
    local power="$5"
    local volt="$6"
    local curr="$7"
    local avg_p="$8"
    local sync_time="$9"
    local note="${10}"

    local body="TeslaMate: Cinderella - Raport Stare Baterie & Alimentare\n"
    body+="======================================================\n"
    body+="🔋 Nivel Baterie:      ${level} %\n"
    body+="⏳ Autonomie Estimată: ${offgrid} ore\n"
    body+="🌡️ Temperatură:        ${temp} °C\n"
    body+="⚡ Consum Instant:     ${power} W\n"
    body+="🔌 Tensiune / Curent:  ${volt} V / ${curr} A\n"
    body+="📊 Consum Mediu (1h):  ${avg_p} W\n"
    body+="🛰️ Sincronizare:       ${sync_time}\n"
    body+="======================================================\n"
    body+="${note}\n"

    send_raw_email "$subject" "$body"
}

# --- FUNCȚIE EMAIL ANOMALIE SISTEM ---
send_anomaly_email() {
    local subject="$1"
    local alert_title="$2"
    local alert_details="$3"
    local top_ram="$4"
    local top_cpu="$5"
    local note="$6"

    local body="TeslaMate: Cinderella - ALERTĂ ANOMALIE SISTEM\n"
    body+="======================================================\n"
    body+="⚠️ Alertă:     ${alert_title}\n"
    body+="🕒 Timestamp:  $(date '+%Y-%m-%d %H:%M:%S')\n"
    body+="📊 Detalii:    \n${alert_details}\n"
    body+="======================================================\n"
    body+="🔝 Top 5 Procese (Consum Memorie RAM):\n"
    body+="${top_ram}\n\n"
    body+="⚡ Top 5 Procese (Consum Procesor CPU):\n"
    body+="${top_cpu}\n"
    body+="======================================================\n"
    body+="${note}\n"

    send_raw_email "$subject" "$body"
}

# --- MOD TEST ---
if [ "$1" == "--test" ]; then
    echo "[*] Trimitere emailuri de test către $RECIPIENT..."
    send_battery_email "🧪 TeslaMate: Cinderella - Test Alert Manager (Baterie)" "100" "N/A" "25" "0.0" "4.1" "0.0" "0.85" "$(date '+%H:%M:%S')" "Test baterie OK."
    
    TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | head -n 6)
    TOP_CPU=$(ps aux --sort=-%cpu 2>/dev/null | head -n 6)
    send_anomaly_email "🧪 TeslaMate: Cinderella - Test Alert Manager (Sistem)" "Test Sistem OK" "Memorie: 1.5GB Libera | Swap: 1.3GB Liber | Load: 0.50" "$TOP_MEM" "$TOP_CPU" "Acesta este un mesaj de test pentru verificarea alertelor de sistem."
    echo "[OK] Emailuri de test trimise!"
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INIT] Unified Guardian v4.0 pornit (Verificare la ${CHECK_INTERVAL}s)..."

while true; do
    NOW_TS=$(date +%s)
    LAST_ANOMALY=$(cat "$LAST_ANOMALY_FILE" 2>/dev/null || echo "NORMAL")
    LAST_ANOMALY_TIME=$(cat "$LAST_ANOMALY_TIME_FILE" 2>/dev/null || echo "0")
    
    # ==========================================================================
    # 1. VERIFICARE ANOMALII HARDWARE & SISTEM (RAM, SWAP, CPU, TEMP, DISK)
    # ==========================================================================
    ANOMALY_DETECTED=0
    ANOMALY_TITLE=""
    ANOMALY_DETAILS=""
    ANOMALY_SEVERITY="WARNING" # WARNING sau CRITICAL

    # Extragere date Memorie & Swap
    MEM_AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 1000)
    MEM_TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 2800)
    SWAP_TOTAL_MB=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 1535)
    SWAP_FREE_MB=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 1535)
    SWAP_USED_MB=$((SWAP_TOTAL_MB - SWAP_FREE_MB))
    SWAP_USED_PCT=0
    [ "$SWAP_TOTAL_MB" -gt 0 ] && SWAP_USED_PCT=$(( (SWAP_USED_MB * 100) / SWAP_TOTAL_MB ))

    # Extragere Load Average CPU
    LOAD_1MIN=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.0")
    LOAD_5MIN=$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo "0.0")

    # Extragere Temperatură Baterie (sysfs nativ direct)
    BAT_TEMP_RAW=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 250)
    BAT_TEMP=$(awk "BEGIN {printf \"%.1f\", $BAT_TEMP_RAW/10.0}")

    # Extragere Spațiu Stocare (/data)
    STORAGE_FREE_MB=$(df -m /data 2>/dev/null | awk 'NR==2 {print $4}' || echo 5000)

    # Detalii generale de stare sistem
    SYS_SUMMARY="• Memorie Disponibilă: ${MEM_AVAIL_MB} MB / ${MEM_TOTAL_MB} MB\n"
    SYS_SUMMARY+="• Utilizare Swap/ZRAM:  ${SWAP_USED_MB} MB / ${SWAP_TOTAL_MB} MB (${SWAP_USED_PCT}%)\n"
    SYS_SUMMARY+="• CPU Load Average:    ${LOAD_1MIN} (1m) / ${LOAD_5MIN} (5m)\n"
    SYS_SUMMARY+="• Temperatură Baterie: ${BAT_TEMP} °C\n"
    SYS_SUMMARY+="• Spațiu Liber /data:  ${STORAGE_FREE_MB} MB"

    # --- REGULĂ A: Memorie RAM Scăzută ---
    if [ "$MEM_AVAIL_MB" -lt 250 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_SEVERITY="CRITICAL"
        ANOMALY_TITLE="🚨 CRITIC: Memorie RAM Extrem de Scăzută (${MEM_AVAIL_MB} MB liberi)"
        ANOMALY_DETAILS="Memoria disponibilă a scăzut sub pragul critic de 250MB. Risc iminent de intervenție a Android Low Memory Killer (LMK)!\n\n${SYS_SUMMARY}"
    elif [ "$MEM_AVAIL_MB" -lt 380 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_TITLE="⚠️ AVERTIZARE: Memorie RAM Scăzută (${MEM_AVAIL_MB} MB liberi)"
        ANOMALY_DETAILS="Memoria RAM disponibilă a coborât sub 380MB.\n\n${SYS_SUMMARY}"
    fi

    # --- REGULĂ B: Utilizare Swap / ZRAM Ridicată (Precursor LMK) ---
    if [ "$SWAP_USED_PCT" -gt 75 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_SEVERITY="CRITICAL"
        ANOMALY_TITLE="🚨 CRITIC: Memorie Swap/ZRAM la ${SWAP_USED_PCT}% (${SWAP_USED_MB} MB)"
        ANOMALY_DETAILS="Swap-ul este aproape plin (${SWAP_USED_PCT}%). Posibilă scurgere de memorie sau acumulare de procese zombie!\n\n${SYS_SUMMARY}"
    fi

    # --- REGULĂ C: CPU Load Average Ridicat ---
    LOAD_INT=${LOAD_5MIN%.*}
    [ -z "$LOAD_INT" ] && LOAD_INT=0
    if [ "$LOAD_INT" -ge 10 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_SEVERITY="CRITICAL"
        ANOMALY_TITLE="🚨 CRITIC: CPU Load Average Foarte Mare (${LOAD_5MIN})"
        ANOMALY_DETAILS="Procesorul este supraîncărcat continuu de mai mult de 5 minute (Load 5m: ${LOAD_5MIN}).\n\n${SYS_SUMMARY}"
    elif [ "$LOAD_INT" -ge 7 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_TITLE="⚠️ AVERTIZARE: CPU Load Ridicat (${LOAD_5MIN})"
        ANOMALY_DETAILS="Încărcare ridicată a procesorului pe telefon.\n\n${SYS_SUMMARY}"
    fi

    # --- REGULĂ D: Temperatură Ridicată ---
    TEMP_INT=${BAT_TEMP%.*}
    [ -z "$TEMP_INT" ] && TEMP_INT=25
    if [ "$TEMP_INT" -ge 46 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_SEVERITY="CRITICAL"
        ANOMALY_TITLE="🔥 CRITIC: Temperatură Hardware Periculoasă (${BAT_TEMP}°C)"
        ANOMALY_DETAILS="Telefonul a atins o temperatură ridicată (${BAT_TEMP}°C). Verifică mediul și ventilația dispozitivului!\n\n${SYS_SUMMARY}"
    elif [ "$TEMP_INT" -ge 42 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_TITLE="🌡️ AVERTIZARE: Temperatură Baterie la ${BAT_TEMP}°C"
        ANOMALY_DETAILS="Temperatura bateriei este peste nivelul normal de operare.\n\n${SYS_SUMMARY}"
    fi

    # --- REGULĂ E: Spațiu Stocare Scăzut ---
    if [ "$STORAGE_FREE_MB" -lt 1000 ]; then
        ANOMALY_DETECTED=1
        ANOMALY_TITLE="💾 AVERTIZARE: Spațiu de Stocare sub 1GB (${STORAGE_FREE_MB} MB liberi)"
        ANOMALY_DETAILS="Spațiul intern de stocare pe partiția /data a scăzut sub 1GB.\n\n${SYS_SUMMARY}"
    fi

    # --- REGULĂ F: Verificare Servicii Critice Oprite ---
    DEAD_SERVICES=""
    ! pgrep -f "postgres" > /dev/null 2>&1 && DEAD_SERVICES+="PostgreSQL, "
    ! pgrep -f "grafana" > /dev/null 2>&1 && DEAD_SERVICES+="Grafana, "
    ! pgrep -f "beam.smp" > /dev/null 2>&1 && DEAD_SERVICES+="TeslaMate, "
    ! pgrep -f "mosquitto" > /dev/null 2>&1 && DEAD_SERVICES+="Mosquitto, "

    if [ -n "$DEAD_SERVICES" ]; then
        ANOMALY_DETECTED=1
        ANOMALY_SEVERITY="CRITICAL"
        DEAD_SERVICES=${DEAD_SERVICES%, }
        ANOMALY_TITLE="🛑 CRITIC: Servicii Oprite ($DEAD_SERVICES)"
        ANOMALY_DETAILS="Următoarele servicii esențiale au fost găsite oprite: ${DEAD_SERVICES}!\n\n${SYS_SUMMARY}"
    fi

    # --- LOGICĂ DE TRANSMISIE ALERTE ANOMALII & RECOVERY ---
    if [ "$ANOMALY_DETECTED" -eq 1 ]; then
        TIME_SINCE_LAST=$((NOW_TS - LAST_ANOMALY_TIME))

        # Trimitem dacă:
        # 1. Este o stare nouă de anomalie (LAST_ANOMALY == NORMAL), SAU
        # 2. A trecut timpul de cooldown (30 min), SAU
        # 3. Severitatea este CRITICAL și anterior era doar WARNING
        if [ "$LAST_ANOMALY" == "NORMAL" ] || [ "$TIME_SINCE_LAST" -gt "$COOLDOWN_INTERVAL" ] || [ "$ANOMALY_SEVERITY" == "CRITICAL" -a "$LAST_ANOMALY" == "WARNING" ]; then
            TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | head -n 6)
            TOP_CPU=$(ps aux --sort=-%cpu 2>/dev/null | head -n 6)
            
            SUBJECT="TeslaMate: Cinderella - ${ANOMALY_TITLE}"
            NOTE="Notificare automată Cinderella System Guardian. Sistemul este monitorizat la fiecare 2 minute."

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SYSTEM ALERT] ${ANOMALY_TITLE}"
            send_anomaly_email "$SUBJECT" "$ANOMALY_TITLE" "$ANOMALY_DETAILS" "$TOP_MEM" "$TOP_CPU" "$NOTE"

            echo "$ANOMALY_SEVERITY" > "$LAST_ANOMALY_FILE"
            echo "$NOW_TS" > "$LAST_ANOMALY_TIME_FILE"
        fi
    else
        # Toți parametrii sunt normali. Dacă anterior a existat o anomalie, trimitem email de revenire (Recovery)
        if [ "$LAST_ANOMALY" != "NORMAL" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SYSTEM RECOVERY] Toți parametrii de sistem au revenit la normal."
            TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | head -n 6)
            TOP_CPU=$(ps aux --sort=-%cpu 2>/dev/null | head -n 6)
            
            RECOVERY_DETAILS="Toți parametrii sistemului (RAM, Swap, CPU Load, Temperatură, Servicii) au revenit în limite sigure.\n\n${SYS_SUMMARY}"
            send_anomaly_email "🟢 TeslaMate: Cinderella - Sistem Restabilit la Parametri Normali" \
                "🟢 Parametri Normalizați" "$RECOVERY_DETAILS" "$TOP_MEM" "$TOP_CPU" \
                "Sistemul funcționează optim și stabil."
            
            echo "NORMAL" > "$LAST_ANOMALY_FILE"
            echo "$NOW_TS" > "$LAST_ANOMALY_TIME_FILE"
        fi
    fi


    # ==========================================================================
    # 2. VERIFICARE NIVEL BATERIE & STARE ALIMENTARE
    # ==========================================================================
    RAW_DATA=$(proot-distro login debian -- sudo -u postgres psql -d teslamate -t -A -F'|' -c \
    "WITH latest AS (SELECT * FROM phone_metrics ORDER BY timestamp DESC LIMIT 1),
          medie AS (SELECT AVG(ABS(power_w)) as avg_p FROM phone_metrics WHERE timestamp > NOW() - INTERVAL '1 hour')
     SELECT 
        l.battery_level, 
        l.is_charging, 
        l.battery_temp, 
        ABS(ROUND(l.power_w::numeric, 3)), 
        l.voltage_v, 
        l.current_a, 
        ROUND(COALESCE(m.avg_p, 0.9)::numeric, 2),
        ROUND((((l.battery_level / 100.0) * 11.4) / NULLIF(COALESCE(m.avg_p, 0.9), 0))::numeric, 2),
        TO_CHAR(l.timestamp, 'HH24:MI:SS')
     FROM latest l, medie m;" 2>/dev/null)

    # Parsare variabile extrase
    IFS='|' read -r LEVEL CHARGING TEMP POWER VOLT CURR AVG_P OFFGRID_TIME SYNC_TIME <<< "$RAW_DATA"

    if [ -n "$LEVEL" ]; then
        LAST_LEVEL=$(cat "$LAST_ALERT_FILE" 2>/dev/null || echo "100")
        [[ ! "$LAST_LEVEL" =~ ^[0-9]+$ ]] && LAST_LEVEL=100

        # --- CAZ 2.1: TELEFONUL ESTE LA ÎNCĂRCARE ---
        if [ "$CHARGING" = "t" ] || [ "$CHARGING" = "true" ]; then
            if [ "$LAST_LEVEL" -lt 95 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERY] Alimentare restabilită la ${LEVEL}%."
                send_battery_email "🔌 TeslaMate: Cinderella - Alimentare restabilită (${LEVEL}%)" \
                    "$LEVEL" "$OFFGRID_TIME" "$TEMP" "$POWER" "$VOLT" "$CURR" "$AVG_P" "$SYNC_TIME" \
                    "Alimentarea cu energie a fost reconectată. Bateria se încarcă în mod normal."
            fi
            echo "100" > "$LAST_ALERT_FILE"

        # --- CAZ 2.2: TELEFONUL RULEAZĂ PE BATERIE ---
        elif [ "$CHARGING" = "f" ] || [ "$CHARGING" = "false" ]; then
            for THRESHOLD in "${THRESHOLDS[@]}"; do
                if [ "$LEVEL" -le "$THRESHOLD" ] && [ "$LAST_LEVEL" -gt "$THRESHOLD" ]; then
                    case $THRESHOLD in
                        90)
                            SUBJECT="⚠️ TeslaMate: Cinderella - Alertă Timpurie: Baterie la 90%"
                            NOTE="Avertisment timpuriu: Telefonul s-a deconectat de la sursa de alimentare."
                            ;;
                        80)
                            SUBJECT="📉 TeslaMate: Cinderella - Baterie la 80%"
                            NOTE="Telefonul continuă descărcarea. Verifică alimentatorul."
                            ;;
                        60)
                            SUBJECT="📉 TeslaMate: Cinderella - Baterie la 60%"
                            NOTE="Bateria a ajuns la 60%. Sistemul funcționează încă stabil."
                            ;;
                        40)
                            SUBJECT="⚠️ TeslaMate: Cinderella - Atenție: Baterie la 40%"
                            NOTE="Atenție: Bateria a atins pragul de 40%."
                            ;;
                        30)
                            SUBJECT="🚨 TeslaMate: Cinderella - Alertă: Baterie la 30%"
                            NOTE="Nivel scăzut de energie. Este recomandată reconectarea la priză."
                            ;;
                        20)
                            SUBJECT="🚨 TeslaMate: Cinderella - Alertă Critică: Baterie la 20%"
                            NOTE="CRITIC: Nivel baterie 20%. Risc de descărcare accelerată."
                            ;;
                        10)
                            SUBJECT="🛑 TeslaMate: Cinderella - Urgență: Baterie la 10%"
                            NOTE="URGENȚĂ: Baterie foarte scăzută! Conectează urgent alimentatorul!"
                            ;;
                        5|1)
                            SUBJECT="⛔ TeslaMate: Cinderella - Oprire Iminentă: Baterie la ${LEVEL}%"
                            NOTE="OPRIRE IMINENTĂ: Serverul se va închide în scurt timp din lipsă de energie!"
                            ;;
                    esac

                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BATTERY ALERT] Declanșare prag ${THRESHOLD}% (Curent: ${LEVEL}%)."
                    send_battery_email "$SUBJECT" "$LEVEL" "$OFFGRID_TIME" "$TEMP" "$POWER" "$VOLT" "$CURR" "$AVG_P" "$SYNC_TIME" "$NOTE"
                    echo "$THRESHOLD" > "$LAST_ALERT_FILE"
                    break
                fi
            done
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
