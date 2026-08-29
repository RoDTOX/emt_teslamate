#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# PROJECT CINDERELLA - AUTOMATED BOOT INSTALLER (TERMUX:BOOT)
# Installs auto-boot hook so Cinderella starts automatically on phone reboot.
# ==============================================================================

BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/start-cinderella.sh"
REPO_DIR="$(pwd)"

echo "[+] Setting up Termux:Boot auto-start hook..."

mkdir -p "$BOOT_DIR"

cat << EOF > "$BOOT_SCRIPT"
#!/data/data/com.termux/files/usr/bin/bash

# Termux:Boot auto-start script for Project Cinderella
# Wait 10 seconds for Android network stack initialization after reboot
sleep 10

cd "$REPO_DIR" || exit 1
./start-teslamate.sh >> \$HOME/cinderella-boot.log 2>&1
EOF

chmod +x "$BOOT_SCRIPT"
chmod +x "$REPO_DIR/start-teslamate.sh"
chmod +x "$REPO_DIR/stop-teslamate.sh"
chmod +x "$REPO_DIR/watchdog.sh"
chmod +x "$REPO_DIR/view.sh"
chmod +x "$REPO_DIR/alert_manager.sh" 2>/dev/null
chmod +x "$REPO_DIR/metrics_pusher.sh" 2>/dev/null

echo "[SUCCESS] Termux:Boot script installed at: $BOOT_SCRIPT"
echo "[INFO] Make sure Termux:Boot app is installed and launched once on the phone."
