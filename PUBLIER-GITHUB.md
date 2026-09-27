# Publier Coucou en open source sur GitHub

But : un repo public propre, qu'on peut installer en 30 secondes, avec une première release téléchargeable.
Le README (anglais), la LICENSE (MIT), CONTRIBUTING.md et les médias (`docs/media/`) sont déjà prêts.

## Règles
- Ne publie rien tant que les vérifications de l'étape 1 ne sont pas vertes.
- Ne touche pas au comportement de l'app. Ne corrige pas de bug sans que je te le demande.
- `_prive/` et `.claude/` ne doivent jamais partir sur GitHub (déjà dans `.gitignore`, vérifie).
- Garde mon historique git local intact : la publication part d'une branche neuve.

## 1. Vérifications avant publication
- `gh auth status` : si je ne suis pas connecté, arrête-toi et dis-moi de lancer `gh auth login`.
- Aucun secret dans les fichiers suivis : cherche `sk-ant-`, `sk_live_`, `sk_test_`, `rk_live`, `whsec_`, `ghp_`, `github_pat_`, `re_`, jetons JWT, URL d'instance n8n, e-mails perso. Rien ne doit sortir à part les textes d'aide des champs de réglages.
- Aucun chemin perso (`/Users/louis`) dans les fichiers suivis.
- `xcodegen` puis build Release sans erreur.

## 2. Fichiers GitHub
Crée :
- `.github/ISSUE_TEMPLATE/bug_report.md` : champs « What happened / What you expected / How to reproduce / macOS version / Mac model / Coucou version », label `bug`.
- `.github/ISSUE_TEMPLATE/feature_request.md` : « What would you like Mochi to do? / Why would it be useful? », label `enhancement`.
- `.github/workflows/build.yml` : sur push et PR, runner `macos-latest`, installe XcodeGen, `xcodegen`, `xcodebuild -scheme NotchBuddy -configuration Release build CODE_SIGNING_ALLOWED=NO`.
- `.github/workflows/release.yml` : sur tag `v*`, même build, signature ad hoc (`codesign --force --deep -s -`), zip `Coucou.zip` (avec `ditto -c -k --keepParent`), publication dans la release du tag.

## 3. Build de la release
- Build Release en local, signature ad hoc, `Coucou.zip` avec `ditto`.
- Lance l'app depuis le zip décompressé pour vérifier qu'elle démarre (coucou, menu, réglages).

## 4. Publication
1. Remplace `OWNER/REPO` dans `README.md` et dans `docs/*.html` par mon login GitHub (`gh api user --jq .login`) et le nom du repo : `coucou`. Remplace `CONTACT_EMAIL` dans `docs/*.html` par l'adresse que je te donne (demande-la moi si je ne l'ai pas précisée).
2. Branche neuve sans historique : `git checkout --orphan public`, `git add -A`, vérifie `git status` (ni `_prive/`, ni `.claude/`), commit « Coucou — first public release ».
3. `gh repo create coucou --public --source . --remote origin --description "A tiny friend that lives in your MacBook's notch and keeps an eye on your Claude Code sessions."`
4. `git push -u origin public:main`, puis reviens sur ma branche habituelle.
5. Sujets du repo : `macos`, `notch`, `claude-code`, `claude`, `anthropic`, `swift`, `swiftui`, `menubar-app`, `dynamic-island`, `ai-agents`, `macos-app`, `open-source`.
6. Tag `v0.1.0`, release « Coucou 0.1.0 » avec `Coucou.zip` et des notes courtes en anglais (fonctionnalités + premier lancement : System Settings → Privacy & Security → « Open Anyway », ou la commande `xattr` du README).

## 5. Site et pages légales (GitHub Pages)
- Active GitHub Pages sur la branche `main`, dossier `/docs` : `gh api -X POST repos/<login>/coucou/pages -f "source[branch]=main" -f "source[path]=/docs"`.
- Vérifie que ces pages répondent : `index.html`, `privacy.html`, `terms.html`, `support.html`, `legal.html`.
- Ajoute en bas du `README.md` une ligne : Website · Privacy · Terms · Support, avec les liens GitHub Pages.
- Mets l'URL du site comme « Website » du repo : `gh repo edit --homepage https://<login>.github.io/coucou/`.

## 6. Fin
Donne-moi l'URL du repo, de la release et des pages (confidentialité, assistance) pour App Store Connect, et rappelle-moi d'ajouter l'image de partage (Settings → Social preview) avec `docs/media/coucou.png`.
