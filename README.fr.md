# siri-say

**Faites lire n'importe quoi par la voix de Siri — depuis votre terminal, avec un lecteur dans l'encoche.**

[English](README.md) · [MIT](LICENSE) · macOS uniquement

macOS embarque un excellent synthétiseur vocal neuronal. C'est celui de Siri, il
fonctionne entièrement hors ligne, et il est déjà sur votre Mac. La commande `say` ne
sait pas l'atteindre : demandez-lui une voix Siri, elle retombe en silence sur celle de
2005 tout en renvoyant un code de succès.

`siri-say` l'atteint. Donnez-lui un paragraphe, un fichier Markdown, ou un PDF de
vingt-deux pages.

```bash
siri-say "Le build est vert, trois tests ont été ignorés."
siri-say notes.md
siri-say -i rapport-trimestriel.pdf     # lit dans l'encoche, et rend la main
```

---

## Le lecteur d'encoche

`-i` confie la lecture à un petit panneau logé sous l'encoche. Il se déplie au survol,
et s'inscrit dans « En cours de lecture » de macOS — les touches média du clavier et le
Centre de contrôle le pilotent donc aussi.

```
                    ┌───────────────┐
   ▁▃▅▂▆▁           │    encoche    │            ◜◝            ← au repos
                    └───────────────┘

        ┌───────────────────────────────────────────┐
        │  ▓▓▓   rapport-trimestriel.pdf         ×  │
        │  ▓▓▓   Voix 1 · page 9 sur 22             │
        │                                           │
        │  ━━━━━━━━━━━━━●─────────────────────      │  ← cliquez ou glissez
        │  17:24                            −28:11  │
        │                                           │
        │        ↺5       ⏸       5↻        1,5×    │
        └───────────────────────────────────────────┘
```

La forme d'onde est à gauche de l'encoche, l'anneau de progression à droite : le
panneau déborde volontairement de la découpe, parce que l'encoche est un trou dans la
dalle et que rien de ce qu'on dessine derrière n'est visible.

Quand un document se termine, le lecteur reste en place, prêt à relire. Seules la croix
et `siri-say -q` le ferment et effacent ses fichiers de travail.

---

## Installation

Demande macOS avec une voix Siri installée, et les outils en ligne de commande Xcode
(`xcode-select --install`).

```bash
git clone https://github.com/tjacquin42/siri-say.git
cd siri-say
./install.sh
```

Tout se pose sous `~/.local` — aucun `sudo`, rien en dehors de votre dossier personnel.
Ajoutez un nom plus court si vous en voulez un :

```bash
./install.sh --alias siri     # « siri » fonctionne aussi désormais
```

`./uninstall.sh` retire l'ensemble.

**Pas encore de voix Siri ?** Réglages Système → Accessibilité → Contenu énoncé → Voix
du système → Gérer les voix. Vérifiez ensuite avec `siri-say --list-voices`.

---

## Utilisation

| | |
|---|---|
| `siri-say "du texte"` | lit l'argument |
| `siri-say fichier.md` | lit un fichier texte, Markdown ou PDF |
| `cat fichier.md \| siri-say` | lit l'entrée standard |
| `siri-say -i fichier.pdf` | lit dans l'encoche, rend le terminal |
| `siri-say -q` | arrête le lecteur d'encoche |
| `siri-say -n fichier.pdf` | affiche ce qui serait prononcé, sans le lire |
| `siri-say -o sortie.caf fichier.md` | écrit un fichier audio |
| `siri-say --list-voices` | liste les voix Siri adressables |

**Deux réglages de vitesse, et ce n'est pas la même chose.** `--rate 0..1` change la
façon dont la voix articule et se fige au moment de la synthèse. `--speed 0.5..2` est
un multiplicateur de lecture, réglable en cours d'écoute depuis le panneau, sans
déformer le timbre.

```bash
siri-say -i -s 1.5 long-rapport.pdf
```

Référence complète : `man siri-say`.

---

## Comment ça marche, et pourquoi c'est fait ainsi

Trois contraintes ont dessiné cet outil. Chacune a coûté un aller-retour de diagnostic,
donc elles sont documentées plutôt qu'enfouies.

**Le synthétiseur doit rester interprété.** Les voix Siri ne sont visibles que d'un
binaire signé par Apple. L'interpréteur `swift` en est un ; un binaire que vous compilez
et signez vous-même ne l'est pas — il voit 180 voix et pas une seule Siri. `tts.swift`
est donc livré en source et exécuté, jamais compilé. Le lecteur d'encoche, lui, *est*
compilé : il ne fait que jouer de l'audio, il ne synthétise rien.

**La synthèse tourne à environ quatre fois le temps réel.** 4 000 caractères demandent
37 secondes pour produire 155 secondes de parole. Un PDF de 40 000 caractères
imposerait six minutes de silence avant le premier mot. `-i` découpe donc le texte,
synthétise un premier fragment court, démarre la lecture, et fabrique la suite pendant
que vous écoutez. Le son arrive en trois secondes environ.

**Le texte des PDF doit être réparé.** `pdftotext` bat PDFKit, qui coupe les mots
(« Docu ment »). Les titres composés en lettres espacées ressortent en `P R A G M A`,
que la voix épellerait lettre par lettre : les suites de caractères isolés sont donc
recollées. Le Markdown est débarrassé de ses blocs de code, cibles de liens, barres de
tableaux et marques de titres avant que quoi que ce soit ne soit prononcé.

---

## En cas de problème

**Rien n'apparaît quand je survole l'encoche.** Le panneau n'existe que pendant une
lecture lancée avec `-i`, et uniquement sur l'écran intégré du Mac — un moniteur externe
n'a pas d'encoche.

**La voix écorche les mots anglais.** C'est attendu. La voix Siri française lit les
termes anglais avec l'accent français. Il n'y a pas de remède, sinon installer une voix
Siri anglaise et basculer avec `-v`.

**Un PDF scanné ne donne rien.** Il n'y a aucune couche de texte à extraire. Passez-le
d'abord à l'OCR.

---

## Licence

MIT. Voir [LICENSE](LICENSE).

Sans lien avec Apple, ni approuvé par Apple. « Siri » est une marque d'Apple Inc. ; ce
projet se contente d'utiliser les voix que macOS fournit déjà.
