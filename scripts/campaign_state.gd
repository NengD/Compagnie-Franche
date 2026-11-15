class_name CampaignState
extends RefCounted
## État de la campagne : jour, or, compagnie, villes et contrats.
## Il survit aux changements de scène grâce à la variable statique « current ».
## current == null (ou aucun contrat en cours) : la bataille est une escarmouche isolée.

static var current: CampaignState = null

const START_GOLD := 300
const MAX_REGIMENTS := 8
const TRAVEL_PX_PER_DAY := 130.0 ## Distance parcourue sur la carte en une journée de marche
const CONTRACT_DAYS := 14 ## Validité d'un contrat, en jours
const DESERT_RATE := 0.15 ## Part des hommes qui désertent chaque jour sans solde
const WOUNDED_RECOVER := 0.3 ## Part des tombés relevés blessés après une victoire
## Solde quotidienne d'un homme, en écus
const WAGE := {"spear": 0.3, "archer": 0.35, "men_at_arms": 0.6, "cavalry": 1.0}
## Prix d'enrôlement d'un homme, en écus
const RECRUIT_COST := {"spear": 6, "archer": 7, "men_at_arms": 12, "cavalry": 20}

## Expérience : seuils des rangs (recrues, aguerris, vétérans) et gains après une bataille
const RANK_XP := [0.0, 100.0, 250.0]
const XP_MAX := 400.0
const XP_BATTLE := 25.0 ## Avoir combattu
const XP_VICTORY := 25.0 ## Avoir vaincu
const XP_KILLS := 60.0 ## Avoir tué autant d'ennemis que le régiment compte d'hommes au complet

## Villes de la carte (positions en pixels d'écran) et types de troupes qu'on peut y lever.
const TOWNS := [
	{"name": "Valombre", "pos": Vector2(140, 560), "recruits": ["spear", "archer"]},
	{"name": "Saint-Aubin", "pos": Vector2(330, 420), "recruits": ["spear", "men_at_arms"]},
	{"name": "Montfaucon", "pos": Vector2(230, 200), "recruits": ["archer", "cavalry"]},
	{"name": "Brévannes", "pos": Vector2(500, 600), "recruits": ["spear", "archer"]},
	{"name": "Castelroux", "pos": Vector2(560, 290), "recruits": ["men_at_arms", "cavalry"]},
	{"name": "Hautemure", "pos": Vector2(770, 140), "recruits": ["men_at_arms", "archer", "cavalry"]},
	{"name": "Pontrieux", "pos": Vector2(760, 470), "recruits": ["spear", "men_at_arms", "archer"]},
]
const ROADS := [[0, 1], [0, 3], [1, 2], [1, 3], [1, 4], [2, 4], [3, 6], [4, 6], [4, 5], [5, 6]]

## Modèles de contrats : composition de l'ennemi, effectifs (part du plein) et prime.
const CONTRACT_KINDS := [
	{
		"difficulty": 1, "foe": "brigands", "reward": 260, "fill": [0.6, 0.85],
		"army": ["spear", "spear", "men_at_arms", "archer"],
		"titles": ["Brigands sur la route de %s", "Des coupe-jarrets près de %s"],
		"text": "Une bande de brigands rançonne les marchands. Le bourg paie pour qu'on l'en débarrasse.",
	},
	{
		"difficulty": 2, "foe": "routiers", "reward": 450, "fill": [0.75, 1.0],
		"army": ["spear", "spear", "men_at_arms", "men_at_arms", "archer", "cavalry"],
		"titles": ["Routiers aux portes de %s", "Une compagnie rivale menace %s"],
		"text": "Des routiers sans contrat pillent la campagne. Ils sont aguerris et ont quelques cavaliers.",
	},
	{
		"difficulty": 3, "foe": "ost du baron", "reward": 720, "fill": [0.9, 1.0],
		"army": ["spear", "spear", "spear", "men_at_arms", "men_at_arms", "archer", "archer", "cavalry"],
		"titles": ["La querelle du baron de %s", "Défendre %s contre l'ost du baron"],
		"text": "Un baron voisin lève son ost. La ville engage des lances pour lui tenir tête en rase campagne.",
	},
]

var day := 1
var gold := float(START_GOLD)
var location := 0 ## Ville où se trouve la compagnie
var company: Array[Dictionary] = [] ## Régiments : {"type", "men", "xp"}
var contracts: Array[Dictionary] = [] ## {"town", "title", "text", "difficulty", "enemy", "reward", "expires", "seed"}
var pending: Dictionary = {} ## Contrat en cours de bataille (vide sinon)
var victories := 0
var defeats := 0
var log_lines: Array[String] = [] ## Derniers évènements, du plus récent au plus ancien
var rng := RandomNumberGenerator.new()


## Nouvelle partie : une petite compagnie à Valombre.
static func new_game(seed_value := 0) -> CampaignState:
	var c := CampaignState.new()
	if seed_value != 0:
		c.rng.seed = seed_value
	else:
		c.rng.randomize()
	for t in ["spear", "spear", "men_at_arms", "archer", "archer", "cavalry"]:
		c.company.append({"type": t, "men": int(UnitTypes.STATS[t]["count"]), "xp": 0.0})
	for i in TOWNS.size():
		c.refresh_contracts(i)
	c.add_log("Jour 1 : la compagnie se forme à %s. Trouvez un contrat !" % TOWNS[0]["name"])
	return c


func add_log(s: String) -> void:
	log_lines.push_front(s)
	if log_lines.size() > 6:
		log_lines.pop_back()


# ---------------------------------------------------------------- Sauvegarde

static var save_path := "user://campagne.json" ## Les tests utilisent un autre fichier
const SAVE_VERSION := 2 ## Version 1 (sans expérience, réputation ni renommée) encore lisible


## Données à sauvegarder (types simples uniquement, pour JSON).
func to_dict() -> Dictionary:
	var cs: Array = []
	for c in contracts:
		var d := c.duplicate(true)
		d["seed"] = str(c["seed"]) # Entier 64 bits : en texte pour ne pas perdre de précision
		cs.append(d)
	return {
		"version": SAVE_VERSION,
		"day": day, "gold": gold, "location": location,
		"victories": victories, "defeats": defeats,
		"company": company.duplicate(true),
		"contracts": cs,
		"log": log_lines.duplicate(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
	}


## Reconstruit une campagne depuis to_dict(). Renvoie null si les données sont invalides.
static func from_dict(d: Dictionary) -> CampaignState:
	var version := int(d.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		return null
	var c := CampaignState.new()
	c.day = int(d.get("day", 1))
	c.gold = float(d.get("gold", 0.0))
	c.location = int(d.get("location", 0))
	c.victories = int(d.get("victories", 0))
	c.defeats = int(d.get("defeats", 0))
	if c.location < 0 or c.location >= TOWNS.size():
		return null
	for r in d.get("company", []):
		if not r is Dictionary or not UnitTypes.STATS.has(str(r.get("type", ""))):
			return null
		var type := str(r["type"])
		var men := clampi(int(r.get("men", 0)), 0, int(UnitTypes.STATS[type]["count"]))
		if men > 0:
			c.company.append({"type": type, "men": men, "xp": clampf(float(r.get("xp", 0.0)), 0.0, XP_MAX)})
	for k in d.get("contracts", []):
		if not k is Dictionary:
			return null
		var town := int(k.get("town", -1))
		if town < 0 or town >= TOWNS.size():
			return null
		var enemy: Array[Dictionary] = []
		for e in k.get("enemy", []):
			if not e is Dictionary or not UnitTypes.STATS.has(str(e.get("type", ""))):
				return null
			enemy.append({"type": str(e["type"]), "men": maxi(1, int(e.get("men", 1))), "rank": clampi(int(e.get("rank", 0)), 0, 2)})
		c.contracts.append({
			"town": town, "title": str(k.get("title", "")), "text": str(k.get("text", "")),
			"foe": str(k.get("foe", "ennemis")), "difficulty": clampi(int(k.get("difficulty", 1)), 1, 3),
			"enemy": enemy, "reward": int(k.get("reward", 0)), "expires": int(k.get("expires", 0)),
			"seed": str(k.get("seed", "1")).to_int(),
		})
	for s in d.get("log", []):
		c.log_lines.append(str(s))
	c.rng.seed = str(d.get("rng_seed", "1")).to_int()
	c.rng.state = str(d.get("rng_state", "1")).to_int()
	return c


## Écrit la sauvegarde sans risque de la corrompre : fichier temporaire, puis remplacement.
func save() -> bool:
	var path := save_path
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("Sauvegarde impossible : %s" % error_string(err))
		return false
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Charge une sauvegarde. Renvoie null si le fichier manque ou est illisible.
static func load_game() -> CampaignState:
	if not FileAccess.file_exists(save_path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK:
		push_warning("Sauvegarde illisible (ligne %d) : %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		return null
	return from_dict(json.data)


static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)


# ---------------------------------------------------------------- Compagnie et or

func total_men() -> int:
	var n := 0
	for r in company:
		n += int(r["men"])
	return n


## Solde quotidienne de toute la compagnie.
func daily_wage() -> float:
	var w := 0.0
	for r in company:
		w += float(WAGE[r["type"]]) * int(r["men"])
	return w


func is_destroyed() -> bool:
	return company.is_empty()


## Lever un nouveau régiment complet dans la ville actuelle. Renvoie un message d'erreur ou "".
func recruit(type: String) -> String:
	if not type in TOWNS[location]["recruits"]:
		return "On ne lève pas ce type de troupe ici."
	if company.size() >= MAX_REGIMENTS:
		return "La compagnie compte déjà %d régiments." % MAX_REGIMENTS
	var men: int = UnitTypes.STATS[type]["count"]
	var cost := recruit_cost(type, men)
	if gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	gold -= cost
	company.append({"type": type, "men": men, "xp": 0.0})
	add_log("Jour %d : %d %s rejoignent la compagnie (-%d écus)." % [day, men, type_name(type).to_lower(), cost])
	return ""


## Compléter un régiment entamé (si son type se lève dans la ville actuelle).
func refill(index: int) -> String:
	var r := company[index]
	var type: String = r["type"]
	if not type in TOWNS[location]["recruits"]:
		return "On ne lève pas ce type de troupe ici."
	var missing := refill_missing(index)
	if missing <= 0:
		return "Ce régiment est déjà au complet."
	var cost := recruit_cost(type, missing)
	if gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	gold -= cost
	add_men(r, missing, 0.0)
	add_log("Jour %d : %d recrues complètent les %s (-%d écus)." % [day, missing, type_name(type).to_lower(), cost])
	return ""


func refill_missing(index: int) -> int:
	var r := company[index]
	return int(UnitTypes.STATS[r["type"]]["count"]) - int(r["men"])


## Ajoute n hommes d'expérience new_xp à un régiment : son expérience est la moyenne des deux.
## Des recrues (new_xp = 0) diluent donc l'expérience d'un régiment aguerri.
static func add_men(r: Dictionary, n: int, new_xp: float) -> void:
	var men := int(r["men"])
	if n <= 0:
		return
	r["xp"] = (float(r.get("xp", 0.0)) * men + new_xp * n) / float(men + n)
	r["men"] = men + n


static func rank_from_xp(xp: float) -> int:
	var k := 0
	for i in RANK_XP.size():
		if xp >= float(RANK_XP[i]):
			k = i
	return k


## Rang d'un régiment de campagne ({"xp"}) ou d'un régiment ennemi ({"rank"}).
static func rank_of(entry: Dictionary) -> int:
	if entry.has("rank"):
		return clampi(int(entry["rank"]), 0, RANK_XP.size() - 1)
	return rank_from_xp(float(entry.get("xp", 0.0)))


static func rank_name(k: int) -> String:
	return str(Regiment.RANK_NAMES[k])


static func recruit_cost(type: String, men: int) -> int:
	return int(RECRUIT_COST[type]) * men


static func type_name(type: String) -> String:
	return str(UnitTypes.STATS[type]["name"])


# ---------------------------------------------------------------- Déplacements

func neighbours(town: int) -> Array[int]:
	var out: Array[int] = []
	for road in ROADS:
		if road[0] == town:
			out.append(road[1])
		elif road[1] == town:
			out.append(road[0])
	return out


func travel_days(to: int) -> int:
	var a: Vector2 = TOWNS[location]["pos"]
	var b: Vector2 = TOWNS[to]["pos"]
	return maxi(1, ceili(a.distance_to(b) / TRAVEL_PX_PER_DAY))


## Marche vers une ville voisine : chaque jour coûte la solde. Renvoie un message d'erreur ou "".
func travel(to: int) -> String:
	if not to in neighbours(location):
		return "Aucune route directe vers %s." % TOWNS[to]["name"]
	if is_destroyed():
		return "Vous n'avez plus de troupes."
	var days := travel_days(to)
	for i in days:
		pass_day()
	location = to
	add_log("Jour %d : arrivée à %s après %d jour%s de marche." % [day, TOWNS[to]["name"], days, "s" if days > 1 else ""])
	refresh_contracts(to)
	return ""


## Un jour passe : solde, désertions si les caisses sont vides, contrats qui expirent.
func pass_day() -> void:
	day += 1
	var wage := daily_wage()
	if gold >= wage:
		gold -= wage
	else:
		# Solde impayée : une partie des hommes s'en va
		var paid := gold / wage if wage > 0.0 else 1.0
		gold = 0.0
		var lost := 0
		for r in company:
			var n := int(round(int(r["men"]) * DESERT_RATE * (1.0 - paid)))
			if n == 0 and int(r["men"]) > 0:
				n = 1
			r["men"] = int(r["men"]) - n
			lost += n
		company = company.filter(func(r): return int(r["men"]) > 0)
		add_log("Jour %d : solde impayée, %d hommes désertent !" % [day, lost])
	contracts = contracts.filter(func(c): return int(c["expires"]) >= day)
	for i in TOWNS.size():
		if rng.randf() < 0.15:
			refresh_contracts(i)


# ---------------------------------------------------------------- Contrats

func contracts_at(town: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in contracts:
		if int(c["town"]) == town:
			out.append(c)
	return out


## Chaque ville propose un ou deux contrats ; la difficulté grimpe avec la réputation.
func refresh_contracts(town: int) -> void:
	var have := contracts_at(town).size()
	var want := 1 + (1 if rng.randf() < 0.5 else 0)
	for i in maxi(0, want - have):
		contracts.append(make_contract(town))


func make_contract(town: int) -> Dictionary:
	var max_d := clampi(1 + victories, 1, 3)
	var d := rng.randi_range(maxi(1, max_d - 1), max_d)
	var kind: Dictionary = CONTRACT_KINDS[d - 1]
	var fill: Array = kind["fill"]
	var enemy: Array[Dictionary] = []
	for t in kind["army"]:
		var full: int = UnitTypes.STATS[t]["count"]
		# Les ennemis des contrats difficiles sont aguerris, voire vétérans
		var rank := 0
		if d == 2 and rng.randf() < 0.4:
			rank = 1
		elif d == 3:
			rank = 2 if rng.randf() < 0.3 else 1
		enemy.append({"type": t, "men": maxi(3, int(round(full * rng.randf_range(fill[0], fill[1])))), "rank": rank})
	var titles: Array = kind["titles"]
	var reward := int(round(int(kind["reward"]) * rng.randf_range(0.9, 1.15) / 10.0)) * 10
	return {
		"town": town,
		"title": str(titles[rng.randi() % titles.size()]) % TOWNS[town]["name"],
		"text": kind["text"],
		"foe": kind["foe"],
		"difficulty": d,
		"enemy": enemy,
		"reward": reward,
		"expires": day + CONTRACT_DAYS,
		"seed": rng.randi_range(1, 1 << 30),
	}


## Résumé lisible d'une armée : « 2 piquiers, 1 archers... » (en régiments et en hommes).
static func army_summary(list: Array) -> String:
	var counts := {}
	var men := 0
	var ranks := [0, 0, 0]
	for r in list:
		counts[r["type"]] = int(counts.get(r["type"], 0)) + 1
		men += int(r["men"])
		ranks[rank_of(r)] += 1
	var parts: Array[String] = []
	for t in ["spear", "men_at_arms", "archer", "cavalry"]:
		if counts.has(t):
			parts.append("%d %s" % [counts[t], type_name(t).to_lower()])
	var s := "%s — %d hommes" % [", ".join(parts), men]
	if ranks[1] + ranks[2] > 0:
		var exp: Array[String] = []
		if ranks[1] > 0:
			exp.append("%d aguerris" % ranks[1])
		if ranks[2] > 0:
			exp.append("%d vétérans" % ranks[2])
		s += " (régiments %s)" % ", ".join(exp)
	return s


## Accepte un contrat de la ville actuelle : la bataille peut commencer.
func accept(contract: Dictionary) -> String:
	if int(contract["town"]) != location:
		return "Ce contrat se signe à %s." % TOWNS[contract["town"]]["name"]
	if is_destroyed():
		return "Vous n'avez plus de troupes."
	pending = contract
	return ""


func in_battle() -> bool:
	return not pending.is_empty()


## Régiments engagés dans la bataille (au plus MAX_REGIMENTS, ceux qui ont encore des hommes).
func battle_army() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in company:
		if int(r["men"]) > 0 and out.size() < MAX_REGIMENTS:
			out.append(r)
	return out


## Fin de bataille. survivors[i] = hommes encore debout (ou enfuis) du régiment battle_army()[i],
## kills[i] = ennemis qu'il a tués. Les pertes et l'expérience sont reportées sur la compagnie.
## Renvoie le compte rendu.
func finish_battle(victory: bool, survivors: Array, kills: Array = []) -> String:
	var army := battle_army()
	var lost := 0
	var healed := 0
	var promoted: Array[String] = []
	for i in army.size():
		var r := army[i]
		var before: int = r["men"]
		var after: int = clampi(int(survivors[i]) if i < survivors.size() else before, 0, before)
		if victory:
			var h := int(floor((before - after) * WOUNDED_RECOVER))
			after += h
			healed += h
		lost += before - after
		r["men"] = after
		# Expérience : participation, victoire, ennemis tués (rapportés à la taille du régiment)
		var k: int = int(kills[i]) if i < kills.size() else 0
		var full := float(UnitTypes.STATS[r["type"]]["count"])
		var rank0 := rank_of(r)
		r["xp"] = minf(float(r.get("xp", 0.0)) + XP_BATTLE + (XP_VICTORY if victory else 0.0) + XP_KILLS * k / full, XP_MAX)
		if after > 0 and rank_of(r) > rank0:
			promoted.append("les %s (%d) deviennent %s" % [type_name(r["type"]).to_lower(), i + 1, rank_name(rank_of(r))])
	company = company.filter(func(r): return int(r["men"]) > 0)
	var report: String
	if victory:
		victories += 1
		gold += int(pending["reward"])
		report = "Victoire contre les %s ! +%d écus. Pertes : %d hommes (%d blessés relevés)." % [pending["foe"], int(pending["reward"]), lost, healed]
	else:
		defeats += 1
		report = "Défaite face aux %s... Pertes : %d hommes. Aucune prime." % [pending["foe"], lost]
	if not promoted.is_empty():
		report += " Promotions : %s." % ", ".join(promoted)
	contracts.erase(pending)
	pending = {}
	add_log("Jour %d : %s" % [day, report])
	pass_day() # La bataille et ses suites prennent la journée
	return report
