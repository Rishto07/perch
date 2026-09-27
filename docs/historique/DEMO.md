# Notch Buddy — mode démo (pour filmer)

Déclenchement : menu barre de menus → « Lancer la démo », ou ⌃⌥⌘D. Échap ou ⌃⌥⌘D à nouveau : arrêt immédiat, retour à l'état réel.

Principe : pendant la démo, l'app **ignore les vraies données** (hooks et n8n mis en file, rejoués après) et joue un scénario avec des tâches factices. Les moments qui demandent un geste attendent le geste de Louis (avec un délai max, puis la démo continue seule). Aucun repère visuel à l'écran : Louis suit ce script. Le son est forcé à ON pendant la démo.

Données factices (reprises du prototype) :
- Korus (Claude Code, `#FF6B5B`) : « Lecture du schéma Prisma », « Migration de la table factures », « Mise à jour des tests », « Lancement de la suite de tests », « Relecture du diff ».
- SBE Hub (Claude Code, `#2DD4A7`) : « Analyse des requêtes lentes », « Index sur les cours », « Écriture des tests ».
- Morning AI Brief (n8n, `#F7B32B`) : « Collecte des sources », « Résumé par Claude », « Envoi Gmail ».
- Publication IG (n8n, `#A78BFA`) : « Rendu du carousel », « Planification ».

## Séquence (≈ 60 s)

| # | Ce qui se passe | Déclencheur | Geste de Louis |
|---|---|---|---|
| 1 | Island `hidden`. | départ | poser la souris sur le notch |
| 2 | `peek`, coucou avec les mains, puis ouverture `empty`. | survol (max 4 s) | laisser la souris |
| 3 | Les 4 tâches arrivent une par une (280 ms d'écart), la vue passe en `overview`, pastilles qui se déroulent. | +1,5 s | — |
| 4 | Survol du bonhomme : clignement, puis 3 claques → `dizzy`, vue `confused` 3,3 s. | 3 clics (max 8 s) | cliquer 3 fois sur le bonhomme |
| 5 | Retour `overview`, puis fermeture en `compact`. | +1,5 s après le retour | éloigner la souris |
| 6 | Alerte permission Korus `npx prisma migrate deploy`. | +1,3 s | cliquer Autoriser (ou Y) |
| 7 | Alerte question SBE Hub « Quel moteur pour la recherche de cours ? ». | +1,5 s après 6 | cliquer Meilisearch |
| 8 | Alerte erreur Morning AI Brief « Le nœud Gmail a expiré après 30 s. ». | +1,5 s après 7 | cliquer Relancer |
| 9 | Dépôt de fichier : upload → uploading → choose. | fichier déposé (max 10 s) | glisser `brief-client.pdf` depuis le Finder vers le notch |
| 10 | Envoyer par mail → vue `mail`. En démo, l'envoi est **simulé** (aucun mail ne part) : vue `note` « Mail envoyé à client@exemple.fr. ». | clic | cliquer Envoyer par mail, taper l'adresse, Envoyer |
| 11 | Korus terminé : roulade verte, vue `finished` 3,4 s, puis tâche retirée. | +1,2 s | — |
| 12 | Attache à une fenêtre : halo arc-en-ciel, vue `prompt`. | bonhomme lâché sur une fenêtre (max 12 s) | attraper le bonhomme dans le notch, le lâcher sur Safari |
| 13 | Recherche : `searching` 2,8 s puis `result` (réponse factice par défaut, réelle si réglage « démo avec vraie API » activé), émote Fier. | Entrée | taper la demande, Entrée |
| 14 | Les 3 dernières tâches passent `finished` une par une (500 ms d'écart), island repliée puis `hidden`. | +3 s | éloigner la souris |

Réponse factice de l'étape 13 (si la fenêtre est Safari sur un site de location) : titre « 3 apparts qui collent », lignes « Príncipe Real, calme, 79 € la nuit », « Alfama, vue sur le Tage, 84 € la nuit », « Graça, terrasse, 88 € la nuit ». Pour n'importe quelle autre fenêtre : titre « Ce que je vois dans cette fenêtre » et 3 lignes génériques tirées du titre de la fenêtre.

Pour le tournage, ouvrir `reference/escale-demo.html` dans Safari : c'est la page factice de location du prototype.
