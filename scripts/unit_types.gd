class_name UnitTypes
extends RefCounted
## Statistiques de chaque type d'unité. Modifiez ces valeurs pour équilibrer le jeu.
## Distances en pixels du monde (un soldat fait environ 16 px de haut).
##
## C'est la seule source des statistiques : la simulation (battle_sim.gd) ne teste jamais le nom
## d'un type, elle lit ses capacités ici. Pour ajouter une unité : une entrée dans STATS (avec
## toutes les clés ci-dessous), une ligne dans bonus() si elle a des avantages, ses sprites
## (sprite_bank.gd) et, à défaut, son dessin de repli et son pictogramme (battle_renderer.gd).
## L'IA (enemy_ai.gd) et la campagne choisissent encore leurs régiments par nom de type.
##
## Capacités :
##   « ranged » : tire des flèches (« range », « reload », « ranged_damage »), se place derrière ;
##   « mounted » : charge (élan), poursuit les fuyards, soulève de la poussière, se place sur les ailes ;
##   « braces » : plante ses piques (blesse le cheval qui charge, moitié moins de peur d'une charge) ;
##   « armored » : les coups reçus sonnent sur le métal (bruitage « clash ») ;
##   « forest_speed » : facteur de vitesse en forêt ;
##   « pierce » : part de l'armure ignorée par ses traits (0 = aucune, 1 = toute : carreaux d'arbalète) ;
##   « pavise » : facteur des traits reçus de face quand le régiment tient sa place (1 = sans pavois) ;
##   « steadfast » : inébranlable (moitié moins de moral perdu sur un flanc, dans le dos ou sous une
##                   charge, et ne recule pas sous le choc) ;
##   « skirmish » : tirailleur monté (tire en marchant, décroche seul quand la mêlée approche,
##                  ne charge pas). Un tireur monté (« ranged » + « mounted ») se place sur les ailes.

const STATS := {
	"men_at_arms": {
		"name": "Hommes d'armes",
		"count": 16, "cols": 8, "spacing": 12.0,
		"hp": 54.0, "damage": 2.0, "cooldown": 1.1, "reach": 10.0,
		"speed": 40.0, "arrow_armor": 0.35, "morale": 100.0,
		"ranged": false, "radius": 5.2,
		"mounted": false, "braces": false, "armored": true, "forest_speed": 0.65,
		"pierce": 0.0, "pavise": 1.0, "steadfast": false, "skirmish": false,
	},
	"spear": {
		"name": "Piquiers",
		"count": 20, "cols": 10, "spacing": 11.0,
		"hp": 36.0, "damage": 1.5, "cooldown": 1.0, "reach": 14.0,
		"speed": 44.0, "arrow_armor": 0.7, "morale": 85.0,
		"ranged": false, "radius": 4.8,
		"mounted": false, "braces": true, "armored": false, "forest_speed": 0.65,
		"pierce": 0.0, "pavise": 1.0, "steadfast": false, "skirmish": false,
	},
	"archer": {
		"name": "Archers",
		"count": 16, "cols": 8, "spacing": 12.0,
		"hp": 21.0, "damage": 0.9, "cooldown": 1.0, "reach": 10.0,
		"speed": 48.0, "arrow_armor": 1.0, "morale": 65.0,
		"ranged": true, "range": 340.0, "reload": 2.4, "ranged_damage": 2.6,
		"radius": 4.8,
		"mounted": false, "braces": false, "armored": false, "forest_speed": 0.65,
		"pierce": 0.0, "pavise": 1.0, "steadfast": false, "skirmish": false,
	},
	"cavalry": {
		"name": "Cavaliers",
		"count": 10, "cols": 5, "spacing": 18.0,
		"hp": 48.0, "damage": 2.0, "cooldown": 1.2, "reach": 14.0,
		"speed": 104.0, "arrow_armor": 0.6, "morale": 90.0,
		"ranged": false, "radius": 8.0,
		"mounted": true, "braces": false, "armored": true, "forest_speed": 0.4,
		"pierce": 0.0, "pavise": 1.0, "steadfast": false, "skirmish": false,
	},
	"crossbow": {
		"name": "Arbalétriers",
		"count": 16, "cols": 8, "spacing": 12.0,
		"hp": 28.0, "damage": 1.0, "cooldown": 1.1, "reach": 10.0,
		"speed": 42.0, "arrow_armor": 0.8, "morale": 70.0,
		"ranged": true, "range": 270.0, "reload": 5.0, "ranged_damage": 4.6,
		"radius": 4.8,
		"mounted": false, "braces": false, "armored": false, "forest_speed": 0.65,
		"pierce": 0.6, "pavise": 0.4, "steadfast": false, "skirmish": false,
	},
	"foot_knight": {
		"name": "Chevaliers à pied",
		"count": 12, "cols": 6, "spacing": 12.0,
		"hp": 80.0, "damage": 2.8, "cooldown": 1.2, "reach": 11.0,
		"speed": 34.0, "arrow_armor": 0.2, "morale": 140.0,
		"ranged": false, "radius": 5.4,
		"mounted": false, "braces": false, "armored": true, "forest_speed": 0.6,
		"pierce": 0.0, "pavise": 1.0, "steadfast": true, "skirmish": false,
	},
	"horse_archer": {
		"name": "Archers montés",
		"count": 10, "cols": 5, "spacing": 18.0,
		"hp": 30.0, "damage": 0.9, "cooldown": 1.2, "reach": 12.0,
		"speed": 98.0, "arrow_armor": 0.85, "morale": 70.0,
		"ranged": true, "range": 250.0, "reload": 2.6, "ranged_damage": 1.9,
		"radius": 8.0,
		"mounted": true, "braces": false, "armored": false, "forest_speed": 0.4,
		"pierce": 0.0, "pavise": 1.0, "steadfast": false, "skirmish": true,
	},
}

## Ordre d'affichage des types (recrutement, résumés d'armée).
const ORDER := ["spear", "men_at_arms", "foot_knight", "archer", "crossbow", "cavalry", "horse_archer"]

## Tirailleurs montés (« skirmish ») : distance à laquelle ils décrochent devant la mêlée,
## durée d'un décrochage et précision du tir en marchant.
const SKIRMISH_DIST := 170.0
const SKIRMISH_TIME := 1.6
const SKIRMISH_SPREAD := 1.6 ## Dispersion des flèches tirées en mouvement (x)

## Moral : pertes et récupération (en points ; un régiment fuit à 0).
const MORALE_PER_DEATH := 130.0 ## Perte totale si tout le régiment mourait (répartie par soldat)
const MORALE_REAR_HIT := 0.5 ## Par coup reçu dans le dos
const MORALE_FLANK_HIT := 0.2 ## Par coup reçu sur le flanc
const MORALE_ARROW_HIT := 0.3 ## Par flèche reçue
const MORALE_CHARGE_HIT := 2.0 ## Par coup de cavalerie lancée (moitié contre les piquiers)
const MORALE_AMBUSH := 15.0 ## Choc d'une embuscade sortie d'une forêt
const MORALE_ROUT_NEARBY := 8.0 ## Quand un régiment allié proche fuit
const MORALE_REGEN := 1.5 ## Par seconde, hors mêlée
const MORALE_RALLY_REGEN := 6.0 ## Par seconde, en fuite loin de l'ennemi

## Formations (touche F).
const COLUMN_WIDTH := 3 ## Soldats de front en colonne
const FORMATION_SPEED := [1.0, 1.15, 0.55] ## Vitesse en ligne, en colonne, en carré

## Course (double clic droit) et endurance, de 0 (épuisé) à 1 (frais).
const RUN_SPEED := 1.6 ## Vitesse en course
const RUN_DRAIN := 0.075 ## Endurance perdue par seconde de course (environ 13 s depuis frais)
const FIGHT_DRAIN := 0.006 ## Par seconde de mêlée
const WALK_REGEN := 0.01 ## Récupération par seconde de marche
const REST_REGEN := 0.04 ## Récupération par seconde au repos
const RUN_MIN_STAMINA := 0.15 ## En dessous, le régiment refuse de courir
const STAMINA_TIRED := 0.6 ## Les pénalités commencent sous ce seuil
const EXHAUSTED_SPEED := 0.6 ## Vitesse d'un régiment épuisé (endurance nulle)
const EXHAUSTED_DAMAGE := 0.6 ## Dégâts d'un régiment épuisé (endurance nulle)
## Usure au contact et relève
const CONTACT_WEAR := 30.0 ## Toutes les 30 s de mêlée continue, l'endurance fond une fois plus vite...
const CONTACT_WEAR_MAX := 2.0 ## ... jusqu'à 3 fois la perte de départ
const EXHAUSTED_MORALE := 0.5 ## Moral perdu par seconde de mêlée par un régiment à bout de forces
const EXHAUSTED_MORALE_AT := 0.15 ## ... sous cette endurance
const REST_MORALE := 1.5 ## Moral regagné en plus par seconde au repos, loin de l'ennemi
const REST_SAFE := 250.0 ## « Loin de l'ennemi » : aucun régiment adverse à moins de ça
const RELIEF_BACK := 260.0 ## Le régiment relevé recule de ça derrière la ligne
const RELIEF_TIME := 15.0 ## Décrochage : temps maximal pendant lequel il ne cherche plus le contact
const REST_TIME := 20.0 ## Repos après une relève (l'IA ne le renvoie pas au combat avant)


## Multiplicateur dû à la fatigue : 1 au-dessus de STAMINA_TIRED, puis décroît jusqu'à at_zero.
static func fatigue_factor(stamina: float, at_zero: float) -> float:
	return lerpf(at_zero, 1.0, clampf(stamina / STAMINA_TIRED, 0.0, 1.0))

## Charge de cavalerie.
const CHARGE_BONUS := 1.8 ## Dégâts de cavalerie lancée : x (1 + élan x CHARGE_BONUS)
const BRACE_DAMAGE := 3.5 ## Blessure infligée au cheval qui charge des piques

## Multiplicateur de dégâts au corps à corps (pierre-feuille-ciseaux).
static func bonus(attacker: String, defender: String) -> float:
	if attacker == "spear" and defender == "cavalry":
		return 2.0
	if attacker == "spear" and defender == "horse_archer":
		return 1.5
	if attacker == "cavalry" and (defender == "archer" or defender == "crossbow"):
		return 2.0
	if attacker == "cavalry" and defender == "horse_archer":
		return 1.5
	if attacker == "cavalry" and defender == "spear":
		return 0.6
	if attacker == "cavalry" and defender == "foot_knight":
		return 0.7 # Des chevaliers en armure de plates ne se laissent pas bousculer
	if (attacker == "men_at_arms" or attacker == "foot_knight") and defender == "spear":
		return 1.4
	if attacker == "archer" or attacker == "crossbow":
		return 0.8
	if attacker == "horse_archer":
		return 0.7
	return 1.0
