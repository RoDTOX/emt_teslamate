#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# PROJECT CINDERELLA - PHONE METRICS PUSHER v8.0 (Bulletproof Sysfs Native)
# Target: Samsung Galaxy A6 (Termux + Debian proot)
# Collects: Battery level/temp, RAM, Wi-Fi RSSI, Voltage, Current, Power (W)
# ==============================================================================

echo "[+] Pusher v8.0 pornit. Colectăm date la fiecare 60 secunde..."

if ! command -v bc &> /dev/null; then
    pkg install bc -y
fi

format_num() {
    sed 's/^-\./-0./; s/^\./0./'
}

while true; do
    # 1. Metrice de bază RAM & Disk
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    DISK_FREE=$(df -h /data | grep /data | awk '{print $4}' | sed 's/G//')

    # 2. Citire Baterie direct via ROOT / sysfs (Rapid, zero overhead, fără crash Termux:API)
    BATT_LEVEL=$(su -c "cat /sys/class/power_supply/battery/capacity 2>/dev/null" | tr -d '\r\n')
    if [[ ! "$BATT_LEVEL" =~ ^[0-9]+$ ]]; then
        # Fallback termux-battery-status dacă sysfs nu răspunde
        BATT_INFO=$(timeout 4s termux-battery-status 2>/dev/null)
        BATT_LEVEL=$(echo "$BATT_INFO" | grep "percentage" | awk '{print $2}' | sed 's/,//')
        BATT_TEMP=$(echo "$BATT_INFO" | grep "temperature" | awk '{print $2}' | sed 's/,//')
        PLUGGED=$(echo "$BATT_INFO" | grep "status" | grep -qi "charging" && echo "true" || echo "false")
    else
        # Sysfs temp (de obicei în zecimi de grad, ex 285 = 28.5C)
        RAW_TEMP=$(su -c "cat /sys/class/power_supply/battery/temp 2>/dev/null" | tr -d '\r\n')
        if [[ "$RAW_TEMP" =~ ^[0-9]+$ ]]; then
            BATT_TEMP=$(echo "scale=1; $RAW_TEMP / 10" | bc -l | format_num)
        else
            BATT_TEMP=25.0
        fi
        STATUS_RAW=$(su -c "cat /sys/class/power_supply/battery/status 2>/dev/null" | tr -d '\r\n')
        if [[ "$STATUS_RAW" =~ [Cc]harging|[Ff]ull ]]; then
            PLUGGED="true"
        else
            PLUGGED="false"
        fi
    fi

    # Wi-Fi RSSI
    WIFI_RSSI=$(termux-wifi-connectioninfo 2>/dev/null | grep "rssi" | awk '{print $2}' | sed 's/,//')
    [ -z "$WIFI_RSSI" ] && WIFI_RSSI=0

    # 3. Citire Hardware via ROOT (Voltaj)
    V_RAW=$(su -c "cat /sys/class/power_supply/battery/voltage_now 2>/dev/null" | tr -d '\r\n')
    if [[ "$V_RAW" =~ ^-?[0-9]+$ ]]; then
        VOLT=$(echo "scale=3; $V_RAW / 1000000" | bc -l | format_num)
    else
        VOLT=0
    fi

    # 4. Citire Hardware via ROOT (Amperaj)
    A_RAW=$(su -c "cat /sys/class/power_supply/battery/current_now 2>/dev/null" | tr -d '\r\n')
    if [[ "$A_RAW" =~ ^-?[0-9]+$ ]]; then
        AMP=$(echo "scale=3; $A_RAW / 1000" | bc -l | format_num)
    else
        AMP=0
    fi

    # 5. Calculare Putere Instanță (Wați)
    WATT=$(echo "scale=2; $VOLT * $AMP" | bc -l | format_num)

    # 6. Trimitere în PostgreSQL dacă avem date valide
    if [[ "$BATT_LEVEL" =~ ^[0-9]+$ ]]; then
        proot-distro login debian -- sudo -u postgres psql -d teslamate -c \
        "INSERT INTO phone_metrics (battery_level, battery_temp, ram_used_mb, wifi_signal, is_charging, disk_free_gb, voltage_v, current_a, power_w) \
         VALUES ($BATT_LEVEL, $BATT_TEMP, $RAM_USED, $WIFI_RSSI, $PLUGGED, $DISK_FREE, $VOLT, $AMP, $WATT);" > /dev/null 2>&1
    fi

    sleep 60
done
