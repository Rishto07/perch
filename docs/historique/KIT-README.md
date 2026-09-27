# Notch Buddy — kit de construction

Ce dossier contient tout ce qu'il faut pour que Claude Code construise l'app sur ton Mac.

## Ce que tu fais (une fois)

1. **Installe Xcode** depuis l'App Store, ouvre-le une fois et accepte la licence. C'est la seule installation que Claude Code ne peut pas faire à ta place.
2. **Place ce dossier** où tu veux, par exemple `~/Documents/Projets/notch-buddy`.
3. **Ouvre Claude Code sur ce dossier** (app Claude, onglet Code, ou `claude` dans un terminal ouvert ici).
4. Choisis le mode qui accepte les modifications de fichiers automatiquement (sinon il te demandera à chaque fichier).
5. **Colle le prompt** de `PROMPT.md`.

## Les seuls moments où il te sollicitera

- Coller ta **clé API Anthropic** (à créer sur console.anthropic.com ; l'API est facturée à part de ton abonnement Claude) dans la fenêtre Réglages de l'app.
- Coller ta **clé API n8n** (dans n8n : Settings → n8n API) et confirmer l'URL de ton instance.
- Valider le **diff de `~/.claude/settings.json`** avant qu'il ajoute les hooks (une sauvegarde est faite avant).
- Cliquer les **autorisations macOS** : Automatisation (Mail, Terminal, navigateur) et Enregistrement de l'écran.

## Contenu

| Fichier | Rôle |
|---|---|
| `PROMPT.md` | le prompt à coller |
| `CLAUDE.md` | règles du projet, relues par Claude Code à chaque session |
| `docs/SPEC.md` | spécification complète et jalons M0 à M9 |
| `docs/INTEGRATIONS.md` | Claude Code, n8n, API Claude, fichiers, fenêtres, Mail |
| `docs/DEMO.md` | séquence démo intégrée (⌃⌥⌘D) pour filmer |
| `reference/notch-buddy.html` | prototype validé, source de vérité visuelle |
| `reference/escale-demo.html` | page factice à ouvrir dans Safari pendant le tournage |
| `reference/screens/` | captures cibles (vues et états de Mochi) |
| `assets/sounds/` | les 28 sons du prototype en WAV |

## Si tu reprends plus tard

Rouvre Claude Code dans ce dossier et dis-lui : « Reprends Notch Buddy là où tu t'es arrêté, relis CLAUDE.md et l'historique git. »
