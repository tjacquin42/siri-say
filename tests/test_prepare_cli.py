import contextlib
import io
import os
import runpy
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from prepare import prepare, main, extract_pdf, split_chunks

PREPARE_PY = os.path.join(os.path.dirname(__file__), "..", "lib", "prepare.py")


class TestPrepareDispatch(unittest.TestCase):
    """prepare() aiguille selon l'extension : texte direct, Markdown, brut, PDF."""

    def test_texte_direct_passe_par_le_nettoyage_markdown(self):
        self.assertEqual(prepare("## Titre", est_fichier=False), "Titre")

    def test_fichier_markdown_est_nettoye(self):
        with tempfile.TemporaryDirectory() as d:
            chemin = os.path.join(d, "notes.md")
            with open(chemin, "w", encoding="utf-8") as f:
                f.write("# Titre\n\nUn **gras**.")
            self.assertEqual(prepare(chemin, est_fichier=True), "Titre\n\nUn gras.")

    def test_fichier_sans_extension_traite_comme_markdown(self):
        with tempfile.TemporaryDirectory() as d:
            chemin = os.path.join(d, "notes")
            with open(chemin, "w", encoding="utf-8") as f:
                f.write("# Titre")
            self.assertEqual(prepare(chemin, est_fichier=True), "Titre")

    def test_fichier_texte_brut_garde_le_balisage(self):
        # .txt n'est pas traité comme du Markdown : le balisage n'est pas retiré.
        with tempfile.TemporaryDirectory() as d:
            chemin = os.path.join(d, "notes.txt")
            with open(chemin, "w", encoding="utf-8") as f:
                f.write("## Pas un titre ici")
            self.assertIn("##", prepare(chemin, est_fichier=True))

    def test_fichier_pdf_delegue_a_extract_pdf(self):
        with mock.patch("prepare.extract_pdf", return_value="Texte extrait  \n") as m:
            self.assertEqual(prepare("rapport.pdf", est_fichier=True), "Texte extrait")
            m.assert_called_once_with("rapport.pdf")


class TestExtractPdf(unittest.TestCase):
    """extract_pdf() : poppler d'abord, repli sur Swift/PDFKit, échec si rien ne marche.

    Aucun processus réel n'est lancé : subprocess.run est simulé dans les trois cas.
    """

    def test_utilise_pdftotext_quand_il_marche(self):
        reponse = mock.Mock(returncode=0, stdout="Texte poppler")
        with mock.patch("prepare.subprocess.run", return_value=reponse) as m:
            self.assertEqual(extract_pdf("x.pdf"), "Texte poppler")
            self.assertEqual(m.call_count, 1)

    def test_bascule_sur_swift_si_pdftotext_est_absent(self):
        reponse_swift = mock.Mock(returncode=0, stdout="Texte swift")
        with mock.patch(
            "prepare.subprocess.run",
            side_effect=[FileNotFoundError(), FileNotFoundError(), reponse_swift],
        ) as m:
            self.assertEqual(extract_pdf("x.pdf"), "Texte swift")
            self.assertEqual(m.call_count, 3)

    def test_echoue_si_rien_ne_marche(self):
        reponse_swift = mock.Mock(returncode=1, stdout="")
        with mock.patch(
            "prepare.subprocess.run",
            side_effect=[FileNotFoundError(), FileNotFoundError(), reponse_swift],
        ):
            with self.assertRaises(SystemExit):
                extract_pdf("x.pdf")


class TestMainCLI(unittest.TestCase):
    """main() : lecture de l'entrée standard, d'un argument, d'un fichier, --split."""

    def _lancer(self, argv, entree=""):
        buf = io.StringIO()
        with mock.patch.object(sys, "argv", ["prepare.py"] + argv), \
                mock.patch.object(sys, "stdin", io.StringIO(entree)), \
                contextlib.redirect_stdout(buf):
            main()
        return buf.getvalue()

    def test_sans_argument_lit_l_entree_standard(self):
        self.assertEqual(self._lancer([], entree="## Depuis stdin"), "Depuis stdin")

    def test_argument_positionnel_est_du_texte(self):
        self.assertEqual(self._lancer(["## Depuis argv"]), "Depuis argv")

    def test_option_file_lit_un_fichier(self):
        with tempfile.TemporaryDirectory() as d:
            chemin = os.path.join(d, "a.md")
            with open(chemin, "w", encoding="utf-8") as f:
                f.write("# Depuis un fichier")
            self.assertEqual(self._lancer(["--file", chemin]), "Depuis un fichier")

    def test_option_split_ecrit_des_fragments_et_annonce_la_duree(self):
        with tempfile.TemporaryDirectory() as d:
            sortie = self._lancer(["--split", d, "500"], entree="Un paragraphe correct.")
            with open(os.path.join(d, "chunk_000.txt"), encoding="utf-8") as f:
                self.assertEqual(f.read(), "Un paragraphe correct.")
            nb_fragments, duree = sortie.split()
            self.assertEqual(nb_fragments, "1")
            self.assertGreater(float(duree), 0)

    def test_option_split_garde_un_premier_fragment_court_si_le_paragraphe_le_permet(self):
        # Quand le premier paragraphe, pris seul, tient déjà sous `premier`,
        # le découpage respecte bien l'intention documentée ("le premier
        # fragment est volontairement court").
        para1 = ("Ceci est un premier paragraphe assez banal, comme on en trouve dans "
                 "beaucoup de documents, avec plusieurs phrases qui s'enchaînent normalement. "
                 "Il décrit le contexte avant d'entrer dans le détail. On continue encore un peu "
                 "pour simuler un paragraphe d'introduction réaliste et pas spécialement long.")
        para2 = ("Second paragraphe, plus loin dans le document, qui contient la suite du propos "
                 "et quelques détails supplémentaires sur le sujet traité ici.")
        para3 = "Troisième paragraphe de conclusion, assez court."
        texte = para1 + "\n\n" + para2 + "\n\n" + para3
        with tempfile.TemporaryDirectory() as d:
            self._lancer(["--split", d, "1400", "380"], entree=texte)
            with open(os.path.join(d, "chunk_000.txt"), encoding="utf-8") as f:
                premier_fragment = f.read()
        self.assertEqual(premier_fragment, para1)
        self.assertLessEqual(len(premier_fragment), 380)


class TestPointEntree(unittest.TestCase):
    """Le `if __name__ == "__main__": main()` de queue de fichier."""

    def test_execute_comme_script_appelle_main(self):
        buf = io.StringIO()
        with mock.patch.object(sys, "argv", ["prepare.py", "## Exécution directe"]), \
                contextlib.redirect_stdout(buf):
            runpy.run_path(PREPARE_PY, run_name="__main__")
        self.assertEqual(buf.getvalue(), "Exécution directe")


class TestPremierFragmentCourt(unittest.TestCase):
    """Documente un comportement surprenant de split_chunks (voir la PR, « Bugs trouvés »)."""

    def test_premier_paragraphe_ordinaire_ignore_la_limite_premier(self):
        # Un paragraphe isolé plus long que `premier` mais sous `taille` part
        # en un seul morceau insécable : la limite « premier fragment court »
        # ne s'applique qu'ENTRE deux morceaux, jamais à l'intérieur de l'un
        # d'eux. Avec les valeurs réelles de bin/siri-say (taille=1400,
        # premier=380), un premier paragraphe de 779 caractères — tout à fait
        # ordinaire — produit donc un premier fragment deux fois plus long
        # que prévu.
        paragraphe = ("Ce premier paragraphe est un peu plus développé que le précédent, comme on en "
                      "trouve couramment en tête d'un article ou d'un rapport, avec plusieurs phrases "
                      "assez longues qui posent le contexte avant d'entrer dans le vif du sujet et qui "
                      "prennent le temps d'expliquer les enjeux pour un lecteur qui découvre le document "
                      "sans aucun repère préalable sur le sujet traité par la suite du texte. ") * 2
        texte = paragraphe.strip() + "\n\n" + "Deuxième paragraphe, plus court."
        fragments = split_chunks(texte, 1400, 380)
        self.assertEqual(fragments[0], paragraphe.strip())
        self.assertGreater(len(fragments[0]), 380)


if __name__ == "__main__":
    unittest.main(verbosity=2)
