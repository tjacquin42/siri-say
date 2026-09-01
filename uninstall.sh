#!/bin/bash
# Retire siri-say et tout ce qu'il a posé.
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"; LIB="$PREFIX/share/siri-say"; MAN="$PREFIX/share/man/man1"

"$BIN/siri-say" -q >/dev/null 2>&1 || true      # arrête une lecture en cours

# Les raccourcis éventuels pointent vers la commande : on les retire aussi.
for f in "$BIN"/*; do
  [ -L "$f" ] && [ "$(readlink "$f")" = "$BIN/siri-say" ] && { echo "→ $f"; rm -f "$f"; }
done
for f in "$MAN"/*.1; do
  [ -L "$f" ] && [ "$(readlink "$f")" = "$MAN/siri-say.1" ] && rm -f "$f"
done

rm -f  "$BIN/siri-say" "$MAN/siri-say.1"
rm -rf "$LIB" "${TMPDIR:-/tmp}/siri-say"
defaults delete siri-say.vitesse >/dev/null 2>&1 || true
echo "siri-say désinstallé."
