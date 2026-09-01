#!/bin/bash
# Installe siri-say. Aucun privilège requis : tout va dans ~/.local par défaut.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
ALIAS=""

usage() {
  cat <<'TXT'
./install.sh [options]

  --prefix <chemin>   racine d'installation (défaut : ~/.local)
  --alias <nom>       crée un raccourci supplémentaire, par exemple « siri »
  -h, --help          cette aide
TXT
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --alias)  ALIAS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install : option inconnue « $1 »." >&2; usage >&2; exit 2 ;;
  esac
done

echo "→ Vérification des prérequis"
[ "$(uname -s)" = "Darwin" ] || { echo "  siri-say ne fonctionne que sur macOS." >&2; exit 1; }
for outil in swift swiftc python3 codesign; do
  command -v "$outil" >/dev/null || {
    echo "  « $outil » est introuvable." >&2
    [ "$outil" = "swift" ] || [ "$outil" = "swiftc" ] && \
      echo "  Installez les outils en ligne de commande Xcode : xcode-select --install" >&2
    exit 1
  }
done

LIB="$PREFIX/share/siri-say"
BIN="$PREFIX/bin"
MAN="$PREFIX/share/man/man1"
mkdir -p "$LIB" "$BIN" "$MAN"

echo "→ Copie des fichiers vers $LIB"
cp "$SRC/lib/prepare.py" "$SRC/lib/tts.swift" "$SRC/lib/player.swift" "$LIB/"

# tts.swift DOIT rester interprété par `swift` : les voix Siri ne sont visibles
# que d'un binaire signé par Apple, et l'interpréteur en est un. Le lecteur, lui,
# ne synthétise pas — il peut donc être compilé.
echo "→ Compilation du lecteur d'encoche"
APP="$LIB/SiriPlayer.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$SRC/lib/SiriPlayer/Info.plist" "$APP/Contents/Info.plist"
swiftc -O -suppress-warnings "$SRC/lib/player.swift" -o "$APP/Contents/MacOS/player"
# Signature ad hoc : suffisante pour « En cours de lecture », et le binaire
# doit être signé sur la machine qui l'exécute.
codesign -f -s - "$APP" >/dev/null 2>&1

echo "→ Installation de la commande"
install -m 755 "$SRC/bin/siri-say" "$BIN/siri-say"
install -m 644 "$SRC/man/siri-say.1" "$MAN/siri-say.1"

if [ -n "$ALIAS" ]; then
  ln -sf "$BIN/siri-say" "$BIN/$ALIAS"
  ln -sf "$MAN/siri-say.1" "$MAN/$ALIAS.1"
  echo "→ Raccourci « $ALIAS » créé"
fi

echo
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "⚠  $BIN n'est pas dans votre PATH. Ajoutez à ~/.zshrc :"
     echo "     export PATH=\"$BIN:\$PATH\""
     echo ;;
esac

VOIX="$(swift "$LIB/tts.swift" --list 2>/dev/null | head -3 || true)"
if [ -z "$VOIX" ]; then
  echo "⚠  Aucune voix Siri n'est installée. Ouvrez :"
  echo "     Réglages Système → Accessibilité → Contenu énoncé → Voix du système"
  echo "   puis ajoutez une voix, et vérifiez avec « siri-say --list-voices »."
else
  echo "Voix Siri disponibles :"; echo "$VOIX" | sed 's/^/  /'
fi

echo
echo "Installé. Essayez :"
echo "  siri-say \"Bonjour, ceci est un test.\""
echo "  siri-say -i un-document.pdf"
echo "  man siri-say"
