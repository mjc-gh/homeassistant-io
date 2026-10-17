#!/usr/bin/env bash
set -euo pipefail

project_dir="$(dirname -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")")"
compose=(docker compose --project-directory "$project_dir" -f "$project_dir/compose.yaml")

case "${1:-}" in
  ""|--check)
    if (( $# > 1 )); then
      printf 'Usage: %s [--check]\n' "$0" >&2
      exit 2
    fi
    ;;
  --help|-h)
    printf 'Usage: %s [--check]\nValidate configuration, then recreate Home Assistant. --check validates only.\n' "$0"
    exit 0
    ;;
  *)
    printf 'Usage: %s [--check]\n' "$0" >&2
    exit 2
    ;;
esac

printf 'Validating Compose configuration...\n'
"${compose[@]}" config --quiet

# Validate using the running container before interrupting the service.
printf 'Validating Home Assistant configuration (requires a running container)...\n'
"${compose[@]}" exec -T homeassistant python -m homeassistant \
  --script check_config --config /config

if [[ "${1:-}" == --check ]]; then
  exit 0
fi

# Recreating also applies Compose changes that a plain restart would not apply.
printf 'Recreating Home Assistant...\n'
"${compose[@]}" up -d --force-recreate homeassistant
"${compose[@]}" ps homeassistant
printf 'Restart requested. Startup may take a moment; open http://localhost:8123 or check docker compose logs.\n'
