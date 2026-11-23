class_name SkirmishSetup
extends RefCounted
## Escarmouche personnalisée : réglage choisi dans l'écran de préparation du menu principal
## (main_menu.gd, page « skirmish ») et mémorisé dans les options (GameOptions.skirmish).
##
## Réglage (types simples, pour l'enregistrer tel quel) :
##   {"player": {type: {"n", "rank", "gear"}}, "enemy": {...},   (n régiments par type, rang 0 à 2,
##                                                                qualité d'équipement 0 à 3)
##    "terrain": "random" ou une clé de Terrain.KINDS, "weather": "random" / "clear" / "rain",
##    "season": "random" ou une clé de SEASONS, "hour": "random" ou une clé de HOURS,
##    "difficulty": clé de Difficulty.IDS}
## resolve() tire au sort ce qui est « au hasard » et rend les réglages de la bataille, que le
## menu dépose dans « pending » ; battle.gd les lit au lancement d'une bataille hors campagne
## (ils restent posés : « Recommencer » rejoue la même escarmouche).

const RANDOM := "random"
const MAX_PER_TYPE := 6 ## Régiments d'un même type au plus
const MAX_REGIMENTS := 12 ## Régiments d'une armée au plus
const SEASONS := ["spring", "summer", "autumn", "winter"] ## Dans l'ordre de WorldSim.SEASONS
const SEASON_NAMES := {"spring": "Printemps", "summer": "Été", "autumn": "Automne", "winter": "Hiver"}
const HOURS := {"dawn": 6.0, "day": 13.0, "dusk": 19.0, "night": 23.0} ## Heure de la bataille
const HOUR_IDS := ["dawn", "day", "dusk", "night"]
const HOUR_NAMES := {"dawn": "Aube", "day": "Plein jour", "dusk": "Crépuscule", "night": "Nuit"}
const WEATHERS := ["clear", "rain", "fog", "wind"]
const WEATHER_NAMES := {"clear": "Temps clair", "rain": "Pluie", "fog": "Brouillard", "wind": "Vent fort"}
const RANK_NAMES := ["Recrues", "Aguerris", "Vétérans"]
const GEAR_NAMES := ["Aucun", "Simple", "Bon", "De maître"]

## Réglages de la prochaine escarmouche (resolve), vides : escarmouche par défaut.
static var pending: Dictionary = {}


## Réglage par défaut : les armées de l'escarmouche classique (BattleSim.spawn_default_armies).
static func default_config() -> Dictionary:
	return {
		"player": {"spear": {"n": 2, "rank": 0, "gear": 0}, "men_at_arms": {"n": 2, "rank": 0, "gear": 0},
			"archer": {"n": 2, "rank": 0, "gear": 0}, "cavalry": {"n": 2, "rank": 0, "gear": 0}},
		"enemy": {"spear": {"n": 3, "rank": 0, "gear": 0}, "men_at_arms": {"n": 2, "rank": 0, "gear": 0},
			"archer": {"n": 2, "rank": 0, "gear": 0}, "cavalry": {"n": 1, "rank": 0, "gear": 0}},
		"terrain": RANDOM, "weather": "clear", "season": "summer", "hour": "day",
		"difficulty": Difficulty.sanitize(GameOptions.difficulty), # Celle des options
	}


static func _pick(v: Variant, allowed: Array, fallback: String) -> String:
	var s := str(v)
	return s if s == RANDOM or s in allowed else fallback


## Réglage relu (options, fichier modifié à la main) : valeurs hors bornes corrigées.
static func sanitize(v: Variant) -> Dictionary:
	var base := default_config()
	if not v is Dictionary:
		return base
	var d: Dictionary = v
	var out := {
		"terrain": _pick(d.get("terrain", RANDOM), Terrain.KINDS, RANDOM),
		"weather": _pick(d.get("weather", "clear"), WEATHERS, "clear"),
		"season": _pick(d.get("season", "summer"), SEASONS, "summer"),
		"hour": _pick(d.get("hour", "day"), HOUR_IDS, "day"),
		"difficulty": Difficulty.sanitize(str(d.get("difficulty", Difficulty.NORMAL))),
	}
	for side in ["player", "enemy"]:
		out[side] = sanitize_side(d.get(side, null)) if d.get(side, null) is Dictionary else base[side]
		if army_size(out[side]) == 0:
			out[side] = base[side]
	return out


## Une armée : {type: {"n", "rank", "gear"}} ; types inconnus écartés, au plus MAX_REGIMENTS.
static func sanitize_side(v: Variant) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		return out
	var left := MAX_REGIMENTS
	for type in UnitTypes.ORDER:
		var e: Variant = (v as Dictionary).get(type, null)
		if not e is Dictionary:
			continue
		var n := mini(clampi(int(e.get("n", 0)), 0, MAX_PER_TYPE), left)
		if n <= 0:
			continue
		left -= n
		out[type] = {"n": n, "rank": clampi(int(e.get("rank", 0)), 0, 2), "gear": clampi(int(e.get("gear", 0)), 0, Equipment.MAX_TIER)}
	return out


static func army_size(side: Dictionary) -> int:
	var n := 0
	for type in side:
		n += int(side[type].get("n", 0))
	return n


## Armée au format de BattleSim.spawn_army : [{"type", "men", "rank", "gear"}], dans l'ordre
## de UnitTypes.ORDER. L'équipement de qualité q donne les trois pièces de cette qualité.
static func army_list(side: Dictionary) -> Array:
	var out: Array = []
	for type in UnitTypes.ORDER:
		if not side.has(type):
			continue
		var e: Dictionary = side[type]
		var gear: Array = []
		var q := int(e.get("gear", 0))
		if q > 0:
			for slot in Equipment.SLOTS:
				gear.append(Equipment.item_id(slot, q))
		for i in int(e.get("n", 0)):
			out.append({"type": type, "men": int(UnitTypes.STATS[type]["count"]), "rank": int(e.get("rank", 0)), "gear": gear.duplicate()})
	return out


## Réglage tiré au sort en entier (bouton « Au hasard ») : deux armées de 4 à 9 régiments.
static func random_config(rng: RandomNumberGenerator) -> Dictionary:
	var out := {
		"terrain": Terrain.KINDS[rng.randi() % Terrain.KINDS.size()],
		"weather": WEATHERS[rng.randi() % WEATHERS.size()],
		"season": SEASONS[rng.randi() % SEASONS.size()],
		"hour": HOUR_IDS[rng.randi() % HOUR_IDS.size()],
		"difficulty": Difficulty.IDS[rng.randi() % Difficulty.IDS.size()],
	}
	for side in ["player", "enemy"]:
		var army := {}
		var count := rng.randi_range(4, 9)
		for i in count:
			var type: String = UnitTypes.ORDER[rng.randi() % UnitTypes.ORDER.size()]
			if not army.has(type):
				army[type] = {"n": 0, "rank": rng.randi_range(0, 2), "gear": rng.randi_range(0, Equipment.MAX_TIER)}
			army[type]["n"] = mini(int(army[type]["n"]) + 1, MAX_PER_TYPE)
		out[side] = army
	return sanitize(out)


## Réglages concrets de la bataille (« au hasard » tiré avec rng) :
## {"player", "enemy" (listes de army_list), "terrain", "raining", "season" (indice de
## WorldSim.SEASONS), "hour", "difficulty"}.
static func resolve(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := sanitize(cfg)
	var terrain := str(c["terrain"])
	if terrain == RANDOM:
		terrain = Terrain.KINDS[rng.randi() % Terrain.KINDS.size()]
	var season := str(c["season"])
	if season == RANDOM:
		season = SEASONS[rng.randi() % SEASONS.size()]
	var weather := str(c["weather"])
	if weather == RANDOM:
		weather = "rain" if rng.randf() < float(WorldSim.RAIN_CHANCE[SEASONS.find(season)]) else "clear"
	var hour := str(c["hour"])
	if hour == RANDOM:
		hour = HOUR_IDS[rng.randi() % HOUR_IDS.size()]
	return {
		"player": army_list(c["player"]), "enemy": army_list(c["enemy"]),
		"terrain": terrain, "raining": weather == "rain", "fog": weather == "fog",
		"wind": (1.0 if rng.randf() < 0.5 else -1.0) if weather == "wind" else 0.0,
		"season": SEASONS.find(season), "hour": float(HOURS[hour]),
		"difficulty": str(c["difficulty"]),
	}


## « Été, plein jour, pluie » : le temps d'une escarmouche résolue (journal de la bataille).
static func describe(r: Dictionary) -> String:
	var season: String = SEASONS[clampi(int(r.get("season", 1)), 0, 3)]
	var hour_id := "day"
	for id in HOUR_IDS:
		if is_equal_approx(float(HOURS[id]), float(r.get("hour", 13.0))):
			hour_id = id
	return "%s, %s, %s" % [SEASON_NAMES[season], str(HOUR_NAMES[hour_id]).to_lower(), describe_weather(r)]


static func describe_weather(r: Dictionary) -> String:
	if bool(r.get("raining", false)):
		return "pluie"
	if bool(r.get("fog", false)):
		return "brouillard"
	if float(r.get("wind", 0.0)) != 0.0:
		return "vent fort"
	return "temps clair"
