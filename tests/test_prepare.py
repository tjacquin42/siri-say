import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from prepare import clean_markdown, unspace_letters, clean_text

class TestUnspace(unittest.TestCase):
    def test_recolle_titre_lettre_espace(self):
        self.assertEqual(unspace_letters("P R AG M A F L O W"), "PRAGMAFLOW")

    def test_preserve_les_separateurs(self):
        self.assertEqual(unspace_letters("P R AG M A — C A D R E"), "PRAGMA — CADRE")

    def test_laisse_le_texte_normal_intact(self):
        t = "Le monitoring des projets tourne depuis trois semaines."
        self.assertEqual(unspace_letters(t), t)

    def test_ne_casse_pas_une_phrase_avec_mots_courts(self):
        t = "Il y a un bug de ce cru et il a du la voir"
        self.assertEqual(unspace_letters(t), t)

class TestMarkdown(unittest.TestCase):
    def test_titres_perdent_les_dieses(self):
        self.assertEqual(clean_markdown("## Le titre"), "Le titre")

    def test_blocs_de_code_supprimes(self):
        md = "Avant\n```bash\nrm -rf /\necho x\n```\nAprès"
        out = clean_markdown(md)
        self.assertNotIn("rm -rf", out)
        self.assertIn("Avant", out); self.assertIn("Après", out)

    def test_code_inline_garde_le_contenu(self):
        self.assertEqual(clean_markdown("la commande `siri-say` marche"),
                         "la commande siri-say marche")

    def test_lien_reduit_au_libelle(self):
        self.assertEqual(clean_markdown("voir [la doc](https://x.io/a?b=1) ici"),
                         "voir la doc ici")

    def test_image_supprimee(self):
        self.assertEqual(clean_markdown("![diagramme](a.png)").strip(), "")

    def test_emphase_retiree(self):
        self.assertEqual(clean_markdown("du **gras** et de l'*italique*"),
                         "du gras et de l'italique")

    def test_puces_retirees(self):
        self.assertEqual(clean_markdown("- premier\n- second"), "premier\nsecond")

    def test_tableau_lu_comme_des_cellules(self):
        md = "| Projet | État |\n|---|---|\n| Vetibble | live |"
        out = clean_markdown(md)
        self.assertNotIn("|", out)
        self.assertNotIn("---", out)
        self.assertIn("Vetibble", out)

    def test_regle_horizontale_retiree(self):
        self.assertEqual(clean_markdown("a\n\n---\n\nb").strip(), "a\n\nb")

    def test_commentaire_html_retire(self):
        self.assertEqual(clean_markdown("avant <!-- caché --> après"),
                         "avant après")

class TestCleanText(unittest.TestCase):
    def test_url_nue_annoncee_sobrement(self):
        out = clean_text("va voir https://example.com/tres/long/chemin?a=1 stp")
        self.assertNotIn("http", out)
        self.assertIn("lien", out)

    def test_lignes_vides_multiples_reduites(self):
        self.assertEqual(clean_text("a\n\n\n\n\nb"), "a\n\nb")

    def test_espaces_multiples_reduits(self):
        self.assertEqual(clean_text("a     b"), "a b")

    def test_texte_vide(self):
        self.assertEqual(clean_text("   \n\n  "), "")

if __name__ == "__main__":
    unittest.main(verbosity=2)

from prepare import split_chunks

class TestDecoupe(unittest.TestCase):
    def test_texte_court_donne_un_seul_fragment(self):
        self.assertEqual(split_chunks("Trois mots ici.", 500), ["Trois mots ici."])

    def test_coupe_aux_paragraphes(self):
        t = "A" * 300 + "\n\n" + "B" * 300
        f = split_chunks(t, 400)
        self.assertEqual(len(f), 2)
        self.assertTrue(f[0].startswith("A")); self.assertTrue(f[1].startswith("B"))

    def test_regroupe_les_petits_paragraphes(self):
        t = "\n\n".join(["para %d." % i for i in range(10)])
        f = split_chunks(t, 500)
        self.assertEqual(len(f), 1)

    def test_coupe_aux_phrases_si_un_paragraphe_est_trop_long(self):
        t = " ".join("Phrase numéro %d assez longue pour compter." % i for i in range(40))
        f = split_chunks(t, 400)
        self.assertTrue(len(f) > 1)
        self.assertTrue(all(len(c) <= 700 for c in f), [len(c) for c in f])

    def test_aucun_fragment_vide(self):
        f = split_chunks("a\n\n\n\nb\n\n\n\n\n", 100)
        self.assertTrue(all(c.strip() for c in f))

    def test_rien_ne_se_perd(self):
        t = "Premier paragraphe.\n\nDeuxième paragraphe.\n\nTroisième."
        f = split_chunks(t, 25)
        recolle = " ".join(f).replace("\n", " ")
        for mot in ["Premier", "Deuxième", "Troisième"]:
            self.assertIn(mot, recolle)
