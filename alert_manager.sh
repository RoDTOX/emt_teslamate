#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# PROJECT CINDERELLA - AUTONOMOUS BATTERY ALERT MANAGER v3.0
# Target: Samsung Galaxy A6 (Termux + Debian proot)
# Supervised: Phone Battery Level, Charging Status, Off-grid Autonomy, Power
# ==============================================================================

RECIPIENT="${ALERT_RECIPIENT:-dtoxpk@gmail.com}"
LAST_ALERT_FILE="$HOME/.last_alert_level"
CHECK_INTERVAL=300 # 5 minute (optimizat pentru consum minim de baterie și CPU)

# Praguri de alertare la descărcare:
# 90% (alertă timpurie) -> 80%, 60%, 40% (din 20 în 20%) -> 30%, 20%, 10% (din 10 în 10%) -> 5%, 1% (critic)
THRESHOLDS=(90 80 60 40 30 20 10 5 1)

# Inițializare memorie stare alertă (100 = complet încărcat / fără alerte active)
[ ! -f "$LAST_ALERT_FILE" ] && echo "100" > "$LAST_ALERT_FILE"

send_email() {
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

    local body="TeslaMate: Cinderella - Raport Stare Sistem\n"
    body+="==========================================\n"
    body+="🔋 Nivel Baterie:      ${level} %\n"
    body+="⏳ Autonomie Estimată: ${offgrid} ore\n"
    body+="🌡️ Temperatură:        ${temp} °C\n"
    body+="⚡ Consum Instant:     ${power} W\n"
    body+="🔌 Tensiune / Curent:  ${volt} V / ${curr} A\n"
    body+="📊 Consum Mediu (1h):  ${avg_p} W\n"
    body+="🛰️ Sincronizare:       ${sync_time}\n"
    body+="==========================================\n"
    body+="${note}\n"

    echo -e "Subject: ${subject}\n\n${body}" | msmtp "$RECIPIENT"
}

# --- MOD TEST ---
if [ "$1" == "--test" ]; then
    echo "[*] Trimitere email de test către $RECIPIENT..."
    send_email "🧪 TeslaMate: Cinderella - Test Alert Manager v3.0" "100" "N/A" "25" "0.0" "4.1" "0.0" "0.85" "$(date '+%H:%M:%S')" "Acesta este un mesaj de test pentru verificarea serviciului msmtp."
    echo "[OK] Email de test trimis!"
    exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INIT] Alert Manager v3.0 pornit (Verificare la ${CHECK_INTERVAL}s)..."

while true; do
    # Extragere date complete din PostgreSQL (Debian proot)
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

    # Verificare dacă datele sunt valide
    if [ -n "$LEVEL" ]; then
        LAST_LEVEL=$(cat "$LAST_ALERT_FILE" 2>/dev/null || echo "100")
        
        # Asigurare că LAST_LEVEL conține un număr valid
        [[ ! "$LAST_LEVEL" =~ ^[0-9]+$ ]] && LAST_LEVEL=100

        # --- CAZ 1: TELEFONUL ESTE LA ÎNCĂRCARE (CHARGING = 't' sau 'true') ---
        if [ "$CHARGING" = "t" ] || [ "$CHARGING" = "true" ]; then
            # Dacă anterior a fost declanșată o alertă (LAST_LEVEL < 95), anunțăm revenirea alimentării
            if [ "$LAST_LEVEL" -lt 95 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RECOVERY] Alimentare restabilită la ${LEVEL}%."
                send_email "🔌 TeslaMate: Cinderella - Alimentare restabilită (${LEVEL}%)" \
                    "$LEVEL" "$OFFGRID_TIME" "$TEMP" "$POWER" "$VOLT" "$CURR" "$AVG_P" "$SYNC_TIME" \
                    "Alimentarea cu energie a fost reconectată. Bateria se încarcă în mod normal."
            fi
            # Resetăm memoria pragurilor pentru următorul ciclu de descărcare
            echo "100" > "$LAST_ALERT_FILE"

        # --- CAZ 2: TELEFONUL RULEAZĂ PE BATERIE (CHARGING = 'f' sau 'false') ---
        elif [ "$CHARGING" = "f" ] || [ "$CHARGING" = "false" ]; then
            for THRESHOLD in "${THRESHOLDS[@]}"; do
                # Verificăm dacă nivelul curent a scăzut sub sau egal cu pragul,
                # iar ultima alertă a fost trimisă când bateria era peste acest prag
                if [ "$LEVEL" -le "$THRESHOLD" ] && [ "$LAST_LEVEL" -gt "$THRESHOLD" ]; then
                    
                    # Personalizare subiect și notă în funcție de gravitate
                    case $THRESHOLD in
                        90)
                            SUBJECT="⚠️ TeslaMate: Cinderella - Alertă Timpurie: Baterie la 90%"
                            NOTE="Avertisment timpiuriu: Telefonul s-a deconectat de la sursa de alimentare. Ai timp suficient să intervii."
                            ;;
                        80)
                            SUBJECT="📉 TeslaMate: Cinderella - Baterie la 80%"
                            NOTE="Telefonul continuă descărcarea. Verifică cablul sau alimentatorul."
                            ;;
                        60)
                            SUBJECT="📉 TeslaMate: Cinderella - Baterie la 60%"
                            NOTE="Bateria a ajuns la 60%. Sistemul funcționează încă stabil."
                            ;;
                        40)
                            SUBJECT="⚠️ TeslaMate: Cinderella - Atenție: Baterie la 40%"
                            NOTE="Atenție: Bateria a atins pragul mediu inferior (40%)."
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
                            NOTE="OPRIRE IMINENTĂ: Serverul TeslaMate se va închide în scurt timp din lipsă de energie!"
                            ;;
                    esac

                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] Declanșare alertă prag ${THRESHOLD}% (Nivel curent: ${LEVEL}%)."
                    send_email "$SUBJECT" "$LEVEL" "$OFFGRID_TIME" "$TEMP" "$POWER" "$VOLT" "$CURR" "$AVG_P" "$SYNC_TIME" "$NOTE"
                    
                    # Salvăm pragul declanșat pentru a evita alerte duplicate
                    echo "$THRESHOLD" > "$LAST_ALERT_FILE"
                    break
                fi
            done
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
