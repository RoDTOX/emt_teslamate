#!/bin/bash

# Setup foldere și nume fișier
BACKUP_DIR="/opt/teslamate/backups"
mkdir -p "$BACKUP_DIR"
DATE=$(date +"%Y-%m-%d_%H-%M")
FILE_NAME="$BACKUP_DIR/teslamate_$DATE.bak"

echo "[*] Incepere backup baze de date la $DATE..."
sudo -u postgres pg_dump teslamate > "$FILE_NAME"
gzip "$FILE_NAME"

echo "[*] Curatare fisiere locale vechi (7 zile)..."
find "$BACKUP_DIR" -type f -name "*.gz" -mtime +7 -exec rm {} \;

echo "[*] Incarcare pe Google Drive..."
# Trimitem pe Drive folosind rclone
rclone copy "$FILE_NAME.gz" gdrive:TeslaMateBackup/

echo "[*] Curatare fisiere cloud vechi (30 zile)..."
# Ștergem de pe Drive backup-urile mai vechi de 30 de zile
rclone delete gdrive:TeslaMateBackup/ --min-age 30d 2>/dev/null

echo "[OK] Backup complet finalizat si securizat in cloud!"
