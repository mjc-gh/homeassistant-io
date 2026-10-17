#!/usr/bin/env bash
set -euo pipefail

project_dir="$(dirname -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")")"
compose=(docker compose --project-directory "$project_dir" -f "$project_dir/compose.yaml")

printf 'Validating configuration before installing HACS...\n'
"$project_dir/scripts/restart-home-assistant.sh" --check

printf 'Installing HACS into the persistent /config directory...\n'
"${compose[@]}" exec -T --workdir /config homeassistant \
  bash -o pipefail -c 'wget -qO - https://get.hacs.xyz | bash -'

"$project_dir/scripts/restart-home-assistant.sh"
printf 'Next: open Settings > Devices & services > Add integration > HACS and authorize GitHub.\n'
