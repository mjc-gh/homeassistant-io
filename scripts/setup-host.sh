#!/usr/bin/env bash
set -euo pipefail

# Allow Home Assistant access from the home LAN and Tailscale.
sudo ufw allow in on enp0s31f6 from 192.168.1.0/24 to any port 8123 proto tcp comment 'Home Assistant LAN'
sudo ufw allow in on tailscale0 to any port 8123 proto tcp comment 'Home Assistant Tailscale'
sudo ufw status verbose

# Keep this computer awake for continuous server use (system-wide).
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
