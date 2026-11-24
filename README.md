# Compagnie Franche — prototype Godot

Prototype de bataille médiévale en temps réel, en pixel art, dans l'esprit des jeux de type Total War / Mount & Blade.
Graphismes et sons : assets libres (voir [CREDITS.md](CREDITS.md)). Si un fichier manque, le jeu revient au dessin en code.

## Lancer le jeu
1. Installez **Godot 4.7 ou plus récent** (version standard, pas besoin de .NET) : https://godotengine.org
2. Dans Godot : **Importer** → choisissez le fichier `project.godot` de ce dossier.
3. Appuyez sur **F5** (ou le bouton ▶). Le jeu s'ouvre sur le **menu principal**.

## Menu principal
- **Continuer la campagne** : reprend l'emplacement joué en dernier (si une sauvegarde existe).
  **Nouvelle campagne** : choix de la **difficulté** (facile, normal, difficile), du **mode indulgent**
  et des **défis** (voir « Défis de campagne »), sur le premier emplacement libre, avec un avertissement si l'emplacement contient une campagne en cours.
  Si la campagne sauvegardée est **terminée**, le premier bouton devient **Bilan de la campagne** (écran de fin).
- **Emplacements de campagne** : 3 emplacements. Chacun montre un **aperçu** : miniature de la carte de
  campagne (villes aux couleurs de leur maître, position de la compagnie), jour, or, hommes, renommée,
  difficulté (et « indulgent »), date réelle de la sauvegarde et état (en cours, bataille en cours, terminée
  par une victoire ou la ruine), avec **Continuer** (ou **Bilan**), **Nouvelle campagne** et **Supprimer**
  (avec confirmation). L'aperçu est un petit en-tête (`campagne_<n>.apercu.json`) écrit à côté de chaque
  sauvegarde : le menu ne charge pas les campagnes (une ancienne sauvegarde sans en-tête est lue une fois).
- **Tutoriel** : petite bataille guidée (4 régiments contre 3). Les consignes s'affichent en haut à droite
  et ne se valident qu'en faisant vraiment l'action : sélectionner, déplacer, tracer une ligne de front,
  changer de formation, courir, cacher les cartes (Tab), ouvrir l'aide (F1), lancer la bataille (l'ennemi
  attend jusque-là), faire tirer les archers, charger les archers ennemis avec la cavalerie, gagner.
  Échap : menu pause (Menu principal pour quitter).
- **Tutoriel guidé** (`scripts/campaign_guide.gd`) : à la **première nouvelle campagne**, le menu propose
  « bataille d'entraînement, puis campagne guidée », « seulement la campagne guidée » ou « non merci ».
  Après la bataille d'entraînement (le tutoriel ci-dessus), Entrée mène à la carte, où un panneau en haut
  à droite guide la **première semaine** : lever un régiment, s'équiper en ville, acheter des vivres,
  accepter un contrat, marcher, entrer dans une autre ville. Chaque étape avance quand l'action est faite
  (boutons « Passer l'étape » et « Quitter le tutoriel »). L'étape est sauvegardée (version 16).
  Option **Tutoriel guidé** (Options et menu pause) : le désactive ; la réactiver le propose de nouveau.
- **Manette sur la carte de campagne** (`scripts/map_pad.gd`) : stick gauche = curseur (la vue suit au bord),
  stick droit = vue, **A** = aller au point visé (ville : y entrer ; groupe : le poursuivre), **B** = fermer la
  fenêtre, **Start** = menu, **Select** = recentrer, **X** = pause, **Y** = halte, **gâchettes** = vitesse
  (droite : plus vite ; gauche : plus lent, puis pause), **LB / RB** = onglets. Dans une fenêtre, la croix
  ou le stick déplacent le focus d'un bouton à l'autre (la fenêtre défile), A presse le bouton. La souris
  ou le clavier reprennent la main dès qu'on les touche.
- **Infobulles** (`scripts/tooltips.gd`) : boutons d'équipement (la pièce comparée à celle portée, gains en %
  de vie, moral, dégâts, flèches reçues, vitesse), **chances estimées** de chaque contrat (rapport de force
  compagnie / ennemi : hommes, rang, équipement, traits, difficulté), compétences du capitaine (effet actuel
  et au niveau suivant), traits des régiments, terrain d'une rencontre (ce qu'il change, un conseil).
- **Escarmouche** : bataille libre hors campagne (Échap : menu pause, d'où l'on revient au menu), d'abord
  **préparée** : pour chaque armée, le nombre de régiments de chaque type (0 à 6, 12 au plus), leur **rang**
  (recrues, aguerris, vétérans) et leur **équipement** (aucun, simple, bon, de maître : les trois pièces de
  cette qualité) ; puis le **terrain** (les 6 terrains), la **météo** (clair, pluie, brouillard, vent fort), la **saison** (le sol se
  couvre de neige en hiver, roussit en automne), l'**heure** (aube, plein jour, crépuscule, nuit : lumière de
  la carte du monde) et la **difficulté** ; chaque réglage peut être « au hasard ». Boutons **Lancer la
  bataille**, **Au hasard** (tout tiré au sort), **Par défaut** (l'escarmouche classique, 8 contre 8). Le
  dernier réglage est **mémorisé dans les options** (`[escarmouche]` de `options.cfg`) ; « Recommencer »
  rejoue la même escarmouche. Données et règles : `scripts/skirmish_setup.gd`.
- **Menu pause** (Échap en bataille : contrat, escarmouche ou tutoriel) : la bataille s'arrête.
  Reprendre (ou Échap), Aide (toutes les commandes), Options (volumes, vitesse, plein écran, taille de l'interface),
  **Abandonner la bataille** (en contrat : retraite ordonnée, après confirmation ; ailleurs : retour au
  menu) et **Menu principal** (en contrat, après un avertissement : compte comme une retraite).
- **Affichage** : toute fenêtre ou écran (16:9, 16:10, 21:9, petites fenêtres) ; la base 1280×720
  s'agrandit selon la hauteur et les formats plus larges ou plus hauts montrent plus de surface.
- **Options** : volumes général / musique / effets, plein écran (aussi **Alt+Entrée** ou **F11**, partout),
  **taille de l'interface** (90 %, 100 %, 125 %, 150 %), **effets visuels** (complets, réduits, aucun), vitesse du jeu (x1, x1,5, x2 ; touche V
  en bataille), **difficulté de l'escarmouche**, **touches de bataille reconfigurables** (cliquez sur une touche puis appuyez sur la nouvelle ;
  si elle sert déjà à une autre action, les deux échangent leurs touches ; Espace, Entrée, Échap, F11, chiffres
  et flèches sont réservés ; bouton « Touches par défaut »). Les touches sont enregistrées
  par lettre, donc correctes en AZERTY comme en QWERTY. Les **touches de caméra** (ZQSD en AZERTY, WASD en
  QWERTY) se changent aussi ; elles gardent la position de la touche sur le clavier et ne peuvent pas
  prendre une touche déjà utilisée par une action.
- **Accessibilité** : **formes des camps** (rond pour vos régiments, losange pour l'ennemi, sur les étendards,
  marque sous chaque soldat, part ennemie rayée dans la barre des forces : les camps se distinguent sans le
  bleu et le rouge) et **sous-titres** des évènements sonores (cor de charge et de retraite, embuscade,
  charges de cavalerie, déroutes, fin de bataille). Aussi dans le menu pause.
- **Interface de bataille** : messages sur fond sombre, police épaissie et plus grande, aide F1 repliée
  par défaut (son état est mémorisé), info-bulle au survol de tout régiment ami ou ennemi visible
  (type, effectif, moral, endurance, rang, formation). Les **numéros des régiments** (cartes et touches
  1 à 8) restent fixes toute la bataille et suivent l'ordre de la compagnie : un régiment anéanti ou en
  fuite garde sa carte, grisée. Les cartes sont compactes (56 px de haut) et se cachent d'un coup de Tab ou
  d'un clic sur leur onglet (état mémorisé). À 150 % dans une fenêtre 1280×720, cartes, barre du haut et aide se resserrent.
- **Mini-carte de bataille** (coin en bas à gauche, au-dessus des cartes si elles prennent la place) : le
  champ en réduction (sol, relief, forêts, maisons et palissades), la zone de déploiement (bleue pendant le
  déploiement), les régiments amis et les ennemis **visibles** (jamais ceux cachés en forêt), le rectangle de
  la vue. Un clic (ou un glisser) dessus y centre la caméra. Touche N (reconfigurable) pour la cacher ou la
  montrer ; l'état est mémorisé.
- **Zoom de la bataille** : la taille de l'interface n'agrandit pas le terrain, et le zoom réel est arrondi
  pour qu'un pixel des sprites fasse un nombre entier de pixels de l'écran (pas de pixels de largeurs
  inégales) ; la molette passe d'une échelle entière à la suivante.
  Fichier : `options.cfg` dans le dossier de données du jeu, appliqué au démarrage.
- Carte de campagne épurée : la carte occupe tout l'écran, sous une fine barre (date, or, solde, effectif,
  pause et vitesses, Marche forcée et Camper (touches F et K), vivres et fatigue, onglets Compagnie, Monde,
  Journal, Quêtes et Menu ; touches E, M, J, T et Échap). Une fenêtre
  centrale n'apparaît que pour une ville, une rencontre ou un onglet ouvert ; Échap ou ✕ la ferme. Les
  messages (arrivée, refus, évènements) s'affichent en bas de l'écran puis s'effacent. Le menu principal
  est dans l'onglet Menu.
- **Statistiques** et **Succès** (deux boutons) : statistiques gardées d'une campagne à l'autre (batailles jouées, gagnées
  et perdues, ennemis tués, hommes perdus, or gagné, campagnes gagnées ou perdues, plus longue campagne,
  régiment le plus ancien et le plus décoré) et 23 succès (première victoire, victoire sans perdre un
  régiment, carré qui repousse une charge, embuscade réussie, campagne gagnée en difficile, régiment
  d'élite, 1 000 ennemis tués…). La page **Succès** les montre en grille : médaillon (doré une fois
  obtenu), nom, description, date d'obtention, ou progression pour les succès à compteur (« 37 / 100 »).
  Chaque succès obtenu s'annonce par une notification discrète en haut à droite (sous la barre de la
  bataille ; elle reste affichée en passant de la bataille à la carte). Fichier : `statistiques.json` dans le dossier de données du jeu (à part des campagnes).
  La carte et l'écran de fin montrent les statistiques de la campagne en cours.

## Difficulté
Définie dans `scripts/difficulty.gd` (un seul endroit, valeurs « normal » = 1) :

| | Facile | Normal | Difficile |
|---|---|---|---|
| Effectifs ennemis | x0,85 | x1 | x1 |
| Moral ennemi | x0,85 | x1 | x1,15 |
| Dégâts ennemis | x0,9 | x1 | x1,1 |
| IA : réflexion / marche / cavalerie | 1,6 s / 25 s / 40 s | 0,8 s / 12 s / 20 s | 0,5 s / 8 s / 15 s |
| IA : carré des piquiers contre les charges | non | oui | oui |
| Recrues / solde (campagne) | x0,8 | x1 | x1,1 |
| Primes des contrats | x1,25 | x1 | x0,95 |
| Vétérans des armées de contrat (les autres sont aguerris) | x0,4 | x0,7 | x0,85 |

L'escarmouche prend la difficulté de sa préparation (celle des Options par défaut) ; la campagne garde
celle choisie à sa création (enregistrée dans la sauvegarde, version 4 ; les sauvegardes plus anciennes
sont relues en « normal »).

### Défis de campagne
Cochés à « Nouvelle campagne » (`scripts/challenges.gd`), gardés dans la sauvegarde (version 15) et
repris par « Nouvelle campagne » de la carte et de l'écran de fin. Ils s'affichent dans la fenêtre du
monde (« Le pays »), dans l'aperçu de l'emplacement et au bilan de fin.
- **Homme de fer** : une seule sauvegarde, sans copie de secours `.bak` ni mode indulgent (fermer le jeu
  en pleine bataille la reprend) ; elle est **effacée** quand la compagnie est ruinée.
- **Sans cavalerie** : aucun régiment monté (cavaliers, archers montés) ne se lève ni ne se complète :
  ni en ville, ni au château, ni parmi les volontaires, déserteurs ou prisonniers.
- **Hiver éternel** : la saison reste l'hiver (marches lentes, froid, armées qui fondent, neige sur la carte).
- **Bourse plate** : la compagnie part avec la moitié de l'or.
- **Contrats maigres** : primes des contrats réduites d'un quart.

## Campagne
Vous menez une compagnie de mercenaires dans le pays de Valfrène, que se disputent trois factions :
le **Comté de Valfrène** (Valombre, Saint-Aubin), la **Baronnie de Montfaucon** (Montfaucon, Castelroux,
Hautemure) et la **Ligue des villes** (Brévannes, Pontrieux) au début de la campagne. Le liseré sous chaque
ville donne la faction qui la tient aujourd'hui (les villes changent de mains, voir « Monde vivant »).
- **Objectif** (annoncé au journal dès le jour 1, rappelé dans
  le panneau) : faire de la compagnie la plus célèbre du comté. À **150 de renommée**, la faction qui vous
  estime le plus (parmi celles qui ne vous ferment pas leurs portes) vous convoque dans sa capitale
  (Saint-Aubin, Montfaucon ou Pontrieux, drapeau doré) pour la **bataille décisive** contre sa rivale :
  9 régiments, dont deux de chevaliers à pied, presque tous aguerris ou vétérans. Ce contrat n'expire pas, et se signe toujours dans une ville tenue par
  son patron : si sa capitale tombe, il se déplace dans une autre de ses villes ; si le patron perd toutes
  ses villes (ou vous ferme ses portes), il est annulé et une autre faction vous convoquera. Le gagner termine la campagne
  (**écran de victoire** avec le bilan : jours, batailles, ennemis tués, pertes, or, vétérans). Le perdre
  coûte de la renommée : il faudra la regagner pour être rappelé.
- **Game over** : si la compagnie n'a plus un homme et ne peut plus lever un seul régiment complet dans la
  ville où elle se trouve (pas assez d'or, ou faction hostile), elle est dissoute : écran de fin avec le
  bilan, puis menu. Une compagnie anéantie mais encore riche peut recruter et repartir.
- **Carte du monde en temps réel** (`scripts/overworld.gd`, `scripts/map_data.gd`, rendu `scripts/map_render.gd`) :
  une grande carte de 3840 × 3120 (deux fois la précédente, prolongée vers l'est et le sud), **45 lieux** : les
  7 villes, des villages, châteaux, abbayes, moulins, un pont fortifié, un gué, des mines, des ruines et des
  repaires de bandits. Grandes routes entre les villes, **chemins** qui relient villages et lieux, **sentiers**
  (en pointillés) vers les ruines, repaires et mines. Quatre cours d'eau (la Vionne, l'Orbe, la Sorgue, le Ru
  de la Combe ; des **ponts** là où les routes les franchissent), six lacs entourés de marais, neuf grandes
  forêts nommées, des collines et trois **chaînes de montagnes** infranchissables (Monts de Fer, Montagnes
  Noires, Dents de Gaste) qu'on ne passe que par les **cols** des routes. Treize **régions** nommées
  (Val d'Ombre, Marches de Fer, Plaines d'Orient, Terres Gastes...) appartiennent au Comté, à la Baronnie,
  à la Ligue ou à personne : frontières en tirets bordées de la couleur de la faction, noms des régions en
  vue éloignée (ils s'effacent quand on zoome), noms des forêts, chaînes, lacs et rivières sur la carte.
  - **Rendu** : le terrain est précalculé une fois dans deux petites textures de champs (eau, relief, forêt,
    montagne, marais, ondulation des frontières) qu'un shader peint en pixels de 2 px : herbe et champs secs,
    ombrage du relief (lumière du nord-ouest), arbres stylisés avec leur ombre, roche, marais, eau et rives
    sablonneuses. Pics des montagnes, bosses des collines, routes, ponts et noms sont tracés une seule fois ;
    chaque lieu a son icône (ville, village, château, abbaye, moulin, pont, gué, mine, ruines, repaire).
  - **Figurines des groupes** (`scripts/map_icons.gd`) : chaque sorte a la sienne, tournée dans le sens de
    sa marche, jambes qui alternent au pas : **caravane** (charrette bâchée et deux bœufs), **villageois**
    (chapeaux de paille, fourche, baluchon), **patrouille** (cavaliers et bannière de la faction), **armée**
    (cavaliers, piquiers et grande bannière fourchée de la faction), **bandits** (silhouettes encapuchonnées,
    lames, chiffon noir), **déserteurs** (piques basses, bannière déchirée et délavée). Une **trace de
    marche** discrète (empreintes qui s'effacent) suit les groupes en mouvement.
  - **Armoiries** (`scripts/heraldry.gd`) : votre compagnie porte les siennes sur sa bannière. Tirées au
    hasard au départ (partition, meuble, trois émaux, en respectant la règle des émaux), modifiables dans
    l'onglet **Compagnie** (section « Armoiries » : partition, meuble, couleurs, au hasard) et sauvegardées.
  - **Villes, châteaux et villages** (`scripts/map_places.gd`) dessinés selon leur taille et leur maître :
    une **cité** (capitale d'une faction) a une double enceinte, quatre tours et une cathédrale, une **ville**
    ses remparts, deux tours et un clocher, un **château** son donjon crénelé, un **village** trois à cinq
    maisons (et une église pour les plus gros). Toits des tours et bannières sont aux couleurs de la faction
    qui tient le lieu et changent quand il est pris ; un village suit sa ville. Le **fief** de la compagnie
    arbore ses armoiries (liseré d'or). Une ville ou un fief **assiégé** s'entoure d'un camp de tentes aux
    couleurs de l'assiégeant, avec ses feux et leurs fumées.
  - **Portraits** (`scripts/portrait.gd`) : le capitaine (en tabard à vos armoiries), chaque compagnon et le
    chef de chaque groupe rencontré ont un visage en pixels assemblé d'après une graine (forme du visage,
    peau, yeux, cheveux, barbe, cicatrice ou bandeau, casque, capuchon ou chapeau, habit selon le métier ;
    certains surnoms se voient : le Roux, Barbe-Grise, le Borgne, Frère...). Toujours le même pour un même
    personnage (tiré de la graine de la campagne ou de l'identifiant du groupe : rien de plus à sauvegarder).
    Ils s'affichent dans l'onglet **Compagnie** (capitaine, compagnons et compagnons à engager) et dans les
    rencontres.
  - **Saisons et météo visibles** (`scripts/map_sky.gd` et le shader) : prés en fleurs au printemps, blés
    mûrs en été, feuillage roux (orange, rouge, or ; les sapins restent verts) et herbe jaunie en automne ;
    en hiver, la neige tient peu à peu au sol et sur les arbres, la glace borde l'eau, les toits blanchissent,
    puis tout fond au début du printemps. Les jours de pluie, le ciel se voile et la pluie tombe (la neige,
    en hiver) ; **brouillard** le matin (plus épais près de l'eau, en automne et sous la pluie). La
    mini-carte suit la saison.
  - **Le temps s'écoule** en heures de jeu (barre en haut à gauche : jour, heure, saison, météo ; 24 h = un
    jour de campagne, avec sa solde, ses contrats qui expirent, sa météo et le monde vivant). **Espace** :
    pause ; boutons ou touches **1, 2, 3** de la rangée du haut (& é " en AZERTY) : vitesses x1, x2, x4
    (x1 = 1,5 heure par seconde). Le temps s'arrête quand le panneau d'une ville ou une rencontre est ouvert.
    Jour et nuit marqués : aube rose, crépuscule orangé, nuit bleue où s'allument les fenêtres des villes,
    villages et châteaux, les feux des repaires et des camps de siège et la torche de la compagnie.
    Sauvegarde automatique chaque jour.
  - **Marcher** : clic gauche sur la carte, la compagnie y va (chemin A* qui préfère les routes et contourne
    l'eau et les montagnes ; pointillés jusqu'au but). Sur la route on marche à x1,3 ; en forêt x0,6, dans les collines x0,7,
    dans les marais x0,5 ; en hiver tout est x0,7. Valombre → Saint-Aubin prend environ deux jours.
    Clic droit : halte. Chaque jour coûte la **solde** (par homme et par jour : voir la colonne « solde » du
    tableau des unités ci-dessous) ; si les caisses sont vides, une partie des hommes **déserte** chaque jour.
    Un jour où la compagnie a marché peut amener un évènement de route (voir plus bas) et, en hiver, le froid.
  - **Entrer dans une ville** : cliquez sur une ville (ou un village, un château) : la compagnie y marche et y
    entre à l'arrivée. Le panneau de la ville s'ouvre (recrutement, contrats, capitaine et équipement) et le
    temps s'arrête ; « Quitter le panneau » le fait repartir, la compagnie restant à l'abri des murs.
  - **Groupes** : villageois, caravanes marchandes, bandits (cerclés de rouge) et armées des factions se
    déplacent sur la carte (infobulle au survol). Cliquez sur un groupe pour le **poursuivre** ; au contact,
    le temps s'arrête et une **rencontre** s'ouvre (« Attaquer » ou « Passer son chemin », ou les choix du
    module des rencontres). Les bandits, les patrouilles et armées hostiles fondent sur la compagnie quand elle passe à
    portée en rase campagne ou dans un village (jamais dans les murs d'une ville ou d'un château) ; fuir
    coûte 8 % de l'or en bagages.
    - **Le champ de bataille vient de l'endroit exact de la carte** (`scripts/battle_site.gd`) : une fenêtre
      de la carte autour du point de contact (6 pixels de bataille par pixel de carte) devient le champ.
      S'il y a une rivière à moins de 90 px, elle traverse le champ entre les deux armées, la compagnie sur sa
      rive, avec **le pont ou le gué de la carte** là où la route la franchit (un pont de planches se
      traverse à pied sec ; sans passage, deux hauts-fonds). Sinon, une route proche traverse le champ d'ouest
      en est, à l'endroit et avec les virages de la carte ; les autres routes et chemins aussi. Les **bois**
      sont ceux de la carte (la lisière du bon côté), les **collines** sont là où le relief monte, l'eau d'un
      **lac** voisin ralentit, et l'on se bat **dans le village** où se trouvait la compagnie (ou tout contre).
      Le contrat porte ce descripteur (`contract["site"]`), sauvegardé avec la bataille en cours ; la
      rencontre l'annonce (« Terrain du combat : rivière, au pont sur la Vionne, près de... ») et la bataille
      aussi. Les embuscades de la route en ont un. Sans descripteur (contrats des villes, escarmouche),
      le terrain est tiré comme avant.
    - **Combattre aux côtés d'alliés** : une patrouille ou une armée d'une faction à moins de 120 px du
      combat se bat avec la compagnie si elle ne vous est pas hostile (réputation positive) et qu'elle sert
      la faction du contrat, que vous la suivez, ou qu'elle combat l'ennemi (bandits et déserteurs pour
      toutes les patrouilles, sinon une faction en guerre avec la sienne). Deux groupes au plus, quatre
      régiments au plus, sur les ailes derrière la compagnie. Ils sont menés par leur propre IA
      (`scripts/allied_ai.gd`, plan agressif : droit sur l'ennemi), dessinés en **bleu-vert**, ne se
      sélectionnent pas et n'ont pas de carte de régiment. La rencontre annonce « À vos côtés : ... ».
      Après la bataille, leurs **pertes sont reportées sur leur groupe** (une armée perd de sa force), le
      butin des tués des deux camps est **partagé** selon les hommes engagés, et une victoire vaut **+4** auprès
      de leur faction.
    - **Se joindre à eux** : quand le groupe que suit la compagnie engage un ennemi (bandits, déserteurs,
      patrouille ou armée d'une faction en guerre) et que la compagnie est à portée, le temps s'arrête :
      « Combattre aux côtés de... » lance la bataille commune, « Les laisser se battre seuls » laisse le combat
      se résoudre d'office comme avant.
    Au retour, la carte reprend à l'endroit du combat. Un groupe vaincu est dispersé et son or va au butin.
  - **Une carte vivante** (`scripts/party_ai.gd`) : chaque sorte de groupe a son comportement.
    - **Villageois** : ils mènent leurs marchandises du village au marché le plus proche (ville ou bourg), y
      restent quelques heures, puis rentrent ; ils fuient les bandits qu'ils voient.
    - **Bandits** : tapis près de leur repaire (cachés en forêt, invisibles tant qu'on ne tombe pas dessus),
      ils rôdent, fondent sur les proies faibles (villageois, caravanes peu gardées, déserteurs, et la
      compagnie si elle ne pèse pas plus d'environ 1,7 fois leur force), rentrent au repaire avec le butin et y
      recrutent (une recrue par 25 écus, 90 hommes au plus). Ils fuient patrouilles et armées plus fortes.
    - **Caravanes** : de ville en ville voisine par les grandes routes, elles vendent avec bénéfice à
      l'arrivée, rechargent leurs chariots et font un détour devant des bandits repérés. Une caravane
      escortée paie l'escorte à l'arrivée.
    - **Patrouilles** de faction (montées, plus rapides que les brigands) : depuis une ville, une tournée de
      deux ou trois lieux de leur territoire puis retour ; elles pourchassent bandits et déserteurs, et la
      compagnie si leur faction la hait (portes fermées) ou est en guerre avec celle qu'elle sert.
    - **Déserteurs** : ils naissent des batailles du monde vivant (armées défaites, sièges levés, villes
      prises) et des guerres, errent loin des villes et tournent au brigandage au bout de trois à cinq jours.
    - **Combats entre groupes** : quand un groupe en attaque un autre (bandits contre villageois ou
      caravane, patrouille contre bandits, patrouilles de factions en guerre...), l'issue est tirée au sort
      d'après la force ; le vaincu perd l'essentiel de ses hommes et détale (ou se disperse), le vainqueur
      prend le butin. Aux nouvelles du monde ; au journal seulement près de la compagnie ou si c'est
      important (caravane escortée, bande nommée détruite).
    - **Peuplement** : la carte entretient environ 30 groupes, d'après son nombre de villages et de villes et
      sa taille (`Overworld.POPULATION`, `population_cap`) ; deux réapparitions par sorte et par jour au
      plus. Moins de caravanes en hiver, plus de bandits et de déserteurs en guerre.
  - **Caméra** : ZQSD (touches physiques) ou flèches, bord de l'écran, clic molette pour déplacer la vue,
    molette pour zoomer (de x0,3 à x2,5), **C** pour recentrer sur la compagnie. **Mini-carte** en bas à
    gauche : toute la carte, les lieux, les groupes et le cadre de la vue (clic ou glisser : y regarder).
- **Recruter** : chaque ville lève certains types de troupes, à son prix (de -15 % à Brévannes à +25 %
  à Hautemure). On peut lever un régiment complet (8 régiments au plus) ou **compléter** un régiment entamé.
- **Unités** : sept types, chacun levé dans certaines villes (le prix est par homme, avant le prix de la ville).

  | Unité | Hommes | Points forts | Points faibles | Prix | Solde / jour | Où la lever | Ennemis dès le niveau |
  |---|---|---|---|---|---|---|---|
  | Piquiers | 20 | piques plantées contre la cavalerie (x2) | hommes d'armes, flèches | 6 | 0,3 | Valombre, Saint-Aubin, Brévannes, Pontrieux | 1 |
  | Hommes d'armes | 16 | blindés, bons contre les piquiers (x1,4) | lents en forêt | 12 | 0,6 | Saint-Aubin, Castelroux, Hautemure, Pontrieux | 1 |
  | Chevaliers à pied | 12 | élite très solide (80 PV, armure de plates), **inébranlables** | très lents, très chers | 30 | 1,4 | Saint-Aubin, Hautemure | 5 |
  | Archers | 16 | tir rapide à longue portée (340 px) | cavalerie (x2), mêlée | 7 | 0,35 | Valombre, Montfaucon, Brévannes, Hautemure, Pontrieux | 1 |
  | Arbalétriers | 16 | carreaux **perçants**, **pavois** quand ils tiennent | rechargent lentement (5 s), portée moyenne (270 px), cavalerie (x2) | 10 | 0,45 | Brévannes, Pontrieux (la Ligue) | 2 |
  | Cavaliers | 10 | charge (jusqu'à x2,8), archers (x2) | piques (x0,6), chevaliers à pied (x0,7) | 20 | 1 | Montfaucon, Castelroux, Hautemure | 2 |
  | Archers montés | 10 | **tirent en marchant**, **décrochent** seuls de la mêlée | faibles au contact, cavalerie (x1,5), piques (x1,5) | 18 | 0,9 | Montfaucon, Castelroux (la Baronnie) | 4 |
- **Contrats** : les villes marquées d'un drapeau rouge proposent des contrats sur **5 niveaux** :
  brigands (4 régiments), routiers (6), gens d'une faction ennemie (8), Grande Compagnie (8), ost d'une faction (9),
  régiment aux couleurs de celui qui lève l'armée compris ; les régiments ennemis sont souvent entamés.
  Les arbalétriers apparaissent chez l'ennemi dès les routiers, les archers montés avec la Grande Compagnie,
  les chevaliers à pied dans l'ost de la faction rivale et dans la bataille décisive (deux régiments).
  Accepter lance la bataille ; la victoire paie la prime **et le butin** (2 écus par ennemi tué).
  Les contrats deviennent plus durs avec votre **renommée** (gagnée par les victoires : 5 + 5 x niveau,
  perdue par les défaites) : un niveau de plus tous les 25 points, le niveau 5 à 100. Chaque ville propose le
  un contrat du niveau le plus haut aux deux d'en dessous. Plus le niveau est haut, plus l'ennemi est nombreux et aguerri
  (niveau 3 : un sur deux aguerri ; niveau 5 : 70 % d'aguerris ou de vétérans ; la part de vétérans dépend de la
  difficulté) et plus la prime est forte
  (de 260 à 1350 écus, +0,2 % par point de renommée, même au-delà du niveau 5). Ils expirent après 14 jours.
  Réglages : `CONTRACT_KINDS`, `FINAL_CONTRACT`, `FAME_STEP` et `FINAL_FAME` dans `scripts/campaign_state.gd`.
- **Contrats variés** : l'objectif ne se limite plus à détruire l'ennemi (la carte l'annonce, « Objectif : … ») :
  - **Détruire l'ennemi** (le plus courant) : briser toute son armée ;
  - **Tenir une position** 3 à 5 minutes (prime x1,1) : une zone marquée au sol (colline, place du village ou
    milieu de la route). Si l'ennemi l'occupe seul 30 s (cumulées), le contrat est perdu ; son infanterie y marche ;
  - **Escorter un convoi** (prime x0,85, **+8 % par chariot sauvé**) : 4 chariots suivent la route d'ouest en est ;
    2 (3 dès le niveau 4) doivent arriver. Un ennemi au contact abîme le chariot et arrête tout le convoi ;
    l'infanterie et la cavalerie ennemies vont aux chariots ;
  - **Prendre un village** (dès le niveau 2, prime x1,2, toujours sur un village) : la garnison est postée sur la
    place et ne contre-attaque pas (sauf saignée par les flèches) ; l'occuper seul 25 s avant la nuit (6 minutes) ;
  - **Poursuivre** (prime x0,95) : la bande, chargée de butin (vitesse x0,55, cavaliers x0,7), part du milieu du
    champ et fuit vers le nord derrière une arrière-garde de piquiers ; si la moitié de ses hommes quitte la carte,
    c'est perdu.
  En bataille : zone ou ligne de fuite au sol, panneau sous la barre du haut (chronomètre ou état, barre de
  progression, jauge rouge du danger) ; le bilan de fin dit si l'objectif est atteint. Un objectif qui ne va pas
  avec le terrain de la ville en change (escorte et poursuite : rase campagne, bois ou collines). Les villes
  fortifiées défendent leur palissade (détruire) dès le niveau 3. Réglages : `OBJECTIVES` dans
  `scripts/campaign_state.gd`, règles dans `scripts/battle_objectives.gd`.
- **Armées par faction** : l'ennemi des niveaux 3 et 5 est le plus souvent la rivale de la ville, sinon la troisième
  faction. Chacun ajoute un régiment à son armée : les **routiers** un de cavalerie, la **Ligue des villes** des
  arbalétriers (et ses archers prennent l'arbalète), la **Baronnie** des archers montés, le **Comté** des
  chevaliers à pied.
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
  **intempéries** (un jour de marche perdu), **hameau abandonné** (un régiment le pille et devient « pillards »).
- **Capitaine** : la compagnie a un capitaine nommé (panneau « Capitaine » de la carte). Il gagne de
  l'expérience à chaque bataille (30 xp, +30 en cas de victoire) et un niveau tous les 100 xp. Chaque niveau donne un
  point de compétence (9 au plus) à dépenser dans la fenêtre **Compétences du capitaine** (bouton de la section
  « Capitaine »), un arbre de trois voies où chaque compétence montre son coût, ses prérequis et son effet :

  | Voie | Compétences (rang max, coût, niveau requis, prérequis) |
  |---|---|
  | **Meneur** (en bataille) | Aura (3, 1) : rayon +25 %/rang · Ralliement (3, 1) : les fuyards de l'aura se rallient · Bannière haute (1, 2 pts, niv. 4, Aura + Ralliement) : moral maximal +10 % · Volonté de fer (1, 2 pts, niv. 6) : la chute du capitaine ou d'un officier ébranle moitié moins |
  | **Tacticien** (en bataille) | Manœuvres (2, 1) : vitesse +5 %/rang · Formations serrées (1, 1, niv. 2) : colonne et carré +25 % · Reconnaissance (1, 2 pts, niv. 4) : zone de déploiement plus profonde de 150 px · Coup d'œil (1, 2 pts, niv. 6) : mêlée +8 % |
  | **Intendant** (toujours) | Solde réduite (3, 1) : -5 %/rang · Économe (2, 1, niv. 2) : vivres mangés -10 %/rang · Marchandeur (1, 2 pts, niv. 4) : recrues, équipement, vivres -10 % · Pillard avisé (1, 2 pts, niv. 6) : butin +20 % |

  L'arbre coûte 26 points : il faut choisir sa voie. Les effets du Meneur et du Tacticien ne jouent que si le
  capitaine est sur le champ. S'il tombe au combat, il n'est que **blessé** : il manque les batailles des 5 jours suivants.
- **Officiers** (`scripts/officers.gd`, section « Officiers » de l'onglet Compagnie) : un compagnon peut être nommé
  à la tête d'un régiment (boutons « → n », « Relever »). Bonus : sergent mêlée, chirurgien moral, éclaireur
  vitesse, quartier-maître tir, +10 % au niveau 1 et +2 % par niveau. En bataille, l'officier marche derrière son
  régiment (petit fanion à sa couleur) ; chaque homme perdu lui fait risquer de tomber (60 % de risque cumulé si
  tout le régiment y passe, chute certaine s'il est anéanti). Tombé, il est tué (40 %, 25 % avec un chirurgien) ou
  blessé (6 jours) ; son régiment perd 20 de moral et le bonus. Un officier tué quitte la compagnie (journal,
  chronique).
- **Chronique** (`scripts/chronicle.gd`) : les faits marquants (batailles, officiers tombés, fiefs pris ou perdus)
  sont notés au fil de la campagne ; l'écran de fin et l'onglet Journal en tirent un récit de quelques paragraphes
  (débuts, plus belle victoire et jour le plus sombre, chutes du capitaine, officiers tombés, domaine, issue).
- **Traits de régiment** : un trait à chaque promotion (dans un ordre propre au type), d'autres en route.
  **Tenaces** (moral +20 %), **rapides** (vitesse +10 %), **adroits** (dégâts +10 %), **pillards** (+1 écu
  de butin par ennemi tué), **frugaux** (solde -20 %).
- **Départ sans un homme** : une nouvelle campagne commence à Valombre avec 300 écus plus le prix de
  l'ancienne compagnie de départ (2 piquiers, 1 homme d'armes, 2 archers, 1 cavalier), soit environ
  1 160 écus, et pas un régiment : à vous de lever votre troupe (la compagnie ne peut pas quitter la ville
  avant). Les tests et les bancs gardent la compagnie de départ (`CampaignState.START_COMPANY`).
- **Équipement** (section « Équipement » de la fenêtre de la ville ; consultable partout, achetable seulement
  en ville, au prix local) : trois pièces par régiment, chacune en trois qualités. Prix par homme du régiment
  au complet ; améliorer une pièce remplace l'ancienne et ne coûte que la différence. La qualité II demande
  des aguerris, la III des vétérans.

  | Pièce | I | II (aguerris) | III (vétérans) |
  |---|---|---|---|
  | Casque | chapels de fer : vie +8 %, moral +5 % (2 écus) | bassinets : vie +15 %, moral +10 % (4) | grands bassinets à visière : vie +22 %, moral +15 % (7) |
  | Armes | bonne trempe : dégâts +10 % (3) | armes de maître : +20 % (6) | armes de Milan : +30 % (10) |
  | Armure | gambisons : flèches -15 %, vie +5 % (3) | brigandines : flèches -30 %, vie +12 %, vitesse -3 % (6) | harnois : flèches -45 %, vie +22 %, vitesse -8 % (11) |

  Les anciennes sauvegardes gardent leur équipement : « armure » devient des brigandines, « meilleures
  armes » des armes de maître.

  L'équipement **se voit en bataille** : chapel de fer sombre à large bord, bassinet d'acier à pointe,
  grand bassinet poli cerclé d'or ; gambison de toile claire, brigandine de cuir rouge cloutée, harnois
  d'acier clair ; les armes de maître lancent un reflet de temps en temps, celles de Milan un halo doré.
- **Armoiries** : la compagnie reçoit au départ des armoiries tirées au sort (partition, meuble et émaux,
  `CampaignState.arms`, voir `scripts/heraldry.gd`), sauvegardées avec la campagne. Elles flottent sur les
  drapeaux de vos régiments ; ceux de l'ennemi portent la couleur de sa faction (contrat contre le Comté,
  la Baronnie ou la Ligue), ou le rouge des bandes sans seigneur.
- **Pertes** : les morts sont perdus pour de bon ; les fuyards reviennent. Après une victoire, 30 % des
  tombés sont relevés blessés (plus avec un chirurgien, qui en relève aussi après une défaite). Les effectifs
  et l'expérience passent d'une bataille à l'autre. En plus, des **blessés graves** suivent dans les chariots
  (15 % des tombés restants après une victoire, 5 % après une défaite) : voir « Vivres, fatigue et repos ».
- **Vivres, fatigue et repos** (`scripts/supplies.gd`) :
  - **Vivres** : comptés en jours de marche pour l'effectif du moment (un homme, un blessé ou un compagnon
    mange une ration par jour, un prisonnier une demi-ration ; la barre du haut affiche « vivres N j »). La
    compagnie part avec 10 jours. On en achète en ville (section « Vivres et repos » : +5 jours, +10 jours,
    remplir les chariots, qui portent 30 jours ; 0,08 écu la ration, au prix de la ville, x1,5 dans une ville
    qui vous ferme ses portes) et auprès des villageois et des caravanes (« Acheter des vivres » : 3 jours, un
    peu moins cher). Sans vivres : **FAMINE** dans la barre, moral de départ x0,75 en bataille, et à partir du
    troisième jour 6 % des hommes désertent chaque jour.
  - **Marche forcée** (bouton de la barre ou touche **F**) : la compagnie va deux fois plus vite sur la carte
    mais se fatigue dix fois plus (fatigue de 0 à 100 : +3 par heure, +0,3 au pas). À 100, elle reprend le pas.
  - **Camper** (bouton de la barre ou touche **K**) : la compagnie s'arrête et monte le camp (-3 de fatigue par
    heure, soins) ; un ordre de marche lève le camp. Dans les murs d'un lieu, elle se repose plus vite (-4 par
    heure) ; à la simple halte, -1 par heure.
  - **Fatigue en bataille** : l'endurance de départ des régiments baisse avec la fatigue (x0,4 à 100).
  - **Blessés graves** : ils guérissent au repos (35 % par jour en ville, 25 % au camp, plus avec un
    chirurgien) et rejoignent un régiment de leur type qui a de la place, avec leur expérience.
- **Prisonniers** (`scripts/prisoners.gd`) : après une victoire, une part des vaincus est faite prisonnière
  (30 % des fuyards et 15 % des tués, au plus 0,75 prisonnier par homme de la compagnie). Sections
  « Prisonniers » de la fenêtre de la ville et de l'onglet Compagnie :
  - **Rançon** (en ville) : 80 % du prix de recrue de leur type par homme, +50 % par rang ; x1,3 dans une ville
    de leur faction, moitié moins pour des brigands ;
  - **Enrôler** : la moitié des hommes accepte de servir ; ils complètent les régiments de leur type, puis en
    forment un nouveau, avec leur expérience mais de la **rancœur** : moral de départ jusqu'à -50 % pour un
    régiment fait d'anciens prisonniers, qui s'efface en une vingtaine de jours (plus vite en combattant) ;
  - **Relâcher** : +1 de réputation auprès de leur faction par 8 hommes (5 au plus).

  Les garder coûte des vivres, et certains s'évadent chaque nuit (3 %, 8 % s'ils sont plus de la moitié de
  l'effectif de la compagnie, 15 % pendant une famine).
- **Compagnons** (`scripts/companions.gd`, section « Compagnons ») : des héros qu'on engage dans certaines
  villes (un de chaque métier au plus), avec un arbre de trois compétences comme le capitaine (un point par
  niveau, 100 xp par niveau ; 30 xp par bataille, +30 en cas de victoire ; 3 niveaux par compétence). Ils
  touchent une solde (1,5 à 2,5 écus par jour, +0,5 par niveau) et peuvent être blessés en bataille (6 % des
  victoires, 20 % des défaites, moitié moins avec un chirurgien) : sans effet pendant 6 jours.

  | Compagnon | Villes | Prix | Effet de base | Compétences |
  |---|---|---|---|---|
  | Sergent | Saint-Aubin, Montfaucon, Castelroux | 120 | moral maximal +5 %, désertions -20 % | Exercice (moral +5 %), Discipline (désertions -20 %), Dressage (prisonniers : +10 % de volontaires, rancœur oubliée plus vite) |
  | Chirurgien | Saint-Aubin, Brévannes, Hautemure | 150 | +5 % de tombés relevés (+15 % après une défaite), +3 % de blessés graves, guérison +20 % | Brancardiers (+5 % relevés), Chariots (+5 % blessés graves), Soins (guérison +30 %) |
  | Éclaireur | Valombre, Montfaucon, Pontrieux | 100 | repère les bandits cachés à 180 px ; rapport sur les groupes rencontrés (composition approchée) | Œil de lynx (portée +25 %), Pistes (vitesse sur la carte +5 %), Espions (effectifs exacts et rangs) |
  | Quartier-maître | Valombre, Brévannes, Pontrieux | 110 | vivres -10 %, solde -3 %, rançons +5 % | Rations (vivres -10 %), Trésorier (solde -4 %), Marchandage (rançons +15 %) |
- **Bilan de fin de bataille** : après quelques secondes de ralenti, un panneau résume la bataille par-dessus
  le champ (qui continue au ralenti) : issue (victoire, défaite, retraite), contrat, terrain et durée ; pour chaque
  régiment, l'effectif avant → après, les morts, les fuyards revenus, les blessés relevés, les ennemis tués,
  l'expérience gagnée et les **promotions** (ligne dorée « ▲ AGUERRIS ! ») ; puis les pertes des deux camps,
  prime, butin ou pillage, solde du jour, or avant → après, réputation et renommée. En escarmouche et au
  tutoriel, le bilan est simplifié (sans or ni expérience). Entrée affiche le bilan tout de suite, puis continue.
  L'onglet **Statistiques** du bilan montre une **carte de chaleur des pertes** (où sont tombés vos hommes,
  en bleu, et les ennemis, en rouge), un **graphique des effectifs** debout des deux camps dans le temps et
  les **ennemis tués par régiment** (les vôtres, puis les ennemis les plus meurtriers). Les relevés se font
  toutes les 2 secondes de bataille (`scripts/battle_recorder.gd`), sans coût notable.
- **Escarmouche libre** : bouton en bas du panneau (bataille hors campagne, Échap : menu pause).
- **Sauvegarde automatique** après chaque marche, recrutement, contrat accepté et bataille.
  Fichiers : `campagne_1.json`, `campagne_2.json`, `campagne_3.json` dans le dossier de données du jeu
  (Windows : `%APPDATA%\Godot\app_userdata\Compagnie Franche\`). L'ancien fichier unique `campagne.json`
  devient automatiquement l'emplacement 1 (au premier passage par le menu).
  Écriture sûre : fichier temporaire, puis l'ancienne version devient la **copie de secours** `.bak`.
  Si le fichier est abîmé (ou absent), la sauvegarde est relue depuis le `.bak`.
  Format versionné (version 16 : étape du tutoriel guidé ; 15 : défis de campagne ; 14 : officiers des régiments,
  arbre du capitaine, chronique ; 13 : domaine — fiefs, commerce, allégeance, quêtes ; 12 : vivres, fatigue, blessés,
  prisonniers et compagnons ; 11 : champ de bataille tiré de la carte et alliés de la bataille en cours ;
  10 : armoiries de la compagnie ; 9 : carte en temps réel — heure, position et chemin de la compagnie, groupes ;
  8 : objectifs des contrats ; 7 : monde vivant ; 6 : capitaine ; 5 : emplacements, mode indulgent, bataille en
  cours) ; les versions 1 à 15 se relisent (difficulté normale, mode indulgent désactivé, aucune bataille en
  cours, monde neuf et en paix ; avant la version 9, la compagnie se retrouve au matin dans sa ville et les
  armées sont replacées sur la grande carte ; avant la version 10, les armoiries sont tirées de la graine de la
  campagne ; avant la version 12, dix jours de vivres, ni prisonniers ni compagnons ; avant la 13, ni fief, ni
  cargaison, ni serment, et de premières offres de quêtes ; avant la 14, ni officier ni chronique, et seules
  les trois premières compétences du capitaine sont relues ; avant la 15, aucun défi ; avant la 16, pas de tutoriel guidé).
- **Bataille en cours sauvegardée** : un contrat accepté ou une embuscade est enregistré avec la campagne.
  Fermer le jeu en pleine bataille puis relancer reprend la bataille (depuis son début, même armée ennemie,
  même terrain) : on ne peut plus annuler une embuscade ni esquiver un contrat mal engagé.
  Quitter par le menu pause compte toujours comme une retraite.
- **Monde vivant** (`scripts/world_sim.gd`) : le pays vit sans vous.
  - **Saisons** de 30 jours (printemps, été, automne, hiver ; barre du temps en haut à gauche de la carte et
    section « Le pays » du panneau). En **hiver**, la compagnie et les armées marchent à x0,7,
    les armées fondent plus vite, et chaque jour de marche
    a une chance sur deux que le **froid** emporte 2 % des hommes. La carte se couvre de neige.
  - **Météo du jour** : pluie 25 % au printemps, 10 % en été, **50 % en automne**, 30 % en hiver. Une bataille
    livrée un jour de pluie se fait **sous la pluie**, sur un sol déjà boueux (la pluie tombe aussi sur la carte).
    Par temps sec, **brouillard** certains jours (15 % au printemps, 5 % en été, 25 % en automne, 20 % en
    hiver), plus souvent près de l'eau et dans les bois ; un jour sur quatre, **vent fort**. La météo du jour
    et du lieu de la rencontre s'impose à la bataille (`WorldSim.battle_weather`, tirée de la graine sans
    toucher aux tirages de la campagne).
  - **Guerres** : à partir du jour 6, deux factions rivales peuvent se déclarer la guerre (une chance sur 33
    par jour ; une sur 100 pour le Comté et la Ligue, qui ne sont pas rivaux), au plus tôt 12 jours après une
    trêve. Une trêve peut se signer après 20 jours de guerre, de plus en plus probable avec le temps (tout de
    suite si une faction n'a plus de ville). Déclarations, trêves et villes prises s'inscrivent au journal.
  - **Armées** : chaque faction a des armées visibles sur la carte (bannière à ses couleurs, effectif écrit
    dessous, infobulle au survol). En paix, une petite patrouille (x0,5) va d'une ville amie à l'autre ; en
    guerre, jusqu'à deux armées (x1,6 ; base 170 hommes pour le Comté, 210 pour la Baronnie, 150 pour la Ligue)
    marchent sur la ville ennemie la plus proche. Arrivées, elles **l'assiègent** (anneau rouge et fumée) :
    chaque jour, assiégeants et garnison (180 hommes, 300 dans une capitale) s'usent ; quand la garnison tombe à
    zéro, la ville **change de mains**, ses contrats sont annulés et la nouvelle faction en propose d'autres.
    Les contrats parlent toujours au nom de la faction qui tient la ville **aujourd'hui** : l'ennemi est une
    faction en guerre avec elle (en paix, sa rivale ou la troisième), jamais elle-même.
    Deux armées ennemies qui se croisent **se livrent bataille** (résolue automatiquement, selon les effectifs
    et un peu de hasard) : le vaincu perd les trois quarts de ses hommes et se replie, ce qui peut lever un siège.
  - **Contrats de guerre** : une ville dont la faction est en guerre propose **un contrat de plus** et paie
    **30 % de plus**.
  - **Réputation** : une faction alliée de la compagnie (réputation 50 et plus) déclare plus volontiers la
    guerre, et la taille des armées varie de x0,75 à x1,25 selon la réputation de la compagnie auprès d'elles.
  - **Rencontres** : une armée est **hostile** (cerclée de rouge) si sa faction vous ferme ses portes, ou si
    elle se méfie de vous (réputation négative) et que vous êtes ami (20 et plus) d'une faction qu'elle combat.
    En croiser une sur la route vous laisse le choix à l'arrivée : **livrer bataille** (pas de prime mais le
    butin ; la disperser coûte 5 de réputation auprès d'elle et en rapporte 5 auprès de ses ennemis) ou
    **fuir** (un jour de détour, 8 % de l'or abandonné avec les bagages). La bataille se livre en chemin : en
    rase campagne, dans les bois ou sur des collines (le terrain de la ville s'il s'y prête), jamais sur la
    palissade de Hautemure ou de Castelroux.
  - **Nouvelles du monde** : les dernières sont listées dans la section « Le pays ».
  - Réglages : constantes en tête de `scripts/world_sim.gd`.
- **Rencontres de la carte en temps réel** (`scripts/encounter.gd`, panneau `scripts/encounter_panel.gd`) :
  quand la compagnie entre en contact avec un groupe (villageois, bandits, caravane, patrouille, armée,
  déserteurs), un panneau affiche l'accueil, la force estimée des deux camps (« Ils sont environ 60, surtout
  des archers ») et des choix numérotés (touches **1 à 9**, **Échap** pour passer son chemin quand c'est permis) :
  - **Bandits** : attaquer, payer un tribut (3 écus par bandit, arrondi), les **intimider** s'ils sont au plus
    moitié moins forts (ils fuient, ou se rendent avec leur bourse : +4 auprès de la faction locale), fuir.
  - **Villageois** : acheter des **vivres** (15 % de la solde du jour ; la solde du lendemain baisse de 30 %),
    vendre du **butin** (60 % de sa valeur, dans la limite de leur bourse), recruter des **volontaires**
    (piquiers, ou archers si la faction locale vous aime ; 80 % du prix), les **rançonner** (si vous êtes 1,5 fois
    plus forts ; -6 de réputation), les attaquer (-8), passer.
  - **Caravane** : commercer (butin repris à 90 %), proposer une **escorte** jusqu'à sa destination (petit
    contrat de 40 à 250 écus payé à l'arrivée, +3 de réputation), la **piller** (-15 ; elle se rend sans combat
    si ses gardes sont quatre fois plus faibles), passer.
  - **Patrouille ou armée** : parler (guerres en cours, contrats de sa faction), **se joindre** à elle (réputation
    20 et plus ; ses combats vous sont alors proposés, voir « Combattre aux côtés d'alliés »), attaquer si vous êtes en guerre contre elle ou qu'elle est hostile ; hostile et plus forte :
    **se rendre** (25 % de l'or confisqué) ou fuir.
  - **Déserteurs** : les recruter (40 % du prix, mais moral bas : moitié moins aguerris), les **livrer** à leur
    faction (3 écus par homme, +3 ; s'ils sont nettement plus faibles), les attaquer.
  - Un groupe qui **fond sur la compagnie** ne laisse que : combattre, payer (ou se rendre) et fuir.
  - **Fuir** : la chance dépend surtout des vitesses, puis de la taille des deux groupes (de 5 à 95 % ; sous
    10 %, la fuite n'est pas proposée). Une fuite manquée force la bataille.
  - Une bataille contre un groupe est un contrat sans prime (`CampaignState.party_contract`) : l'ennemi est le
    groupe lui-même, découpé en régiments complets (10 au plus). Après la bataille, `apply_party_battle`
    reporte ses pertes sur le groupe (les survivants et les fuyards revenus), donne son or et ses marchandises
    (butin à revendre) au vainqueur, et la réputation (villageois -8, caravane -15, bandits +4 à la faction
    locale, armée -5 / +5 à ses ennemis).
  - Aucun tirage pendant l'affichage : le hasard (fuite, intimidation, terrain) est tiré dans `resolve` avec une
    graine dérivée du groupe, du jour et du choix ; le `rng` de la campagne n'est pas touché.
- **Domaine** (`scripts/fiefs.gd`, `trade.gd`, `diplomacy.gd`, `quests.gd` ; fenêtres `scripts/realm_panel.gd`) :
  quatre systèmes branchés sur `campaign_state.gd` par quelques lignes (bloc « Domaine » en fin de fichier).
  Sans serment, fief ni quête, la campagne reste celle d'avant (ils ne tirent jamais son hasard).
  - **Fiefs** : les six châteaux de la carte (Tour du Guet, Grisemont, Fort-Lisière, Château-Corbin, Fort-Orient,
    Castel-Brume) appartiennent à une faction. Entrez dans un château : on peut l'**acheter** (6 000 écus, -20 % chez
    son suzerain ; réputation 20 au moins) ou **donner l'assaut** (siège avec bélier et échelles contre sa garnison,
    de 5 à 6 régiments à moitié aguerris ; -20 de réputation auprès de son seigneur, renommée +10 s'il tombe). Son
    fief rapporte **400 écus par semaine** moins la solde de sa garnison (moitié de la solde en campagne). On y lève
    les **sept sortes de troupes** à -10 %, et on y laisse jusqu'à **4 régiments en garnison** (la compagnie garde
    au moins un régiment). Une faction hostile (portes fermées, en guerre avec votre suzerain, ou dépossédée et
    encore méfiante) peut l'**assiéger** (3 % par jour, après 10 jours) : la compagnie a **3 jours** pour venir le
    défendre (bataille de défense des murs, l'ennemi diminué de ce que retient la garnison) ; sinon la garnison
    se bat seule (sa force doublée par les murs) et le château est perdu si elle cède. Le fief porte la bannière bleue
    et or de la compagnie, cerclée de bleu (de rouge s'il est assiégé).
  - **Commerce** : grain, vin, draps, fer et sel (prix de base 6, 16, 24, 14, 10 écus la charge). Chaque ville vend
    bon marché ce qu'elle **produit** (x0,65) et cher ce qui lui **manque** (x1,6) ; infobulle et section « Marché »
    de la fenêtre de la ville. Chaque charge achetée fait monter le prix (vendue : baisser), puis l'offre revient
    vers la normale (15 % par jour) ; les **caravanes** arrivées en ville y déchargent ce que produit leur ville
    d'origine, et une ville **assiégée** paie tout 30 % plus cher, son grain et son vin s'épuisant. Le marchand
    rachète à 88 % du prix. **Charge** : une demi-charge par homme, +25 par **chariot** (60 écus, 6 au plus,
    revendus à moitié prix). Une défaite fait perdre la moitié de la cargaison.
  - **Allégeance** (section de la fenêtre de la ville) : à 20 de réputation, prêter serment à la faction qui tient
    la ville. Vassale : **solde mensuelle** (150 écus + 2 par point de renommée), levées dans les **châteaux du
    suzerain** (piquiers, hommes d'armes, archers, cavaliers), un **contrat réservé** (+25 %) dans sa capitale. Mais
    ses ennemis deviennent les vôtres : -10 de réputation chez eux au serment, leurs villes vous ferment leurs portes,
    leurs patrouilles et armées vous pourchassent ; combattre les troupes du suzerain coûte -15. **Rompre** le
    serment : -45 de réputation, -15 de renommée, et la faction ne vous reprend pas avant 60 jours. Un suzerain
    qui perd toutes ses villes vous libère.
  - **Quêtes** (onglet « Quêtes », touche **T** ; les villes et les seigneurs des châteaux en proposent, 8 offres au
    plus, valables 10 jours ; 3 quêtes à la fois) : **nettoyer un repaire** (ruines ou repaire : la bande y attend,
    on l'attaque depuis le lieu), **escorter un noble** jusqu'à une ville (à remettre dans sa fenêtre ; une défaite
    en route et il est pris), **tenir un pont ou un gué** 2 ou 3 jours (dresser le camp sur place : chaque jour une
    bande de pillards, menée par l'IA des groupes, vient attaquer ; s'éloigner remet le compte à zéro), **livrer
    des marchandises** à une ville qui en manque. Réussie : la récompense, +5 de réputation auprès de qui la donne,
    +3 de renommée ; manquée (date limite, abandon) : -5. Les cibles des quêtes portent un « ! » doré sur la carte.
- **Mode indulgent** (option de la nouvelle campagne) : la bataille en cours n'est pas sauvegardée. Fermer
  la fenêtre en pleine bataille revient à l'état d'avant la bataille, et une embuscade interrompue est oubliée.

## Commandes
Les touches marquées * se changent dans **Options**.

| Action | Touche |
|---|---|
| Sélectionner | Clic gauche ou glisser un cadre (Maj pour ajouter) |
| Déplacer / attaquer | Clic droit sur le sol / sur un ennemi |
| File d'ordres | Maj + clic droit (ou ligne tracée) : l'ordre s'ajoute après ceux en cours (points de passage numérotés pour la sélection) ; un ordre sans Maj remplace la file, Halte la vide |
| Tracer la ligne de front | Clic droit maintenu + glisser : la longueur règle la largeur du front, les troupes font face à l'opposé de leur position |
| Tout sélectionner / un régiment | Ctrl+A / 1 à 8 |
| Courir (fatigue) | Double clic droit (sur le sol, un ennemi, ou en traçant une ligne) |
| Groupes de contrôle | Ctrl + 1 à 8 : mémoriser la sélection ; 1 à 8 : la rappeler (sinon, sélectionne le régiment n°) ; deux appuis rapides : centrer la caméra dessus |
| Halte | H * |
| Formation : ligne → colonne → carré | F * |
| Tenir la position (on/off) | G * : le régiment frappe ce qui est à sa portée mais ne poursuit pas et ne s'engage pas seul (indiqué « tient » sur sa carte) |
| Tir à volonté / cesser le tir (archers) | X * : sans tir à volonté, les archers ne tirent que sur la cible désignée par clic droit (« tir retenu ») |
| Caméra | ZQSD (ou WASD) *, flèches, clic molette maintenu |
| Détails d'un régiment (ami ou ennemi) | Survol à la souris |
| Zoom | Molette |
| Météo (escarmouche) : clair → pluie → brouillard → vent | T * |
| Relever / se replier | E * : avec un régiment sélectionné, survolez le régiment ami qui prend sa place (ou sélectionnez les deux : le plus frais relève l'autre) ; sans désignation, la sélection rompt le contact et recule pour souffler |
| Lancer la bataille / pause | Espace (pendant le déploiement, aucun combat : les ordres restent dans la zone bleue et on ne peut pas attaquer) |
| Couper / remettre le son | M * |
| Sonner la retraite | R * deux fois |
| Capitaine | Clic sur le capitaine : le sélectionner avec son escorte (son aura s'affiche) ; C * : il rejoint le régiment sélectionné |
| Pièges (déploiement) | P * : pieux → fossé → chausse-trapes → aucun (ou les boutons au-dessus des cartes) ; clic gauche : poser ; clic droit : retirer le piège visé (remboursé) ou ranger l'outil |
| Vitesse du jeu x1 → x1,5 → x2 | V * |
| Aide (repliée par défaut, état mémorisé) | F1 * |
| Cartes des régiments : cacher / montrer (état mémorisé ; aussi l'onglet cliquable au-dessus des cartes) | Tab * |
| Mini-carte : cacher / montrer (état mémorisé) ; clic ou glisser dessus : y centrer la vue | N * |
| Fin de bataille | Entrée : afficher le bilan, puis carte de campagne (contrat) ou rejouer (escarmouche, tutoriel) |
| Menu pause (reprendre, aide, options, abandonner, menu principal) | Échap ; sur l'écran de fin d'escarmouche : retour au menu |

## Règles de combat
- **Pierre-feuille-ciseaux** : piquiers > cavalerie > archers et arbalétriers ; hommes d'armes et chevaliers à pied > piquiers ;
  carreaux d'arbalète > armures ; archers montés > infanterie lente ; cavalerie et piques > archers montés.
- **Arbalétriers** : leurs carreaux ignorent 60 % de l'armure (redoutables contre hommes d'armes et chevaliers). Quand ils
  tiennent leur place (à l'arrêt, hors mêlée), leur **pavois** arrête 60 % des dégâts des traits reçus de face et la moitié
  du choc moral. En marche, ils sont à découvert.
- **Chevaliers à pied** : **inébranlables** — moitié moins de moral perdu sur un flanc, dans le dos ou sous une charge, et
  le choc d'une charge ne les fait pas reculer.
- **Archers montés** : ils tirent en marchant (moins juste) et, quand une troupe de mêlée approche à moins de 170 px, ils
  **décrochent** seuls au galop en continuant de tirer. L'ordre « tenir la position » (G) les en empêche. Ils ne chargent pas.
- **Flancs et dos** : frapper un régiment sur le côté (x1,4) ou dans le dos (x2) fait plus de dégâts et casse son moral.
- **Charge** : la cavalerie lancée à pleine vitesse fait de gros dégâts et repousse l'ennemi… mais s'empale sur les piques.
- **Moral** : un régiment qui subit trop de pertes fuit (une seule chance de se rallier). Une déroute fait paniquer les voisins.
- **Capitaine** : visible derrière le régiment qu'il escorte (fanion doré). Son **aura** (180 px) rend du moral
  aux régiments proches, même en mêlée. Les ennemis au contact le blessent ; s'il tombe, chaque régiment perd
  40 points de moral, mais la bataille continue. Si son escorte fuit, il rejoint le régiment le plus proche.
- **Chef ennemi** : dans les contrats de niveau 2 et plus et la bataille décisive (pas en escarmouche ni dans les
  embuscades de la route), l'ennemi est mené par un chef nommé : cavalier en heaume doré sous un étendard à
  queue fourchue, derrière un **régiment de garde** (son infanterie la plus robuste : moral et vie x1,3, coups x1,15).
  Il recule quand vos soldats approchent à 110 px ; vos soldats au contact et vos flèches qui tombent sur lui le
  blessent. S'il tombe, **chaque régiment ennemi perd 35 points de moral**. En campagne, sa tête rapporte 25 % de la
  prime du contrat (60 écus au moins) et +6 de renommée en cas de victoire, +3 de renommée même en cas de défaite ;
  le bilan l'indique (« Chef ennemi : … est tombé (+N écus, renommée +6) »).
- **Pièges** (déploiement) : un petit budget de points selon le terrain (rase campagne 6, bois 8, collines 6,
  rivière 5, village 7, palissade 5 ; pluie −2, au moins 2). **Pieux** (2 points) : un cavalier qui les charge y perd
  60 à 110 % de sa vie, est rejeté et son régiment s'arrête net (la rangée cède après 10 chocs) ; au pas, on passe
  lentement (x0,4). **Fossé** (3 points) : x0,4, plus d'élan ni de course, moral qui s'effrite, coups reçus x1,3.
  **Chausse-trapes** (1 point) : x0,5, plus de charge, les chevaux s'y blessent. Les pièges ne gênent que l'ennemi,
  se posent dans la zone bleue (ni sur l'eau, ni sur une maison, ni sur un autre piège) et se dessinent sur le terrain ;
  le bilan dit ce qu'ils ont fait.
- **Forêts** : ralentissent (surtout les chevaux), arrêtent la moitié des flèches, et **cachent** les troupes. Une attaque sortie d'une forêt déclenche une **embuscade** (gros choc moral).
- **Météo** (barre du haut ; effets détaillés sous l'onglet d'aide et en tête de l'aide F1, voir `battle_weather.gd`) :
  - **pluie** : arcs -30 % de portée, -25 % de dégâts et tir bien moins juste ; les **arbalètes** n'en perdent que -10 % ;
  - **boue** (elle monte sous la pluie, pleine d'emblée en campagne, puis sèche lentement) : fantassins x0,88,
    **cavalerie x0,7**, élan des charges réduit de moitié, la course fatigue davantage ;
  - **brouillard** : un régiment adverse s'estompe au-delà de 220 pas et disparaît au-delà de 380 (ni affiché, ni
    sur la mini-carte, ni cliquable, ni visé par les archers) ; l'IA y est soumise aussi (ses tireurs ne tirent que
    sur ce qu'ils voient, elle avance à tâtons d'après ses éclaireurs) ;
  - **vent** : +15 % de portée vent arrière, -15 % vent de face, et les flèches dérivent.
- **Usure et relève** : plus une mêlée dure, plus l'endurance fond (jusqu'à 3 fois plus vite après une minute de
  contact) ; à bout de forces, un régiment au contact perd aussi du moral. La **relève** (E) envoie un régiment frais
  à la place du régiment usé (il reprend son ennemi, qui se retourne contre lui), le relevé décroche (il ne cherche
  plus le contact) et recule derrière la ligne pour reprendre endurance et moral (bonus de moral au repos loin de
  l'ennemi). L'IA ennemie relève aussi ses régiments épuisés en mode normal et difficile. L'info-bulle indique
  l'usure au contact et le repos.
- **Course et endurance** : le double clic droit fait courir le régiment (x1,6), mais la course vide l'endurance en une douzaine de secondes ; la mêlée fatigue aussi, lentement. Sous 60 % d'endurance, la vitesse et les dégâts baissent (jusqu'à x0,6 pour un régiment épuisé). La marche et surtout le repos font récupérer. La barre jaune de la carte du régiment montre l'endurance.
- **Formations** (touche F) : la **ligne** (par défaut) ; la **colonne** (3 de front) avance 15 % plus vite ; le **carré** creux est lent (x0,55) mais n'a ni flanc ni dos : il annule les bonus de flanc et de dos.
- **Ressenti** : une charge de cavalerie qui percute fait trembler la caméra (moins si elle est loin), les chevaux au galop soulèvent de la poussière, un régiment qui fuit pousse des cris, et la fin de la bataille passe quelques secondes au ralenti.
- **Effets visuels** (option complets / réduits / aucun) : gouttes et taches de sang aux coups portés, étincelles sur les armures, mottes de terre des flèches perdues, éclat blanc d'une charge de cavalerie qui percute, traînées des flèches, fumée des cheminées du village, gerbes d'eau dans les gués et la rivière, pluie au sol (impacts, flaques qui se remplissent puis sèchent) et étendards qui flottent au vent ; nuages de poussière derrière les cavaliers lancés, sang qui sèche et reste au sol toute la bataille (900 taches au plus, 300 en effets réduits). Aucun effet ne trahit un ennemi en embuscade.
- **Soldats animés** : marche (cycle des planches), fente vers l'adversaire à chaque coup (plus longue pour les piques et les cavaliers), recul de l'arc au tir, galop des cavaliers lancés, et chute à la renverse des tués, dont le corps reste au sol avec son équipement. Flèches et carreaux en vol ont une hampe épaisse, un empennage clair et une ombre au sol qui montre leur trajectoire.
- **Étendards** : à gauche de la hampe, une plaque à la couleur du camp (bleu, rouge) avec le pictogramme du type ; à droite, le drapeau aux armoiries de la compagnie ou aux couleurs de la faction ennemie ; dessous, la barre de moral.
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
- **Choix** : sur la carte en temps réel, d'après l'endroit exact du combat (voir « Le champ de bataille vient
  de l'endroit exact de la carte » ; rivière, pont et gué, routes, bois, collines, lac et village peuvent alors
  se combiner). En escarmouche, au hasard. Pour les contrats des villes, d'après la ville : Valombre bois,
  Saint-Aubin village, Montfaucon et Castelroux collines, Brévannes et Pontrieux rivière, Hautemure rase
  campagne ; les contrats de difficulté 3 et plus à **Hautemure** et **Castelroux** sont des défenses de palissade.
  Table modifiable dans `scripts/terrain.gd` (`TOWN_TERRAINS`, `SIEGE_TOWNS`).

### Vrais sièges (assaut ou défense d'une ville)
Deux terrains de plus, jamais tirés au sort : **assaut d'une ville** (`town_assault`, la ville est en haut,
tenue par l'ennemi) et **défense d'une ville** (`town_defense`, la ville est en bas, vous la tenez).
- **Rempart** de pierre dessiné en code : un front percé d'une **porte**, deux murs latéraux, **6 tours**,
  un **chemin de ronde** derrière le parapet, des maisons et une **place** dallée (avec son puits).
- Sur le chemin de ronde, on tire 35 % plus loin, on frappe d'en haut (+50 %), et le parapet arrête la
  moitié des flèches tirées du dehors ; frapper vers le haut (de l'échelle ou du pied du mur vers le chemin
  de ronde) porte 40 % de moins. Les **tours** tirent seules sur l'assaillant hors les murs (300 px),
  tant que la garnison les tient.
- L'assaillant reçoit au déploiement un **bélier** (son régiment à pied le plus solide) et jusqu'à
  **3 échelles** (les suivants). Le bélier avance à 60 % de la vitesse et ses porteurs, bras pris, prennent
  35 % de dégâts de plus des flèches ; mené devant la porte, il l'enfonce en 30 s environ (plus lentement
  s'il perd des hommes). Tant que la porte tient, on n'entre que par les échelles. Si ses porteurs meurent ou
  fuient, le bélier reste sur place (cerclé) : un autre régiment à pied le reprend en le rejoignant. Une échelle se dresse en 3 s quand ses porteurs
  arrivent au pied du rempart ; on y monte lentement (40 % de la vitesse), et pas à cheval.
- La garnison qui se tient au débouché d'une échelle, sans assaillant arrivé en haut pour la tenir, la
  **repousse** : les grimpeurs tombent, l'échelle se redresse 6 s plus tard ou se brise (une fois sur trois).
- **Mâchicoulis** : avec 3 défenseurs au moins au-dessus de la porte, la garnison verse l'**huile bouillante**
  (2 chaudrons, 22 points de dégâts en nappe et un coup au moral) et jette des **pierres** (toutes les 4-5 s)
  sur ceux qui frappent la porte, les porteurs du bélier d'abord. L'infanterie la plus solide de la garnison
  est postée derrière la porte pour cela, et l'IA l'y laisse tant que la porte tient.
- **Panneau de siège** sous la barre du haut : solidité de la porte (jauge, puis « Porte enfoncée »), bélier
  abandonné, échelles dressées, huile restante, temps à tenir et prise de la place.
- **Victoire** : l'assaillant prend la ville s'il tient la **place** 20 s (6 soldats au moins, trois fois
  plus nombreux que les défenseurs ; un anneau montre l'avancée). En défense, la ville est sauvée après
  **5 min** de bataille, ou si l'assaut est repoussé (déroute ou retraite de l'ennemi).
- En **défense**, vos tireurs sont postés sur le chemin de ronde, l'infanterie derrière la porte et le
  rempart, la cavalerie sur la place ; vous vous déployez dans la ville. L'IA assaillante attend hors de
  portée des tours qu'une échelle soit dressée ou la porte enfoncée, puis marche sur la place. Elle
  **répartit ses échelles** (loin les unes des autres, là où le chemin de ronde est le moins garni), mène
  le bélier droit à la porte, fait tirer ses archers sur les défenseurs au-dessus de la porte pour le couvrir
  et renvoie un régiment reprendre un bélier abandonné. L'IA en garnison ne sort pas des murs, garde le
  débouché des échelles, tient la porte et charge ce qui entre.
- **Fiefs** : l'assaut d'un château et la défense de votre château assiégé se jouent aussi sur ces terrains.
- **Campagne** : environ un contrat sur huit à partir du niveau 2 est un siège (« Assiéger la place
  forte… » ou « Défendre les murs de… »), payé 60 % de plus ; la garnison a des archers de plus, ou
  l'assaillant un régiment de piquiers de plus. Sur la carte, la ligne d'objectif du contrat dit ce qu'il
  faut faire (tenir la place 20 s, ou tenir les murs 5 minutes).
  - Une ville **assiégée sur la carte** embauche des défenseurs contre l'assiégeant réel (« Saint-Aubin
    assiégée par la Baronnie ») : gagner **lève le siège**, et l'armée assiégeante, réduite à 40 %, rentre chez elle.
  - En guerre, un assaut vise une **ville voisine** tenue par l'ennemi (« Prendre Montfaucon à la Baronnie ») :
    le gagner donne la ville au patron du contrat. Sans voisine ennemie, c'est une place forte ou un bourg
    rebelle, sans effet sur la carte.

## IA ennemie
L'IA (`scripts/enemy_ai.gd`) choisit au début de chaque bataille un **plan** d'après le rapport de forces
(effectif × solidité × dégâts) et le terrain. Le tirage dépend de la graine : même bataille, même plan.
- **Agressif** : l'infanterie marche en colonne, se déploie en ligne et avance d'un même pas ; les archers
  tirent, depuis une colline s'il y en a une de leur côté ; la cavalerie contourne pour prendre à revers.
  Plus probable quand l'IA est la plus forte. À l'assaut d'une palissade, l'infanterie s'arrête à
  portée le temps que les archers tirent sur les défenseurs, puis donne l'assaut par les brèches.
- **Défensif** : l'armée tient une position (le sommet d'une **colline** avec l'infanterie sur le versant
  en avant, la lisière du **village**, sa **rive** de la rivière, sa palissade ou sa ligne de départ),
  ses archers tirent sans quitter leur poste et chaque régiment contre-charge ce qui l'approche sans
  poursuivre loin. Elle **contre-attaque** après quelques secondes de mêlée, si l'ennemi s'est affaibli,
  si les flèches lui coûtent trop sans combat, ou au bout d'environ 1 min 35 s sans assaut.
  Plus probable quand l'IA est la plus faible ; obligatoire si elle l'est nettement (rapport sous 0,65).
- **Débordement** : l'infanterie s'arrête à distance pour fixer l'ennemi, la cavalerie part tôt et large,
  ou s'**embusque dans un bois** sur le flanc adverse et en sort pour charger ce qui passe à portée.
  Choisi surtout s'il y a un bois propice ou si l'IA a plus de cavaliers.
- **Gués** : pour franchir la rivière, chaque régiment rejoint le gué le plus avantageux en colonne,
  sauf si le détour est bien plus long que de traverser à la nage.
- **Retraite en bon ordre** : quand il lui reste moins de 40 % de sa force et moins de 60 % de celle du
  joueur, l'IA sonne la retraite. Ses régiments reculent face à l'ennemi, la cavalerie couvre l'infanterie,
  et chacun quitte le champ par son bord au lieu de se faire détruire. La bataille est alors gagnée.
- Toujours : carré des piquiers contre une charge, course des hommes d'armes sur les derniers mètres,
  galop de la cavalerie en fin de charge, archers qui reculent derrière l'infanterie.
- Ajouter un type d'unité : une branche dans `think_regiment()` ; à défaut, le type est joué d'après
  ses capacités (tireur, monté, ou infanterie). Les requêtes de terrain (sommets, rives, gués) sont dans
  `terrain.gd`.

## Structure
```
scenes/menu.tscn        Menu principal (scène de départ)
scenes/tutorial.tscn    Tutoriel (bataille guidée)
scenes/campaign.tscn    Carte de campagne
scenes/end.tscn         Écran de fin de campagne (victoire ou game over, bilan)
scenes/main.tscn        Bataille (un seul nœud, tout est construit par le code)
scripts/campaign_state.gd  État de la campagne : or, jours, compagnie, villes, contrats
scripts/campaign_map.gd    Carte du monde en temps réel : rendu, caméra, mini-carte, jour et nuit, ordres de marche,
                        panneau (compagnie, ville, recrutement, contrats, rencontre, monde, journal)
scripts/map_data.gd     Géographie (MapData, seule source de vérité) : taille, lieux et leurs sortes, routes
                        (tracés, sortes, ponts), rivières, lacs, montagnes, forêts, régions, terrain sur une
                        grille, vitesse (speed_at), terrain de bataille (battle_terrain_at), chemins A*
scripts/map_render.gd   Rendu du fond de la carte (MapRender) : textures de champs, shader du terrain (et ses
                        saisons), pics, collines, routes, ponts, noms des régions et des lieux naturels
scripts/map_icons.gd    Figurines des groupes sur la carte (MapIcons) : caravane, villageois, patrouille, armée,
                        bandits, déserteurs, compagnie et sa bannière
scripts/map_sky.gd      Saisons, lumière et météo de la carte (MapSky) : mélange des saisons, jour et nuit,
                        brouillard, pluie et neige, lumières de la nuit (calques légers)
scripts/map_places.gd   Villes, châteaux et villages de la carte (MapPlaces) : taille, propriétaire et bannière,
                        fief de la compagnie à ses armoiries, camp d'un siège
scripts/portrait.gd     Portraits à graine (Portrait) : pièces, dessin, capitaine, compagnons, groupes rencontrés,
                        vue des panneaux
scripts/heraldry.gd     Armoiries de la compagnie (Heraldry) : tirage, validation, dessin, blason, section
                        « Armoiries » de l'onglet Compagnie
scripts/overworld.gd    Carte en temps réel sans rendu (Overworld) : heure, compagnie, registre des groupes,
                        contact et rencontres, fin de journée, population (plafonds, saisons, guerres,
                        déserteurs des batailles), sauvegarde
scripts/party.gd        Groupe de la carte (Party) : sorte, position, chemin, régiments, état
scripts/party_ai.gd     Comportements des groupes (PartyAI.think -> think_<sorte> : villageois, bandits,
                        caravanes, patrouilles, déserteurs) et combats entre groupes (skirmishes, fight)
scripts/end_screen.gd   Écran de fin : bilan, nouvelle campagne, retour au menu
scripts/main_menu.gd    Menu principal, page Options (rebind des touches), fond pixel art
scripts/game_options.gd Options (GameOptions) : volumes et bus audio, plein écran, taille de l'interface, vitesse, difficulté, touches, dernier réglage d'escarmouche
scripts/stats.gd        Statistiques globales et succès débloqués (Stats, statique), user://statistiques.json
scripts/achievements.gd Succès (Achievements) : liste, conditions, notification, observateur de bataille, page du menu
scripts/difficulty.gd   Niveaux de difficulté (Difficulty) : multiplicateurs ennemis, IA, économie
scripts/challenges.gd   Défis de campagne (Challenges) : Homme de fer, Sans cavalerie, Hiver éternel...
scripts/skirmish_setup.gd Escarmouche personnalisée (SkirmishSetup) : réglage, bornes, tirage, armées
scripts/ui_theme.gd     Thème des menus, placement des panneaux selon la taille de la vue
scripts/display_keys.gd Autoload DisplayKeys : Alt+Entrée / F11 (plein écran) partout, taille minimale de fenêtre
scripts/tutorial.gd     Tutoriel : hérite de battle.gd, armées réduites, étapes validées par les actions
scripts/campaign_guide.gd Tutoriel guidé de la première semaine de campagne (CampaignGuide) : étapes, panneau
scripts/map_pad.gd      Manette sur la carte de campagne (MapPad) : curseur, boutons, gâchettes, focus
scripts/tooltips.gd     Infobulles calculées (Tooltips) : équipement comparé, chances des contrats, compétences, terrain
scripts/battle.gd       Nœud de la bataille (classe Battle) : assemble simulation, rendu, ordres, caméra,
                        HUD, son, menu pause ; temps (pause, vitesse, ralenti), campagne et bilan
scripts/battle_sim.gd   Simulation sans rendu (BattleSim) : monde, armées, déplacements, mêlée, moral,
                        flèches, endurance, usure et relève, retraite, fin ; prévient le reste par des signaux
scripts/battle_weather.gd Météo de bataille (BattleWeather) : pluie, boue, brouillard, vent et leurs effets,
                        textes de la barre du haut et de l'aide
scripts/battle_renderer.gd  Rendu pixel art (BattleRenderer, nœud enfant) : sol, soldats, arbres, effets ;
                            silhouettes par type (piques, arcs longs, arbalètes et rechargement, lances,
                            harnois), quatre manières de tomber, étendards tombés des régiments brisés
scripts/battle_field.gd     Traces persistantes (BattleField) : armes et boucliers au sol (morts, fuyards),
                            flèches plantées, boue des mêlées, étendards tombés ; hasard à part, plafonds
scripts/battle_orders.gd    Saisie et ordres du joueur (BattleOrders) : sélection, groupes, ligne de front
scripts/battle_effects.gd   Effets visuels (BattleEffects) : sang, étincelles, éclat des charges, traînées des
                            flèches, fumée, éclaboussures, pluie au sol, étendards ; hasard à part, plafond
scripts/battle_camera.gd    Caméra (BattleCamera) : défilement (touches des Options), zoom entier compensant
                            la taille de l'interface, bornes, secousse
scripts/terrain.gd      Collines, rivière et gués, village, palissade : effets, passages, rendu du relief
scripts/siege_terrain.gd  Ville fortifiée (SiegeTerrain) : rempart, porte, tours, chemin de ronde, place, ouvertures
scripts/siege.gd        Vrai siège (Siege) : bélier, échelles, repoussage, huile et pierres, tours, prise de la place, fin, rendu
scripts/regiment.gd     Régiment : formation, moral, ordres
scripts/captain.gd      Capitaine (Captain) : niveaux, arbre de compétences (trois voies), blessure ; sur le champ : escorte, aura, mort
scripts/enemy_commander.gd Chef ennemi (EnemyCommander) : garde renforcée, recul, mort (moral), tête payée en campagne, dessin
scripts/battle_traps.gd Pièges du déploiement (BattleTraps) : budget, pose et retrait, pieux / fossé / chausse-trapes, dessin
scripts/traits.gd       Traits de régiment (Traits) et application des traits et de l'équipement aux stats
scripts/equipment.gd    Équipement des régiments (Equipment) : casque, armes, armure en trois qualités, améliorations
scripts/company_panel.gd Sections « Capitaine », « Officiers » et « Équipement » ; fenêtre de l'arbre du capitaine
scripts/officers.gd     Officiers (Officers) : compagnons à la tête des régiments, bonus, chute en bataille, suites
scripts/chronicle.gd    Chronique (Chronicle) : faits marquants de la campagne et récit de fin (écran de fin, Journal)
scripts/supplies.gd     Vivres, fatigue, marche forcée, camp et blessés graves (Supplies) ; effets en début de bataille
scripts/prisoners.gd    Prisonniers (Prisoners) : capture, rançon, enrôlement (rancœur), libération, évasions
scripts/companions.gd   Compagnons (Companions) : sergent, chirurgien, éclaireur, quartier-maître ; compétences, effets
scripts/life_panel.gd   Sections « Vivres et repos », « Prisonniers », « Compagnons » ; boutons Marche forcée et Camper
scripts/world_sim.gd    Monde vivant sans rendu (WorldSim) : saisons, météo, guerres, armées, sièges, prises
                        de villes, rencontres, contrats de guerre ; appelé par CampaignState (pass_day, travel)
scripts/encounter.gd    Rencontres de la carte (Encounter) : choix par sorte et attitude, résolution, accueil
scripts/encounter_panel.gd Panneau d'une rencontre (EncounterPanel) : choix numérotés, Échap, signal closed
scripts/world_army.gd   Armée de faction sur la carte (WorldArmy, une Party « army ») : marche, siège, sauvegarde
scripts/world_view.gd   Affichage du monde sur la carte (WorldView) : armées, sièges, section « Le pays »
scripts/soldier.gd      Soldat individuel
scripts/unit_types.gd   Statistiques et capacités des unités (seule source lue par la simulation)
scripts/battle_objectives.gd Objectifs de bataille (détruire, tenir, escorter, prendre, poursuivre) : victoire,
                        défaite, zone et chariots au sol, panneau du HUD, consignes à l'IA, bilan
scripts/enemy_ai.gd     IA ennemie

scripts/hud.gd          Interface
scripts/pause_menu.gd   Menu pause de la bataille (Échap)
scripts/battle_report.gd  Panneau du bilan de fin de bataille (données : battle.build_end_report), onglet Statistiques
scripts/battle_recorder.gd Relevés de la bataille pour le bilan : effectifs toutes les 2 s, lieux des morts, tués
scripts/minimap.gd      Mini-carte de bataille (dessinée par le HUD ; clic : battle_orders.gd)
scripts/save_preview.gd Aperçu des emplacements : en-tête à côté de la sauvegarde, miniature de la carte
scripts/sprite_bank.gd  Chargement et découpage des sprites (repli en code si absents), planches repeintes
                        selon l'équipement (casque, armure) et pointe des lames (éclat des armes)
scripts/battle_audio.gd Sons de bataille : banques, cors de charge et de retraite, fanfare, vent, oiseaux, pluie
scripts/game_audio.gd   Audio persistant (GameAudio) : musiques menu / carte / bataille / victoire / défaite
                        avec fondu enchaîné, sons d'interface branchés sur tous les boutons
assets/                 Sprites et sons (voir CREDITS.md)
tests/smoke_test.gd     Test automatique sans fenêtre
tests/campaign_test.gd  Test de la campagne (règles, vétérans, réputation, défaite, économie, évènements,
                        niveaux 1 à 5, pluriels, objectif et fin (victoire, ruine), deux batailles de
                        contrat, une retraite, bilan de fin de bataille, carte et embuscade, écrans de fin et menu)
tests/ai_test.gd        Test de l'IA (formations, course, colline, gués, défense, retraite, embuscade)
tests/objectives_test.gd Test des objectifs (détruire, tenir, escorter, prendre, poursuivre : IA, victoire,
                        défaite, panneau, bilan ; contrats de campagne et supplément de l'escorte)
tests/encounter_test.gd Test des rencontres : chaque sorte et chaque choix, contrat, pertes, butin, réputation,
                        fuite, sauvegarde, panneau (touches)
tests/encounter_capture.gd Captures du panneau de rencontre dans user://captures (avec fenêtre ; option --out)
tests/objectives_capture.gd Captures de chaque objectif en bataille (avec fenêtre ; option --out)

tests/menu_test.gd      Test du menu, des options (sauvegarde, rebind), du tutoriel complet et de sa proposition
tests/confort_test.gd   Test du confort : file d'ordres (enchaînée, remplacée), tutoriel guidé de campagne,
                        infobulles (différence d'équipement, chances des contrats), manette sur la carte
tests/interface_test.gd Test de l'interface de bataille : numéros fixes, aide, info-bulle, sous-titres,
                        touches de caméra, zoom et taille de l'interface, HUD et bilan à 150 %
tests/interface_capture.gd Captures de l'interface de bataille dans user://captures_interface/ (avec fenêtre)
tests/deploy_pause_test.gd  Test du déploiement (aucun combat, zone bleue) et du menu pause
tests/weather_test.gd   Test de la météo (pluie, boue, vent, brouillard, météo de campagne) et de la relève
tests/difficulty_test.gd Test de la difficulté (multiplicateurs, options, sauvegarde, bataille de contrat)
tests/skirmish_test.gd  Test de l'escarmouche préparée (armées, terrain, temps, options, menu) et des défis
                        de campagne (cavalerie refusée, hiver bloqué, sauvegarde unique, aller-retour)
tests/perf_test.gd      Test de performance (bataille à 2x les effectifs : temps d'étape et d'image)
tests/effects_test.gd   Test des effets visuels (même bataille quel que soit le niveau, plafond, option)
tests/effects_capture.gd Captures des effets (village sous la pluie, gué, mêlée, charge, équipement) (avec fenêtre ; option --out)
tests/field_test.gd     Test des traces de bataille (débris, flèches, boue plafonnés ; étendard tombé à la
                        déroute, relevé au ralliement ; manières de tomber ; rendu sans erreur)
tests/field_capture.gd  Captures des silhouettes, des morts, du champ après la mêlée et d'une déroute (avec fenêtre)
tests/visuals_test.gd   Test du rendu : équipement porté en bataille, planches repeintes, armoiries (sauvegarde),
                        bannières des factions, corps qui gardent leur régiment
tests/realm_test.gd     Test du domaine (commerce, fiefs et leurs sièges, allégeance, quêtes, sauvegarde, fenêtres)
tests/realm_capture.gd  Captures du domaine (marché de la ville, onglet Quêtes, fief) (avec fenêtre ; option --out)
tests/interface_plus_test.gd Test de la mini-carte (cadre, clic, glisser, touche N), des statistiques de
                        bataille (relevés, morts par camp, onglet du bilan), de l'aperçu des emplacements et
                        de la page Succès
tests/save_test.gd      Test de la sauvegarde (emplacements, migration, copie .bak, bataille en cours reprise,
                        mode indulgent, versions, menu des emplacements)
tests/chefs_pieges_test.gd Test du chef ennemi (garde, recul, mort et moral, prime) et des pièges (budget, pose en
                        déploiement seulement, pieux contre une charge, fossé, chausse-trapes, HUD, touche P)
tests/chefs_pieges_capture.gd Captures des pièges posés et du chef ennemi (avec fenêtre ; option --out)
tests/captain_test.gd   Test du capitaine (aura, ralliement, mort, blessure, niveaux), des traits, de l'équipement et de la sauvegarde v6
tests/officers_test.gd  Test des officiers (nomination, bonus, chute, mort ou blessure), de l'arbre du capitaine
                        (prérequis, coûts, effets), de la chronique (récit, Journal, écran de fin) et de la sauvegarde v14
tests/life_test.gd      Test des prisonniers, des vivres et de la fatigue, des blessés graves, des compagnons
                        (dont l'éclaireur sur la carte), de la sauvegarde v10, du début de bataille et des panneaux
tests/world_test.gd     Test du monde vivant (saisons, 200 jours sur 5 graines, prise d'une ville, contrats de
                        guerre, réputation, rencontre, bataille décisive chez son patron, contrats au nom du
                        maître actuel, sièges qui lèvent ou prennent une ville, terrain des rencontres,
                        sauvegarde, pluie en bataille, carte)
tests/overworld_test.gd Test de la carte en temps réel (MapData : lieux, routes hors des lacs, ponts, montagnes,
                        régions et factions des lieux, tout lieu accessible ; marche, vitesse sur et hors route, hiver, jour
                        qui passe, registre et errance, poursuite, bandits, armées, rencontres, sauvegarde v9 et
                        migration v8, scène : clics, pause, vitesses, rencontre, retour de bataille)
tests/party_ai_test.gd  Test des groupes de la carte : marché des villageois, chasse et fuite des bandits,
                        caravanes et escorte, patrouilles, déserteurs, peuplement, déterminisme, performances
tests/overworld_capture.gd Captures de la carte (ville, marche, nuit, rencontre, figurines des groupes, printemps,
                        automne, hiver, nuit d'hiver sous la neige, pluie, brouillard, lumières d'une ville la nuit)
                        dans user://captures (avec fenêtre ; option --out)
tests/map_capture.gd    Captures de la grande carte (vue éloignée, moyenne, rapprochée, montagnes, sud, hiver, automne,
                        nuit, pluie, fenêtre de la compagnie et ses armoiries ; avec fenêtre ; option --out)
tests/map_visuals_test.gd Test du rendu de la carte : armoiries (tirage, sauvegarde v10, relecture v9, réparation,
                        blason, boutons), saisons, nuit et brouillard, traces et sens de marche, shader et mini-carte
tests/places_test.gd    Test des lieux et portraits : portrait déterministe pour une graine, variété, surnoms,
                        stable après relecture ; taille des lieux, bannière qui change avec le propriétaire, fief,
                        sièges ; portraits dans l'onglet Compagnie et les rencontres
tests/places_capture.gd Captures des lieux (villes, siège, fief) et des portraits (planche, onglet Compagnie,
                        rencontre) ; avec fenêtre ; option --out
tests/audio_test.gd     Test de l'audio (chargement de tous les sons, bus, son coupé pendant les tests, fondu)
tests/screenshot.gd     Captures d'écran (avec fenêtre)
tests/terrain_shots.gd  Captures de chaque terrain (avec fenêtre ; option --out)
tests/skirmish_capture.gd Captures de la préparation d'escarmouche, des défis et de deux batailles préparées (avec fenêtre)
tests/menu_capture.gd   Captures du menu, des options, des emplacements (aperçus), des succès et du tutoriel
                        (avec fenêtre ; option --out)
tests/report_capture.gd Captures du bilan et de son onglet Statistiques (contrat avec promotions, escarmouche)
                        (avec fenêtre ; option --out)
tests/capture_dir.gd    Dossier de sortie commun des captures (--out=<dossier>, défaut user://captures)
tests/resolution_capture.gd Captures multi-résolution (menu, carte, fin, bataille, pause) dans user:// (avec fenêtre)
tests/balance.gd        Banc d'essai d'équilibrage (nombreuses batailles simulées)
tests/test_player.gd    Joueurs simulés utilisés par les tests
tests/campaign_balance.gd  Banc d'équilibrage de la campagne (campagnes entières jouées par un joueur simulé)
tests/campaign_player.gd   Joueur de campagne simulé (recrute, marche, choisit ses contrats, joue les batailles)
```

Pour ajouter à la bataille :
- une unité : une entrée dans `UnitTypes.STATS` (capacités `ranged`, `mounted`, `braces`, `armored`,
  `forest_speed`), une ligne dans `UnitTypes.bonus()`, ses sprites ; la simulation ne teste jamais le
  nom d'un type (l'IA et la campagne, si) ;
- un objectif de contrat : une classe qui étend `BattleObjectives.Objective` (`battle_objectives.gd` :
  `setup`, `step`, `check`, affichage, consignes à l'IA), une entrée dans `BattleObjectives.create()`, puis
  ses contrats dans `CampaignState.OBJECTIVES` ; `BattleSim.check_end()` l'interroge à chaque pas ;
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
(`.github/workflows/tests.yml`) télécharge Godot 4.7.2 et lance `tools/run_tests.sh` à chaque push ;
`.github/workflows/release.yml` publie les archives à chaque étiquette de version (voir « Exporter le jeu »).

Un test à la fois :
```
godot --headless --path . -s tests/smoke_test.gd      # bataille accélérée, code de sortie 1 si échec
godot --headless --path . -s tests/smoke_test.gd -- --terrain=siege   # idem sur un terrain imposé
                                                      # (plain, forest, hills, river, village, siege, random)
godot --headless --path . -s tests/campaign_test.gd   # campagne : règles, niveaux, fin, batailles, sauvegarde, carte
godot --headless --path . -s tests/ai_test.gd         # IA : formations, carré, colline, gués, défense, retraite, embuscade
godot --headless --path . -s tests/menu_test.gd       # options, rebind, menu, tutoriel parcouru étape par étape
godot --headless --path . -s tests/confort_test.gd    # file d'ordres, tutoriel guidé, infobulles, manette
godot --headless --path . -s tests/interface_test.gd  # interface de bataille, accessibilité, caméra
godot --headless --path . -s tests/interface_plus_test.gd  # mini-carte, statistiques du bilan, aperçus, succès
godot --headless --path . -s tests/deploy_pause_test.gd   # déploiement sans combat, menu pause, abandon = retraite
godot --headless --path . -s tests/weather_test.gd    # pluie, boue, brouillard, vent ; usure, relève, repli, IA
godot --headless --path . -s tests/difficulty_test.gd # difficulté : ennemis, IA, prix, sauvegarde
godot --headless --path . -s tests/skirmish_test.gd   # escarmouche préparée et défis de campagne
godot --headless --path . -s tests/perf_test.gd      # performance à 2x les effectifs (--factor=K, --out=<fichier.json>)
godot --headless --path . -s tests/stats_test.gd      # statistiques et succès (fichier de test, jamais le vrai)
godot --headless --path . -s tests/save_test.gd       # sauvegarde : emplacements, .bak, bataille en cours, indulgent
godot --headless --path . -s tests/world_test.gd      # monde vivant : saisons, guerres, armées, sièges, sauvegarde
godot --headless --path . -s tests/overworld_test.gd  # carte en temps réel : marche, terrain, jour, groupes, rencontres
godot --headless --path . -s tests/party_ai_test.gd   # groupes de la carte : comportements, peuplement, déterminisme
godot --path . --resolution 1280x720 -s tests/overworld_capture.gd   # carte_ville/marche/nuit/rencontre.png
godot --headless --path . -s tests/siege_test.gd      # sièges : rempart, bélier, échelles, assaut gagné, défense tenue, hauteur,
                                                      # huile et pierres, bélier repris, fiefs, campagne
godot --path . -s tests/siege_capture.gd              # siege_assaut*.png, siege_defense*.png (fenêtre)
godot --path . -s tests/menu_capture.gd               # menu.png, menu_options.png, menu_emplacements.png, menu_succes.png, tutoriel.png
godot --headless --path . -s tests/encounter_test.gd  # rencontres de la carte : choix, bataille, réputation, fuite
godot --headless --path . -s tests/places_test.gd    # lieux de la carte (bannières, sièges) et portraits à graine
godot --path . --resolution 1280x720 -s tests/places_capture.gd   # lieux_*.png, portraits_*.png
godot --path . -s tests/encounter_capture.gd          # rencontre_villageois.png, rencontre_bandits.png
godot --path . -s tests/report_capture.gd             # bilan_campagne(_stats).png, bilan_escarmouche(_stats).png
godot --headless --path . -s tests/site_test.gd       # champ tiré de la carte (rivière et pont, route, village...) et alliés
godot --path . -s tests/site_capture.gd               # site_pont.png, site_allies.png (fenêtre)
godot --path . --resolution 2560x1080 -s tests/resolution_capture.gd   # captures user://captures_resolution/ (-- --ui=1.5 : interface à 150 %)
godot --path . --resolution 1280x720 -s tests/interface_capture.gd -- --ui=1.5   # captures user://captures_interface/
godot --path . -s tests/screenshot.gd                 # captures dans le dossier user:// du projet
godot --headless --path . -s tests/balance.gd -- --seeds=10   # taux de victoire et durée par stratégie
godot --headless --path . -s tests/balance.gd -- --seeds=10 --terrain=all   # idem, terrain par terrain
godot --headless --path . -s tests/balance.gd -- --seeds=20 --difficulty=all # idem, par difficulté
godot --headless --path . -s tests/campaign_bench_test.gd  # mini-cas du banc de campagne (dans run_tests)
godot --headless --path . -s tests/campaign_balance.gd -- --seeds=8 --difficulty=all   # campagnes entières (long)
godot --path . -s tests/terrain_shots.gd              # terrain_*.png
godot --headless --path . -s tests/effects_test.gd    # effets visuels : déterminisme, plafond, option
godot --headless --path . -s tests/visuals_test.gd    # équipement visible, armoiries, bannières, corps
godot --headless --path . -s tests/field_test.gd      # traces de bataille : plafonds, étendard tombé, morts
godot --path . -s tests/field_capture.gd              # champ_silhouettes.png, champ_morts.png, champ_melee.png, champ_deroute.png
godot --path . -s tests/effects_capture.gd            # effets_village.png, effets_gue.png, effets_melee.png, effets_charge.png, effets_equipement.png
godot --path . -s tests/menu_capture.gd -- --out=captures   # met à jour les captures versionnées du dépôt
```
Les scripts de capture (`menu_capture`, `report_capture`, `terrain_shots`, `effects_capture`, `field_capture`) écrivent par défaut dans
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
La version (`application/config/version` dans `project.godot`, actuellement 0.7.0) s'affiche en bas à
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

### Publication automatique sur GitHub
Le workflow `.github/workflows/release.yml` se déclenche quand on pousse une étiquette `vX.Y.Z` :
il vérifie que l'étiquette correspond à `config/version` de `project.godot`, télécharge Godot 4.7.2 et
ses modèles d'export, lance les tests, exporte Windows et Linux, puis crée la publication GitHub
(onglet *Releases*) avec `CompagnieFranche-<version>-windows.zip` et `-linux.zip`. Si les tests échouent,
rien n'est publié. Pour publier une version :
1. changez `config/version` dans `project.godot` et committez ;
2. étiquetez et poussez :
   ```
   git tag v0.7.1
   git push origin main v0.7.1
   ```
On peut aussi le relancer à la main (onglet *Actions* → *Publication* → *Run workflow*, avec l'étiquette) :
les archives d'une publication existante sont alors remplacées.

## Équilibrage
Réglages dans `scripts/unit_types.gd` (statistiques, moral, charge) et `scripts/enemy_ai.gd`.
Objectif : une bataille dure 2 à 4 minutes ; l'ennemi a plus d'infanterie (8 régiments contre 8,
mais 5 d'infanterie contre 4) et une seule cavalerie, le joueur doit donc manœuvrer pour gagner.

Banc d'essai par terrain (10 à 20 graines, victoires du joueur « tactique » / « naïf ») : état de départ
4/10 et 4/10 ; rase campagne 2/10 et 2/10 ; bois 4/10 et 4/10 ; collines 6/10 et 3/10 ; rivière 3/10 et 2/10 ;
village 6/10 et 3/10 ; palissade 11/20 et 10/20. Toutes les batailles se terminent (aucune bloquée).
Les écarts restent dans le bruit d'une série de 10 batailles.

IA qui utilise le terrain (`balance.gd -- --seeds=10 --terrain=all`, normal, joueur « tactique ») : avant 29/60
(48 %) : plaine 4, bois 5, collines 5, rivière 6, village 1, palissade 8. Après 22/60 (37 %) : plaine 4,
bois 1, collines 6, rivière 4, village 2, palissade 5. Le banc affiche aussi les plans choisis et les retraites :
le plan défensif est le plus dur à battre pour ce joueur simulé, l'embuscade en forêt aussi (il ne voit pas
les troupes cachées). L'objectif est de garder le joueur tactique entre 25 et 40 % en normal.

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

### Campagne (banc `tests/campaign_balance.gd`)

Vivres, prisonniers et compagnons (version 10) : le joueur simulé achète 12 jours de vivres et rançonne ses
prisonniers à chaque passage en ville. Normal, mode rapide, graines 1 à 20 : **6/20** campagnes gagnées,
contre **7/20** pour la version d'avant mesurée le même jour sur les mêmes graines (écart dans le bruit du banc).
Un joueur de campagne simulé (`tests/campaign_player.gd`) joue des campagnes entières, sans fenêtre : il lève
des régiments (4 fantassins, 3 tireurs, 1 cavalier visés ; le plus fort qu'il peut payer, en gardant 8 jours
de solde), marche vers le contrat qui paie le mieux par jour de marche parmi ceux qu'il peut gagner (force
estimée d'au moins 1,15 fois celle de l'ennemi, seuil qui baisse quand il reste sans contrat ou sans or),
livre ou fuit les armées rencontrées et attend d'être prêt pour la bataille décisive. Les batailles sont
jouées par la vraie simulation, en accéléré, par le joueur tactique de `tests/test_player.gd` (qui suit
aussi l'objectif du contrat : tenir, prendre, escorter, poursuivre) ; il sonne la retraite quand la bataille
est perdue. Une campagne dure de 3 à 10 minutes de calcul.
```
godot --headless --path . -s tests/campaign_balance.gd -- --seeds=8 --difficulty=all [--days=240] [--fast]
godot --headless --path . -s tests/campaign_balance.gd -- --first=3 --seeds=1 --difficulty=hard --out=user://banc.jsonl
godot --headless --path . -s tests/campaign_balance.gd -- --merge=<f1.jsonl>,<f2.jsonl>   # rapport commun
```
`--fast` résout les batailles ordinaires par un modèle calibré sur les vraies (la bataille décisive reste
jouée) : 60 campagnes en 10 à 20 minutes, mais moins fidèle (réglages actuels, graines 1 à 20 : 19/20 en
facile, 11/20 en normal, 1/20 en difficile, contre 19/20, 14/20 et 0/20 en vraies batailles). `--trace` raconte chaque décision. Pour aller vite,
lancer un processus par graine et par difficulté avec `--out`, puis `--merge`. Le rapport donne, par
difficulté : le taux de victoire, les causes d'échec, les jours jusqu'à l'offre et jusqu'à la bataille
décisive, les courbes d'or, de renommée et d'effectifs (tous les 20 jours), et l'issue des vraies batailles
selon le rapport de force estimé et selon leur sorte. `tests/campaign_bench_test.gd` (dans `run_tests.ps1`)
en joue un mini-cas : 60 jours en mode rapide, puis une vraie bataille de contrat.

Mesures (vraies batailles, limite de 240 jours ; avant : graines 1 à 8, après : graines 1 à 20, par difficulté) :

| | Facile avant | Facile après | Normal avant | Normal après | Difficile avant | Difficile après |
|---|---|---|---|---|---|---|
| Campagnes gagnées | 2/8 (25 %) | **19/20 (95 %)** | 0/8 | **14/20 (70 %)** | 0/8 | **0/20** |
| Causes d'échec | ruine 5, décisive perdue 1 | ruine 1 | ruine 8 | ruine 6 | ruine 8 | ruine 20 |
| Bataille décisive proposée (jour médian) | 6/8 (50) | 20/20 (28) | 1/8 (37) | 16/20 (37) | 0/8 | 5/20 (48) |
| Première décisive (jour médian) | 5/8 (72) | 19/20 (42) | 1/8 (55) | 16/20 (55) | — | 3/20 (72) |
| Décisives gagnées / livrées | 2/15 | 19/22 | 0/1 | 14/29 | — | 0/5 |
| Jour moyen de la victoire | 144 | 45 | — | 74 | — | — |

Courbes en normal (moyenne des campagnes en cours) : avant, jour 20 : 1 384 écus, renommée 83, 127 hommes ;
jour 40 : 708 écus, 104, 128 hommes ; jour 60 : 94 écus, 109, 57 hommes (la compagnie se ruine au pied du
niveau 3). Après, jour 20 : 2 721 écus, 98, 122 hommes ; jour 40 : 4 806 écus, 157, 120 hommes ; jour 60 :
4 097 écus, 163, 99 hommes. En difficile, l'or plafonne vers 1 100 écus et la compagnie fond après le
jour 60 (78 hommes, puis 53 au jour 80).

Ce qui bloquait : à 8 régiments au plus, la compagnie ne battait plus les armées de 9 régiments du niveau 3
(70 % d'aguerris, 30 % de vétérans) ; elle errait sans contrat à sa portée et se ruinait en soldes. La
bataille décisive (11 régiments, 90 % de vétérans) restait hors de portée, même en facile. Corrections (N6) :
- armées plus petites, régiment de couleur compris : 6, 8, 8 et 9 régiments aux niveaux 2 à 5 (au lieu de 7,
  9, 10 et 11), souvent entamées, et moins de vétérans (niveau 4 : 15 %, niveau 5 : 20 %, au lieu de 55 et 80 %) ;
- bataille décisive : 9 régiments au lieu de 11 (dont deux de chevaliers à pied), entamés (75 à 90 %),
  50 % d'aguerris et 30 % de vétérans au lieu de 90 % de vétérans ;
- nouvelle valeur de difficulté `enemy_veterans` (facile 0,4, normal 0,7, difficile 1) : la part des
  vétérans des armées de contrat qui le restent, les autres sont aguerris (`Difficulty.enemy_ranks`).
L'économie ne bloque plus en facile et en normal : l'or monte jusqu'à la bataille décisive, qu'on peut
retenter (une sur deux est gagnée en normal). Par rapport à la cible (la plupart en facile, une sur deux en
normal, rarement en difficile), le normal reste un peu facile (70 %) et le difficile trop dur (0/20) : les
compagnies s'y ruinent aux niveaux 3 et 4, avant même l'offre. Leviers suivants : `enemy_veterans` et les
primes en difficile, ou une décisive un peu plus forte en normal. Le régiment allié prêté par le patron n'a
pas été nécessaire. Sur 10 campagnes, le hasard fait varier le taux de victoire de 15 à 30 points (mêmes
graines, réglages presque identiques : normal 6/10 puis 9/10) : mesurer sur 20 graines au moins.

## Pistes pour continuer
- Sièges : brancher la prise de la place sur les objectifs de contrat, tours prenables, sapes, engins de jet,
  ordre au joueur de verser l'huile lui-même.
- D'autres types d'unités (piquiers suisses, vétérans d'élite par faction) ; vrais sprites pour les arbalétriers,
  chevaliers à pied et archers montés (ils reprennent aujourd'hui une planche MiniWorld teintée).
