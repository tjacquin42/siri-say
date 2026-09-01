#!/usr/bin/env python3
"""Transforme un texte, un Markdown ou un PDF en texte prêt à être lu à voix haute."""
import os
import re
import subprocess
import sys

SEPARATEURS = {"—", "–", "|", "·", "•", "/", ":"}


def unspace_letters(texte: str) -> str:
    """Recolle les titres lettre-espacés que l'extraction PDF produit.

    « P R AG M A F L O W » redevient « PRAGMAFLOW ». Le critère est la
    proportion de jetons d'une seule lettre : un titre espacé en est fait
    presque entièrement, une phrase française normale non, même quand elle
    enchaîne les mots courts.
    """
    sorties = []
    for ligne in texte.split("\n"):
        jetons = ligne.split()
        lettres = [j for j in jetons if j not in SEPARATEURS]
        seuls = [j for j in lettres if len(j) == 1]
        if len(lettres) >= 4 and len(seuls) / len(lettres) >= 0.6:
            morceaux, courant = [], ""
            for j in jetons:
                if j in SEPARATEURS:
                    if courant:
                        morceaux.append(courant)
                        courant = ""
                    morceaux.append(j)
                else:
                    courant += j
            if courant:
                morceaux.append(courant)
            sorties.append(" ".join(morceaux))
        else:
            sorties.append(ligne)
    return "\n".join(sorties)


def clean_markdown(texte: str) -> str:
    """Retire le balisage Markdown qui n'a aucun sens une fois prononcé."""
    t = texte
    t = re.sub(r"```.*?```", "", t, flags=re.DOTALL)          # blocs de code
    t = re.sub(r"~~~.*?~~~", "", t, flags=re.DOTALL)
    t = re.sub(r"<!--.*?-->", "", t, flags=re.DOTALL)          # commentaires HTML
    t = re.sub(r"!\[([^\]]*)\]\([^)]*\)", "", t)               # images
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)             # liens
    t = re.sub(r"^\s{0,3}#{1,6}\s+", "", t, flags=re.M)        # titres
    t = re.sub(r"^\s*>\s?", "", t, flags=re.M)                 # citations
    t = re.sub(r"^\s*([-*_])\s*\1\s*\1[\s\1]*$", "", t, flags=re.M)  # règles horizontales
    t = re.sub(r"^\s*[-*+]\s+", "", t, flags=re.M)             # puces

    lignes = []
    for ligne in t.split("\n"):
        nue = ligne.strip()
        if re.fullmatch(r"\|?[\s:|-]*\|[\s:|-]*\|?", nue) and "-" in nue:
            continue                                            # séparateur de tableau
        if nue.startswith("|") and nue.endswith("|"):
            cellules = [c.strip() for c in nue.strip("|").split("|")]
            ligne = ", ".join(c for c in cellules if c)
        lignes.append(ligne)
    t = "\n".join(lignes)

    t = re.sub(r"`([^`]*)`", r"\1", t)                          # code en ligne
    t = re.sub(r"\*\*([^*]+)\*\*", r"\1", t)
    t = re.sub(r"__([^_]+)__", r"\1", t)
    t = re.sub(r"\*([^*\n]+)\*", r"\1", t)
    t = re.sub(r"~~([^~]+)~~", r"\1", t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t


def clean_text(texte: str) -> str:
    """Dernière passe, commune à toutes les sources."""
    t = re.sub(r"https?://\S+", "lien", texte)
    t = re.sub(r"\bwww\.\S+", "lien", t)
    t = unspace_letters(t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r"[ \t]+\n", "\n", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def extract_pdf(chemin: str) -> str:
    """Extrait le texte d'un PDF. poppler d'abord : il recolle les mots
    coupés à l'extraction là où PDFKit les casse ('Docu ment')."""
    for cmd in (["pdftotext", chemin, "-"], ["/opt/homebrew/bin/pdftotext", chemin, "-"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    swift = ('import PDFKit; import Foundation; '
             'print(PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))?.string ?? "")')
    r = subprocess.run(["swift", "-e", swift, chemin], capture_output=True, text=True, timeout=180)
    if r.returncode != 0 or not r.stdout.strip():
        raise SystemExit(f"siri-say : impossible d'extraire le texte de {chemin}")
    return r.stdout


def prepare(source: str, est_fichier: bool) -> str:
    if not est_fichier:
        return clean_text(clean_markdown(source))
    ext = os.path.splitext(source)[1].lower()
    if ext == ".pdf":
        return clean_text(extract_pdf(source))
    with open(source, "r", encoding="utf-8", errors="replace") as f:
        brut = f.read()
    if ext in (".md", ".markdown", ".mdx", ""):
        return clean_text(clean_markdown(brut))
    return clean_text(brut)


# Mesuré sur cette machine : 4 000 caractères produisent 154,7 s de parole.
CARACTERES_PAR_SECONDE = 25.9


def split_chunks(texte: str, taille: int, premier: int = 0):
    """Découpe en fragments d'environ `taille` caractères, aux frontières de
    paragraphe quand c'est possible, de phrase sinon.

    Sert à démarrer la lecture sur le premier fragment pendant que la suite
    se synthétise : un PDF entier demande sinon six minutes de silence."""
    morceaux = []
    for para in [p.strip() for p in texte.split("\n\n") if p.strip()]:
        if len(para) <= taille:
            morceaux.append(para)
            continue
        phrases = re.split(r"(?<=[.!?…])\s+", para)
        courant = ""
        for ph in phrases:
            if courant and len(courant) + len(ph) + 1 > taille:
                morceaux.append(courant)
                courant = ph
            else:
                courant = f"{courant} {ph}".strip()
        if courant:
            morceaux.append(courant)

    fragments, courant = [], ""
    for m in morceaux:
        # Le premier fragment est volontairement court : c'est lui qui fixe
        # le délai avant le premier mot prononcé.
        limite = premier if (premier and not fragments) else taille
        if courant and len(courant) + len(m) + 2 > limite:
            fragments.append(courant)
            courant = m
        else:
            courant = f"{courant}\n\n{m}" if courant else m
    if courant:
        fragments.append(courant)
    return [f for f in fragments if f.strip()]


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--split":
        # --split <dossier> <taille> : écrit chunk_000.txt… depuis l'entrée standard
        dossier, taille = args[1], int(args[2])
        premier = int(args[3]) if len(args) > 3 else taille
        fragments = split_chunks(sys.stdin.read(), taille, premier)
        os.makedirs(dossier, exist_ok=True)
        for i, f in enumerate(fragments):
            with open(os.path.join(dossier, "chunk_%03d.txt" % i), "w", encoding="utf-8") as fh:
                fh.write(f)
        total = sum(len(f) for f in fragments)
        print("%d %.1f" % (len(fragments), total / CARACTERES_PAR_SECONDE))
        return
    if args and args[0] == "--file":
        sortie = prepare(args[1], est_fichier=True)
    elif args:
        sortie = prepare(args[0], est_fichier=False)
    else:
        sortie = prepare(sys.stdin.read(), est_fichier=False)
    sys.stdout.write(sortie)


if __name__ == "__main__":
    main()
