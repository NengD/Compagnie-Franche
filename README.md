# Compagnie Franche — prototype Godot

Prototype de bataille médiévale en temps réel, en pixel art, dans l'esprit des jeux de type Total War / Mount & Blade.
Graphismes et sons : assets libres (voir [CREDITS.md](CREDITS.md)). Si un fichier manque, le jeu revient au dessin en code.

## Lancer le jeu
1. Installez **Godot 4.7 ou plus récent** (version standard, pas besoin de .NET) : https://godotengine.org
2. Dans Godot : **Importer** → choisissez le fichier `project.godot` de ce dossier.
3. Appuyez sur **F5** (ou le bouton ▶). Le jeu s'ouvre sur le **menu principal**.

## Menu principal
- **Continuer la campagne** : reprend l'emplacement joué en dernier (si une sauvegarde existe).
  **Nouvelle campagne** : choix de la **difficulté** (facile, normal, difficile) et du **mode indulgent**,
  sur le premier emplacement libre, avec un avertissement si l'emplacement contient une campagne en cours.
  Si la campagne sauvegardée est **terminée**, le premier bouton devient **Bilan de la campagne** (écran de fin).
- **Emplacements de campagne** : 3 emplacements. Chacun affiche le jour, l'or, les hommes, la difficulté
  (et « indulgent ») et son état (en cours, bataille en cours, terminée par une victoire ou la ruine), avec
  **Continuer** (ou **Bilan**), **Nouvelle campagne** et **Supprimer** (avec confirmation).
- **Tutoriel** : petite bataille guidée (4 régiments contre 3). Les consignes s'affichent en haut à droite
  et ne se valident qu'en faisant vraiment l'action : sélectionner, déplacer, tracer une ligne de front,
  changer de formation, courir, lancer la bataille (l'ennemi attend jusque-là), envoyer la cavalerie
  sur les archers, gagner. Échap : menu pause (Menu principal pour quitter).
- **Escarmouche** : bataille libre hors campagne (Échap : menu pause, d'où l'on revient au menu), à la
  difficulté des Options (rappelée sous le bouton et dans la barre du haut en bataille).
- **Menu pause** (Échap en bataille : contrat, escarmouche ou tutoriel) : la bataille s'arrête.
  Reprendre (ou Échap), Aide (toutes les commandes), Options (volumes, vitesse, plein écran, taille de l'interface),
  **Abandonner la bataille** (en contrat : retraite ordonnée, après confirmation ; ailleurs : retour au
  menu) et **Menu principal** (en contrat, après un avertissement : compte comme une retraite).
- **Affichage** : toute fenêtre ou écran (16:9, 16:10, 21:9, petites fenêtres) ; la base 1280×720
  s'agrandit selon la hauteur et les formats plus larges ou plus hauts montrent plus de surface.
- **Options** : volumes général / musique / effets, plein écran (aussi **Alt+Entrée** ou **F11**, partout),
  **taille de l'interface** (90 %, 100 %, 125 %, 150 %), **effets visuels** (complets, réduits, aucun), vitesse du jeu (x1, x1,5, x2 ; touche V
  en bataille), **difficulté de l'escarmouche**, **touches de bataille reconfigurables** (cliquez sur une touche puis appuyez sur la nouvelle ;
  si elle sert déjà à une autre action, les deux échangent leurs touches ; Espace, Entrée, Échap, F11, chiffres,
  flèches et caméra ZQSD sont réservés ; bouton « Touches par défaut »). Les touches sont enregistrées
  par lettre, donc correctes en AZERTY comme en QWERTY.
  Fichier : `options.cfg` dans le dossier de données du jeu, appliqué au démarrage.
- La carte de campagne revient au menu par le bouton « Menu principal » ou Échap.

## Difficulté
Définie dans `scripts/difficulty.gd` (un seul endroit, valeurs « normal » = 1) :

| | Facile | Normal | Difficile |
|---|---|---|---|
| Effectifs ennemis | x0,85 | x1 | x1 |
| Moral ennemi | x0,85 | x1 | x1,15 |
| Dégâts ennemis | x0,9 | x1 | x1,1 |
| IA : réflexion / marche / cavalerie | 1,6 s / 25 s / 40 s | 0,8 s / 12 s / 20 s | 0,5 s / 8 s / 15 s |
| IA : carré des piquiers contre les charges | non | oui | oui |
| Recrues / solde (campagne) | x0,8 | x1 | x1,2 |
| Primes des contrats | x1,25 | x1 | x0,85 |

L'escarmouche prend la difficulté des Options ; la campagne garde celle choisie à sa création
(enregistrée dans la sauvegarde, version 4 ; les sauvegardes plus anciennes sont relues en « normal »).

## Campagne
Vous menez une compagnie de mercenaires dans le pays de Valfrène, que se disputent trois factions :
le **Comté de Valfrène** (Valombre, Saint-Aubin), la **Baronnie de Montfaucon** (Montfaucon, Castelroux,
Hautemure) et la **Ligue des villes** (Brévannes, Pontrieux). Le liseré sous chaque ville donne sa faction.
- **Objectif** (annoncé au journal dès le jour 1, rappelé par l'encart en haut à gauche de la carte et dans
  le panneau) : faire de la compagnie la plus célèbre du comté. À **150 de renommée**, la faction qui vous
  estime le plus (parmi celles qui ne vous ferment pas leurs portes) vous convoque dans sa capitale
  (Saint-Aubin, Montfaucon ou Pontrieux, drapeau doré) pour la **bataille décisive** contre sa rivale :
  11 régiments presque tous vétérans. Ce contrat n'expire pas. Le gagner termine la campagne
  (**écran de victoire** avec le bilan : jours, batailles, ennemis tués, pertes, or, vétérans). Le perdre
  coûte de la renommée : il faudra la regagner pour être rappelé.
- **Game over** : si la compagnie n'a plus un homme et ne peut plus lever un seul régiment complet dans la
  ville où elle se trouve (pas assez d'or, ou faction hostile), elle est dissoute : écran de fin avec le
  bilan, puis menu. Une compagnie anéantie mais encore riche peut recruter et repartir.
- **Marcher** : cliquez sur une ville reliée par une route à la vôtre. Chaque jour de marche coûte la **solde**
  (par homme et par jour : piquier 0,3 écu, archer 0,35, homme d'armes 0,6, cavalier 1).
  Si les caisses sont vides, une partie des hommes **déserte** chaque jour.
- **Recruter** : chaque ville lève certains types de troupes, à son prix (de -15 % à Brévannes à +25 %
  à Hautemure). On peut lever un régiment complet (8 régiments au plus) ou **compléter** un régiment entamé.
- **Contrats** : les villes marquées d'un drapeau rouge proposent des contrats sur **5 niveaux** :
  brigands (4 régiments), routiers (6), ost du baron (8), Grande Compagnie (9), ost de la faction rivale (10).
  Accepter lance la bataille ; la victoire paie la prime **et le butin** (2 écus par ennemi tué).
  Les contrats deviennent plus durs avec votre **renommée** (gagnée par les victoires : 5 + 5 x niveau,
  perdue par les défaites) : un niveau de plus tous les 25 points, le niveau 5 à 100. Chaque ville propose le
  niveau le plus haut ou celui d'en dessous. Plus le niveau est haut, plus l'ennemi est nombreux et aguerri
  (niveau 3 : tous aguerris, 30 % de vétérans ; niveau 5 : 80 % de vétérans) et plus la prime est forte
  (de 260 à 1350 écus, +0,2 % par point de renommée, même au-delà du niveau 5). Ils expirent après 14 jours.
  Réglages : `CONTRACT_KINDS`, `FINAL_CONTRACT`, `FAME_STEP` et `FINAL_FAME` dans `scripts/campaign_state.gd`.
- **Réputation** : un contrat gagné rapporte +10 auprès de la faction qui paie et -5 auprès de sa rivale
  (le Comté et la Baronnie se haïssent ; la Ligue est rivale de la Baronnie). La prime varie de x0,5 à x1,5
  selon la réputation. À -30, la faction vous ferme ses portes : ni contrat ni recrutement dans ses villes.
  Les rancunes s'apaisent d'un point tous les deux jours.
- **Vétérans** : chaque régiment gagne de l'expérience à chaque bataille (participation, victoire, ennemis
  tués, flèches comprises). Rangs : **recrues**, **aguerris** (100 xp, un chevron), **vétérans** (250 xp,
  deux chevrons). Chaque rang donne +10 % de dégâts et +15 % de moral. Compléter un régiment avec des
  recrues dilue son expérience (moyenne pondérée par les hommes).
- **Défaite** : l'ennemi pille 30 % de votre or, la faction qui payait vous retire 8 points de réputation,
  et vous perdez de la renommée.
- **Retraite** : en bataille, **R deux fois** (en moins de 3 s) sonne la retraite. C'est une défaite,
  mais seuls les hommes au contact de l'ennemi risquent d'être rattrapés (un sur deux), et la pénalité
  est réduite (10 % de l'or, -4 de réputation, moitié moins de renommée perdue).
- **Évènements de route** (environ une chance sur huit par jour de marche, inscrits au journal) :
  **embuscade** de brigands (bataille forcée à l'arrivée, sans prime mais avec butin), **marchand** à escorter
  (40 à 90 écus), **épidémie** (8 % des hommes), **déserteurs** qui complètent un régiment (un peu aguerris),
  **intempéries** (un jour de marche perdu).
- **Pertes** : les morts sont perdus pour de bon ; les fuyards reviennent. Après une victoire, 30 % des
  tombés sont relevés blessés. Les effectifs et l'expérience passent d'une bataille à l'autre.
- **Bilan de fin de bataille** : après quelques secondes de ralenti, un panneau résume la bataille par-dessus
  le champ (qui continue au ralenti) : issue (victoire, défaite, retraite), contrat, terrain et durée ; pour chaque
  régiment, l'effectif avant → après, les morts, les fuyards revenus, les blessés relevés, les ennemis tués,
  l'expérience gagnée et les **promotions** (ligne dorée « ▲ AGUERRIS ! ») ; puis les pertes des deux camps,
  prime, butin ou pillage, solde du jour, or avant → après, réputation et renommée. En escarmouche et au
  tutoriel, le bilan est simplifié (sans or ni expérience). Entrée affiche le bilan tout de suite, puis continue.
- **Escarmouche libre** : bouton en bas du panneau (bataille hors campagne, Échap : menu pause).
- **Sauvegarde automatique** après chaque marche, recrutement, contrat accepté et bataille.
  Fichiers : `campagne_1.json`, `campagne_2.json`, `campagne_3.json` dans le dossier de données du jeu
  (Windows : `%APPDATA%\Godot\app_userdata\Compagnie Franche\`). L'ancien fichier unique `campagne.json`
  devient automatiquement l'emplacement 1 (au premier passage par le menu).
  Écriture sûre : fichier temporaire, puis l'ancienne version devient la **copie de secours** `.bak`.
  Si le fichier est abîmé (ou absent), la sauvegarde est relue depuis le `.bak`.
  Format versionné (version 5 : emplacements, mode indulgent, bataille en cours) ; les versions 1 à 4
  se relisent (difficulté normale, mode indulgent désactivé, aucune bataille en cours).
- **Bataille en cours sauvegardée** : un contrat accepté ou une embuscade est enregistré avec la campagne.
  Fermer le jeu en pleine bataille puis relancer reprend la bataille (depuis son début, même armée ennemie,
  même terrain) : on ne peut plus annuler une embuscade ni esquiver un contrat mal engagé.
  Quitter par le menu pause compte toujours comme une retraite.
- **Mode indulgent** (option de la nouvelle campagne) : la bataille en cours n'est pas sauvegardée. Fermer
  la fenêtre en pleine bataille revient à l'état d'avant la bataille, et une embuscade interrompue est oubliée.

## Commandes
Les touches marquées * se changent dans **Options**.

| Action | Touche |
|---|---|
| Sélectionner | Clic gauche ou glisser un cadre (Maj pour ajouter) |
| Déplacer / attaquer | Clic droit sur le sol / sur un ennemi |
| Tracer la ligne de front | Clic droit maintenu + glisser : la longueur règle la largeur du front, les troupes font face à l'opposé de leur position |
| Tout sélectionner / un régiment | Ctrl+A / 1 à 8 |
| Courir (fatigue) | Double clic droit (sur le sol, un ennemi, ou en traçant une ligne) |
| Groupes de contrôle | Ctrl + 1 à 8 : mémoriser la sélection ; 1 à 8 : la rappeler (sinon, sélectionne le régiment n°) ; deux appuis rapides : centrer la caméra dessus |
| Halte | H * |
| Formation : ligne → colonne → carré | F * |
| Tenir la position (on/off) | G * : le régiment frappe ce qui est à sa portée mais ne poursuit pas et ne s'engage pas seul (indiqué « tient » sur sa carte) |
| Tir à volonté / cesser le tir (archers) | X * : sans tir à volonté, les archers ne tirent que sur la cible désignée par clic droit (« tir retenu ») |
| Caméra | ZQSD (ou WASD), flèches, clic molette maintenu |
| Zoom | Molette |
| Pluie on/off | T * |
| Lancer la bataille / pause | Espace (pendant le déploiement, aucun combat : les ordres restent dans la zone bleue et on ne peut pas attaquer) |
| Couper / remettre le son | M * |
| Sonner la retraite | R * deux fois |
| Vitesse du jeu x1 → x1,5 → x2 | V * |
| Aide | F1 * |
| Fin de bataille | Entrée : afficher le bilan, puis carte de campagne (contrat) ou rejouer (escarmouche, tutoriel) |
| Menu pause (reprendre, aide, options, abandonner, menu principal) | Échap ; sur l'écran de fin d'escarmouche : retour au menu |

## Règles de combat
- **Pierre-feuille-ciseaux** : piquiers > cavalerie > archers ; hommes d'armes > piquiers.
- **Flancs et dos** : frapper un régiment sur le côté (x1,4) ou dans le dos (x2) fait plus de dégâts et casse son moral.
- **Charge** : la cavalerie lancée à pleine vitesse fait de gros dégâts et repousse l'ennemi… mais s'empale sur les piques.
- **Moral** : un régiment qui subit trop de pertes fuit (une seule chance de se rallier). Une déroute fait paniquer les voisins.
- **Forêts** : ralentissent (surtout les chevaux), arrêtent la moitié des flèches, et **cachent** les troupes. Une attaque sortie d'une forêt déclenche une **embuscade** (gros choc moral).
- **Pluie** : les archers tirent moins loin et moins juste, tout le monde avance plus lentement.
- **Course et endurance** : le double clic droit fait courir le régiment (x1,6), mais la course vide l'endurance en une douzaine de secondes ; la mêlée fatigue aussi, lentement. Sous 60 % d'endurance, la vitesse et les dégâts baissent (jusqu'à x0,6 pour un régiment épuisé). La marche et surtout le repos font récupérer. La barre jaune de la carte du régiment montre l'endurance.
- **Formations** (touche F) : la **ligne** (par défaut) ; la **colonne** (3 de front) avance 15 % plus vite ; le **carré** creux est lent (x0,55) mais n'a ni flanc ni dos : il annule les bonus de flanc et de dos.
- **Ressenti** : une charge de cavalerie qui percute fait trembler la caméra (moins si elle est loin), les chevaux au galop soulèvent de la poussière, un régiment qui fuit pousse des cris, et la fin de la bataille passe quelques secondes au ralenti.
- **Effets visuels** (option complets / réduits / aucun) : gouttes et taches de sang aux coups portés, étincelles sur les armures, mottes de terre des flèches perdues, éclat blanc d'une charge de cavalerie qui percute, traînées des flèches, fumée des cheminées du village, gerbes d'eau dans les gués et la rivière, pluie au sol (impacts, flaques qui se remplissent puis sèchent) et étendards qui flottent au vent. Aucun effet ne trahit un ennemi en embuscade.
- **Tir ami** : les flèches touchent ce qu'elles trouvent… évitez de tirer dans une mêlée.

## Terrains
Le terrain est affiché en haut de l'écran et annoncé au début de la bataille.
- **Rase campagne** et **bois** : route, bosquets ou forêts épaisses (embuscades).
- **Collines** (courbes de niveau, sol éclairci) : des archers au sommet tirent jusqu'à 35 % plus loin ;
  frapper un ennemi situé plus bas fait jusqu'à +50 % de dégâts ; monter une pente ralentit (jusqu'à -45 %).
- **Rivière** (remplace la route) : on la traverse à 35 % de la vitesse, sauf aux **2 ou 3 gués**
  (bandes claires de galets) où l'on passe à vitesse normale.
- **Village** : une dizaine de maisons bloquent le passage ; les soldats les contournent.
- **Palissade** (défense) : une ligne de pieux barre le champ devant votre zone de déploiement, avec
  **2 brèches**. Personne ne franchit les pieux : les régiments des deux camps passent par les brèches et
  on ne se bat pas à travers le mur. Les flèches passent, mais la moitié s'arrête dans les pieux pour les
  soldats postés juste derrière (moins de 80 px). Votre infanterie est déployée de part et d'autre de chaque
  brèche pour prendre en tenaille ce qui la franchit ; l'assaillant amène en échange un régiment d'archers
  de renfort.
- **Choix** : en escarmouche, au hasard. En campagne, d'après la ville du contrat : Valombre bois,
  Saint-Aubin village, Montfaucon et Castelroux collines, Brévannes et Pontrieux rivière, Hautemure rase
  campagne ; les contrats de difficulté 3 et plus à **Hautemure** et **Castelroux** sont des défenses de palissade.
  Table modifiable dans `scripts/terrain.gd` (`TOWN_TERRAINS`, `SIEGE_TOWNS`).

## Structure
```
scenes/menu.tscn        Menu principal (scène de départ)
scenes/tutorial.tscn    Tutoriel (bataille guidée)
scenes/campaign.tscn    Carte de campagne
scenes/end.tscn         Écran de fin de campagne (victoire ou game over, bilan)
scenes/main.tscn        Bataille (un seul nœud, tout est construit par le code)
scripts/campaign_state.gd  État de la campagne : or, jours, compagnie, villes, contrats
scripts/campaign_map.gd    Carte de campagne : rendu, marche, panneau de recrutement et contrats, objectif
scripts/end_screen.gd   Écran de fin : bilan, nouvelle campagne, retour au menu
scripts/main_menu.gd    Menu principal, page Options (rebind des touches), fond pixel art
scripts/game_options.gd Options (GameOptions) : volumes et bus audio, plein écran, taille de l'interface, vitesse, difficulté, touches
scripts/difficulty.gd   Niveaux de difficulté (Difficulty) : multiplicateurs ennemis, IA, économie
scripts/ui_theme.gd     Thème des menus, placement des panneaux selon la taille de la vue
scripts/display_keys.gd Autoload DisplayKeys : Alt+Entrée / F11 (plein écran) partout, taille minimale de fenêtre
scripts/tutorial.gd     Tutoriel : hérite de battle.gd, armées réduites, étapes validées par les actions
scripts/battle.gd       Nœud de la bataille (classe Battle) : assemble simulation, rendu, ordres, caméra,
                        HUD, son, menu pause ; temps (pause, vitesse, ralenti), campagne et bilan
scripts/battle_sim.gd   Simulation sans rendu (BattleSim) : monde, armées, déplacements, mêlée, moral,
                        flèches, endurance, retraite, fin ; prévient le reste par des signaux
scripts/battle_renderer.gd  Rendu pixel art (BattleRenderer, nœud enfant) : sol, soldats, arbres, effets
scripts/battle_orders.gd    Saisie et ordres du joueur (BattleOrders) : sélection, groupes, ligne de front
scripts/battle_effects.gd   Effets visuels (BattleEffects) : sang, étincelles, éclat des charges, traînées des
                            flèches, fumée, éclaboussures, pluie au sol, étendards ; hasard à part, plafond
scripts/battle_camera.gd    Caméra (BattleCamera) : défilement ZQSD, zoom, bornes, secousse
scripts/terrain.gd      Collines, rivière et gués, village, palissade : effets, passages, rendu du relief
scripts/regiment.gd     Régiment : formation, moral, ordres
scripts/soldier.gd      Soldat individuel
scripts/unit_types.gd   Statistiques et capacités des unités (seule source lue par la simulation)
scripts/enemy_ai.gd     IA ennemie
scripts/hud.gd          Interface
scripts/pause_menu.gd   Menu pause de la bataille (Échap)
scripts/battle_report.gd  Panneau du bilan de fin de bataille (données : battle.build_end_report)
scripts/sprite_bank.gd  Chargement et découpage des sprites (repli en code si absents)
scripts/battle_audio.gd Sons de bataille : banques, cors de charge et de retraite, fanfare, vent, oiseaux, pluie
scripts/game_audio.gd   Audio persistant (GameAudio) : musiques menu / carte / bataille / victoire / défaite
                        avec fondu enchaîné, sons d'interface branchés sur tous les boutons
assets/                 Sprites et sons (voir CREDITS.md)
tests/smoke_test.gd     Test automatique sans fenêtre
tests/campaign_test.gd  Test de la campagne (règles, vétérans, réputation, défaite, économie, évènements,
                        niveaux 1 à 5, pluriels, objectif et fin (victoire, ruine), deux batailles de
                        contrat, une retraite, bilan de fin de bataille, carte et embuscade, écrans de fin et menu)
tests/ai_test.gd        Test de l'IA (colonne, ligne, carré face à une charge, course)
tests/menu_test.gd      Test du menu, des options (sauvegarde, rebind) et du tutoriel complet
tests/deploy_pause_test.gd  Test du déploiement (aucun combat, zone bleue) et du menu pause
tests/difficulty_test.gd Test de la difficulté (multiplicateurs, options, sauvegarde, bataille de contrat)
tests/perf_test.gd      Test de performance (bataille à 2x les effectifs : temps d'étape et d'image)
tests/effects_test.gd   Test des effets visuels (même bataille quel que soit le niveau, plafond, option)
tests/effects_capture.gd Captures des effets (village sous la pluie, gué, mêlée, charge) (avec fenêtre ; option --out)
tests/save_test.gd      Test de la sauvegarde (emplacements, migration, copie .bak, bataille en cours reprise,
                        mode indulgent, versions, menu des emplacements)
tests/audio_test.gd     Test de l'audio (chargement de tous les sons, bus, son coupé pendant les tests, fondu)
tests/screenshot.gd     Captures d'écran (avec fenêtre)
tests/terrain_shots.gd  Captures de chaque terrain (avec fenêtre ; option --out)
tests/menu_capture.gd   Captures du menu, des options et du tutoriel (avec fenêtre ; option --out)
tests/report_capture.gd Captures du bilan (contrat avec promotions, escarmouche) (avec fenêtre ; option --out)
tests/capture_dir.gd    Dossier de sortie commun des captures (--out=<dossier>, défaut user://captures)
tests/resolution_capture.gd Captures multi-résolution (menu, carte, fin, bataille, pause) dans user:// (avec fenêtre)
tests/balance.gd        Banc d'essai d'équilibrage (nombreuses batailles simulées)
tests/test_player.gd    Joueurs simulés utilisés par les tests
```

Pour ajouter à la bataille :
- une unité : une entrée dans `UnitTypes.STATS` (capacités `ranged`, `mounted`, `braces`, `armored`,
  `forest_speed`), une ligne dans `UnitTypes.bonus()`, ses sprites ; la simulation ne teste jamais le
  nom d'un type (l'IA et la campagne, si) ;
- un objectif de contrat : dans `BattleSim.check_end()` ;
- un effet sonore : un signal de `BattleSim` branché dans `battle.gd` ;
- un effet visuel : une sorte de particule dans `BattleEffects` (`battle_effects.gd`), déclenchée par
  un signal de `BattleSim` (`hit`, `sound_played`, `impact`) ; son hasard vient de `fx_rng`, jamais
  du `rng` de la simulation (les graines fixes doivent donner la même bataille) ;
- un ordre : une touche dans `BattleOrders.handle_key()`.

## Tests
Tous les tests headless d'un coup (import du projet, test de fumée sur les 6 terrains, puis chaque
`tests/*_test.gd`) ; récapitulatif à la fin, code de sortie 1 si un test échoue :
```
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Only smoke,menu -Terrains plain
bash tools/run_tests.sh          # Linux / macOS (Godot : variable GODOT ou « godot » dans le PATH)
```
Les journaux complets vont dans `build/test-logs/`. Une GitHub Action facultative
(`.github/workflows/tests.yml`) télécharge Godot 4.7.2 et lance `tools/run_tests.sh` à chaque push.

Un test à la fois :
```
godot --headless --path . -s tests/smoke_test.gd      # bataille accélérée, code de sortie 1 si échec
godot --headless --path . -s tests/smoke_test.gd -- --terrain=siege   # idem sur un terrain imposé
                                                      # (plain, forest, hills, river, village, siege, random)
godot --headless --path . -s tests/campaign_test.gd   # campagne : règles, niveaux, fin, batailles, sauvegarde, carte
godot --headless --path . -s tests/ai_test.gd         # IA : formations utilisées, carré face à une charge
godot --headless --path . -s tests/menu_test.gd       # options, rebind, menu, tutoriel parcouru étape par étape
godot --headless --path . -s tests/deploy_pause_test.gd   # déploiement sans combat, menu pause, abandon = retraite
godot --headless --path . -s tests/difficulty_test.gd # difficulté : ennemis, IA, prix, sauvegarde
godot --headless --path . -s tests/perf_test.gd      # performance à 2x les effectifs (--factor=K, --out=<fichier.json>)
godot --headless --path . -s tests/save_test.gd       # sauvegarde : emplacements, .bak, bataille en cours, indulgent
godot --path . -s tests/menu_capture.gd               # menu.png, menu_options.png, tutoriel.png
godot --path . -s tests/report_capture.gd             # bilan_campagne.png, bilan_escarmouche.png
godot --path . --resolution 2560x1080 -s tests/resolution_capture.gd   # captures user://captures_resolution/ (-- --ui=1.5 : interface à 150 %)
godot --path . -s tests/screenshot.gd                 # captures dans le dossier user:// du projet
godot --headless --path . -s tests/balance.gd -- --seeds=10   # taux de victoire et durée par stratégie
godot --headless --path . -s tests/balance.gd -- --seeds=10 --terrain=all   # idem, terrain par terrain
godot --headless --path . -s tests/balance.gd -- --seeds=20 --difficulty=all # idem, par difficulté
godot --path . -s tests/terrain_shots.gd              # terrain_*.png
godot --headless --path . -s tests/effects_test.gd    # effets visuels : déterminisme, plafond, option
godot --path . -s tests/effects_capture.gd            # effets_village.png, effets_gue.png, effets_melee.png, effets_charge.png
godot --path . -s tests/menu_capture.gd -- --out=captures   # met à jour les captures versionnées du dépôt
```
Les scripts de capture (`menu_capture`, `report_capture`, `terrain_shots`, `effects_capture`) écrivent par défaut dans
`user://captures` (sous Windows : `%APPDATA%\Godot\app_userdata\Compagnie Franche\captures\`), donc hors
du dépôt. `--out=<dossier>` choisit un autre dossier ; un chemin relatif part de la racine du projet,
et `--out=captures` remplace les images versionnées de `captures/`.

Le test de performance écrit ses résultats en JSON dans `user://perf/perf_results.json`. Lancé sans
`--headless`, il mesure aussi le vrai coût du rendu. `--max-step-ms=X` le fait échouer si l'étape
moyenne dépasse X ms (aucun seuil par défaut, car les chiffres dépendent de la machine).
`--effects=full|reduced|none` choisit le niveau des effets visuels (complets par défaut). Mesure avec
fenêtre (Radeon RX 7800 XT, 513 soldats) : environ 21 à 23 ms par image en mêlée avec ou sans
effets, l'écart restant dans le bruit de mesure ; l'étape de simulation est inchangée (~8 ms).

## Exporter le jeu
Produit un exécutable Windows autonome `build/CompagnieFranche.exe` (pck intégré, ~110 Mo),
accompagné de `CREDITS.md` (obligatoire : licences des assets) et `README.md`, et l'archive prête à
distribuer `build/CompagnieFranche-<version>-windows.zip`. Si le modèle d'export Linux est installé,
le script exporte aussi `build/linux/CompagnieFranche.x86_64` et `build/CompagnieFranche-<version>-linux.zip`
(`-NoLinux` pour s'en passer).
La version (`application/config/version` dans `project.godot`, actuellement 0.5.0) s'affiche en bas à
droite du menu principal : changez-la là avant une nouvelle diffusion.
1. Installez une fois les **modèles d'export 4.7.2** : dans l'éditeur, *Éditeur → Gérer les modèles d'export →
   Télécharger et installer* (ils vont dans `%APPDATA%\Godot\export_templates\4.7.2.stable\`).
2. Lancez :
   ```
   powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1
   ```
   Godot est cherché dans `E:\_jeu perso\godot\` ; sinon passez `-Godot <chemin\vers\godot.exe>`
   ou définissez la variable d'environnement `GODOT`.

Les préréglages « Windows » et « Linux » (`export_presets.cfg`) excluent `tests/`, `captures/`, `tools/` et `build/`.
On peut aussi exporter depuis l'éditeur : *Projet → Exporter… → Windows*.
Pour distribuer : envoyez le zip de `build/` (l'exe et les deux fichiers .md).
L'icône de l'exe vient de `assets/icon.ico` (générée avec `tools/make_icon.py`, comme `assets/icon.png`).

## Équilibrage
Réglages dans `scripts/unit_types.gd` (statistiques, moral, charge) et `scripts/enemy_ai.gd`.
Objectif : une bataille dure 2 à 4 minutes ; l'ennemi a plus d'infanterie (8 régiments contre 8,
mais 5 d'infanterie contre 4) et une seule cavalerie, le joueur doit donc manœuvrer pour gagner.

Banc d'essai par terrain (10 à 20 graines, victoires du joueur « tactique » / « naïf ») : état de départ
4/10 et 4/10 ; rase campagne 2/10 et 2/10 ; bois 4/10 et 4/10 ; collines 6/10 et 3/10 ; rivière 3/10 et 2/10 ;
village 6/10 et 3/10 ; palissade 11/20 et 10/20. Toutes les batailles se terminent (aucune bloquée).
Les écarts restent dans le bruit d'une série de 10 batailles.

Par difficulté (`balance.gd -- --seeds=20 --first=101 --difficulty=…`, terrain tiré au sort ; victoires du joueur,
durée médiane) :

| Difficulté | Tactique | Naïf | IA contre IA | Durée médiane (tactique) |
|---|---|---|---|---|
| Facile | 20/20 (100 %) | 12/20 (60 %) | 19/20 | 125 s |
| Normal | 11/20 (55 %) | 3/20 (15 %) | 5/20 | 139 s |
| Difficile | 6/20 (30 %) | 5/20 (25 %) | 5/20 | 126 s |

« Normal » est la référence (tous les multiplicateurs à 1, même résultat qu'avant la difficulté).
« Difficile » joue surtout sur le moral et les dégâts ennemis et une IA plus vive ; on ne peut pas
dépasser l'effectif plein d'un régiment.

## Pistes pour continuer
- Sièges plus complets (échelles, portes, assaut d'une ville).
- Nouveaux types d'unités (arbalétriers, chevaliers démontés).
