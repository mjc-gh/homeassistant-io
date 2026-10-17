# Home Assistant on galactica

Home Assistant Container with persistent local storage and direct LAN/Tailscale
access. Run the Docker commands below from this directory.

## Start and access

```sh
docker compose config --quiet
docker compose up -d
docker compose ps
docker compose logs --tail=100 homeassistant
```

- On this host: http://localhost:8123
- On the home LAN: http://192.168.1.4:8123
- On Tailscale: http://100.76.184.55:8123
- With Tailscale MagicDNS enabled: http://galactica:8123

Create the owner account in the browser on first launch. Use America/New_York for
US Eastern time, including daylight saving time. The container's `TZ` is set to
that timezone; confirm the Home Assistant timezone during onboarding.

Remote clients must connect to Tailscale and their tailnet access policy must
allow this host on TCP port 8123. Tailscale encrypts the connection between peers;
ordinary LAN HTTP traffic is unencrypted. Home Assistant still requires login.
No router port forwarding, subnet routing, or Tailscale Serve is needed.

The LAN IP is assigned by DHCP. A router DHCP reservation for this computer keeps
the LAN URL stable.

## Host firewall (requires sudo)

UFW is active on this host. Inspect its existing rules and add these scoped rules:

```sh
sudo ufw status verbose
sudo ufw allow in on enp0s31f6 from 192.168.1.0/24 to any port 8123 proto tcp comment 'Home Assistant LAN'
sudo ufw allow in on tailscale0 to any port 8123 proto tcp comment 'Home Assistant Tailscale'
sudo ufw status numbered
```

Tailscale's own firewall integration may already allow tailnet traffic. These UFW
rules do not replace tailnet access policies. Host networking exposes the service
on the host's interfaces; existing broader firewall rules still apply.

Test the LAN URL from another LAN device, then test the Tailscale URL from a phone
with Wi-Fi off and Tailscale on.

## Persistence and power

`./config` contains all Home Assistant settings, credentials, and the database.
It is excluded from Git. Keep it when replacing or updating the container.

Docker and tailscaled are enabled at boot. `restart: unless-stopped` restarts the
container after failures and host reboots unless it was explicitly stopped.
`docker compose up -d` starts it again after an intentional stop.

The host already has `HandleLidSwitch=ignore`. To disable system sleep and
hibernation for continuous server use, run:

```sh
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

This is a system-wide setting. To restore normal sleep support later:

```sh
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

## Configuration changes and restart

Edit `config/configuration.yaml` for Home Assistant YAML settings. The default
configuration also includes `config/automations.yaml`, `config/scripts.yaml`, and
`config/scenes.yaml`. Files created by the container may be root-owned, so use
`sudoedit` when needed:

```sh
sudoedit config/configuration.yaml
./scripts/restart-home-assistant.sh
```

The script validates both Compose and Home Assistant configuration first. If
validation fails, it exits without restarting. On success, it recreates the
container while preserving `config/`. Expect a brief interruption during startup.
The container must already be running for Home Assistant validation.

To validate without restarting:

```sh
./scripts/restart-home-assistant.sh --check
```

For container settings such as timezone or USB mappings, edit `compose.yaml` and
run the same script. Recreating the container applies these changes; a plain
`docker compose restart` does not. The script can be invoked by absolute path
from any directory. It does not pull a new image.

Many integrations and automations can also be configured in the Home Assistant
UI, which may offer reload options that avoid a full restart. Avoid manually
editing files under `config/.storage`.

## HACS

HACS is a custom integration installed into `config/custom_components/hacs/`.
The existing persistent config mount preserves it across container replacements.
It is configured in the UI and does not need a `hacs:` YAML entry.

To install using the official HACS download script:

```sh
./scripts/install-hacs.sh
```

Home Assistant must be running. The script validates the current configuration,
runs the official installer inside the container, then validates and restarts
Home Assistant using the restart script. Running it again downloads the latest
HACS release and replaces the existing HACS integration files.

After startup:

1. Open Home Assistant and hard-refresh the browser (or clear its cache).
2. Go to **Settings > Devices & services > Add integration** and select **HACS**.
3. Follow the prompts and authorize HACS with your GitHub account using the
   device code at https://github.com/login/device.
4. Finish the setup to enable the HACS dashboard.

HACS requires outbound access to GitHub and Cloudflare. No additional inbound
firewall rules are needed. Use Home Assistant backups to protect HACS data too.

View startup and HACS logs with:

```sh
docker compose logs --tail=100 -f homeassistant
```

For troubleshooting, use **Enable debug logging** on the HACS integration's menu
under **Settings > Devices & services**. Reproduce the problem, then disable debug
logging. If HACS cannot be configured yet, temporarily add this to
`config/configuration.yaml` and run the restart script:

```yaml
logger:
  default: info
  logs:
    custom_components.hacs: debug
```

If a `logger:` section already exists, merge these settings into it. Remove the
temporary debug setting and restart when finished.

Official instructions: https://www.hacs.xyz/docs/use/download/download/

## Maintenance and backups

Use Home Assistant's Settings > System > Backups after onboarding to configure
scheduled backups and keep copies off this machine. Retain any backup encryption
key/emergency kit separately. Backups stored only on this disk do not protect
against disk failure.

Create and download a backup before updating, then run:

```sh
docker compose pull
docker compose up -d
docker compose logs --tail=100 homeassistant
```

Updates are manual. The `stable` tag selects the current stable release when
pulled. Logs use Docker's rotating local driver, limited to three 10 MB files.
The container has up to 60 seconds to close its database cleanly when stopped.

## Add a USB radio later

Once a Zigbee or Z-Wave adapter is connected, identify its stable path under
`/dev/serial/by-id/`, then add a mapping to the homeassistant service:

```yaml
    devices:
      - /dev/serial/by-id/REPLACE_WITH_ACTUAL_RADIO_ID:/dev/ttyUSB0
```

Run `docker compose up -d` to recreate the container, then configure the
integration. Zigbee ZHA can use the radio directly. Z-Wave typically needs a
separate Z-Wave JS server; give the radio to that service instead. A radio should
only be opened by one service at a time.

Bluetooth and blanket privileged access are not enabled. This installation type
does not include the Home Assistant OS managed add-on/app system; companion
services can be managed as additional containers.
