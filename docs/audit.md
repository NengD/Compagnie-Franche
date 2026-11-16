# Compagnie Franche — audit complet (16 novembre 2026)

Version 0.5.0, branche `main` (commit `ce348af`), Godot 4.7.2. Audit fait en lisant le code (15 055 lignes
de GDScript dans `scripts/`, 7 383 dans `tests/`), en lançant les tests, le banc d'équilibrage et le test de
performance, et en regardant des captures prises avec fenêtre (dans `user://`, hors du dépôt).
Il fait suite à `docs/analyse.md` (15 novembre), dont presque tous les points ont été traités depuis.

---

## 1. Résumé

**État du jeu.** Le prototype est devenu un jeu complet sur le papier. On a un menu, des options riches, un
tutoriel, l'escarmouche et une campagne avec un but, une fin (victoire ou ruine) et 3 emplacements de
sauvegarde. La bataille est profonde : 7 unités, moral, flancs, charges, endurance, formations, 6 terrains,
2 vrais sièges, 5 objectifs de contrat, un capitaine et la météo. L'IA choisit un plan selon le terrain.
Autour, un monde vivant : saisons, guerres, armées qui assiègent et prennent des villes. Le code est propre et
découpé, presque sans code mort. Les **21 suites de tests passent** (388 s).

**Points forts.**
- La simulation tactique est riche et cohérente, et l'IA est crédible.
- Tout est rejouable à l'identique depuis une graine, et la couverture de tests est large.
- L'accessibilité est soignée : formes des camps, sous-titres, taille de l'interface, touches reconfigurables
  en AZERTY ou QWERTY.
- La sauvegarde est robuste : écriture atomique, copie `.bak`, versions 1 à 8 relues, bataille en cours
  reprise au lancement.

**Faiblesse principale.** Dix-sept sessions ont écrit les systèmes en parallèle, et **ils se croisent mal**.
Le monde vivant ignore les sièges et les objectifs. Les contrats lisent encore la faction de départ des villes,
alors que les villes changent de mains environ tous les 7 jours. Le contrat final peut se retrouver dans une
capitale tenue par l'ennemi. Et **personne n'a encore joué une campagne à la main** : l'équilibrage de la
campagne (économie, bataille décisive à 11 régiments contre 8 au plus) n'est mesuré nulle part.

**Trois priorités.**
1. **Recoudre les systèmes** : faction actuelle des villes dans les contrats, contrat final, effets des sièges
   sur le monde, pluie forcée par T en campagne (section 3.1). Corriger aussi l'IA de la palissade, qu'un
   joueur passif bat 10 fois sur 10.
2. **Jouer et mesurer la campagne** : une partie complète à la main, plus un banc de campagne automatique
   (économie, renommée, bataille décisive).
3. **Lisibilité et ressenti** : distinguer les nouvelles unités, montrer le terrain et l'objectif réel des
   contrats, corriger les chevauchements de la carte, et alléger le rendu (performances à 500 soldats).

---

## 2. Inventaire des fonctionnalités (vérifié dans le code)

Maturité : **solide** (complet, testé, cohérent), **correct** (marche, avec des manques ou des bords
rugueux), **ébauche** (minimal ou mal intégré).

### 2.1 Menu, options et accessibilité — solide
- **Fichiers :** `scripts/main_menu.gd`, `scripts/game_options.gd`, `scripts/ui_theme.gd`,
  `scripts/display_keys.gd` (autoload), `scenes/menu.tscn`.
- **Fonctionnement :** le menu propose Continuer, Nouvelle campagne (difficulté et mode indulgent),
  3 emplacements, Tutoriel, Escarmouche, Options, Statistiques et Quitter. Le fond pixel art est animé
  (colonne des 7 unités) et le numéro de version s'affiche.
- **Options** (`user://options.cfg`) : 3 volumes, plein écran (Alt+Entrée ou F11 partout), taille de
  l'interface (90 à 150 %), effets visuels (complets, réduits, aucun), vitesse, difficulté de l'escarmouche.
  On peut rebrancher les touches de bataille et de caméra : deux actions échangent leurs touches en cas de
  conflit, certaines touches sont réservées, et les touches sont gardées par lettre (AZERTY correct).
- **Accessibilité :** formes des camps (rond ou losange, part ennemie rayée), sous-titres des évènements
  sonores, aide F1 repliée (état mémorisé).
- L'affichage s'adapte à toute résolution (`canvas_items` + `expand`, panneaux réduits par
  `UiTheme.fit_panel`).

### 2.2 Tutoriel — correct
- **Fichier :** `scripts/tutorial.gd` (hérite de `battle.gd`), `scenes/tutorial.tscn`.
- **Fonctionnement :** une bataille de 4 régiments contre 3, en 8 étapes. Chaque étape se valide par la vraie
  action : sélectionner, déplacer, ligne de front, formation, courir, lancer, cavalerie sur les archers,
  gagner. Le menu pause marche.
- **Manques :** rien sur la carte de campagne, le capitaine, tenir (G), le tir retenu (X), la retraite ou
  les 3 nouvelles unités. Le panneau recouvre l'onglet « F1 : aide » (capture `tutoriel.png`).

### 2.3 Bataille — solide
| Domaine | Fichiers | Ce qui existe | Maturité |
|---|---|---|---|
| Architecture | `battle.gd` (572 lignes), `battle_sim.gd`, `battle_renderer.gd`, `battle_orders.gd`, `battle_camera.gd` | `battle.gd` orchestre ; `BattleSim` simule sans rendu et prévient le reste par des signaux | solide |
| Unités | `unit_types.gd`, `regiment.gd`, `soldier.gd`, `sprite_bank.gd` | 7 types (piquiers, hommes d'armes, chevaliers à pied, archers, arbalétriers, cavaliers, archers montés) avec capacités (`braces`, `pierce`, `pavise`, `steadfast`, `skirmish`) ; simulation soldat par soldat sur grille | solide |
| Formations | `regiment.gd`, `battle_orders.gd` | ligne, colonne (+15 %), carré creux (sans flancs, x0,55) | solide |
| Ordres | `battle_orders.gd` | sélection au cadre, ligne de front glissée avec aperçu, course (double clic), groupes Ctrl+1-8, halte, tenir, tir retenu, retraite (R deux fois), numéros fixes 1-8 | solide |
| Moral | `battle_sim.gd` | pertes, flancs x1,4 et dos x2, charges, panique des voisins, une chance de ralliement (plus avec le capitaine) | solide |
| Endurance | `battle_sim.gd` | course, mêlée, récupération ; vitesse et dégâts réduits sous 60 % | solide |
| Terrain | `terrain.gd`, `siege_terrain.gd` | rase campagne, bois (embuscades), collines (hauteur, portée), rivière et gués, village, palissade ; ville fortifiée pour les sièges | solide |
| Météo | `battle_sim.gd`, `battle_orders.gd:124` | pluie seulement (portée, précision, vitesse) ; imposée par la campagne mais modifiable par T (voir B1) | correct |
| Effets | `battle_effects.gd` | sang, étincelles, éclat de charge, traînées, fumée, gerbes d'eau, flaques, étendards ; 3 niveaux ; rien ne trahit une embuscade | solide |
| Caméra | `battle_camera.gd` | touches, flèches, clic molette, zoom à échelle entière (pixels nets), bornes, secousse | solide |
| HUD | `hud.gd` | barre du haut, cartes de régiment, messages sur fond, info-bulle ami ou ennemi, panneau d'objectif, état du siège, aide F1 | solide |
| Pause et déploiement | `pause_menu.gd`, `battle.gd` | Échap : reprendre, aide, options, abandonner, menu ; aucun combat ni sortie de zone pendant le déploiement | solide |
| Bilan | `battle_report.gd`, `battle.gd:318` | ralenti puis panneau : une ligne par régiment, promotions, pertes des deux camps, or, réputation, renommée, objectif | solide |
| Audio de bataille | `battle_audio.gd` | épées, chocs, arcs, sifflements, cris, galop, cors, fanfare, vent, oiseaux, pluie ; spatialisé, 20 voix | correct (aucun son propre au siège ni à l'arbalète) |

### 2.4 Capitaine, traits et équipement — correct
- **Fichiers :** `scripts/captain.gd`, `scripts/traits.gd`, `scripts/equipment.gd`, `scripts/company_panel.gd`.
- **Capitaine :** il a un nom et gagne de l'xp, puis des niveaux, qui donnent 3 compétences (aura, ralliement,
  solde réduite). Sur le champ, il escorte un régiment ; son aura rend du moral. S'il tombe, chaque régiment
  perd 40 de moral, et il reste blessé 5 jours. Il n'est pas présent au tutoriel.
- **Traits :** 5 traits (tenaces, rapides, adroits, pillards, frugaux), un à chaque promotion, dans un ordre
  propre au type. Le hameau pillé donne aussi « pillards ».
- **Équipement :** armure (-30 % de dégâts des flèches) et meilleures armes (+15 %), achetés en ville.
- **Limites :** les 3 nouvelles unités suivent l'ordre de traits par défaut (`traits.gd:17-22`). Le
  capitaine n'a aucun portrait, aucun évènement, aucune conséquence narrative.

### 2.5 IA — solide
- **Fichier :** `scripts/enemy_ai.gd` (1 009 lignes).
- **Fonctionnement :** au début de la bataille, l'IA choisit un plan d'après le rapport de forces et le
  terrain : agressif, défensif (sommet, lisière, rive, palissade) ou débordement (embuscade en forêt).
  Elle choisit ses gués, contre-attaque, et se retire en bon ordre sous 40 % de sa force. Elle a des
  comportements propres aux tireurs, aux archers montés et à la cavalerie, et suit les consignes des
  objectifs (`ai_plan`, `ai_point`, `ai_anchor`) et des sièges (`think_siege`). La difficulté règle son
  temps de réflexion, sa patience et l'emploi du carré.

### 2.6 Objectifs de contrat — correct
- **Fichiers :** `scripts/battle_objectives.gd`, `campaign_state.gd` (`OBJECTIVES`, `roll_objective`,
  `objective_bonus`).
- **Fonctionnement :** 5 objectifs. Détruire ; tenir une position 3 à 5 min ; escorter 4 chariots (prime
  par chariot sauvé) ; prendre un village avant la nuit ; poursuivre une bande chargée de butin. Chacun a
  sa zone au sol, son panneau dans le HUD, ses consignes à l'IA et sa ligne au bilan. Si le terrain de la
  ville ne convient pas à l'objectif, le terrain change.
- **Limites :** les objectifs n'existent qu'en campagne (pas d'escarmouche à objectif). Les sièges et les
  rencontres d'armées n'en ont pas, et leur ligne « Objectif » sur la carte est fausse (B5).

### 2.7 Sièges — correct
- **Fichiers :** `scripts/siege.gd`, `scripts/siege_terrain.gd` ; la palissade est dans `terrain.gd`.
- **Fonctionnement :** l'assaut ou la défense d'une ville fortifiée se joue avec rempart, porte, 6 tours,
  chemin de ronde et place. L'assaillant a un bélier et 3 échelles qu'il faut dresser ; les défenseurs
  peuvent repousser une échelle. La ville tombe si l'assaillant tient la place 20 s, et elle est sauvée si
  elle tient 5 min. L'IA sait faire les deux rôles. En campagne, environ 12 % des contrats de niveau 2 et
  plus sont des sièges (prime x1,6), et une ville assiégée sur la carte propose une défense.
- **Limites :**
  - Deux systèmes de « siège » coexistent : la palissade (terrain `siege`, imposé par `Terrain.for_contract`)
    et les vrais sièges.
  - Le résultat d'un siège n'a aucun effet sur le monde (B3).

### 2.8 Campagne — correct
| Domaine | Fichiers | Ce qui existe | Maturité |
|---|---|---|---|
| Carte | `campaign_map.gd`, `world_view.gd` | 7 villes, 10 routes, durée des trajets, panneau à droite (compagnie, pays, ville, recrutement, contrats, réputation, journal), encart d'objectif, armées, sièges, neige et pluie | correct (chevauchements, panneau très long) |
| Villes et factions | `campaign_state.gd:31-71` | 3 factions et 3 capitales, prix et recrues par ville, réputation de -100 à +100, portes fermées à -30 | correct |
| Contrats | `campaign_state.gd:906-1003` | 5 niveaux d'après la renommée, armées colorées par faction, objectifs, sièges, contrats de guerre, expiration à 14 jours | correct |
| Monde vivant | `world_sim.gd`, `world_army.gd` | guerres et trêves, armées qui patrouillent, assiègent, se battent et prennent des villes ; rencontres hostiles (combattre ou fuir) ; camper | correct (mal relié aux contrats, voir 3.1) |
| Saisons et météo | `world_sim.gd` | 4 saisons de 30 jours, hiver plus lent et froid meurtrier, pluie selon la saison, reprise en bataille | correct (rien de l'hiver en bataille) |
| Économie | `campaign_state.gd` | solde par homme, désertion sans solde, prime, butin, pillage, prix des villes, difficulté | correct (non mesurée) |
| Recrutement | `campaign_map.gd`, `campaign_state.gd` | lever un régiment (8 au plus) ou compléter un régiment entamé (l'xp se dilue) | solide |
| Vétérans | `campaign_state.gd` | xp, 3 rangs (+10 % de dégâts et +15 % de moral par rang), traits, statistiques par régiment | solide |
| Évènements de route | `campaign_state.gd:784` | embuscade, marchand, épidémie, déserteurs, intempéries, hameau | correct (sans choix) |
| Fin de campagne | `end_screen.gd`, `campaign_state.gd` | à 150 de renommée, bataille décisive dans la capitale de la faction la plus amie ; victoire, ou ruine si plus d'hommes ni d'argent | correct (voir B2) |

### 2.9 Sauvegarde — solide
- **Fichier :** `campaign_state.gd` (section Sauvegarde, `SAVE_VERSION := 8` à la ligne 211).
- **Fonctionnement :** 3 emplacements JSON. L'écriture passe par un `.tmp`, puis l'ancienne version devient
  la copie `.bak`, relue si le fichier est abîmé. Toutes les versions de 1 à 8 se relisent, et chaque champ
  est validé. La bataille en cours est sauvegardée et reprise au lancement, sauf en mode indulgent.
  L'ancien `campagne.json` est repris automatiquement.

### 2.10 Audio — correct
- **Fichiers :** `game_audio.gd`, `battle_audio.gd`.
- **Fonctionnement :** une musique par contexte (menu, carte, bataille, victoire, défaite) avec fondu
  enchaîné. Clic et survol sont branchés sur tous les boutons. On entend aussi la recrue, l'or et les refus.
- **Limites :** une seule piste par contexte, qui se répète vite. Rien pour le bélier, les échelles,
  l'arbalète ou les chariots. Aucune ambiance propre à la carte (saison, guerre).

### 2.11 Statistiques et succès — correct
- **Fichiers :** `stats.gd` (`user://statistiques.json`), `achievements.gd`.
- **Fonctionnement :** des compteurs suivent toutes les parties, plus des records (plus longue campagne,
  régiment le plus ancien ou le plus décoré). 23 succès s'annoncent par une notification, et une page leur
  est consacrée dans le menu.
- **Limites :** aucun succès pour les objectifs (escorte, poursuite...), le monde vivant (disperser une
  armée, survivre à l'hiver), le capitaine ou les nouvelles unités.

### 2.12 Difficulté — solide
- **Fichier :** `difficulty.gd`, seule source des valeurs.
- **Fonctionnement :** facile, normal ou difficile. La difficulté agit sur les effectifs, le moral et les
  dégâts ennemis, sur l'IA (réflexion, patience, carré), et sur l'économie (recrues, solde, primes). Elle est
  gardée dans la sauvegarde. Le monde vivant ne suit pas la difficulté : taille des armées, fréquence des
  guerres.

### 2.13 Export — ébauche
- **Fichiers :** `tools/export_windows.ps1`, `export_presets.cfg` (préréglages Windows et Linux),
  `tools/make_icon.py`.
- **Fonctionnement :** le script produit un `.exe` avec son `.pck` intégré, un zip versionné, et le build
  Linux si le modèle d'export est installé.
- **Limites :** le seul build présent (`build/CompagnieFranche.exe`, 15 novembre 13 h 57) est antérieur à la
  plupart des fonctionnalités, et aucun zip 0.5.0 n'existe. Rien n'a été testé hors de l'éditeur.

### 2.14 Tests et outils — solide
- **Fichiers :**
  - `tools/run_tests.ps1` et `run_tests.sh` : import, test de fumée sur 6 terrains, puis tous les
    `*_test.gd` ;
  - 16 suites de tests ;
  - des outils : `balance.gd` (banc), `perf_test.gd`, `test_player.gd` (joueur simulé) et 9 scripts de
    capture ;
  - `.github/workflows/tests.yml`.
- **Limites :**
  - Le dépôt n'a **pas de remote** (`git remote -v` est vide), donc l'intégration continue ne tourne jamais.
  - Le banc d'équilibrage ne joue que des escarmouches.
  - Les tests partagent `user://` et peuvent se gêner s'ils tournent en parallèle (une erreur intermittente
    de `campaign_test` est notée par une session).

---

## 3. Problèmes constatés

Gravité : **haute** (casse une partie ou un objectif), **moyenne** (exploit, incohérence visible),
**basse** (finition).

### 3.1 Intégrations incomplètes entre systèmes
| # | Gravité | Où | Problème |
|---|---|---|---|
| B1 | **moyenne** | `scripts/battle_orders.gd:124-126`, `scripts/hud.gd:341` | **La touche T change la météo même en campagne.** `battle.gd:110` impose la pluie du jour, mais T l'inverse librement, et la barre du haut affiche « Pluie [T] ». C'est un exploit facile contre les archers ennemis, et cela trahit le monde vivant. Correctif : ignorer T si `battle.campaign != null` (ou réserver T à l'escarmouche) et retirer « [T] » de la barre. |
| B2 | **haute** | `scripts/campaign_state.gd:1286` (`make_final`), `:1269-1274` (`offer_final`), `scripts/world_sim.gd:525` | **La bataille décisive peut se trouver dans une capitale ennemie.** Le contrat final se signe toujours dans `FACTIONS[f]["capital"]`, sans regarder qui la tient, et une prise de ville le conserve. Or le monde prend des villes très souvent (30 prises en 200 jours dans `world_test`, capitales comprises). Si la capitale tombe aux mains d'une faction qui a fermé ses portes au joueur, `accept()` refuse le contrat, qui n'expire pas : **la campagne ne peut plus être gagnée**. Correctif : choisir une ville tenue par le patron, déplacer le contrat quand sa ville change de mains, et ne pas convoquer un patron qui n'a plus de ville. |
| B3 | moyenne | `scripts/world_sim.gd:686-704` (`after_battle`), `scripts/campaign_state.gd:921-924` | **Les sièges n'ont aucun effet sur le monde.** Défendre une ville assiégée sur la carte et gagner ne lève pas le siège : la ville peut tomber le lendemain. Prendre une ville d'assaut ne la donne à personne. `after_battle` ne traite que `world_army`. Correctif : en défense gagnée, mettre `world.siege_at(t).men` à une fraction et faire partir l'armée ; en assaut gagné, appeler `world.capture` pour le patron. |
| B4 | moyenne | `scripts/campaign_state.gd:1104` (`roll_enemy_faction`), `:992`, `:1039` (`make_siege`) | **Les contrats lisent la faction de départ** (`town_faction`, statique) au lieu de `town_owner`. Une ville prise par la Baronnie peut donc proposer un contrat contre... la Baronnie, avec une armée Baronnie (archers montés) et `enemy_faction` égal au patron. `adjust_contract` ne corrige que les noms dans les textes, pas l'armée ni `enemy_faction`. Les titres de siège nomment la rivale de départ, pas la faction qui assiège vraiment. Correctif : passer `town_owner` partout et tirer l'ennemi parmi `world.enemies_of(owner)`. |
| B5 | basse | `scripts/campaign_state.gd:1205-1217`, `:1044` | Sur la carte, **un contrat de siège affiche « Objectif : détruire l'armée ennemie »**, alors qu'il faut tenir la place 20 s ou tenir les murs 5 min. `objective_line` ignore la clé `siege`. |
| B6 | basse | `scripts/world_sim.gd:679`, `scripts/terrain.gd:78` | Une **rencontre d'armée sur la route** (difficulté 3 ou plus) vers Hautemure ou Castelroux devient une **défense de palissade**, car `for_contract` impose la palissade dans ces villes. Une rencontre en chemin devrait se jouer en rase campagne, en bois ou sur des collines. |
| B7 | basse | `scripts/terrain.gd:37,78`, `scripts/achievements.gd:51` | Les deux systèmes de siège se recouvrent. « siege » désigne la palissade dans `Terrain.KINDS` mais un vrai siège dans `Siege`. Hautemure et Castelroux sont des « défenses de palissade » dès le niveau 3, même pour un contrat « Querelle de frontière ». Il faut choisir une règle (la palissade comme fort de campagne, les villes comme vrais sièges) et renommer. |
| B8 | basse | `scripts/campaign_state.gd:64-70` | Les recrues d'une ville ne changent pas avec son maître : la Baronnie qui tient Brévannes y lève des arbalétriers de la Ligue. C'est défendable, mais cela n'est dit nulle part. |
| B9 | basse | `scripts/battle_sim.gd:153-171` | **L'escarmouche n'utilise que les 4 unités d'origine** : on ne peut voir chevaliers à pied, arbalétriers et archers montés qu'en campagne (à partir du niveau 2, 4 ou 5). Le tutoriel ne les présente pas non plus. |
| B10 | basse | `scripts/traits.gd:17-22` | `PROMOTION_ORDER` ne connaît pas les 3 nouvelles unités. Elles reçoivent « tenaces, adroits, rapides », donc un chevalier à pied devient « rapide ». |

### 3.2 Interface et textes (vus sur les captures 1280×720)
| # | Gravité | Où | Problème |
|---|---|---|---|
| U1 | moyenne | `scripts/world_view.gd:164-165` contre `scripts/campaign_map.gd:674-675` | **Sur la carte, l'effectif des armées en garnison chevauche le nom des villes** (« Hautemu17 », « Valomb32 », « Brévann79 » sur `1280x720_ui100_carte.png`). |
| U2 | moyenne | `scripts/sprite_bank.gd:41-58` | Les **nouvelles unités se distinguent mal** : l'arbalétrier reprend le sprite de l'archer, le chevalier à pied celui de l'homme d'armes, l'archer monté celui du cavalier, avec une simple teinte. À zoom 1, on ne voit la différence qu'au pictogramme de l'étendard. |
| U3 | moyenne | `scripts/campaign_map.gd:475-489` | Un contrat n'indique **ni le terrain** (rivière, palissade, siège...) ni le nombre de régiments. Le panneau de droite est long et il faut défiler pour voir contrats, réputation et journal. |
| U4 | basse | `scripts/tutorial.gd:190-209` | Le panneau du tutoriel recouvre l'onglet « F1 : aide » et coupe la consigne centrale (« appuyez sur Esp… »). |
| U5 | basse | `scripts/hud.gd` (cartes) | « Hommes d'ar… » est tronqué sur les cartes de régiment, et les messages longs (terrain, objectif) aussi, avec « … ». L'information est perdue au bout de 5 s. |
| U6 | basse | `scripts/pause_menu.gd` | Le menu pause ne grise pas le champ, et « DÉPLOIEMENT » reste visible au travers (déjà noté par la session affichage). |
| U7 | basse | `scripts/campaign_state.gd` (`finish_battle`) | Le bilan affiche « La Baronnie -4 » pour une perte de -5 : la décrue quotidienne de la rancune (+1) est appliquée par `pass_day()` avant la mesure. C'est exact, mais déroutant. |

### 3.3 Équilibrage
- **Escarmouche :** voir 5.2. Le joueur tactique gagne 43 % sur l'ensemble des terrains en normal, et le
  bois reste le plus dur pour lui (2/10).
- **La palissade est cassée à l'envers.** Un joueur naïf qui attend derrière les pieux gagne 10/10, car l'IA
  agressive s'empale aux brèches (`enemy_ai.gd`, `choose_plan` force AGGRESSIVE en siège). C'est un exploit
  sur Hautemure et Castelroux dès le niveau 3. Gravité moyenne.
- **La campagne n'est pas mesurée.**
  - Le joueur a 8 régiments au plus (`MAX_REGIMENTS`) contre 10 au niveau 5 et 11 dans la bataille décisive,
    presque tous vétérans (`campaign_state.gd:104-118`). En difficile, le joueur tactique gagne 3/10
    escarmouches à forces égales : la bataille décisive risque d'être hors de portée.
  - Les armées de faction ennemies grossissent avec la guerre, mais pas avec la difficulté.
- **Le monde bouge trop vite** : 30 villes prises en 200 jours, avec 7 villes. Chaque prise annule les
  contrats de la ville (`world_sim.gd:524-527`), et la carte des factions devient illisible. Il faudrait
  ralentir les sièges (`SIEGE_HIT`) ou espacer les guerres.

### 3.4 Performances
- Le rendu dessine soldat par soldat en GDScript, **sans tri hors champ**. `battle_renderer.gd` n'a ni
  culling ni MultiMesh. À 516 soldats, une image de mêlée coûte environ 23 ms (44 i/s) : voir 5.3.
- En vitesse x2, on fait deux étapes de simulation par image : il faut s'attendre à 30 i/s ou moins dans
  les grosses batailles (bataille décisive : 11 régiments ennemis et 8 joueurs).
- `soldiers_near()` crée un `Array` à chaque appel (`battle_sim.gd:338`), une fois par soldat et par étape
  dans `separate()`.

### 3.5 Code mort et dette technique
- **Code mort (presque rien) :** `Siege.is_siege_kind` (`siege.gd:73`), `Terrain.blocked_at`
  (`terrain.gd:471`) et `Battle.clamp_camera` (servi seulement par les tests). La banque `swish` est
  désormais jouée.
- **Façade de `battle.gd:419-572`.** Environ 150 lignes de propriétés et de fonctions « Raccourcis »
  renvoient vers `sim`, `orders` et `camera`. Elles gardent l'ancienne interface pour le HUD, le tutoriel et
  les tests, mais doublent chaque nom. Il faut migrer les appelants, puis les supprimer.
- **`campaign_state.gd` (1 494 lignes) fait tout :** économie, contrats, objectifs, sièges, fin,
  sauvegarde, évènements. Les contrats (environ 400 lignes) méritent leur fichier `contracts.gd`.
- **Deux sources pour la faction d'une ville :** `town_faction` (statique, celle de départ) et `town_owner`.
  B2 et B4 viennent de là. Il faudrait renommer `town_faction` en `initial_faction` pour rendre l'erreur
  visible.
- **Données de contrat en `Dictionary` libres**, sur une vingtaine de clés optionnelles (`final`, `ambush`,
  `world_army`, `siege`, `objective`...). Chaque session en a ajouté une, et les combinaisons ne sont pas
  vérifiées. Une petite classe `Contract` avec `kind()` éviterait B5 et B6.
- **Hygiène du dépôt :**
  - `.gitignore` ignore `captures` alors que `captures/*.png` est versionné ;
  - plusieurs lignes du `.gitignore` (`logs`, `perf`, `vulkan`, `shader_cache`) visent des dossiers de
    `user://` qui n'existent pas dans le dépôt ;
  - `build/` contient un exe périmé de 110 Mo.

---

## 4. Améliorations proposées

Taille : **petit** (moins d'une demi-journée), **moyen** (1 à 2 jours), **gros** (plusieurs jours).

### 4.1 Nécessaire (avant de faire jouer quelqu'un)
| # | Amélioration | Taille | Fichiers |
|---|---|---|---|
| N1 | Contrat final toujours dans une ville du patron ; le déplacer ou l'annuler proprement si la ville tombe (B2) | petit | `campaign_state.gd` (`offer_final`, `make_final`), `world_sim.gd` (`capture`) |
| N2 | Faction actuelle partout dans les contrats : ennemi tiré parmi les ennemis du maître, titres de siège avec l'assiégeant réel (B4) | petit | `campaign_state.gd` (`roll_enemy_faction`, `make_contract`, `make_siege`), `world_sim.gd` (`adjust_contract`) |
| N3 | La touche T est réservée à l'escarmouche et au tutoriel, et « [T] » disparaît de la barre en campagne (B1) | petit | `battle_orders.gd`, `hud.gd` |
| N4 | Les sièges agissent sur le monde : la défense gagnée lève le siège, l'assaut gagné prend la ville pour le patron (B3) | moyen | `world_sim.gd` (`after_battle`), `campaign_state.gd` |
| N5 | Une campagne complète jouée à la main, puis un **banc de campagne** automatique : joueur simulé qui recrute, marche et accepte, avec courbes d'or, de renommée et de jours jusqu'à la bataille décisive, par difficulté | moyen | nouveau `tests/campaign_balance.gd`, `tests/test_player.gd` |
| N6 | Rééquilibrer la bataille décisive et le niveau 5 d'après N5 : 9 ou 10 régiments, moins de vétérans en facile et en normal, ou un régiment allié prêté par le patron | petit | `campaign_state.gd` (`FINAL_CONTRACT`, `CONTRACT_KINDS`), `difficulty.gd` |
| N7 | Refaire l'export 0.5.0 et le lancer hors de l'éditeur (Windows, et Linux si possible), avec une sauvegarde neuve et une ancienne | petit | `tools/export_windows.ps1` |
| N8 | Corriger la ligne d'objectif des sièges et le terrain des rencontres (B5, B6) | petit | `campaign_state.gd` (`objective_line`), `terrain.gd` (`for_contract`), `world_sim.gd` (`make_battle`) |
| N9 | IA d'assaut de la palissade plus patiente : faire tirer les archers d'abord, puis donner l'assaut seulement si elle domine, sinon garder une posture défensive. Aujourd'hui, le joueur naïf gagne 10/10 ; vérifier ensuite avec `balance.gd --terrain=siege` | petit | `enemy_ai.gd` (`choose_plan`, assaut de palissade) |

### 4.2 Important (ressenti, lisibilité, solidité)
| # | Amélioration | Taille | Fichiers |
|---|---|---|---|
| I1 | Sprites ou silhouettes propres aux 3 nouvelles unités (arbalète visible, armure de plates, arc à cheval), et un mot de chacune dans l'info-bulle (« pavois », « inébranlables ») | moyen | `assets/sprites/units/`, `sprite_bank.gd`, `battle_renderer.gd`, `hud.gd` |
| I2 | Carte : effectifs des armées à côté de la ville et non dessus, et dans chaque contrat le terrain, l'objectif réel et le nombre de régiments. Panneau en onglets (Compagnie, Ville, Contrats, Pays, Journal) au lieu d'une seule colonne à défiler | moyen | `campaign_map.gd`, `world_view.gd`, `company_panel.gd` |
| I3 | Un monde plus lisible : moins de prises de villes (sièges plus longs, guerres plus rares), et un résumé « ce qui a changé depuis votre dernière visite » | petit | `world_sim.gd` (constantes) |
| I4 | Unifier les sièges : renommer la palissade (`fort` ou `palisade`) et la réserver aux combats de campagne ; Hautemure et Castelroux passent aux vrais sièges | moyen | `terrain.gd`, `siege.gd`, `campaign_state.gd`, `achievements.gd`, tests |
| I5 | Escarmouche personnalisée : choix du terrain, de l'objectif, des armées (7 unités) et de la difficulté. Donne de la rejouabilité hors campagne et un bac à sable pour tester | moyen | `main_menu.gd`, `battle_sim.gd` (`spawn_default_armies`), `battle.gd` |
| I6 | Tutoriel de campagne en quelques bulles (marcher, recruter, accepter, solde, réputation) et une étape « tenir et retraite » au tutoriel de bataille | moyen | `campaign_map.gd`, `tutorial.gd` |
| I7 | Performances du rendu : ignorer les soldats hors de la vue de la caméra, puis passer à un `MultiMeshInstance2D` par type et par camp si besoin ; réutiliser un tampon dans `soldiers_near` | moyen | `battle_renderer.gd`, `battle_sim.gd` |
| I8 | Une classe `Contract` (genre, objectif, siège, armée rencontrée), et les contrats sortis de `campaign_state.gd` dans `contracts.gd` | moyen | `campaign_state.gd`, `world_sim.gd`, `battle.gd`, `battle_objectives.gd` |
| I9 | Supprimer la façade « Raccourcis » de `battle.gd` (appelants vers `battle.sim.*`) | moyen | `battle.gd`, `hud.gd`, `tutorial.gd`, `battle_audio.gd`, tests |
| I10 | Brancher un remote (GitHub ou autre) pour que `tests.yml` tourne. Donner à chaque test son propre dossier de `user://` pour pouvoir les lancer en parallèle | petit | `.github/workflows/tests.yml`, tests |
| I11 | Ordre de traits propre aux nouvelles unités (B10) ; escarmouche avec au moins une unité nouvelle par camp (B9) | petit | `traits.gd`, `battle_sim.gd` |

### 4.3 Bonus (contenu et rejouabilité)
| # | Amélioration | Taille | Fichiers |
|---|---|---|---|
| X1 | L'hiver en bataille : sol enneigé, eau gelée aux gués, endurance qui baisse plus vite ; brouillard d'automne qui réduit la vue | moyen | `terrain.gd`, `battle_renderer.gd`, `battle_sim.gd`, `battle.gd` |
| X2 | Évènements à choix sur la route et en ville (payer ou combattre, recruter des déserteurs douteux, rançon du capitaine) | moyen | `campaign_state.gd`, `campaign_map.gd` |
| X3 | Plus de musiques (2 ou 3 par contexte), des sons pour le bélier, les échelles, l'arbalète et les chariots, et une ambiance de carte selon la saison | petit (si assets libres) | `game_audio.gd`, `battle_audio.gd`, `CREDITS.md` |
| X4 | Succès pour les objectifs, les sièges en défense, l'armée dispersée, l'hiver et le capitaine au niveau max | petit | `achievements.gd` |
| X5 | Capitaine plus vivant : portrait pixel art, 2 ou 3 compétences actives en bataille (cri de ralliement, charge menée), et sa mort possible en mode difficile | moyen | `captain.gd`, `company_panel.gd`, `hud.gd` |
| X6 | Rejouabilité : carte tirée au sort (positions, routes, factions de départ), et choix de l'origine de la compagnie au départ (or, troupes, réputation) | gros | `campaign_state.gd`, `campaign_map.gd`, `world_sim.gd` |
| X7 | Mini-carte en bataille, et ordres en file (Maj + clic droit) | moyen | `hud.gd`, `battle_orders.gd`, `regiment.gd` |
| X8 | Batailles de siège sur la carte du monde : le joueur peut rejoindre une armée de faction qui assiège | gros | `world_sim.gd`, `siege.gd`, `campaign_map.gd` |

---

## 5. Mesures

### 5.1 Tests (`tools\run_tests.ps1`)
**21/21 réussis en 388,6 s.** Le détail :

| Suite | Durée | Suite | Durée |
|---|---|---|---|
| ai | 71,9 s | perf | 19,2 s |
| audio | 0,7 s | save | 2,5 s |
| campaign | 22,1 s | siege | 22,8 s |
| captain | 1,9 s | smoke plain / forest / hills | 19,1 / 19,1 / 23,2 s |
| deploy_pause | 4,5 s | smoke river / village / siege | 22,3 / 29,9 / 24,2 s |
| difficulty | 2,1 s | stats | 1,6 s |
| effects | 69,8 s | world | 2,9 s |
| interface | 1,4 s | menu | 2,9 s |
| objectives | 24,5 s | | |

Les journaux ne montrent aucune erreur de script. Seuls apparaissent les avertissements attendus des tests
de fichiers abîmés (relecture du `.bak`). `world_test`, sur 5 graines et 200 jours, compte **30 villes
prises** et 711 jours de guerre.

### 5.2 Banc d'équilibrage (`tests/balance.gd -- --seeds=10 --terrain=all`, normal)
Victoires sur 10 batailles par terrain et par stratégie du joueur simulé (6 processus en parallèle,
environ 7 min chacun) :

| Terrain | Passif (idle) | Naïf | Tactique | Durée médiane (tactique) | Retraites de l'IA (tactique) |
|---|---|---|---|---|---|
| Rase campagne | 0 | 3 | 5 | 136 s | 5 |
| Bois | 0 | 4 | **2** | 136 s | 2 |
| Collines | 0 | 1 | 6 | 155 s | 6 |
| Rivière | 0 | 1 | 4 | 132 s | 4 |
| Village | 0 | 1 | 4 | 146 s | 4 |
| Palissade | 0 | **10** | 5 | 152 s | 5 |
| **Total** | **0/60** | **20/60** | **26/60 (43 %)** | | |

À retenir :
- **Normal est exigeant, mais pas injuste.** Le joueur tactique gagne 43 % (contre 37 % lors de la session
  IA). Les batailles durent 2 à 2,5 min, et l'IA se retire en bon ordre dans chacune de ses défaites (26 sur
  26), ce qui raccourcit les fins.
- **Le bois reste le terrain le plus dur** pour le joueur tactique (2/10). L'IA y choisit le débordement
  5 fois sur 10.
- **Anomalie de la palissade : le joueur naïf gagne 10/10**, contre 5/10 pour le tactique. Tenir derrière
  les pieux en attendant suffit : l'IA, toujours agressive en siège, vient s'empaler aux brèches. Il faut
  soit rendre l'IA patiente (archers d'abord, assaut seulement si le rapport de forces le permet), soit
  pousser le joueur à sortir (objectif, renfort ennemi en retard).
- Deux parties « non finies » sur 600 s pour le joueur passif (bois, palissade) : l'IA ne vient pas
  chercher un défenseur immobile. C'est sans gravité, car un joueur réel agit.

### 5.3 Performance (`tests/perf_test.gd`, graine 12345, effectifs x2 : 516 soldats, 32 régiments)
Le test a été lancé seul, sans autre processus Godot :

| Mesure | x1 (258 soldats) | x2 (516 soldats), sans fenêtre | x2, avec fenêtre |
|---|---|---|---|
| Étape de simulation, approche | 3,7 ms (p95 4,6) | 8,1 ms (p95 10,8) | 8,0 ms (p95 10,2) |
| Étape de simulation, mêlée | 4,5 ms (p95 6,5, max 8,6) | 7,9 ms (p95 12,0, max 17,2) | 7,5 ms (p95 11,5, max 14,3) |
| Image complète en mêlée | 9,1 ms (**110 i/s**) | 22,3 ms (p95 31,0, **45 i/s**) | 25,6 ms (p95 29,5, **39 i/s**) |

À retenir :
- Une bataille normale tient largement les 60 i/s.
- Au double des effectifs, on tombe à 40-45 i/s. Le coût vient surtout du dessin en GDScript, à environ
  14 ms par image ; le rendu GPU reste négligeable (avec fenêtre ≈ sans fenêtre).
- La simulation a gagné environ 20 % depuis la mesure de la session outils (10-11 ms à x2), mais
  l'image complète n'a presque pas bougé (24,9 → 22,3 ms).
- La bataille décisive (environ 19 régiments, 300 à 330 soldats) restera fluide à x1, mais limite en
  vitesse x2. La priorité est I7 : ne pas dessiner hors champ.

### 5.4 Captures (1280×720, interface 100 %, dans `user://captures_audit`, `user://captures_resolution` et `user://captures_interface`)
- **Menu et options** : lisibles et cohérents ; version affichée.
- **Carte** : belle et claire, mais les effectifs des armées chevauchent les noms des villes (U1), et il
  faut défiler dans le panneau.
- **Bataille** : le HUD est lisible (messages sur fond, cartes, info-bulle ennemie). À zoom 1 en 720p, les
  soldats font environ 16 px, et les nouvelles unités ne se distinguent qu'au pictogramme (U2). La plaine,
  vaste et uniforme, paraît vide.
- **Siège** : rempart, porte, tours et échelles se lisent bien, et l'état « Porte 50 % » est utile.
- **Objectifs** : le panneau d'escorte est clair (arrivés, en route, perdus, jauge).
- **Bilan** : complet et lisible ; la promotion est mise en valeur.
- **Tutoriel** : la consigne est claire, mais le panneau recouvre l'onglet d'aide (U4).
