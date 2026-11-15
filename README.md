# Compagnie Franche — prototype Godot

Prototype de bataille médiévale en temps réel, en pixel art, dans l'esprit des jeux de type Total War / Mount & Blade.
Graphismes et sons : assets libres (voir [CREDITS.md](CREDITS.md)). Si un fichier manque, le jeu revient au dessin en code.

## Lancer le jeu
1. Installez **Godot 4.7 ou plus récent** (version standard, pas besoin de .NET) : https://godotengine.org
2. Dans Godot : **Importer** → choisissez le fichier `project.godot` de ce dossier.
3. Appuyez sur **F5** (ou le bouton ▶). Le jeu s'ouvre sur le **menu principal**.

## Menu principal
- **Continuer la campagne** (si une sauvegarde existe) / **Nouvelle campagne** (demande confirmation
  si une campagne est en cours : elle serait effacée).
- **Tutoriel** : petite bataille guidée (4 régiments contre 3). Les consignes s'affichent en haut à droite
  et ne se valident qu'en faisant vraiment l'action : sélectionner, déplacer, tracer une ligne de front,
  changer de formation, courir, lancer la bataille (l'ennemi attend jusque-là), envoyer la cavalerie
  sur les archers, gagner. Échap : retour au menu.
- **Escarmouche** : bataille libre hors campagne (Échap : retour au menu).
- **Options** : volumes général / musique / effets, plein écran, vitesse du jeu (x1, x1,5, x2 ; touche V
  en bataille), **touches de bataille reconfigurables** (cliquez sur une touche puis appuyez sur la nouvelle ;
  si elle sert déjà à une autre action, les deux échangent leurs touches ; Espace, Entrée, Échap, chiffres,
  flèches et caméra ZQSD sont réservés ; bouton « Touches par défaut »). Les touches sont enregistrées
  par lettre, donc correctes en AZERTY comme en QWERTY.
  Fichier : `options.cfg` dans le dossier de données du jeu, appliqué au démarrage.
- La carte de campagne revient au menu par le bouton « Menu principal » ou Échap.

## Campagne
Vous menez une compagnie de mercenaires dans le comté de Valfrène.
- **Marcher** : cliquez sur une ville reliée par une route à la vôtre. Chaque jour de marche coûte la **solde**
  (par homme et par jour : piquier 0,3 écu, archer 0,35, homme d'armes 0,6, cavalier 1).
  Si les caisses sont vides, une partie des hommes **déserte** chaque jour.
- **Recruter** : chaque ville lève certains types de troupes. On peut lever un régiment complet
  (8 régiments au plus) ou **compléter** un régiment entamé.
- **Contrats** : les villes marquées d'un drapeau rouge proposent des contrats (brigands, routiers,
  ost du baron). Accepter lance la bataille ; la victoire paie la prime. Les contrats deviennent plus
  durs avec vos victoires et expirent après 14 jours.
- **Pertes** : les morts sont perdus pour de bon ; les fuyards reviennent. Après une victoire, 30 % des
  tombés sont relevés blessés. Les effectifs passent d'une bataille à l'autre.
- **Escarmouche libre** : bouton en bas du panneau (bataille hors campagne, Échap pour revenir au menu).
- **Sauvegarde automatique** après chaque marche, recrutement et bataille, reprise au lancement du jeu.
  Fichier : `campagne.json` dans le dossier de données du jeu
  (Windows : `%APPDATA%\Godot\app_userdata\Compagnie Franche\`). « Nouvelle campagne » demande confirmation.
  Quitter en pleine bataille revient à l'état d'avant la bataille.

## Commandes
Les touches marquées * se changent dans **Options**.

| Action | Touche |
|---|---|
| Sélectionner | Clic gauche ou glisser un cadre (Maj pour ajouter) |
| Déplacer / attaquer | Clic droit sur le sol / sur un ennemi |
| Tracer la ligne de front | Clic droit maintenu + glisser : la longueur règle la largeur du front, les troupes font face à l'opposé de leur position |
| Tout sélectionner / un régiment | Ctrl+A / 1 à 8 |
| Courir (fatigue) | Double clic droit (sur le sol, un ennemi, ou en traçant une ligne) |
| Halte | H * |
| Formation : ligne → colonne → carré | F * |
| Caméra | ZQSD (ou WASD), flèches, clic molette maintenu |
| Zoom | Molette |
| Pluie on/off | T * |
| Lancer la bataille / pause | Espace |
| Couper / remettre le son | M * |
| Vitesse du jeu x1 → x1,5 → x2 | V * |
| Aide | F1 * |
| Fin de bataille | Entrée : carte de campagne (contrat) ou rejouer (escarmouche) |
| Retour au menu (escarmouche, tutoriel) | Échap |

## Règles de combat
- **Pierre-feuille-ciseaux** : piquiers > cavalerie > archers ; hommes d'armes > piquiers.
- **Flancs et dos** : frapper un régiment sur le côté (x1,4) ou dans le dos (x2) fait plus de dégâts et casse son moral.
- **Charge** : la cavalerie lancée à pleine vitesse fait de gros dégâts et repousse l'ennemi… mais s'empale sur les piques.
- **Moral** : un régiment qui subit trop de pertes fuit (une seule chance de se rallier). Une déroute fait paniquer les voisins.
- **Forêts** : ralentissent (surtout les chevaux), arrêtent la moitié des flèches, et **cachent** les troupes. Une attaque sortie d'une forêt déclenche une **embuscade** (gros choc moral).
- **Pluie** : les archers tirent moins loin et moins juste, tout le monde avance plus lentement.
- **Course et endurance** : le double clic droit fait courir le régiment (x1,6), mais la course vide l'endurance en une douzaine de secondes ; la mêlée fatigue aussi, lentement. Sous 60 % d'endurance, la vitesse et les dégâts baissent (jusqu'à x0,6 pour un régiment épuisé). La marche et surtout le repos font récupérer. La barre jaune de la carte du régiment montre l'endurance.
- **Formations** (touche F) : la **ligne** (par défaut) ; la **colonne** (3 de front) avance 15 % plus vite ; le **carré** creux est lent (x0,55) mais n'a ni flanc ni dos : il annule les bonus de flanc et de dos.
- **Tir ami** : les flèches touchent ce qu'elles trouvent… évitez de tirer dans une mêlée.

## Structure
```
scenes/menu.tscn        Menu principal (scène de départ)
scenes/tutorial.tscn    Tutoriel (bataille guidée)
scenes/campaign.tscn    Carte de campagne
scenes/main.tscn        Bataille (un seul nœud, tout est construit par le code)
scripts/campaign_state.gd  État de la campagne : or, jours, compagnie, villes, contrats
scripts/campaign_map.gd    Carte de campagne : rendu, marche, panneau de recrutement et contrats
scripts/main_menu.gd    Menu principal, page Options (rebind des touches), fond pixel art
scripts/game_options.gd Options (GameOptions) : volumes et bus audio, plein écran, vitesse, touches
scripts/ui_theme.gd     Thème des menus
scripts/tutorial.gd     Tutoriel : hérite de battle.gd, armées réduites, étapes validées par les actions
scripts/battle.gd       Terrain, simulation, ordres, caméra, rendu pixel art
scripts/regiment.gd     Régiment : formation, moral, ordres
scripts/soldier.gd      Soldat individuel
scripts/unit_types.gd   Statistiques des unités (à modifier pour équilibrer)
scripts/enemy_ai.gd     IA ennemie
scripts/hud.gd          Interface
scripts/sprite_bank.gd  Chargement et découpage des sprites (repli en code si absents)
scripts/battle_audio.gd Sons de bataille et musique
assets/                 Sprites et sons (voir CREDITS.md)
tests/smoke_test.gd     Test automatique sans fenêtre
tests/campaign_test.gd  Test de la campagne (règles, deux batailles de contrat, carte)
tests/menu_test.gd      Test du menu, des options (sauvegarde, rebind) et du tutoriel complet
tests/screenshot.gd     Captures d'écran (avec fenêtre)
tests/menu_capture.gd   Captures du menu, des options et du tutoriel dans captures/ (avec fenêtre)
tests/balance.gd        Banc d'essai d'équilibrage (nombreuses batailles simulées)
tests/test_player.gd    Joueurs simulés utilisés par les tests
```

## Tests
```
godot --headless --path . -s tests/smoke_test.gd      # bataille accélérée, code de sortie 1 si échec
godot --headless --path . -s tests/campaign_test.gd   # campagne : solde, recrutement, pertes reportées, sauvegarde
godot --headless --path . -s tests/menu_test.gd       # options, rebind, menu, tutoriel parcouru étape par étape
godot --path . -s tests/menu_capture.gd               # captures/menu.png, menu_options.png, tutoriel.png
godot --path . -s tests/screenshot.gd                 # captures dans le dossier user:// du projet
godot --headless --path . -s tests/balance.gd -- --seeds=10   # taux de victoire et durée par stratégie
```

## Équilibrage
Réglages dans `scripts/unit_types.gd` (statistiques, moral, charge) et `scripts/enemy_ai.gd`.
Objectif : une bataille dure 2 à 4 minutes ; l'ennemi a plus d'infanterie (8 régiments contre 8,
mais 5 d'infanterie contre 4) et une seule cavalerie, le joueur doit donc manœuvrer pour gagner.

## Pistes pour continuer
- Expérience des régiments, événements sur les routes.
- IA qui utilise les formations (carré contre la cavalerie) et la course.
