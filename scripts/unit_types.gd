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
##   « forest_speed » : facteur de vitesse en forêt.

const STATS := {
	"men_at_arms": {
		"name": "Hommes d'armes",
		"count": 16, "cols": 8, "spacing": 12.0,
		"hp": 54.0, "damage": 2.0, "cooldown": 1.1, "reach": 10.0,
		"speed": 40.0, "arrow_armor": 0.35, "morale": 100.0,
		"ranged": false, "radius": 5.2,
		"mounted": false, "braces": false, "armored": true, "forest_speed": 0.65,
	},
	"spear": {
		"name": "Piquiers",
		"count": 20, "cols": 10, "spacing": 11.0,
		"hp": 36.0, "damage": 1.5, "cooldown": 1.0, "reach": 14.0,
		"speed": 44.0, "arrow_armor": 0.7, "morale": 85.0,
		"ranged": false, "radius": 4.8,
		"mounted": false, "braces": true, "armored": false, "forest_speed": 0.65,
	},
	"archer": {
		"name": "Archers",
		"count": 16, "cols": 8, "spacing": 12.0,
		"hp": 21.0, "damage": 0.9, "cooldown": 1.0, "reach": 10.0,
		"speed": 48.0, "arrow_armor": 1.0, "morale": 65.0,
		"ranged": true, "range": 340.0, "reload": 2.4, "ranged_damage": 2.6,
		"radius": 4.8,
		"mounted": false, "braces": false, "armored": false, "forest_speed": 0.65,
	},
	"cavalry": {
		"name": "Cavaliers",
		"count": 10, "cols": 5, "spacing": 18.0,
		"hp": 48.0, "damage": 2.0, "cooldown": 1.2, "reach": 14.0,
		"speed": 104.0, "arrow_armor": 0.6, "morale": 90.0,
		"ranged": false, "radius": 8.0,
		"mounted": true, "braces": false, "armored": true, "forest_speed": 0.4,
	},
}

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
	if attacker == "cavalry" and defender == "archer":
		return 2.0
	if attacker == "cavalry" and defender == "spear":
		return 0.6
	if attacker == "men_at_arms" and defender == "spear":
		return 1.4
	if attacker == "archer":
		return 0.8
	return 1.0
