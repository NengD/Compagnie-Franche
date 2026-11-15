# Compagnie Franche — analyse du projet (15 novembre 2026)

## Résumé

**Où en est le jeu.** Le cœur tactique est solide et bien testé : batailles en temps réel avec moral, flancs,
charges, endurance, formations, 6 terrains, une IA qui manœuvre, des ordres riches (ligne de front tracée,
groupes, tenir, tir retenu, retraite). Autour, une campagne déjà jouable : 7 villes, 3 factions, solde,
contrats, vétérans, évènements de route, sauvegarde automatique. Il y a aussi un menu, des options, un
tutoriel guidé et un export Windows. Tous les tests headless passent (smoke sur les 6 terrains, campagne,
menu, IA).

**Ce qui empêche d'en faire un jeu complet.**
1. **La campagne n'a ni but ni fin.** Aucune condition de victoire, pas d'écran de fin (ni victoire, ni
   game over). La difficulté plafonne dès 50 de renommée (environ 5 victoires), puis rien ne change.
2. **La partie manque de variété à moyen terme.** Il y a 4 types d'unités et 3 modèles d'armée ennemie. Les
   textes de contrat sont fixes et la carte ne change jamais. Après 1 h, on a tout vu.
3. **Il n'y a pas de menu pause en bataille de campagne.** Échap n'y fait rien : pour quitter, il faut fermer
   la fenêtre (le jeu revient alors à l'état d'avant la bataille).
4. **Un exploit casse le déploiement.** On peut marcher sur l'ennemi et le tuer avant d'appuyer sur Espace,
   et l'IA ne réagit pas (vérifié : 17 ennemis sur 134 tués sans lancer la bataille).
5. **La finition n'est pas au niveau d'un jeu publié.** La difficulté n'est pas réglable, alors que
   l'escarmouche est dure (le joueur simulé « tactique » gagne 2 à 6 parties sur 10 selon le terrain). La
   musique n'existe qu'en bataille et il n'y a aucun son d'interface. Les textes sont petits et l'aide masque
   un quart de l'écran. Le rendu est inégal hors 16:9 ou à une échelle non entière.

En résumé, c'est un **prototype avancé**, jouable de bout en bout sur le plan technique. Pour en faire un
jeu « complet et agréable », il manque surtout une **structure de campagne** (objectif, progression, fin),
du **contenu** et une couche de **confort et de lisibilité**. Le code et les tests sont une bonne base
pour y arriver.

---

## 1. Inventaire : ce qui existe réellement

### 1.1 Boucle de jeu
Menu → (tutoriel | escarmouche | campagne). Sur la carte de campagne, on marche, on recrute et on accepte un
contrat. Cela lance la bataille, puis le compte rendu ramène à la carte. Escarmouche et tutoriel reviennent
au menu par Échap. La boucle est **complète et fonctionnelle**, mais **sans fin ni objectif** (voir 3.1).

### 1.2 Bataille (`scripts/battle.gd`, 1958 lignes, `regiment.gd`, `soldier.gd`, `unit_types.gd`, `terrain.gd`)
| Fonction | État |
|---|---|
| Simulation soldat par soldat (grille spatiale, séparation, cibles individuelles) | complet |
| 4 types : piquiers, hommes d'armes, archers, cavaliers ; pierre-feuille-ciseaux | complet |
| Moral, déroute, ralliement unique, panique des voisins | complet |
| Flancs / dos (x1,4 / x2), charge de cavalerie, piques contre chevaux | complet |
| Endurance, course (double clic droit), fatigue en mêlée | complet |
| Formations ligne / colonne / carré creux | complet |
| Ligne de front tracée au clic droit glissé avec aperçu fantôme | complet |
| Groupes de contrôle Ctrl+1-8, double appui pour centrer la caméra | complet |
| Tenir la position (G), tir à volonté / retenu (X), halte (H) | complet |
| Retraite (R deux fois) avec pénalités réduites | complet |
| Embuscades depuis les forêts (unités cachées) | complet |
| Terrains : plaine, bois, collines (hauteur, portée, dégâts), rivière et gués, village (maisons à contourner), palissade (brèches, abri contre les flèches) | complet, mais un seul type de siège (défense de palissade) |
| Pluie (touche T) : portée, précision, vitesse | complet, mais déclenchée **par le joueur**, jamais par la météo de campagne |
| Ressenti : secousse de caméra, poussière, flash au coup, ralenti de fin, cris de déroute | complet |
| Vitesse x1 / x1,5 / x2, pause | complet |
| Déploiement | **partiel** : la zone bleue est seulement dessinée, rien n'y oblige (bug B1) |

### 1.3 IA (`scripts/enemy_ai.gd`)
Elle fait avancer l'infanterie en ligne, colonne de loin, ligne au contact. Les piquiers forment le carré
face à une charge. Les archers tirent et se replient vers l'infanterie. La cavalerie reste en réserve 20 s,
puis contourne pour viser les archers ou un flanc. Les hommes d'armes courent sur les derniers mètres.
**Limites :** l'IA n'utilise pas le terrain (collines, forêts, gués). Elle n'a qu'une seule stratégie, ne
se retire jamais, et la même IA sert en attaque comme en défense. Son seul « niveau » est la composition de
l'armée.

### 1.4 Campagne (`scripts/campaign_state.gd`, `scripts/campaign_map.gd`)
- 7 villes, 10 routes, 3 factions avec rivalités ; la réputation module la prime et ferme les portes à -30.
- Solde quotidienne, désertion si les caisses sont vides, recrutement selon la ville et à son prix,
  complément des régiments entamés (l'expérience se dilue).
- Contrats sur 3 niveaux (brigands, routiers, ost du baron), qui expirent en 14 jours. La difficulté suit la
  renommée.
- Expérience : 3 rangs (+10 % de dégâts et +15 % de moral par rang), chevrons sur la carte et dans le HUD.
- Évènements de route : embuscade, marchand, épidémie, déserteurs, intempéries.
- Pertes durables, 30 % de blessés relevés après une victoire, butin de 2 écus par ennemi tué.
- Sauvegarde JSON automatique et atomique (fichier `.tmp` puis renommage), version 2 qui lit encore la
  version 1, chargement validé champ par champ.
- **Absent :** but de campagne, fin, autres compagnies ou armées qui bougent sur la carte, météo, saisons,
  équipement, officiers, plusieurs emplacements de sauvegarde, événements à choix.

### 1.5 Interface
- Menu principal en pixel art animé (colonne de soldats), confirmation avant d'effacer une campagne.
- Options : volumes (général, musique, effets), plein écran, vitesse, touches de bataille reconfigurables
  avec échange en cas de conflit et touches réservées. Les touches sont stockées par lettre, donc
  correctes en AZERTY.
- HUD de bataille : rapport de forces, terrain, météo, cartes de régiment (effectif, moral, endurance,
  ordres, groupe, rang), messages, aide (F1), titres DÉPLOIEMENT / PAUSE / VICTOIRE / DÉFAITE / RETRAITE.
- Carte : panneau à droite (compagnie, recrutement, contrats, réputation, journal), info-bulle sur les
  villes, durée des trajets sur les routes.
- Tutoriel en 8 étapes, validées par les vraies actions du joueur.
- **Absent :** menu pause en bataille, écran de fin de bataille détaillé (pertes par régiment, xp gagnée),
  info-bulle sur les régiments ennemis, mini-carte, réglage de la taille de l'interface, police propre au
  jeu (on utilise `ThemeDB.fallback_font`).

### 1.6 Audio (`scripts/battle_audio.gd`)
Épées, chocs, arc, cris de mort (10 variantes chacun), galop en boucle selon le nombre de cavaliers en
mouvement, une musique de bataille. Spatialisation simple par distance à la caméra, 20 voix au maximum,
bus Musique et Effets.
**Absent :** musique de menu et de carte, sons d'interface (clic, recrutement, or), cor ou tambour pour les
ordres, la charge et la retraite, fanfare de victoire ou de défaite, ambiance (vent, oiseaux, pluie). La
banque `swish` est chargée mais jamais jouée.

### 1.7 Graphismes
Sprites MiniWorld CC0 (4 unités x 2 couleurs, arbres, herbe) ; maisons, palissade, relief, rivière, menu et
carte dessinés en code. Il y a un repli dessiné en code si un sprite manque. Le rendu est cohérent et
lisible à 1280x720 (captures vérifiées : menu, carte, déploiement, mêlée).

### 1.8 Tests
| Test | Couvre | Résultat (15/11/2026) |
|---|---|---|
| `smoke_test.gd --terrain=` plain, forest, hills, river, village, siege | lignes de front, formations, course, ordres, assets, terrain, bataille complète | **6/6 OK** |
| `campaign_test.gd` | règles, vétérans, réputation, défaite/retraite, économie, évènements, sauvegarde (y compris fichier corrompu), batailles de contrat | **OK** |
| `menu_test.gd` | options, rebind, menu, tutoriel complet (victoire en 28 s) | **OK** |
| `ai_test.gd` | formations de l'IA, carré face à une charge, course | **OK** |
| `balance.gd`, `screenshot.gd`, `terrain_shots.gd`, `menu_capture.gd` | outils (non bloquants) | non relancés (`menu_capture` et `terrain_shots` écrivent dans `captures/`) |

Aucun test ne vérifie le rendu automatiquement (seulement des captures à regarder), ni les performances, ni
l'export. Il n'y a pas d'intégration continue.

### 1.9 Export
`tools/export_windows.ps1` produit `build/CompagnieFranche.exe` (pck intégré, environ 110 Mo, icône) avec
README et CREDITS. Un `build/` existe déjà. Il n'y a pas de numéro de version visible dans le jeu, ni
d'export Linux ou macOS.

---

## 2. Problèmes trouvés

### Bugs
| # | Gravité | Où | Problème |
|---|---|---|---|
| B1 | **haute** | `scripts/battle.gd:467-478`, `:1431`, `:1555` | **On peut combattre pendant le déploiement.** `simulate()` fait bouger et frapper les soldats dans l'état DEPLOY, mais l'IA ne pense qu'en BATTLE. Les ordres ne sont pas limités à la zone bleue (`DEPLOY_Y` ne sert qu'au dessin). Sonde : l'infanterie envoyée au contact sans appuyer sur Espace tue 17 ennemis sur 134 qui ne réagissent pas. Correctif : limiter `dest` sous `DEPLOY_Y` en DEPLOY et/ou ne pas lancer de coups avant BATTLE. |
| B2 | moyenne | `scripts/battle.gd:1193-1196` | **Pas de sortie ni de pause en bataille de contrat** : Échap ne fait rien et il n'existe pas de menu pause. Seule la fermeture de la fenêtre permet de quitter. |
| B3 | moyenne | `scripts/campaign_state.gd:125-140`, `scripts/campaign_map.gd:57,73,215-221` | `pending` (contrat ou embuscade en cours) n'est jamais sauvegardé. Après une embuscade, la carte sauvegarde puis lance la bataille : quitter le jeu (ou Échap pendant la marche) **annule l'embuscade**. Fermer la fenêtre pendant un contrat permet aussi de le **rejouer à volonté** (même graine). C'est voulu (« revient à l'état d'avant ») mais exploitable. |
| B4 | basse | `scripts/hud.gd:60`, `scripts/battle.gd:1229-1236` | La numérotation des cartes de régiment (et des touches 1-8) suit `player_regiments()`, qui exclut les régiments morts ou en fuite. Les numéros **se décalent en pleine bataille** et ne correspondent plus à ceux de la carte de campagne (`company_index`). |
| B5 | basse | `scripts/battle_audio.gd:17` | La banque `swish` est chargée mais jamais jouée (code mort). |
| B6 | basse | `scripts/campaign_state.gd:608` | Pluriels figés : « 1 archers », « 1 hommes d'armes », « 1 cavaliers » dans le résumé des armées (visible sur la carte). |
| B7 | basse | `scripts/campaign_state.gd:566` | La difficulté des contrats plafonne à 3 dès 50 de renommée (environ 5 victoires). Ensuite tous les contrats sont de niveau 2-3 et la progression s'arrête. |

### Lisibilité et interface (constatés sur les captures)
- Les messages de bataille s'affichent **sans fond** en haut à gauche, par-dessus les arbres : peu lisibles
  (`scripts/hud.gd`, bloc « Messages »).
- L'aide (F1) est **affichée par défaut à chaque bataille** et masque environ 23 % de l'écran à droite,
  par-dessus les troupes (`scripts/battle.gd:35`, `show_help := true`, non mémorisé).
- Les textes sont petits (11-13 px) avec la police par défaut. Dans les cartes de régiment, « 3 Hommes
  d'armes » touche le bord.
- Rien n'identifie un régiment ennemi : pas d'info-bulle ni de survol, seulement le pictogramme du drapeau.
- Sur la carte, deux contrats d'une même ville peuvent porter le même texte, et le panneau est long (il faut
  défiler pour voir le journal et les boutons du bas).

### Résolutions et affichage
- `project.godot` : `stretch/mode="canvas_items"` sans `scale_mode` ni `aspect`. En 1680x1050 (16:10),
  l'image est mise à l'échelle 1,31 : bandes noires, et la police pixel (filtre « nearest ») devient
  **irrégulière**, avec des lettres de largeurs inégales (capture `carte_1610`). Il faudrait
  `scale_mode = "integer"` ou une police lissée et une meilleure prise en charge des formats ultra-larges et
  16:10.
- Valeurs codées en dur pour 1280x720 et pour la taille du monde : `scripts/campaign_map.gd:249`
  (`1280.0 - MAP_SIZE.x`), `scripts/main_menu.gd:341-342`, `scripts/enemy_ai.gd:99,152`
  (`Vector2(3160, 1960)` au lieu de `WORLD_SIZE`).

### AZERTY et clavier
- Bon dans l'ensemble : caméra par position physique (ZQSD/WASD), chiffres par position physique, touches
  d'action par lettre. Un test couvre le rebind.
- Ctrl+A se teste par lettre (`k.keycode == KEY_A`, `scripts/battle.gd:1150`) : c'est bien la touche « A »
  en AZERTY, ce qui est cohérent.
- La caméra, Espace, Entrée et Échap ne sont pas reconfigurables. Il n'y a pas de raccourci plein écran
  (Alt+Entrée ou F11) ni de manette.

### Sauvegarde
- L'écriture est atomique et la lecture validée, ce qui est très bien. Il n'y a **qu'un seul
  emplacement**, aucune copie de secours (`.bak`) si le fichier est corrompu (le jeu repart alors sur une
  nouvelle campagne avec un simple avertissement, `scripts/campaign_map.gd:53-55`), et pas de sauvegarde en
  cours de bataille.

### Performances
- Les effectifs restent modestes (16 à 20 hommes par régiment, environ 250 soldats au total) : aucun
  problème mesurable.
- Si l'on veut des batailles plus grandes : `_draw()` redessine tout le monde à chaque image, sans tri
  limité à l'écran (soldats, arbres et maisons triés à chaque image, jusqu'à 2000 cadavres dessinés un par
  un), et `soldiers_near()` crée un tableau à chaque appel (une fois par soldat et par pas pour
  `separate`). Pour doubler les effectifs, il faudra du culling, une MultiMesh ou un dessin par couches.

### Structure du code
- `battle.gd` fait 1958 lignes : terrain, simulation, ordres, caméra et rendu y sont mêlés. `hud.gd` et
  `enemy_ai.gd` reçoivent la bataille sans type (`var battle`, `think(b, …)`), et le HUD compare l'état à
  des entiers (`match battle.state: 0, 2, 3`, `scripts/hud.gd:143`).
- C'est propre et commenté en français, mais ajouter du contenu (nouvelles unités, nouveaux objectifs)
  touchera toujours ce même fichier.

### Textes
Tout est en français, et je n'ai trouvé aucune chaîne en anglais visible par le joueur. Les avertissements
de code (`push_warning`) sont eux aussi en français.

---

## 3. Ce qui manque

Effort : **petit** (moins d'une demi-journée), **moyen** (1 à 3 jours), **gros** (plus d'une semaine).

### 3.1 Nécessaire : bloquant pour un jeu jouable de bout en bout
| # | Manque | Effort | Fichiers |
|---|---|---|---|
| N1 | **Objectif et fin de campagne** : condition de victoire (par exemple une renommée ou un trésor à atteindre, ou un contrat final « l'ost du roi », ou une faction à faire triompher), **écran de fin** avec bilan, et **game over** explicite quand la compagnie est détruite et ruinée. | moyen | `campaign_state.gd`, `campaign_map.gd`, nouvelle scène de fin, `campaign_test.gd` |
| N2 | **Menu pause en bataille** (Échap) : reprendre, options, aide, abandonner (= retraite en contrat), menu principal. | petit | `battle.gd`, `hud.gd` (ou nouvelle scène), `menu_test.gd` |
| N3 | **Corriger le déploiement** (B1) : ordres limités à la zone bleue, aucun combat avant Espace. | petit | `battle.gd`, `smoke_test.gd` |
| N4 | **Difficulté réglable** (facile / normal / difficile : effectifs ennemis, moral, agressivité de l'IA, prix et solde), choisie au début de la campagne et dans les options pour l'escarmouche. | moyen | `game_options.gd`, `campaign_state.gd`, `enemy_ai.gd`, `unit_types.gd`, `main_menu.gd` |
| N5 | **Courbe de progression au-delà de 5 victoires** (B7) : niveaux 4-5 (armées plus grandes, plus de vétérans, deux armées), primes croissantes. Sans cela, la campagne stagne. | moyen | `campaign_state.gd` (`CONTRACT_KINDS`, `make_contract`) |
| N6 | **Bilan de fin de bataille lisible** : pertes et xp par régiment, promotions, or. Aujourd'hui, une ligne de texte centrée qui peut déborder. | petit | `hud.gd`, `battle.gd` |

### 3.2 Important : rend le jeu agréable et rejouable
| # | Manque | Effort | Fichiers |
|---|---|---|---|
| I1 | **Plus de contenu d'unités** : arbalétriers, chevaliers à pied, cavalerie légère (archers montés), peut-être piquiers suisses et vétérans d'élite par faction. | moyen | `unit_types.gd`, `sprite_bank.gd`, assets + CREDITS, `campaign_state.gd` |
| I2 | **Variété des contrats** : objectifs autres que « détruire » (tenir une position X minutes, escorter un convoi, prendre un village, poursuivre), armées ennemies tirées par faction, textes variés. | gros | `battle.gd`, `campaign_state.gd`, `enemy_ai.gd`, `terrain.gd` |
| I3 | **IA qui utilise le terrain et qui se défend** : occuper les collines, contourner par les gués, attendre en défense, se retirer quand elle perd. | moyen | `enemy_ai.gd`, `ai_test.gd`, `balance.gd` |
| I4 | **Audio hors bataille et retour sonore** : musique de menu et de carte, sons d'interface, cor de charge et de retraite, fanfare victoire/défaite, ambiance, son de pluie ; utiliser ou supprimer `swish`. | moyen | `battle_audio.gd`, `main_menu.gd`, `campaign_map.gd`, assets + CREDITS |
| I5 | **Lisibilité en bataille** : fond derrière les messages, aide repliée par défaut (ou mémorisée), info-bulle au survol de tout régiment (type, effectif, moral, rang), numéros de régiment fixes (B4), police pixel dédiée et plus grande. | moyen | `hud.gd`, `battle.gd`, `ui_theme.gd` |
| I6 | **Affichage multi-résolution** : `scale_mode` entier ou police lissée, gestion du 16:10 et de l'ultra-large, plus de tailles codées en dur, Alt+Entrée / F11. | petit | `project.godot`, `campaign_map.gd`, `main_menu.gd`, `enemy_ai.gd` |
| I7 | **Sauvegarde** : 3 emplacements, copie de secours `.bak`, sauvegarde du contrat en cours (B3) pour supprimer l'exploit embuscade et la relance infinie (ou l'assumer en option « mode indulgent »). | moyen | `campaign_state.gd`, `campaign_map.gd`, `main_menu.gd`, `campaign_test.gd` |
| I8 | **Monde de campagne vivant** : armées de factions qui se déplacent, guerres entre factions qui changent les contrats, météo et saisons (pluie imposée en bataille). | gros | `campaign_state.gd`, `campaign_map.gd` |
| I9 | **Accessibilité** : taille de l'interface, alternative aux couleurs rouge/bleu (motifs, formes), sous-titres des évènements sonores, toutes les touches reconfigurables (caméra comprise). | moyen | `game_options.gd`, `main_menu.gd`, `hud.gd`, `battle.gd` |
| I10 | **Équilibrage de l'escarmouche** : le joueur simulé « tactique » ne gagne que 2/10 en plaine et 3/10 en rivière (README) ; viser 50 à 60 % pour un joueur moyen en mode normal (dépend de N4). | petit | `unit_types.gd`, `enemy_ai.gd`, `balance.gd` |

### 3.3 Bonus : souhaitable
| # | Manque | Effort | Fichiers |
|---|---|---|---|
| X1 | Vrais sièges (échelles, porte, assaut ou défense d'une ville), déjà listé au README. | gros | `terrain.gd`, `battle.gd`, `enemy_ai.gd` |
| X2 | Capitaine ou héros sur le champ (aura de moral, mort = défaite), traits de régiment, équipement achetable. | moyen | `regiment.gd`, `campaign_state.gd`, `hud.gd` |
| X3 | Mini-carte en bataille, ralenti ou caméra de suivi, replay de la bataille. | moyen | `hud.gd`, `battle.gd` |
| X4 | Mode « bataille personnalisée » (choix des armées, du terrain et de la météo). | petit | `main_menu.gd`, `battle.gd` |
| X5 | Effets visuels supplémentaires (sang ou poussière d'impact, traînées de flèches, fumée au village, animation de pluie au sol). | petit | `battle.gd` |
| X6 | Manette (navigation des menus déjà prête : focus clavier). | moyen | `battle.gd`, `game_options.gd` |
| X7 | Statistiques et succès (batailles gagnées, ennemis tués, régiment le plus ancien). | petit | `campaign_state.gd`, `main_menu.gd` |

### 3.4 Technique
| # | Manque | Priorité | Effort | Fichiers |
|---|---|---|---|---|
| T1 | Tests de non-régression pour B1 (aucun combat en DEPLOY), N1 (fin de campagne) et N2 (pause). | nécessaire (avec chaque correctif) | petit | `tests/*` |
| T2 | Découper `battle.gd` : simulation (sans rendu), rendu, ordres et caméra, pour faciliter l'ajout d'unités et d'objectifs ; typer `battle` dans `hud.gd` et `enemy_ai.gd`, utiliser l'enum `State` dans le HUD. | important | moyen | `battle.gd`, `hud.gd`, `enemy_ai.gd` |
| T3 | Script unique qui lance tous les tests headless (et éventuellement une GitHub Action). | important | petit | `tools/` |
| T4 | Numéro de version (menu et nom du zip) ; script d'export qui zippe `build/` ; exports Linux et macOS facultatifs. | important | petit | `project.godot`, `main_menu.gd`, `tools/export_windows.ps1`, `export_presets.cfg` |
| T5 | Mesure de performance (images par seconde sur une bataille à 2x les effectifs), puis culling ou MultiMesh si nécessaire. | bonus | moyen | `battle.gd`, `tests/` |
| T6 | `menu_capture.gd` et `terrain_shots.gd` écrivent dans `captures/` (versionné) : prévoir une option de dossier de sortie pour ne pas salir le dépôt. | bonus | petit | `tests/menu_capture.gd`, `tests/terrain_shots.gd` |

---

## 4. Méthode
- J'ai lu tous les scripts de `scripts/`, les scènes, le README, les CREDITS, `project.godot`, le
  préréglage et le script d'export, ainsi que les notes de passation des sessions précédentes.
- J'ai lancé, en headless avec Godot 4.7.2, `smoke_test.gd` sur les 6 terrains, `campaign_test.gd`,
  `menu_test.gd` et `ai_test.gd` : tous ont fini avec le code 0.
- J'ai fait des captures fenêtrées en 1280x720 et 1680x1050 (menu, carte, déploiement, mêlée) avec un
  script temporaire hors du dépôt, et une sauvegarde et des options pointant hors du dossier du joueur.
- J'ai écrit des sondes temporaires (hors dépôt) : (1) un joueur passif en escarmouche sur 5 graines
  perd en 100 à 260 s, donc toutes les batailles se terminent ; (2) un combat pendant le déploiement est
  possible (B1).
