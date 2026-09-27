# Coucou — retirer le mode tournage, le Studio et le menu Debug

La vidéo est faite : tout ce qui servait à la démo et aux fausses vues doit disparaître. L'app ne doit garder que son comportement réel.

## Règles
- Ne change rien au comportement réel : pollers, hooks Claude Code, coucou, sons, claques et tournis, dépôt de fichier, mail, chat, réglages.
- **Ne corrige pas les bugs existants**, même si tu les croises en supprimant du code.
- Garde le Bundle ID `fr.louisraille.NotchBuddy`, les clés du trousseau, les UserDefaults et les chemins `Application Support/NotchBuddy`. Ne lis ni n'écris le trousseau. N'écris pas dans `~/.claude`.
- Ne touche pas au dossier `notch-buddy-kit/` (c'est la référence).
- Avant de supprimer quoi que ce soit, cherche tous les appels (`grep -rn`) pour ne rien casser.

## À supprimer

### Mode tournage et Studio 9:16
- Fichiers `DemoController.swift`, `DemoScenes.swift`, `StudioWindow.swift` (et leurs entrées dans le projet si besoin).
- Les raccourcis globaux Carbon du mode tournage (⌃⌥⌘D, ⌃⌥0 à 8, ⌃⌥P, Échap) et le « warm up » `_ = DemoController.shared` dans `AppDelegate.setupIsland()`.
- Menu de la barre de menus : « Filming mode » et « Studio 9:16 », et leurs actions `toggleFilmingMode` / `toggleStudio`.
- `AppState` : `isDemoMode`, `demoModeActive`, `demoCursorPos`, `demoCursorCarrying`, `demoInputText`, `demoIgnoreMouse`, `demoCursorPressed`.
- `IslandRootView` : `DemoCursorView` et son utilisation.
- Les notifications `.demoSetPromptText`, `.demoSubmitPrompt`, `.demoMailTo`, `.demoMailSubject`, `.demoMailBody`, `.demoSendMail` et leurs `onReceive` dans `IslandViewContent`.
- Les branches démo : `if AppState.shared.isDemoMode { onSuccess…; return }` (mail), la réponse scriptée dans `ClaudeService`, la mise en file des événements dans `HookServer` (et la fonction de rejeu), le test `demoIgnoreMouse` dans `IslandWindowController`.
- Les gardes `guard !AppState.demoModeActive else { return }` dans tous les pollers (GitHub, Vercel, Resend, Notion, Stripe, n8n, Cal.com).
- `IslandStateMachine` : `forceHidden()` et `forceCompact()` s'ils ne servaient qu'à la démo.
- Le fichier `~/Library/Application Support/NotchBuddy/demo-data.json` (ce fichier seulement, rien d'autre dans ce dossier).
- `DEMO-TOURNAGE.md` à la racine du projet.

### Fausses données
- `StripePoller.triggerDemo()` et le bouton « Demo » de la carte Stripe dans `IslandViewContent`.
- `AppState.debugAgents` (les agents « Research » / « Looping »), `addDebugTask()`, `clearDebugTasks()`.
- La propriété `isFake` des tâches, `purgeFakeTasks()` et le test `guard !task.isFake` sur les pastilles, si plus rien n'en dépend.

### Menu Debug (fausses vues)
- Le sous-menu « Debug » en entier : Vue ▸, State ▸, Emote ▸, Launch greeting, Simulate mouse enter/leave, Short timers, Slow motion, 3 slaps, Add Korus task, Clear all tasks, Mode ▸, et la simulation de glisser-déposer.
- Leurs actions `debug…` dans `AppDelegate` et les aides `debug…` dans `IslandWindowController`.
- `AppState.debugSlowMotion` et son utilisation dans `BotCanvasView` (garder `dt` tel quel).

Le menu de la barre de menus doit finir avec : **Open Coucou**, **Settings…**, **Quit**.

## Vérification
1. `xcodegen` puis build sans erreur ni nouvel avertissement.
2. `grep -rn -i "demo\|studio\|isFake\|debugAgents\|debugSlow\|triggerDemo" NotchBuddy/Sources` ne renvoie plus rien (hors « Visual Studio Code »).
3. Lance l'app : coucou au lancement, petit → grand au clic, pastilles réelles, Stripe/n8n/GitHub qui se mettent à jour, sons, claques et tournis, dépôt de fichier → mail, chat. Tout marche comme avant.
4. Commit : « Retire le mode tournage, le Studio 9:16 et le menu Debug ».
5. Résumé final : fichiers supprimés, nombre de lignes retirées, et tout ce que tu as laissé en place parce qu'autre chose en dépendait.
