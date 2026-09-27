# Coucou

App macOS perso : Mochi, un petit personnage qui vit dans le notch du MacBook. Il montre les sessions Claude Code et les intégrations (Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com), permet de discuter avec Claude, de déposer un fichier pour l'envoyer par mail, et il réagit quand on le survole ou qu'on le tape.

## Lancer

```
cd NotchBuddy
xcodegen          # régénère NotchBuddy.xcodeproj depuis project.yml
open NotchBuddy.xcodeproj
```

Puis ⌘R dans Xcode. Les clés API se collent dans Réglages (menu Coucou de la barre de menus), elles vont dans le Trousseau.

## Dossier

| Dossier | Contenu |
|---|---|
| `NotchBuddy/Sources/App/` | tout le code Swift |
| `NotchBuddy/Resources/sounds/` | les 28 sons du notch (WAV) |
| `NotchBuddy/Assets.xcassets/` | icône de l'app, icône de la barre de menus |
| `NotchBuddy/project.yml` | définition du projet XcodeGen |
| `docs/SPEC.md` | comportement, vues, états, sons |
| `docs/INTEGRATIONS.md` | hooks Claude Code, n8n, API Claude, Mail, fichiers |
| `docs/historique/` | anciens documents (kit de départ, démo, nettoyage) |
| `design/prototype/` | prototype HTML d'origine, source de vérité visuelle |
| `design/captures/` | captures cibles des vues et des états de Mochi |
| `design/animations/` | séquences de référence (coucou, upload) et leurs images |
| `video/` | vidéo de présentation et musique |
| `CLAUDE.md` | règles du projet pour Claude Code |

Identifiant de l'app : `fr.louisraille.NotchBuddy` (à ne pas changer : trousseau, réglages et autorisations en dépendent).
