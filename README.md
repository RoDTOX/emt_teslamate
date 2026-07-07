# EMT TeslaMate (Project Cinderella)

A customized, self-hosted deployment of [TeslaMate](https://github.com/teslamate-org/teslamate) running directly on an Android smartphone (Samsung A6) via Termux and a Debian proot environment.

## Overview
This repository contains the full source code for the custom TeslaMate deployment, including all startup scripts, Elixir dependencies, and environment configurations necessary to run the suite directly from a mobile device serving as an always-on server, without utilizing Docker.

## Features
- **TeslaMate v4.0.1 (Fleet API Support)**: Fully upgraded to interact with Tesla's new Fleet API, bypassing previous 403 Forbidden limitations.
- **Android / Termux Native**: Custom bash scripts manage the lifecycle of the Erlang VM, PostgreSQL, Grafana, and Mosquitto, enabling a bare-metal feel inside a Debian container.
- **Automated Management**: 
  - `start-teslamate.sh`: Initiates WakeLock, cleans up old tmux sessions, starts the Debian proot environment, and boots all services.
  - `stop-teslamate.sh`: Gracefully shuts down all services (`beam.smp`, `grafana`, `mosquitto`, `postgres`).
- **Tailscale Integration**: Remote access securely configured via Tailscale, allowing monitoring and SSH access from anywhere.

## Directory Structure
- `debian_teslamate/`: The core Elixir application source for TeslaMate (v4.0.1).
- `start-teslamate.sh`: Termux boot sequence script.
- `stop-teslamate.sh`: Graceful shutdown script.
- `patch_acvariu.sh`: Specific environment patch script.

## Getting Started
*Note: This repository is tailored for a specific mobile server deployment (Cinderella) and may require modifications to run on standard Linux/Docker environments.*

To start the services locally on the provisioned phone:
```bash
./start-teslamate.sh
```
To monitor the console output (from the attached TMUX session):
```bash
./view.sh
```
To gracefully stop the server:
```bash
./stop-teslamate.sh
```
