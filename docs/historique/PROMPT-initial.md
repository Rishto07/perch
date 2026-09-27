Copie tout le bloc ci-dessous dans Claude Code, ouvert sur ce dossier.

```
Tu construis Notch Buddy, mon app macOS perso : un personnage animé (Mochi) qui vit dans le notch de mon MacBook et me montre mes sessions Claude Code et mes workflows n8n.

Tout est dans ce dossier. Dans cet ordre :
1. Lis CLAUDE.md en entier : ce sont les règles du projet.
2. Lis docs/SPEC.md, docs/INTEGRATIONS.md et docs/DEMO.md.
3. Lis le code de reference/notch-buddy.html : c'est le prototype que j'ai validé. Le personnage (classe Bot), les couleurs, les timings et les vues doivent être identiques dans l'app. Regarde les captures de reference/screens/.
4. Vérifie mon environnement : macOS (sw_vers), Xcode (xcodebuild -version), Homebrew, XcodeGen. S'il manque Xcode, arrête-toi et dis-le moi. Installe XcodeGen toi-même s'il manque.

Ensuite enchaîne les jalons M0 à M9 de docs/SPEC.md sans me demander de validation entre eux. À la fin de chaque jalon : build, lance l'app, capture le notch, compare avec reference/screens/, corrige, commit, et donne-moi un résumé de 3 lignes max.

Tu ne t'arrêtes pour me parler que pour :
- me faire coller une clé API (ouvre la fenêtre Réglages de l'app) ;
- me montrer le diff de ~/.claude/settings.json avant d'y ajouter les hooks ;
- me dire quelle autorisation macOS cliquer ;
- me demander l'URL de mon instance n8n si tu n'arrives pas à la confirmer.

Avant d'implémenter les hooks Claude Code et l'appel à l'API Claude, vérifie les formats actuels dans la doc officielle (liens dans INTEGRATIONS.md). Réponds-moi en français.
```
