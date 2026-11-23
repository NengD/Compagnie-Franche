class_name Fiefs
extends RefCounted
## Fiefs : l'objectif à long terme de la compagnie, un château à elle.
##
## Les châteaux de la carte (MapData.places, sorte « castle ») appartiennent à une faction. La
## compagnie peut en acheter un (très cher, à une faction qui l'estime) ou le prendre d'assaut : un
## contrat de siège (« siege » : « assault », « fief » : le lieu) livré sur le terrain de siège
## (siege.gd). Son fief lui rapporte un revenu chaque semaine ; on y lève toutes les sortes de
## troupes, un peu moins cher qu'en ville, et on y laisse une garnison (régiments retirés de la
## compagnie) qui le défend. Une faction hostile (portes fermées, en guerre avec le suzerain, ou
## dépossédée et encore rancunière) peut l'assiéger : la compagnie a ATTACK_DAYS jours pour venir le
## défendre (bataille de défense de siège), sinon la garnison se bat seule derrière ses murs.
## Un vassal (diplomacy.gd) peut aussi lever des troupes dans les châteaux de son suzerain.
## Branché par CampaignState (bloc « Domaine ») ; panneau : realm_panel.gd.

const PLAYER := -2 ## Propriétaire « la compagnie » dans owners
const BUY_PRICE := 6000 ## Prix d'un château
const LIEGE_DISCOUNT := 0.8 ## Un vassal achète un château de son suzerain moins cher
const BUY_REP := 20 ## Réputation minimale auprès du seigneur pour acheter
const INCOME := 400 ## Revenu d'un fief par semaine (avant la solde de la garnison)
const WEEK := 7
const GARRISON_WAGE := 0.5 ## Une garnison coûte la moitié de la solde en campagne
const MAX_GARRISON := 4 ## Régiments au plus en garnison
const LEVY_PRICE := 0.9 ## Prix des recrues de son fief (x RECRUIT_COST)
const LORD_LEVY := ["spear", "men_at_arms", "archer", "cavalry"] ## Troupes d'un château du suzerain
const LORD_PRICE := 1.0
const FIEF_FAME := 10 ## Renommée d'un château acquis
const REP_ASSAULT := -20 ## Prendre d'assaut le château d'une faction
const GRACE_DAYS := 10 ## Aucun siège avant ce délai après l'acquisition
const ATTACK_CHANCE := 0.03 ## Chance quotidienne qu'une faction hostile assiège le fief
const ATTACK_DAYS := 3 ## Jours pour venir défendre le fief
const WALLS := 2.0 ## Les murs doublent la force de la garnison
const GARRISON_SALLY := 0.6 ## Pendant une défense, la garnison retient tant d'assiégeants par homme
## Garnison d'un château de faction (pour l'assaut) : type et part du plein.
const CASTLE_GARRISON := [["spear", 0.9], ["spear", 0.8], ["men_at_arms", 0.8], ["archer", 0.9], ["crossbow", 0.8]]
const ATTACKER_TYPES := ["spear", "men_at_arms", "archer", "spear", "crossbow", "cavalry", "men_at_arms", "archer", "spear"]

var owners := {} ## str(lieu) -> faction (PLAYER : la compagnie) des châteaux qui ont changé de main
## Fiefs de la compagnie : {"place", "garrison": [{"type", "men", "xp"}], "since", "from" (faction
## dépossédée, -1 si acheté), "siege": {} ou {"faction", "men", "days"}}
var held: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


static func is_castle(i: int) -> bool:
	return i >= 0 and i < MapData.place_count() and str(MapData.place(i)["kind"]) == "castle"


static func place_name(i: int) -> String:
	return str(MapData.place(i)["name"])


## Faction qui tient un château (PLAYER : la compagnie).
func owner_of(i: int) -> int:
	if owners.has(str(i)):
		return int(owners[str(i)])
	return int(MapData.place(i).get("faction", -1))


func owns(i: int) -> bool:
	return owner_of(i) == PLAYER


func fief(i: int) -> Dictionary:
	for e in held:
		if int(e["place"]) == i:
			return e
	return {}


# ---------------------------------------------------------------- Acquérir un château

func buy_price(c: CampaignState, i: int) -> int:
	var k := LIEGE_DISCOUNT if c.diplomacy.liege >= 0 and c.diplomacy.liege == owner_of(i) else 1.0
	return int(round(BUY_PRICE * k / 10.0)) * 10


## Raison pour laquelle on ne peut pas acheter ce château ("" : possible).
func buy_refusal(c: CampaignState, i: int) -> String:
	if not is_castle(i):
		return "Ce lieu n'est pas un château."
	if owns(i):
		return "Ce château est déjà à vous."
	var f := owner_of(i)
	if f < 0:
		return "Personne ne peut vous vendre ce château."
	if c.reputation[f] < BUY_REP:
		return "%s ne vend pas ses châteaux à une compagnie qu'il n'estime pas (réputation %d au moins)." % [CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])), BUY_REP]
	if c.diplomacy.at_war_with(c, f):
		return "Votre suzerain est en guerre contre %s." % CampaignState.FACTIONS[f]["short"]
	if c.gold < buy_price(c, i):
		return "Pas assez d'or (%d écus)." % buy_price(c, i)
	return ""


func buy(c: CampaignState, i: int) -> String:
	var why := buy_refusal(c, i)
	if why != "":
		return why
	var price := buy_price(c, i)
	c.gold -= price
	grant(c, i, -1)
	c.add_log("Jour %d : la compagnie achète le château de %s pour %d écus. Voici son fief !" % [c.day, place_name(i), price])
	return ""


## Raison pour laquelle on ne peut pas donner l'assaut ("" : possible).
func assault_refusal(c: CampaignState, i: int) -> String:
	if not is_castle(i):
		return "Ce lieu n'est pas un château."
	if owns(i):
		return "Ce château est déjà à vous."
	if c.is_over():
		return "La campagne est terminée."
	if c.is_destroyed():
		return "Vous n'avez plus de troupes."
	if c.in_battle():
		return "Une bataille vous attend déjà."
	var f := owner_of(i)
	if f >= 0 and f == c.diplomacy.liege:
		return "Vous avez juré fidélité à %s : vous ne pouvez pas prendre ses châteaux." % CampaignState.FACTIONS[f]["short"]
	return ""


## Garnison d'un château de faction : tirée d'après le château et la quinzaine (sans toucher au
## hasard de la campagne).
func castle_garrison(c: CampaignState, i: int) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	@warning_ignore("integer_division")
	r.seed = hash([c.rng.seed, i, c.day / 15, "garnison"])
	var out: Array[Dictionary] = []
	var big := 1 if c.day >= 60 else 0
	for k in CASTLE_GARRISON.size() + big:
		var spec: Array = CASTLE_GARRISON[k % CASTLE_GARRISON.size()]
		var full := int(UnitTypes.STATS[spec[0]]["count"])
		out.append({"type": str(spec[0]), "men": maxi(3, int(round(full * float(spec[1]) * r.randf_range(0.85, 1.05)))),
			"rank": 1 if r.randf() < 0.5 else 0})
	return out


## Ville pour un contrat de siège de fief : la plus proche du château qui n'est pas assiégée (le
## monde vivant ne doit pas croire qu'on défend une de ses villes).
static func safe_town(c: CampaignState, pos: Vector2) -> int:
	var best := -1
	for t in CampaignState.TOWNS.size():
		if c.world.besieged(t):
			continue
		if best < 0 or pos.distance_to(MapData.place_pos(t)) < pos.distance_to(MapData.place_pos(best)):
			best = t
	return maxi(best, 0)


## Contrat d'assaut d'un château : pas de prime, le château pour récompense.
func make_assault(c: CampaignState, i: int) -> Dictionary:
	var f := owner_of(i)
	var who := str(CampaignState.FACTIONS[f]["short"]) if f >= 0 else "son seigneur"
	return {
		"town": safe_town(c, MapData.place_pos(i)), "faction": -1, "fief": i, "siege": "assault",
		"title": "Assaut du château de %s" % place_name(i),
		"text": "La garnison de %s tient les murs. Enfoncez la porte, montez aux échelles et tenez la cour : le château sera à vous." % who,
		"foe": "garnison de %s" % place_name(i), "difficulty": 3,
		"enemy": castle_garrison(c, i), "reward": 0, "expires": c.day,
		"seed": absi(hash([c.rng.seed, i, c.day, "assaut"])) % (1 << 30) + 1,
		"objective": {"kind": "destroy"}, "enemy_faction": f,
	}


## Lance l'assaut (bataille en attente). Renvoie une erreur ou "".
func assault(c: CampaignState, i: int) -> String:
	var why := assault_refusal(c, i)
	if why != "":
		return why
	c.pending = make_assault(c, i)
	return ""


## Le château devient le fief de la compagnie (from : faction dépossédée, -1 si acheté).
func grant(c: CampaignState, i: int, from: int) -> void:
	owners[str(i)] = PLAYER
	held.append({"place": i, "garrison": [], "since": c.day, "from": from, "siege": {}})
	c.fame += FIEF_FAME


## Le fief tombe aux mains de la faction f.
func lose(c: CampaignState, e: Dictionary, f: int) -> void:
	held.erase(e)
	var i := int(e["place"])
	owners[str(i)] = f
	if f == int(MapData.place(i).get("faction", -1)):
		owners.erase(str(i))
	c.add_log("Jour %d : %s prend votre château de %s ; la garnison est passée au fil de l'épée." % [c.day, CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])), place_name(i)])


# ---------------------------------------------------------------- Troupes et garnison

## Troupes qu'on lève dans un château : toutes dans son fief, quelques-unes chez son suzerain.
func levy_types(c: CampaignState, i: int) -> Array:
	if owns(i):
		return UnitTypes.ORDER
	if is_castle(i) and c.diplomacy.liege >= 0 and owner_of(i) == c.diplomacy.liege:
		return LORD_LEVY
	return []


func levy_cost(c: CampaignState, i: int, type: String, men: int) -> int:
	var k := LEVY_PRICE if owns(i) else LORD_PRICE
	return int(ceil(int(CampaignState.RECRUIT_COST[type]) * men * k * Difficulty.value(c.difficulty, "recruit")))


## Lever un régiment complet dans le château où se trouve la compagnie. Renvoie une erreur ou "".
func levy(c: CampaignState, i: int, type: String) -> String:
	if c.overworld.inside != i:
		return "Il faut être au château."
	if not type in levy_types(c, i):
		return "On ne lève pas ce type de troupe ici."
	if Challenges.forbids_type(c.challenges, type):
		return Challenges.NO_CAVALRY_REFUSAL
	if c.company.size() >= CampaignState.MAX_REGIMENTS:
		return "La compagnie compte déjà %d régiments." % CampaignState.MAX_REGIMENTS
	var men := int(UnitTypes.STATS[type]["count"])
	var cost := levy_cost(c, i, type, men)
	if c.gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	c.gold -= cost
	c.company.append({"type": type, "men": men, "xp": 0.0})
	c.add_log("Jour %d : %s levés à %s rejoignent la compagnie (-%d écus)." % [c.day, CampaignState.type_count(type, men), place_name(i), cost])
	return ""


## Laisse le régiment index de la compagnie en garnison dans le fief i.
func station(c: CampaignState, i: int, index: int) -> String:
	var e := fief(i)
	if e.is_empty():
		return "Ce château n'est pas à vous."
	if c.overworld.inside != i:
		return "Il faut être au château."
	if index < 0 or index >= c.company.size():
		return "Régiment inconnu."
	if c.company.size() <= 1:
		return "La compagnie ne peut pas laisser son dernier régiment."
	var g: Array = e["garrison"]
	if g.size() >= MAX_GARRISON:
		return "La garnison compte déjà %d régiments." % MAX_GARRISON
	var r: Dictionary = c.company[index]
	c.company.remove_at(index)
	g.append(r)
	c.add_log("Jour %d : les %s restent en garnison à %s." % [c.day, CampaignState.type_name(str(r["type"])).to_lower(), place_name(i)])
	return ""


## Reprend le régiment index de la garnison du fief i dans la compagnie.
func withdraw(c: CampaignState, i: int, index: int) -> String:
	var e := fief(i)
	if e.is_empty():
		return "Ce château n'est pas à vous."
	if c.overworld.inside != i:
		return "Il faut être au château."
	var g: Array = e["garrison"]
	if index < 0 or index >= g.size():
		return "Régiment inconnu."
	if c.company.size() >= CampaignState.MAX_REGIMENTS:
		return "La compagnie compte déjà %d régiments." % CampaignState.MAX_REGIMENTS
	var r: Dictionary = g[index]
	g.remove_at(index)
	c.company.append(r)
	return ""


static func garrison_men(e: Dictionary) -> int:
	var n := 0
	for r in e["garrison"]:
		n += int(r["men"])
	return n


static func garrison_strength(e: Dictionary) -> float:
	var s := 0.0
	for r in e["garrison"]:
		s += int(r["men"]) * (1.0 + float(r.get("xp", 0.0)) / 200.0)
	return s


func garrison_wage(c: CampaignState, e: Dictionary) -> float:
	var w := 0.0
	for r in e["garrison"]:
		w += float(CampaignState.WAGE[r["type"]]) * int(r["men"])
	return w * GARRISON_WAGE * Difficulty.value(c.difficulty, "wage")


## Revenu net d'une semaine (revenu moins la solde de la garnison).
func weekly_net(c: CampaignState, e: Dictionary) -> int:
	if not (e["siege"] as Dictionary).is_empty():
		return -int(round(garrison_wage(c, e) * WEEK))
	return int(round(INCOME - garrison_wage(c, e) * WEEK))


# ---------------------------------------------------------------- Sièges du fief

## Factions qui en veulent au fief : portes fermées, en guerre avec le suzerain, ou dépossédée et
## encore rancunière.
func hostile_factions(c: CampaignState, e: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for f in CampaignState.FACTIONS.size():
		if c.world.towns_of(f).is_empty():
			continue
		if c.faction_closed(f) or c.diplomacy.at_war_with(c, f) or (int(e.get("from", -1)) == f and c.reputation[f] < 0):
			out.append(f)
	return out


## Un jour passe pour les fiefs : revenu chaque semaine, sièges qui commencent ou se décident.
func day(c: CampaignState) -> void:
	for e in held.duplicate():
		var s: Dictionary = e["siege"]
		if not s.is_empty():
			s["days"] = int(s["days"]) - 1
			if int(s["days"]) <= 0:
				resolve_siege(c, e)
			continue
		if c.day - int(e["since"]) < GRACE_DAYS:
			continue
		for f in hostile_factions(c, e):
			if rng.randf() < ATTACK_CHANCE:
				start_siege(c, e, f)
				break
	if c.day % WEEK == 0:
		var total := 0
		for e in held:
			total += weekly_net(c, e)
		if not held.is_empty():
			c.gold = maxf(0.0, c.gold + total)
			if total > 0:
				c.gold_earned += total
			c.add_log("Jour %d : vos fiefs rapportent %+d écus cette semaine." % [c.day, total])


func start_siege(c: CampaignState, e: Dictionary, f: int) -> void:
	@warning_ignore("integer_division")
	var men := mini(80 + rng.randi_range(0, 80) + c.day / 2, 280)
	e["siege"] = {"faction": f, "men": men, "days": ATTACK_DAYS}
	c.add_log("Jour %d : %s assiège votre château de %s avec %d hommes ! Venez le défendre (%d jours)." % [c.day, CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])), place_name(int(e["place"])), men, ATTACK_DAYS])


## Personne n'est venu : la garnison se bat seule derrière ses murs.
func resolve_siege(c: CampaignState, e: Dictionary) -> void:
	var s: Dictionary = e["siege"]
	var f := int(s["faction"])
	var attack := int(s["men"]) * rng.randf_range(0.7, 1.3)
	var defense := garrison_strength(e) * WALLS
	e["siege"] = {}
	if defense >= attack and defense > 0.0:
		var keep := clampf(1.0 - 0.5 * attack / defense, 0.3, 0.95)
		for r in e["garrison"]:
			r["men"] = maxi(1, int(round(int(r["men"]) * keep)))
		c.add_log("Jour %d : la garnison de %s repousse %s !" % [c.day, place_name(int(e["place"])), CampaignState.FACTIONS[f]["short"]])
	else:
		lose(c, e, f)


## Contrat de défense du fief assiégé (la compagnie est venue) : l'ennemi, moins ce que la
## garnison retient depuis les murs.
func make_defense(c: CampaignState, e: Dictionary) -> Dictionary:
	var i := int(e["place"])
	var s: Dictionary = e["siege"]
	var f := int(s["faction"])
	var men := maxi(30, int(s["men"]) - int(garrison_men(e) * GARRISON_SALLY))
	var enemy: Array[Dictionary] = []
	var k := 0
	while men > 0 and enemy.size() < 9:
		var t := str(ATTACKER_TYPES[k % ATTACKER_TYPES.size()])
		var n := mini(int(UnitTypes.STATS[t]["count"]), men)
		if n < 3:
			break
		enemy.append({"type": t, "men": n, "rank": 1 if k % 3 == 0 else 0})
		men -= n
		k += 1
	return {
		"town": safe_town(c, MapData.place_pos(i)), "faction": -1, "fief": i, "siege": "defense",
		"title": "Défendre votre château de %s" % place_name(i),
		"text": "%s donne l'assaut à votre château. Garnissez les murs et tenez !" % CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])),
		"foe": "troupes de %s" % CampaignState.FACTIONS[f]["short"], "difficulty": 3,
		"enemy": enemy, "reward": 0, "expires": c.day,
		"seed": absi(hash([c.rng.seed, i, c.day, "défense"])) % (1 << 30) + 1,
		"objective": {"kind": "destroy"}, "enemy_faction": f,
	}


func defend_refusal(c: CampaignState, i: int) -> String:
	var e := fief(i)
	if e.is_empty() or (e["siege"] as Dictionary).is_empty():
		return "Votre château n'est pas assiégé."
	if c.overworld.inside != i:
		return "Il faut être au château."
	if c.is_destroyed():
		return "Vous n'avez plus de troupes."
	if c.in_battle():
		return "Une bataille vous attend déjà."
	return ""


func defend(c: CampaignState, i: int) -> String:
	var why := defend_refusal(c, i)
	if why != "":
		return why
	c.pending = make_defense(c, fief(i))
	return ""


## Fin d'une bataille de fief (assaut ou défense). Renvoie la note du compte rendu.
func after_battle(c: CampaignState, victory: bool) -> String:
	if not c.pending.has("fief"):
		return ""
	var i := int(c.pending["fief"])
	if not is_castle(i):
		return ""
	if str(c.pending.get("siege", "")) == "assault":
		var f := owner_of(i)
		var note := ""
		if f >= 0:
			c.change_reputation(f, REP_ASSAULT)
			note = " Réputation : %s %+d." % [CampaignState.FACTIONS[f]["short"], REP_ASSAULT]
		if victory and not owns(i):
			grant(c, i, f)
			return " Le château de %s est à vous : voici le fief de la compagnie !%s" % [place_name(i), note]
		return note
	var e := fief(i)
	if e.is_empty() or (e["siege"] as Dictionary).is_empty():
		return ""
	var f2 := int(e["siege"]["faction"])
	if victory:
		e["siege"] = {}
		return " Le siège de %s est levé." % place_name(i)
	lose(c, e, f2)
	return " Le château de %s est perdu." % place_name(i)


# ---------------------------------------------------------------- Sauvegarde

func to_dict() -> Dictionary:
	return {"owners": owners.duplicate(), "held": held.duplicate(true), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}


static func from_dict(v: Variant, seed_value: int) -> Fiefs:
	var out := Fiefs.new()
	out.rng.seed = hash([seed_value, "fiefs"])
	if not v is Dictionary:
		return out
	var o: Variant = v.get("owners", {})
	if o is Dictionary:
		for k in o:
			if is_castle(str(k).to_int()):
				out.owners[str(k)] = clampi(int(o[k]), PLAYER, CampaignState.FACTIONS.size() - 1)
	for e in v.get("held", []):
		if not e is Dictionary or not is_castle(int(e.get("place", -1))):
			continue
		var g: Array = []
		for r in e.get("garrison", []):
			if r is Dictionary and UnitTypes.STATS.has(str(r.get("type", ""))) and int(r.get("men", 0)) > 0:
				var entry := {"type": str(r["type"]), "men": int(r["men"]), "xp": float(r.get("xp", 0.0))}
				Traits.read_entry(entry, r)
				g.append(entry)
		var s: Dictionary = {}
		var sv: Variant = e.get("siege", {})
		if sv is Dictionary and (sv as Dictionary).has("faction"):
			s = {"faction": clampi(int(sv["faction"]), 0, CampaignState.FACTIONS.size() - 1), "men": maxi(1, int(sv.get("men", 1))), "days": maxi(1, int(sv.get("days", 1)))}
		var i := int(e["place"])
		out.held.append({"place": i, "garrison": g, "since": int(e.get("since", 0)), "from": int(e.get("from", -1)), "siege": s})
		out.owners[str(i)] = PLAYER
	if v.has("rng_state"):
		out.rng.seed = str(v.get("rng_seed", "1")).to_int()
		out.rng.state = str(v.get("rng_state", "1")).to_int()
	return out
