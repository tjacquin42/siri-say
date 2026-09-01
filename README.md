# siri-say

**Read anything aloud in the Siri voice — from your terminal, with a player in the notch.**

[Français](README.fr.md) · [MIT](LICENSE) · macOS only

macOS ships an excellent neural speech synthesizer. It powers Siri, it runs entirely
offline, and it is already on your Mac. The `say` command cannot reach it — ask `say`
for a Siri voice and it silently falls back to the 2005-era one while returning a
success code.

`siri-say` reaches it. Point it at a paragraph, a Markdown file, or a 22-page PDF.

```bash
siri-say "The build is green, three tests were skipped."
siri-say notes.md
siri-say -i quarterly-report.pdf     # plays in the notch, gives your terminal back
```

---

## The notch player

`-i` hands playback to a small panel that lives under the notch. It expands on hover,
and it registers with macOS Now Playing — so the media keys on your keyboard and
Control Center drive it too.

```
                    ┌───────────────┐
   ▁▃▅▂▆▁           │    notch      │            ◜◝            ← at rest
                    └───────────────┘

        ┌───────────────────────────────────────────┐
        │  ▓▓▓   quarterly-report.pdf            ×  │
        │  ▓▓▓   Voix 1 · page 9 of 22              │
        │                                           │
        │  ━━━━━━━━━━━━━●─────────────────────      │  ← click or drag to seek
        │  17:24                            −28:11  │
        │                                           │
        │        ↺15      ⏸      15↻        1,5×    │
        └───────────────────────────────────────────┘
```

The waveform sits left of the notch, the progress ring right of it — the panel is
deliberately wider than the cutout, because the notch is a hole in the panel and
nothing drawn behind it is visible.

When a document finishes, the player stays put with the play button ready to replay.
Only the `×` or `siri-say -q` closes it and deletes its working files.

---

## Install

Requires macOS with a Siri voice installed, and the Xcode command line tools
(`xcode-select --install`).

```bash
git clone https://github.com/tjacquin42/siri-say.git
cd siri-say
./install.sh
```

Everything lands under `~/.local` — no `sudo`, nothing outside your home directory.
Add a shorter name if you want one:

```bash
./install.sh --alias siri     # now `siri` works too
```

`./uninstall.sh` removes all of it.

**No Siri voice yet?** System Settings → Accessibility → Spoken Content → System
Voice → Manage Voices. Then check with `siri-say --list-voices`.

---

## Usage

| | |
|---|---|
| `siri-say "text"` | read the argument |
| `siri-say file.md` | read a text, Markdown or PDF file |
| `cat file.md \| siri-say` | read standard input |
| `siri-say -i file.pdf` | read in the notch, return the terminal |
| `siri-say -q` | stop the notch player |
| `siri-say -n file.pdf` | print what would be spoken, without speaking |
| `siri-say -o out.caf file.md` | write an audio file |
| `siri-say --list-voices` | list the addressable Siri voices |

**Two speed settings, and they are not the same thing.** `--rate 0..1` changes how the
voice articulates and is baked in at synthesis time. `--speed 0.5..2` is a playback
multiplier you can change mid-listen from the panel, pitch preserved.

```bash
siri-say -i -s 1.5 long-report.pdf
```

Full reference: `man siri-say`.

---

## How it works, and why it's built this way

Three constraints shaped this tool. Each cost a round of debugging, so they are
documented rather than buried.

**The synthesizer must stay interpreted.** Siri voices are only visible to an
Apple-signed binary. The `swift` interpreter is one; a binary you compile and sign
yourself is not — it sees 180 voices and not a single Siri among them. So `tts.swift`
ships as source and is run, never compiled. The notch player *is* compiled, because it
only plays audio and never synthesizes.

**Synthesis runs at roughly 4× real time.** 4,000 characters take about 37 seconds to
produce 155 seconds of speech. A 40,000-character PDF would mean six minutes of silence
before the first word. So `-i` splits the text, synthesizes a short first chunk, starts
playing, and builds the rest while you listen. You get audio in about three seconds.

**PDF text needs repairing.** `pdftotext` beats PDFKit — PDFKit splits words apart
("Docu ment"). Letter-spaced display titles come out as `P R A G M A`, which the voice
would spell out letter by letter, so runs of single characters are glued back together.
Markdown is stripped of code blocks, link targets, table pipes and heading marks before
anything is spoken.

---

## Troubleshooting

**Nothing appears when I hover the notch.** The panel only exists while a `-i` reading
is running, and only on the Mac's built-in display — an external monitor has no notch.

**The voice mispronounces English words.** Expected. The French Siri voice reads
English inline terms with a French accent. There is no fix short of installing an
English Siri voice and switching with `-v`.

**A scanned PDF reads as nothing.** There is no text layer to extract. Run OCR first.

---

## License

MIT. See [LICENSE](LICENSE).

Not affiliated with or endorsed by Apple. "Siri" is a trademark of Apple Inc.; this
project simply uses the speech voices macOS already provides.
