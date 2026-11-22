#!/usr/bin/env bash
# One-shot permanence pass for the Omatunes bar pill.
#
#   - sync this plugin into the live Omarchy plugin directory
#   - install the SUPER+ALT+O panel binding in the user's Hyprland config
#   - rebuild the patched player into /usr/local/bin (ahead of the package)
#   - reload both Hyprland and the shell, then verify everything
#
# Safe to re-run at any time: the keybinding edit is idempotent and nothing is
# deleted from the user's configs except this plugin's own stale binding.
set -euo pipefail

plugin_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_repo="${OMATUNES_APP_REPO:-$HOME/Projects/omatunes}"
installed="$HOME/.config/omarchy/plugins/omatunes"
bindings="$HOME/.config/hypr/bindings.lua"

for path in "$plugin_repo" "$app_repo"; do
  if [[ ! -d "$path" ]]; then
    echo "make-permanent: missing checkout: $path" >&2
    exit 1
  fi
done

echo "==> Syncing plugin to $installed"
rsync -a --delete --exclude '.git' "$plugin_repo/" "$installed/"

echo "==> Installing the panel keybinding"
python3 - "$bindings" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines(keepends=True)
canonical = [
    "-- Raise the Omatunes card from anywhere. The card anchors to the bar's strip,\n",
    "-- so it still appears in place when the bar itself is hidden.\n",
    'o.bind("SUPER + ALT + O", "Omatunes card", { panel = "omatunes" })\n',
]

out = []
i = 0
while i < len(lines):
    line = lines[i]
    if 'o.bind("SUPER + ALT + O"' in line or 'omatunes-popup' in line:
        # Drop both comment lines that belong to our own binding, even when a
        # continuation line does not repeat the word "Omatunes".
        dropped = 0
        while out and out[-1].lstrip().startswith('--') and dropped < 2:
            out.pop()
            dropped += 1
        # Drop the whole bind statement, including a multi-line one.
        depth = 0
        while i < len(lines):
            depth += lines[i].count('(') - lines[i].count(')')
            i += 1
            if depth <= 0:
                break
        continue
    out.append(line)
    i += 1

if out and not out[-1].endswith('\n'):
    out[-1] += '\n'
out.append('\n')
out.extend(canonical)
path.write_text(''.join(out))
PY

echo "==> Rebuilding the patched player into /usr/local/bin"
OMATUNES_APP_REPO="$app_repo" "$app_repo/scripts/install-shadow.sh"

echo "==> Reloading Hyprland and the shell"
hyprctl reload >/dev/null 2>&1 || true
omarchy-restart-shell >/dev/null 2>&1 || true
sleep 6

echo "==> Verifying"
resolved="$(command -v omatunes)"
if [[ "$resolved" != "/usr/local/bin/omatunes" ]]; then
  echo "FAIL: omatunes resolves to $resolved, not /usr/local/bin/omatunes" >&2
  exit 1
fi
if ! diff -rq "$plugin_repo" "$installed" -x .git >/dev/null; then
  echo "FAIL: installed plugin differs from this checkout" >&2
  exit 1
fi
if ! grep -Fq 'o.bind("SUPER + ALT + O", "Omatunes card", { panel = "omatunes" })' "$bindings"; then
  echo "FAIL: panel binding missing from $bindings" >&2
  exit 1
fi
errors="$(hyprctl configerrors 2>&1 | sed '/^[[:space:]]*$/d')"
if [[ -n "$errors" ]]; then
  echo "FAIL: Hyprland config errors:" >&2
  echo "$errors" >&2
  exit 1
fi

echo "Permanent, Master Bruce."
echo "  plugin:  $installed"
echo "  binding: SUPER + ALT + O -> omatunes panel"
echo "  player:  $resolved"
