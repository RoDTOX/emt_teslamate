#!/data/data/com.termux/files/usr/bin/bash

# Project Cinderella - Console Viewer
# Attaches to the active TMUX session running Debian TeslaMate

if tmux has-session -t teslamate 2>/dev/null; then
    echo "[+] Attaching to Cinderella TMUX console..."
    echo "[!] To detach without stopping the server, press: CTRL+B, then D"
    sleep 1
    tmux attach-session -t teslamate
else
    echo "[!] Cinderella TMUX session is not currently running."
    echo "[*] Start the server using: ./start-teslamate.sh"
fi
