#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--status|--help]\n' "$0"
  printf 'Configure persistent, tailnet-only HTTPS for Home Assistant.\n'
  printf '  --status  Check the configuration and HTTP/HTTPS endpoints without changes.\n'
}

if (( $# > 1 )); then
  usage >&2
  exit 2
fi
case "${1:-}" in
  ""|--status) ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for dependency in tailscale curl python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$dependency" >&2
    exit 1
  fi
done

backend='http://127.0.0.1:8123'
tailnet_status="$(tailscale status --json)"
hostname="$(python3 -c '
import json, sys
status = json.load(sys.stdin)
if status.get("BackendState") != "Running":
    sys.exit("Tailscale is not connected. Run sudo tailscale up first.")
name = status.get("Self", {}).get("DNSName", "").rstrip(".")
if not name:
    sys.exit("Tailscale has not assigned this host a DNS name.")
print(name)
' <<< "$tailnet_status")"
url="https://$hostname"

proxy_instructions() {
  printf '\nIn Home Assistant, open Settings > System > Network > HTTP server:\n'
  printf '  Enable Trust X-Forwarded-For.\n'
  printf '  Add 127.0.0.1 to Trusted proxies.\n'
  printf '  Keep HTTP on port 8123 (Tailscale terminates HTTPS).\n'
  printf 'Save, then confirm the settings after Home Assistant restarts.\n'
  printf 'Then run this script again.\n'
}

check_backend() {
  local code
  if ! code="$(curl --noproxy '*' --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 5 --max-time 15 "$backend/")"; then
    printf 'FAIL: Home Assistant is unreachable at %s.\n' "$backend" >&2
    return 1
  fi
  if [[ "$code" != 200 ]]; then
    printf 'FAIL: Home Assistant returned HTTP %s at %s.\n' "$code" "$backend" >&2
    return 1
  fi
  printf 'OK: Home Assistant responds at %s.\n' "$backend"

  # Exercise HA's reverse-proxy middleware from the same loopback address as Serve.
  if ! code="$(curl --noproxy '*' --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 5 --max-time 15 \
    --header 'X-Forwarded-For: 127.0.0.1' \
    --header 'X-Forwarded-Proto: https' "$backend/")"; then
    printf 'FAIL: Could not check Home Assistant reverse-proxy settings.\n' >&2
    return 1
  fi
  if [[ "$code" != 200 ]]; then
    printf 'FAIL: Proxied request returned HTTP %s.\n' "$code" >&2
    proxy_instructions >&2
    return 1
  fi
  printf 'OK: Home Assistant accepts forwarded requests from 127.0.0.1.\n'
}

check_serve_config() {
  tailscale serve status --json | python3 -c '
import json, sys
config = json.load(sys.stdin)
host = sys.argv[1] + ":443"
handler = config.get("Web", {}).get(host, {}).get("Handlers", {}).get("/", {})
if handler.get("Proxy") != sys.argv[2]:
    sys.exit("FAIL: HTTPS / is not configured to proxy to " + sys.argv[2])
if not config.get("TCP", {}).get("443", {}).get("HTTPS"):
    sys.exit("FAIL: HTTPS is not enabled on port 443.")
if config.get("AllowFunnel", {}).get(host):
    sys.exit("FAIL: Funnel is enabled for this endpoint; access is public.")
print("OK: Tailnet-only HTTPS proxy is configured.")
' "$hostname" "$backend"
}

check_status() {
  local result=0 code
  printf 'Home Assistant HTTPS: %s\n\n' "$url"
  tailscale serve status || result=1
  check_serve_config || result=1
  check_backend || result=1
  if code="$(curl --noproxy '*' --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 5 --max-time 30 "$url/")"; then
    if [[ "$code" == 200 ]]; then
      printf 'OK: HTTPS responds with HTTP 200 and a valid certificate.\n'
    else
      printf 'FAIL: HTTPS returned HTTP %s.\n' "$code" >&2
      result=1
    fi
  else
    printf 'FAIL: HTTPS request failed; check DNS, certificates, and tailnet TCP 443 access.\n' >&2
    result=1
  fi
  return "$result"
}

if [[ "${1:-}" == --status ]]; then
  check_status
  exit 0
fi

python3 -c '
import json, sys
status = json.load(sys.stdin)
if not status.get("CurrentTailnet", {}).get("MagicDNSEnabled"):
    sys.exit("Enable MagicDNS at https://login.tailscale.com/admin/dns, then rerun.")
if sys.argv[1] not in (status.get("CertDomains") or []):
    sys.exit("Enable HTTPS Certificates at https://login.tailscale.com/admin/dns, then rerun.")
' "$hostname" <<< "$tailnet_status"

check_backend
printf '\nConfiguring persistent HTTPS proxy for %s...\n' "$url"
if (( EUID == 0 )); then
  tailscale serve --bg --https=443 "$backend"
else
  sudo tailscale serve --bg --https=443 "$backend"
fi
check_status
printf '\nOpen %s from a device connected to Tailscale.\n' "$url"
printf 'Use this URL as the Companion app external URL; allow tailnet TCP port 443.\n'
