class_name Difficulty
extends RefCounted
## Niveaux de difficulté : facile, normal, difficile. Toutes les valeurs sont ici.
##  - Escarmouche : réglée dans les Options (GameOptions.difficulty, sauvegardée).
##  - Campagne : choisie à « Nouvelle campagne » (CampaignState.difficulty, dans la sauvegarde).
## Les multiplicateurs « enemy_* » s'appliquent à l'armée ennemie au moment du déploiement
## (battle.gd), les « ai_* » à l'IA (enemy_ai.gd), les autres à l'économie de campagne.

const EASY := "easy"
const NORMAL := "normal"
const HARD := "hard"
const IDS: Array[String] = [EASY, NORMAL, HARD]

const LEVELS := {
	EASY: {
		"name": "Facile",
		"hint": "Ennemis moins nombreux et plus fragiles, IA lente. Recrues et solde moins chères, primes plus fortes.",
		"enemy_men": 0.8, ## Effectif de chaque régiment ennemi (part de l'effectif prévu)
		"enemy_morale": 0.8, ## Moral maximal des ennemis
		"enemy_damage": 0.9, ## Dégâts des ennemis (mêlée et flèches)
		"ai_think": 1.6, ## Intervalle de réflexion de l'IA, en secondes (plus long = moins réactive)
		"ai_advance": 25.0, ## Délai avant que l'IA ne marche sur le joueur, en secondes
		"ai_cavalry_wait": 40.0, ## Délai avant que la cavalerie ennemie ne quitte la réserve
		"ai_square": false, ## Les piquiers ennemis forment le carré contre la cavalerie
		"recruit": 0.8, ## Prix de recrutement
		"wage": 0.8, ## Solde quotidienne
		"reward": 1.25, ## Primes des contrats
	},
	NORMAL: {
		"name": "Normal",
		"hint": "L'expérience prévue.",
		"enemy_men": 1.0,
		"enemy_morale": 1.0,
		"enemy_damage": 1.0,
		"ai_think": 0.8,
		"ai_advance": 12.0,
		"ai_cavalry_wait": 20.0,
		"ai_square": true,
		"recruit": 1.0,
		"wage": 1.0,
		"reward": 1.0,
	},
	HARD: {
		"name": "Difficile",
		"hint": "Ennemis plus tenaces et plus durs au combat, IA vive. Recrues et solde plus chères, primes réduites.",
		"enemy_men": 1.0,
		"enemy_morale": 1.15,
		"enemy_damage": 1.1,
		"ai_think": 0.5,
		"ai_advance": 8.0,
		"ai_cavalry_wait": 15.0,
		"ai_square": true,
		"recruit": 1.2,
		"wage": 1.2,
		"reward": 0.85,
	},
}


## Identifiant valide (une valeur inconnue ou vide redevient « normal »).
static func sanitize(id: String) -> String:
	return id if LEVELS.has(id) else NORMAL


static func level(id: String) -> Dictionary:
	return LEVELS[sanitize(id)]


static func value(id: String, key: String) -> float:
	return float(level(id)[key])


static func display_name(id: String) -> String:
	return str(level(id)["name"])


static func hint(id: String) -> String:
	return str(level(id)["hint"])


## Effectif d'un régiment ennemi après application de la difficulté (au moins un homme).
static func enemy_men(id: String, men: int) -> int:
	return maxi(1, int(round(men * value(id, "enemy_men"))))
