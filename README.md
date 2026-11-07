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
No router port forwarding or subnet routing is needed. For browser-trusted HTTPS,
configure Tailscale Serve as described below.

The LAN IP is assigned by DHCP. A router DHCP reservation for this computer keeps
the LAN URL stable.

## Tailscale HTTPS reverse proxy

Tailscale Serve provides tailnet-only HTTPS at
https://galactica.tailda91c5.ts.net and proxies to `http://127.0.0.1:8123`.
Tailscale automatically provisions and renews the certificate.

Before setup:

1. Enable **MagicDNS** and **HTTPS Certificates** in the
   [Tailscale DNS settings](https://login.tailscale.com/admin/dns).
2. In Home Assistant 2026.8 or newer, open **Settings > System > Network >
   HTTP server**. Enable **Trust X-Forwarded-For** and add `127.0.0.1` to
   **Trusted proxies**. Keep Home Assistant on HTTP port `8123`. Save and confirm
   the settings after the restart, within the five-minute confirmation window.
3. Allow this host on TCP port **443** in your tailnet access policy.

Run setup (it requests sudo for the Tailscale configuration):

```sh
./scripts/setup-tailscale.sh
```

The script checks prerequisites and forwarded requests, configures persistent
Serve with `--bg`, and verifies the proxy configuration and HTTPS certificate.
It can be invoked from any directory. To check status without changes:

```sh
./scripts/setup-tailscale.sh --status
```

The status command exits nonzero if a check fails, including if Funnel makes the
endpoint public. If a conflicting Serve configuration exists, review Tailscale's
prompt before replacing it. Initial certificate provisioning can take time; rerun
the status check if necessary.

Open the HTTPS URL from a device connected to Tailscale and verify login and live
dashboard updates. Use it as the Companion app's external URL. Home Assistant
still requires login. Serve resumes after reboot, and the existing direct HTTP
URLs remain available.

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

## Z-Wave with Connect ZWA-2

The `zwave-js-ui` companion service owns the ZWA-2 USB adapter. Compose maps its
stable host path
`/dev/serial/by-id/usb-Nabu_Casa_ZWA-2_9070690BB058-if00` to `/dev/zwave`
inside that container. Home Assistant connects to its WebSocket server rather
than opening the serial device directly. Only one service should open the radio.

Start or recreate the companion service without restarting Home Assistant:

```sh
docker compose config --quiet
docker compose up -d zwave-js-ui
docker compose logs --tail=100 zwave-js-ui
```

Open http://localhost:8091 on this host. The management UI (8091) and WebSocket
server (8092) are bound only to host loopback, not the LAN or Tailscale interfaces.
For remote administration, run this on your client computer, then open
http://localhost:8091 there:

```sh
ssh -L 8091:127.0.0.1:8091 mcoyne@galactica
```

In Z-Wave JS UI settings:

1. Set the Z-Wave serial port to `/dev/zwave`.
2. Set the RF region to **USA** for US-region devices.
3. For a new network, generate and retain the network security keys. If replacing
   an existing controller, migrate its network and keys instead of starting over.
4. Under Home Assistant settings, enable the **WS Server** on port **3000** and
   save the settings. Compose exposes this internal port as host port **8092**.
   MQTT is not required.

In Home Assistant, go to **Settings > Devices & services > Add integration >
Z-Wave** and connect to the existing server at `ws://127.0.0.1:8092`. This address
works because the Home Assistant container uses host networking. Pair devices
through the integration after the controller connects.

Z-Wave JS UI settings and security keys persist in the Compose-managed
`zwave-data` volume mounted at `/usr/src/app/store`. This data is outside
`./config` and is not covered by Home Assistant's own backups. Use Z-Wave JS UI's
backup/export features to save the store and controller NVM backups, and retain
copies off this machine. Do not use `docker compose down -v` unless you intend to
delete the persistent volume.

If the adapter is unplugged or its device node changes, reconnect it and run
`docker compose up -d --force-recreate zwave-js-ui` to refresh the USB mapping.

Bluetooth and blanket privileged access are not enabled. This installation type
does not include the Home Assistant OS managed add-on/app system; companion
services can be managed as additional containers.
