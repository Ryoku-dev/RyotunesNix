#!/usr/bin/env bash
# Explicit opt-in setup for the separately acquired Spotify Soloist backend.
# Never downloads Soloist, commits credentials, or changes the Ryotunes daemon.
set -euo pipefail
umask 077

if [[ ${1:-} == --help || $# -gt 1 ]]; then
  printf 'Usage: ryotunes-soloist-setup [absolute-path-to-soloist]\n'
  printf 'Soloist is an external runtime. Supply your own executable and API key.\n'
  exit 0
fi

home=${HOME:?HOME is required}
config_dir="$home/.config/ryotunes-soloist"
key_file="$config_dir/api-key"
unit_dir="$home/.config/systemd/user"
unit_file="$unit_dir/ryotunes-soloist-backend.service"
launcher_dir="$home/.local/bin"
launcher="$launcher_dir/ryotunes-soloist-backend"

if [[ -e "$unit_file" ]] && ! grep -Fq '# Managed by RyotunesNix Soloist setup' "$unit_file"; then
  printf 'Existing Soloist user service detected; leaving it unchanged: %s\n' "$unit_file"
  printf 'Run: systemctl --user status ryotunes-soloist-backend.service\n'
  exit 0
fi

binary=${1:-${RYOTUNES_SOLOIST_BINARY:-}}
if [[ -z $binary ]]; then
  for candidate in \
    "$home/.local/opt/ryotunes-soloist/soloist" \
    "$home/.local/opt/ryotunes-soloist-eval/soloist"; do
    if [[ -x $candidate ]]; then
      binary=$candidate
      break
    fi
  done
fi

if [[ -z $binary || ! -x $binary ]]; then
  printf 'Missing Soloist executable. Supply an executable path:\n' >&2
  printf '  nix run github:Ryoku-dev/RyotunesNix#setup-soloist -- /absolute/path/to/soloist\n' >&2
  exit 1
fi

binary=$(realpath -- "$binary")
if [[ ${binary:0:1} != / ]]; then
  printf 'Soloist executable must use an absolute path.\n' >&2
  exit 1
fi

if [[ -n ${RYOTUNES_SOLOIST_DATA_DIR:-} ]]; then
  data_dir=$RYOTUNES_SOLOIST_DATA_DIR
elif [[ -d "$home/.local/share/ryotunes-soloist-eval" ]]; then
  # Match the Ryotunes bridge's legacy evaluation-data discovery rule.
  data_dir="$home/.local/share/ryotunes-soloist-eval"
else
  data_dir="${XDG_DATA_HOME:-$home/.local/share}/soloist"
fi

mkdir -p -- "$config_dir" "$data_dir" "$launcher_dir" "$unit_dir"
chmod 700 "$config_dir" "$data_dir"

if [[ ! -s "$key_file" ]]; then
  if [[ ! -r /dev/tty ]]; then
    printf 'An interactive terminal is needed to enter the Soloist API key.\n' >&2
    exit 1
  fi
  IFS= read -r -s -p 'Spotify Soloist API key: ' secret < /dev/tty
  printf '\n'
  if [[ -z $secret ]]; then
    printf 'Empty API key. Setup stopped.\n' >&2
    exit 1
  fi
  printf '%s' "$secret" > "$key_file"
  unset secret
fi
chmod 600 "$key_file"

printf '%s\n' "$binary" > "$config_dir/backend-path"
printf '%s\n' "$data_dir" > "$config_dir/data-dir"
chmod 600 "$config_dir/backend-path" "$config_dir/data-dir"

cat > "$launcher" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

config="${HOME:?}/.config/ryotunes-soloist"
backend="$(<"$config/backend-path")"
data="$(<"$config/data-dir")"
key="$config/api-key"

if [[ ! -x "$backend" || ! -s "$key" ]]; then
  printf 'Soloist executable or private API key is unavailable.\n' >&2
  exit 1
fi

export PATH="/run/current-system/sw/bin:${PATH:-/usr/bin:/bin}"
exec nix shell nixpkgs#steam-run-free -c steam-run \
  "$backend" \
  --device-name Ryotunes \
  --api-key "$(<"$key")" \
  --data-dir "$data" \
  --ws 127.0.0.1:0
LAUNCHER
chmod 700 "$launcher"

cat > "$unit_file" <<'UNIT'
# Managed by RyotunesNix Soloist setup
[Unit]
Description=Spotify Soloist backend for Ryotunes
After=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=%h/.local/bin/ryotunes-soloist-backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
chmod 600 "$unit_file"

systemctl --user daemon-reload
systemctl --user enable --now ryotunes-soloist-backend.service

# An already-active managed service needs a restart to pick up changed paths.
if systemctl --user is-active --quiet ryotunes-soloist-backend.service; then
  systemctl --user restart ryotunes-soloist-backend.service
fi

for ((attempt = 0; attempt < 30; attempt++)); do
  if [[ -s "$data_dir/ws.addr" && -s "$data_dir/ws.port" ]] &&
     systemctl --user is-active --quiet ryotunes-soloist-backend.service; then
    printf 'Soloist WebSocket ready at %s:%s\n' \
      "$(<"$data_dir/ws.addr")" "$(<"$data_dir/ws.port")"
    printf 'Enabled user service: ryotunes-soloist-backend.service\n'
    exit 0
  fi
  sleep 1
done

printf 'Soloist endpoint not ready. Review the service without sharing credentials:\n' >&2
printf '  systemctl --user status ryotunes-soloist-backend.service\n' >&2
exit 1
