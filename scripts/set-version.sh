#!/bin/bash
# Pose la prochaine version dans le fichier VERSION.
#   scripts/set-version.sh major|minor|patch
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIVEAU="${1:-patch}"
case "$NIVEAU" in major|minor|patch) ;; *) echo "usage: set-version.sh major|minor|patch" >&2; exit 2 ;; esac
A="$(tr -d '[:space:]' < "$R/VERSION")"
B="$(awk -F. -v n="$NIVEAU" '{
  if (n=="major") printf "%d.0.0", $1+1;
  else if (n=="minor") printf "%d.%d.0", $1, $2+1;
  else printf "%d.%d.%d", $1, $2, $3+1;
}' <<<"$A")"
printf '%s\n' "$B" > "$R/VERSION"
echo "VERSION : $A → $B"
