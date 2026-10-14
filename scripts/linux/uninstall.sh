#!/usr/bin/env bash
# codex-ssh-eg-managed
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/codex-ssh-eg"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/codex-ssh-eg"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/codex-ssh-eg"
bin_dir="$HOME/.local/bin"

pid_file="$state_dir/proxy.pid"
if [ -r "$pid_file" ]; then
  pid="$(sed -n '1p' "$pid_file")"
  case "$pid" in
    ''|*[!0-9]*) ;;
    *)
      if [ -r "/proc/$pid/cmdline" ] &&
          tr '\0' ' ' <"/proc/$pid/cmdline" | grep -Fq -- '-m codex_ssh_eg.proxy'; then
        kill -TERM "$pid" 2>/dev/null || true
      fi
      ;;
  esac
fi

for name in codex-ssh-eg codex-ssh-eg-ensure-proxy codex-ssh-eg-verify \
  codex-ssh-eg-diagnose codex-ssh-eg-recover-orphan; do
  path="$bin_dir/$name"
  if [ -f "$path" ] && grep -Fq 'codex-ssh-eg-managed' "$path"; then
    rm "$path"
  fi
done

if [ -L "$bin_dir/codex" ] && [ "$(readlink "$bin_dir/codex")" = "codex-ssh-eg" ]; then
  rm "$bin_dir/codex"
fi

rm -f "$config_dir/config" "$state_dir/proxy.pid" "$state_dir/proxy.log"
find "$data_dir/codex_ssh_eg" -type f -delete 2>/dev/null || true
find "$data_dir/codex_ssh_eg" -depth -type d -empty -delete 2>/dev/null || true
rmdir "$config_dir" "$data_dir" "$state_dir" 2>/dev/null || true

echo "Removed managed Codex SSH Egress Bridge files."
