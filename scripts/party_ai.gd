class_name PartyAI
extends RefCounted
## Comportements des groupes de la carte en temps réel : Overworld.step appelle think(c, ow, party,
## heures) pour chaque groupe (sauf la compagnie et les armées de faction, que le monde vivant
## mène), puis skirmishes(c, ow) après la marche (combats entre groupes de la carte).
##
## think choisit d'après party.kind ; party.state garde ce que fait le groupe, party.busy_hours le
## temps qu'il reste sur place, party.target_id le groupe poursuivi, party.home son lieu d'attache,
## party.goal le lieu visé, party.base le repaire des bandits. Pour un nouveau comportement :
## écrire think_<sorte>(c, ow, p, hours) et l'ajouter au match de think.
##
## - villageois : du village au marché (ville ou bourg proche) avec leurs marchandises, quelques
##   heures sur place, puis retour ; ils fuient les bandits qu'ils voient ;
## - bandits : tapis en forêt (hidden) près du repaire, ils rôdent, chassent les proies faibles
##   (villageois, caravanes peu gardées, la compagnie si elle est faible), rentrent au repaire avec
##   le butin et y recrutent ; ils fuient plus fort qu'eux ;
## - caravanes : de ville en ville par les routes, commerce à l'arrivée, détour devant les bandits ;
## - patrouilles : boucle sur les lieux de leur faction, chasse aux bandits et aux déserteurs, et à
##   la compagnie quand la faction lui est hostile ;
## - déserteurs : errent loin des villes, puis tournent au brigandage au bout de quelques jours.
##
## Performances : les groupes ne regardent autour d'eux qu'une fois par heure de jeu (scan) ; un
## chemin (MapData.find_path) n'est calculé qu'au changement d'état ou quand une cible s'écarte.
## Hasard : toujours ow.rng (déterministe et sauvegardé).

## États où un groupe fond sur sa cible (même liste qu'Encounter.ATTACK_STATES).
const ATTACK_STATES := ["chase", "attack", "ambush"]
## Tous les états que prennent les groupes de la carte (pour les tests et la carte).
const STATES := ["idle", "travel", "rest", "chase", "flee", "home", "market_bound", "market", "home_bound",
	"lurk", "prowl", "return", "return_loot", "trade", "patrol", "garrison", "wander"]
## Sortes de lieu où les villageois vont vendre (« bourg » : si la carte en a).
const MARKET_KINDS := ["town", "bourg"]
## Sortes de lieu que visitent les patrouilles sur leur territoire.
const PATROL_KINDS := ["town", "bourg", "village", "castle"]

const SCAN_EVERY := 1.0 ## Heures entre deux regards autour de soi
const VILLAGER_FEAR := 150.0 ## Distance à laquelle des villageois voient des bandits (cachés : à moitié)
const MARKET_HOURS := Vector2(3.0, 6.0) ## Temps passé au marché
const HOME_HOURS := Vector2(14.0, 30.0) ## Temps passé au village entre deux marchés
const BANDIT_PREY := 0.8 ## Des bandits attaquent une proie jusqu'à cette part de leur force...
const BANDIT_DARE := 0.6 ## ... la compagnie seulement si elle pèse moins que leur force / ce facteur
const BANDIT_FEAR := 1.2 ## Ils fuient un groupe plus fort que leur force x ce facteur
const BANDIT_RANGE := 600.0 ## Rayon de rôde autour du repaire
const BANDIT_GIVE_UP := 420.0 ## Poursuite abandonnée au-delà de cette distance du repaire... (x2)
const BANDIT_MAX := 90 ## Effectif maximal d'une bande
const BANDIT_RECRUIT_GOLD := 25 ## Écus de butin par recrue au retour au repaire
const CARAVAN_FEAR := 0.7 ## Une caravane évite des bandits d'au moins cette part de sa force
const CARAVAN_MARGIN := Vector2(1.1, 1.4) ## Bénéfice d'une caravane à la vente
const PATROL_RANGE := 800.0 ## Rayon de la boucle d'une patrouille autour de sa ville
const PATROL_DARE := 0.8 ## Une patrouille attaque un groupe jusqu'à sa force / ce facteur
const DESERTER_DAYS := Vector2(3.0, 5.0) ## Jours avant que des déserteurs tournent au brigandage
const DESERTER_TOWN_DIST := 300.0 ## Les déserteurs restent au moins à cette distance des villes
const FIGHT_DARE := 0.6 ## Un agresseur n'engage un combat qu'à au moins cette part de la force adverse
const LOSER_KEEP := Vector2(0.2, 0.5) ## Part des hommes que garde le vaincu d'un combat entre groupes
const MIN_MEN := 6 ## Sous cet effectif, un groupe vaincu se disperse
const TRUCE_HOURS := 6.0 ## Un vaincu ne peut plus être attaqué pendant ce temps (il détale)
const LOG_RANGE := 400.0 ## Combat entre groupes au journal s'il a lieu à moins de tant de la compagnie


static func think(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	p.age += hours
	match p.kind:
		"villagers":
			think_villagers(c, ow, p, hours)
		"bandits":
			think_bandits(c, ow, p, hours)
		"caravan":
			think_caravan(c, ow, p, hours)
		"patrol":
			think_patrol(c, ow, p, hours)
		"deserters":
			think_deserters(c, ow, p, hours)
		_:
			wander(c, ow, p, hours)


# ---------------------------------------------------------------- Outils communs

## Le groupe regarde-t-il autour de lui pendant ce pas ? (environ une fois par SCAN_EVERY heures,
## d'après le compteur entier des pas : les groupes ne regardent pas tous au même pas, et la
## sauvegarde, qui arrondit les flottants, ne décale rien)
static func scanning(ow: Overworld, p: Party, hours: float) -> bool:
	var every := maxi(1, int(round(SCAN_EVERY / Overworld.MAX_STEP)))
	return hours >= SCAN_EVERY or (ow.steps + p.id) % every == 0


## Groupes vus par p à moins de radius (sans lui-même, ni la compagnie), cachés exclus sauf de très
## près. Boucle directe sur le registre, sans tri : appelée souvent.
static func seen(c: CampaignState, ow: Overworld, p: Party, radius: float, kinds: Array) -> Array[Party]:
	var out: Array[Party] = []
	var r2 := radius * radius
	var close2 := r2 * 0.09 # Un groupe caché ne se voit qu'à 30 % de la portée
	for q in ow.parties:
		var d2 := p.pos.distance_squared_to(q.pos)
		if d2 > r2 or q == p or (q.hidden and d2 > close2) or not q.kind in kinds or q.is_dead():
			continue
		out.append(q)
	if "army" in kinds:
		for a in c.world.armies:
			if a.force > 0 and p.pos.distance_squared_to(a.pos) <= r2:
				out.append(a)
	return out


## Le plus proche d'une liste (null si vide).
static func nearest(p: Party, list: Array[Party]) -> Party:
	var best: Party = null
	for q in list:
		if best == null or p.pos.distance_squared_to(q.pos) < p.pos.distance_squared_to(best.pos):
			best = q
	return best


## Lieux d'une sorte (MapData.places, filtrés par kind ; leur nombre n'est jamais supposé).
static func places_of(kinds: Array) -> Array[int]:
	var out: Array[int] = []
	for pl in MapData.places():
		if pl["kind"] in kinds:
			out.append(int(pl["id"]))
	return out


## Faction qui tient un lieu : le maître de la ville pour une ville, le seigneur sinon.
static func place_owner(c: CampaignState, i: int) -> int:
	if i >= 0 and i < CampaignState.TOWNS.size():
		return c.town_owner(i)
	return int(MapData.place(i).get("faction", -1))


## Envoie p vers un lieu (chemin calculé une fois).
static func head_to(p: Party, place: int, state: String) -> void:
	p.goal = place
	p.go(MapData.find_path(p.pos, MapData.place_pos(place)))
	p.state = state
	p.busy_hours = 0.0


## Envoie p vers un point.
static func head_to_point(p: Party, to: Vector2, state: String) -> void:
	p.go(MapData.find_path(p.pos, to))
	p.state = state
	p.busy_hours = 0.0


## p est-il sur un lieu ?
static func at_place(p: Party, place: int) -> bool:
	return place >= 0 and p.pos.distance_to(MapData.place_pos(place)) <= MapData.PLACE_RADIUS


## Poursuite de target : le chemin n'est recalculé que si la cible s'est écartée de son bout.
static func pursue(p: Party, target: Party) -> void:
	p.target_id = target.id
	p.state = "chase"
	p.busy_hours = 0.0
	p.hidden = false
	if p.path.is_empty() or p.path[-1].distance_to(target.pos) > Overworld.REPATH_DIST:
		var keep := p.target_id
		p.go(MapData.find_path(p.pos, target.pos))
		p.target_id = keep # go() efface la cible


## Fuite loin de from (Overworld.run_away), sauf si p détale déjà.
static func flee(ow: Overworld, p: Party, from: Vector2) -> void:
	if p.state == "flee" and not p.path.is_empty():
		return
	ow.run_away(p, from)
	p.hidden = false


## Point praticable au hasard à moins de radius de center.
static func random_point(ow: Overworld, center: Vector2, radius: float) -> Vector2:
	var a := ow.rng.randf() * TAU
	var r := ow.rng.randf_range(radius * 0.25, radius)
	var to := (center + Vector2.RIGHT.rotated(a) * r).clamp(Vector2(30, 30), MapData.SIZE - Vector2(30, 30))
	return MapData.walkable_point(to)


## La compagnie, vue comme une proie ou une menace par p (null : hors de vue, dans les murs, à l'abri).
static func player_seen(c: CampaignState, ow: Overworld, p: Party, radius: float) -> Party:
	if ow.inside >= 0 or c.is_destroyed() or c.is_over() or ow.cooldown.has(str(p.id)):
		return null
	if p.pos.distance_to(ow.player.pos) > radius:
		return null
	return ow.player


## Force de la compagnie (ses régiments, comme Party.strength).
static func player_strength(c: CampaignState, ow: Overworld) -> float:
	if not ow.player.troops.is_empty():
		return ow.player.strength()
	var s := 0.0
	for r in c.company:
		s += float(r.get("men", 0)) * (1.0 + float(r.get("xp", 0.0)) / 200.0)
	return s


## Force d'un groupe quelconque (la compagnie : ses régiments).
static func strength_of(c: CampaignState, ow: Overworld, q: Party) -> float:
	return player_strength(c, ow) if q == ow.player else q.strength()


## Une poursuite en cours : renvoie la cible si elle vaut encore la peine, null sinon.
static func chased(c: CampaignState, ow: Overworld, p: Party, max_dist: float) -> Party:
	if p.target_id < 0 or not p.state in ATTACK_STATES:
		return null
	var t := lookup(c, ow, p.target_id)
	if t == null or t.is_dead() or t.hidden or p.pos.distance_to(t.pos) > max_dist:
		return null
	if t == ow.player and (ow.inside >= 0 or ow.cooldown.has(str(p.id)) or c.is_destroyed()):
		return null
	if t != ow.player and ow.truce.has(str(t.id)):
		return null
	return t


## Groupe d'après son identifiant, sans construire la liste de tous les groupes (null : disparu).
static func lookup(c: CampaignState, ow: Overworld, id: int) -> Party:
	if id == ow.player.id:
		return ow.player
	for q in ow.parties:
		if q.id == id:
			return q
	for a in c.world.armies:
		if a.id == id:
			return a
	return null


## Fin d'une poursuite : le groupe redevient libre.
static func stop_chase(p: Party) -> void:
	p.target_id = -1
	p.path.clear()
	p.state = "idle"


## Errer : aller à un lieu, s'y reposer quelques heures, repartir vers un autre (sortes sans
## comportement propre).
static func wander(c: CampaignState, ow: Overworld, p: Party, _hours: float) -> void:
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	if p.state == "travel" or p.state == "chase":
		p.state = "rest"
		p.busy_hours = ow.rng.randf_range(4.0, 12.0)
		return
	var goal := pick_goal(c, ow, p)
	if goal < 0:
		p.busy_hours = 6.0
		return
	head_to(p, goal, "travel")


## Lieu où un groupe errant se rend (-1 : aucun).
static func pick_goal(_c: CampaignState, ow: Overworld, p: Party) -> int:
	var pool: Array[int] = []
	var from := p.pos if p.home < 0 else MapData.place_pos(p.home)
	for pl in MapData.places():
		var i := int(pl["id"])
		if MapData.place_pos(i).distance_to(p.pos) < MapData.PLACE_RADIUS:
			continue # Pas le lieu où il est déjà
		match p.kind:
			"caravan":
				if pl["kind"] != "town":
					continue
			"villagers":
				if MapData.place_pos(i).distance_to(from) > 900.0:
					continue
			"bandits":
				if MapData.place_pos(i).distance_to(from) > 700.0:
					continue
		pool.append(i)
	return -1 if pool.is_empty() else pool[ow.rng.randi() % pool.size()]


# ---------------------------------------------------------------- Villageois

## Marché des villageois d'un village : la ville ou le bourg le plus proche (-1 : aucun).
static func market_of(home: int) -> int:
	if home < 0:
		return -1
	return MapData.nearest_place(MapData.place_pos(home), MARKET_KINDS)


## Villageois : « home » (au village), « market_bound », « market » (vendent), « home_bound »,
## « flee » (bandits en vue). Ce qu'ils font après une fuite dépend de ce qu'ils portent.
static func think_villagers(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	if scanning(ow, p, hours) and p.state != "market" and not (p.state == "home" and at_place(p, p.home)):
		var threat := nearest(p, seen(c, ow, p, VILLAGER_FEAR, ["bandits"]))
		if threat != null:
			flee(ow, p, threat.pos)
			return
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	var market := market_of(p.home)
	match p.state:
		"market_bound":
			if at_place(p, p.goal):
				p.state = "market" # Ils vendent leurs marchandises
				p.gold += p.goods
				p.goods = 0
				p.busy_hours = ow.rng.randf_range(MARKET_HOURS.x, MARKET_HOURS.y)
				return
		"market":
			if p.home >= 0:
				head_to(p, p.home, "home_bound")
				return
		"home_bound":
			if at_place(p, p.home):
				p.state = "home"
				p.gold = 0 # La recette va au village
				p.busy_hours = ow.rng.randf_range(HOME_HOURS.x, HOME_HOURS.y)
				if ow.count(p.kind) > ow.population_cap(c, p.kind):
					ow.remove(c, p) # Trop de monde sur les chemins : ils restent chez eux
				return
		"home":
			if market >= 0:
				p.goods = ow.rng.randi_range(4, 12) * 10 # Nouvelle charrette
				head_to(p, market, "market_bound")
				return
	# Après une fuite ou au départ : finir ce qu'ils faisaient
	if p.goods > 0 and market >= 0:
		head_to(p, market, "market_bound")
	elif p.home >= 0:
		head_to(p, p.home, "home_bound")
	else:
		p.busy_hours = 6.0


# ---------------------------------------------------------------- Bandits

## Bandits : « lurk » (tapis au repaire ou à l'affût, cachés en forêt), « prowl » (rôdent),
## « chase » (fondent sur une proie), « flee », « return » (rentrent au repaire), « return_loot »
## (y rentrent avec le butin d'un coup réussi : il attire des recrues).
static func think_bandits(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	if p.base.x < 0.0:
		p.base = p.pos
	var mine := p.strength()
	var look := scanning(ow, p, hours)
	# Fuir plus fort que soi : patrouilles, armées, la compagnie qui les poursuit
	if look:
		for q in seen(c, ow, p, Overworld.SIGHT, ["patrol", "army"]):
			if q.strength() > mine * BANDIT_FEAR:
				flee(ow, p, q.pos)
				p.target_id = -1
				return
		var pl := player_seen(c, ow, p, Overworld.SIGHT)
		if pl != null and ow.player.target_id == p.id and player_strength(c, ow) > mine * BANDIT_FEAR:
			flee(ow, p, pl.pos)
			p.target_id = -1
			return
	# Poursuite en cours
	var t := chased(c, ow, p, Overworld.SIGHT * 1.5)
	if t != null and p.pos.distance_to(p.base) < BANDIT_GIVE_UP * 2.0 and not in_town(t):
		pursue(p, t)
		return
	if p.state in ATTACK_STATES:
		stop_chase(p) # Proie perdue de vue ou à l'abri
	# Chercher une proie
	if look and not p.state in ["return", "return_loot", "flee"]:
		var prey := pick_prey(c, ow, p)
		if prey != null:
			pursue(p, prey)
			return
	p.hidden = p.state == "lurk" and MapData.ground_at(p.pos) == MapData.Ground.FOREST
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	match p.state:
		"return_loot":
			# Au repaire après un coup réussi : le butin attire des recrues
			var recruits := mini(floori(p.gold / float(BANDIT_RECRUIT_GOLD)), BANDIT_MAX - p.men())
			if recruits > 0:
				add_men(p, recruits)
				p.gold -= recruits * BANDIT_RECRUIT_GOLD
			p.goods = 0
			lurk(ow, p, 8.0, 20.0)
		"return":
			lurk(ow, p, 8.0, 20.0)
		"lurk":
			head_to_point(p, random_point(ow, p.base, BANDIT_RANGE), "prowl")
		"prowl":
			if ow.rng.randf() < 0.35:
				head_to_point(p, p.base, "return")
			else:
				lurk(ow, p, 3.0, 8.0) # À l'affût là où ils sont
		_:
			if p.pos.distance_to(p.base) < MapData.PLACE_RADIUS:
				lurk(ow, p, 2.0, 8.0)
			else:
				head_to_point(p, p.base, "return")


## Les bandits se tapissent quelques heures (cachés s'ils sont en forêt).
static func lurk(ow: Overworld, p: Party, a: float, b: float) -> void:
	p.state = "lurk"
	p.busy_hours = ow.rng.randf_range(a, b)
	p.hidden = MapData.ground_at(p.pos) == MapData.Ground.FOREST


## Un groupe à l'abri des murs d'une ville ou d'un lieu (les bandits n'y entrent pas).
static func in_town(q: Party) -> bool:
	var i := MapData.place_at(q.pos)
	return i >= 0 and MapData.place(i)["kind"] in ["town", "bourg", "castle"]


## Proie des bandits en vue : villageois, caravane peu gardée, la compagnie si elle est faible.
## Préfère la plus riche à force égale (null : aucune).
static func pick_prey(c: CampaignState, ow: Overworld, p: Party) -> Party:
	var mine := p.strength()
	var best: Party = null
	var best_score := 0.0
	for q in seen(c, ow, p, Overworld.SIGHT, ["villagers", "caravan", "deserters"]):
		if ow.truce.has(str(q.id)) or in_town(q) or q.strength() > mine * BANDIT_PREY:
			continue
		var score := float(q.gold + q.goods + 20) / (1.0 + p.pos.distance_to(q.pos) / 100.0)
		if score > best_score:
			best_score = score
			best = q
	var pl := player_seen(c, ow, p, Overworld.SIGHT)
	if pl != null and player_strength(c, ow) * BANDIT_DARE <= mine:
		var score := float(c.gold + 20) / (1.0 + p.pos.distance_to(pl.pos) / 100.0)
		if best == null or score > best_score:
			best = pl
	return best


## Ajoute des hommes à un groupe (au premier régiment, ou un régiment de piquiers).
static func add_men(p: Party, n: int) -> void:
	if n <= 0:
		return
	if p.troops.is_empty():
		p.troops.append({"type": "spear", "men": n, "xp": 0.0})
	else:
		var r: Dictionary = p.troops[0]
		var old := int(r["men"])
		r["xp"] = float(r.get("xp", 0.0)) * old / float(old + n) # Les recrues sont des bleus
		r["men"] = old + n


# ---------------------------------------------------------------- Caravanes

## Caravanes : « travel » (vers goal, une autre ville, par les routes), « trade » (à l'arrivée),
## « flee » (détour devant des bandits), puis la route reprend vers le même but.
static func think_caravan(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	if scanning(ow, p, hours) and p.state == "travel":
		for q in seen(c, ow, p, Overworld.SIGHT, ["bandits"]):
			if q.strength() >= p.strength() * CARAVAN_FEAR:
				# Bandits devant (ou tout près) : détour
				var ahead := p.path.is_empty() or (q.pos - p.pos).dot(p.path[-1] - p.pos) > 0.0
				if ahead or p.pos.distance_to(q.pos) < Overworld.SIGHT * 0.5:
					flee(ow, p, q.pos)
					return
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	if p.state == "travel" and at_place(p, p.goal):
		# Vente avec bénéfice, puis on recharge les chariots
		p.home = p.goal
		var sale := int(p.goods * ow.rng.randf_range(CARAVAN_MARGIN.x, CARAVAN_MARGIN.y))
		p.gold += sale
		p.goods = 0
		var buy := mini(p.gold, ow.rng.randi_range(20, 50) * 10)
		p.goods = buy
		p.gold -= buy
		p.state = "trade"
		p.busy_hours = ow.rng.randf_range(6.0, 12.0)
		if ow.count(p.kind) > ow.population_cap(c, p.kind) and c.escort_for(p.id).is_empty():
			ow.remove(c, p) # Saison morte : la caravane reste en ville
		return
	if p.state == "flee" and p.goal >= 0 and not at_place(p, p.goal):
		head_to(p, p.goal, "travel") # Le danger passé, la route reprend
		return
	var next := next_town(c, ow, p)
	if next < 0:
		p.busy_hours = 6.0
		return
	head_to(p, next, "travel")


## Prochaine ville d'une caravane : une ville voisine par la grande route (sinon une autre ville,
## plutôt proche), jamais assiégée.
static func next_town(c: CampaignState, ow: Overworld, p: Party) -> int:
	var pool: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	var towns := places_of(["town"])
	var here := MapData.place_at(p.pos)
	if here >= 0 and here < CampaignState.TOWNS.size():
		var next: Array[int] = []
		for t in WorldSim.neighbours_of(here):
			if t in towns and not c.world.besieged(t):
				next.append(t)
		if not next.is_empty():
			return next[ow.rng.randi() % next.size()]
	for t in towns:
		if at_place(p, t) or (t < CampaignState.TOWNS.size() and c.world.besieged(t)):
			continue
		var w := 1.0 / (1.0 + p.pos.distance_to(MapData.place_pos(t)) / 400.0)
		pool.append(t)
		weights.append(w)
		total += w
	if pool.is_empty():
		return -1
	var r := ow.rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[-1]


# ---------------------------------------------------------------- Patrouilles

## La faction de la patrouille est-elle hostile à la compagnie ? (portes fermées, ou en guerre
## avec la faction que sert la compagnie)
static func patrol_hostile(c: CampaignState, ow: Overworld, p: Party) -> bool:
	if p.faction < 0:
		return false
	if c.faction_closed(p.faction):
		return true
	return ow.player.faction >= 0 and c.world.at_war(ow.player.faction, p.faction)


## Patrouilles : « garrison » (repos en ville), « patrol » (tournée : deux ou trois lieux de leur
## territoire puis retour, tout le chemin calculé au départ), « return » (vers leur ville),
## « chase » (bandits, déserteurs, ou la compagnie si leur faction lui est hostile).
static func think_patrol(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	var mine := p.strength()
	var t := chased(c, ow, p, Overworld.SIGHT * 2.0)
	if t != null and (t != ow.player or patrol_hostile(c, ow, p)):
		pursue(p, t)
		return
	if p.state in ATTACK_STATES:
		stop_chase(p)
	if scanning(ow, p, hours):
		var best: Party = null
		for q in seen(c, ow, p, Overworld.SIGHT, ["bandits", "deserters"]):
			if not ow.truce.has(str(q.id)) and q.strength() * PATROL_DARE <= mine and (best == null or p.pos.distance_squared_to(q.pos) < p.pos.distance_squared_to(best.pos)):
				best = q
		if best == null and patrol_hostile(c, ow, p) and player_seen(c, ow, p, Overworld.SIGHT) != null \
				and player_strength(c, ow) * PATROL_DARE <= mine:
			best = ow.player
		if best != null:
			pursue(p, best)
			return
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	# Ville perdue : la patrouille se rattache à la ville amie la plus proche
	if p.home < 0 or place_owner(c, p.home) != p.faction:
		p.home = home_town(c, p.faction, p.pos)
		if p.home < 0:
			p.troops.clear() # Plus une ville : la patrouille se disperse
			return
	if not at_place(p, p.home):
		head_to(p, p.home, "return")
		return
	if p.state != "garrison":
		p.state = "garrison"
		p.busy_hours = ow.rng.randf_range(8.0, 16.0)
		if ow.count(p.kind) > ow.population_cap(c, p.kind):
			ow.remove(c, p) # Moins de patrouilles : celle-ci rejoint la garnison
		return
	if not start_round(c, ow, p):
		p.busy_hours = 6.0


## Tournée d'une patrouille : deux ou trois lieux de sa faction près de sa ville, puis retour (tout
## le chemin calculé d'un coup). Faux si elle n'a nulle part où aller.
static func start_round(c: CampaignState, ow: Overworld, p: Party) -> bool:
	var stops: Array[int] = []
	for i in ow.rng.randi_range(2, 3):
		var next := patrol_stop(c, ow, p, stops)
		if next < 0:
			break
		stops.append(next)
	if stops.is_empty():
		return false
	var pts: Array[Vector2] = []
	var from := p.pos
	stops.append(p.home)
	for s in stops:
		var leg := MapData.find_path(from, MapData.place_pos(s))
		pts.append_array(leg)
		if not leg.is_empty():
			from = leg[-1]
	p.go(pts)
	p.goal = stops[0]
	p.state = "patrol"
	p.busy_hours = 0.0
	return true


## Ville de la faction f la plus proche de pos (-1 : aucune).
static func home_town(c: CampaignState, f: int, pos: Vector2) -> int:
	var best := -1
	for t in places_of(["town"]):
		if place_owner(c, t) != f:
			continue
		if best < 0 or pos.distance_to(MapData.place_pos(t)) < pos.distance_to(MapData.place_pos(best)):
			best = t
	return best


## Étape d'une tournée : un lieu de la faction près de la ville, hors de skip (-1 : aucun).
static func patrol_stop(c: CampaignState, ow: Overworld, p: Party, skip: Array[int]) -> int:
	var from := MapData.place_pos(p.home) if p.home >= 0 else p.pos
	var pool: Array[int] = []
	for i in places_of(PATROL_KINDS):
		if i == p.home or i in skip or place_owner(c, i) != p.faction:
			continue
		if MapData.place_pos(i).distance_to(from) > PATROL_RANGE:
			continue
		pool.append(i)
	return -1 if pool.is_empty() else pool[ow.rng.randi() % pool.size()]


# ---------------------------------------------------------------- Déserteurs

## Déserteurs : errent loin des villes (« wander », « rest »), fuient patrouilles et armées, et
## tournent au brigandage au bout de DESERTER_DAYS jours.
static func think_deserters(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	var days := DESERTER_DAYS.x + float(absi(p.id) % 100) / 100.0 * (DESERTER_DAYS.y - DESERTER_DAYS.x)
	if p.age >= days * Overworld.HOURS_PER_DAY:
		turn_bandit(c, ow, p)
		return
	if scanning(ow, p, hours):
		var threat := nearest(p, seen(c, ow, p, Overworld.SIGHT, ["patrol", "army"]))
		if threat != null:
			flee(ow, p, threat.pos)
			return
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	if p.state == "wander":
		p.state = "rest"
		p.busy_hours = ow.rng.randf_range(4.0, 10.0)
		return
	head_to_point(p, far_point(ow, p.pos), "wander")


## Point praticable loin des villes, à quelques heures de marche de pos.
static func far_point(ow: Overworld, pos: Vector2) -> Vector2:
	var best := MapData.walkable_point(pos)
	var best_d := -1.0
	for i in 6:
		var q := random_point(ow, pos, 350.0)
		var d := q.distance_to(MapData.place_pos(MapData.nearest_town(q)))
		if d >= DESERTER_TOWN_DIST:
			return q
		if d > best_d:
			best_d = d
			best = q
	return best


## Des déserteurs deviennent une bande de brigands là où ils sont.
static func turn_bandit(c: CampaignState, ow: Overworld, p: Party) -> void:
	var was := p.display_name()
	p.kind = "bandits"
	p.faction = -1
	p.name = ow.bandit_name()
	p.base = MapData.walkable_point(p.pos)
	p.home = MapData.nearest_place(p.pos)
	p.target_id = -1
	p.path.clear()
	p.age = 0.0
	lurk(ow, p, 4.0, 10.0)
	var text := "%s tournent au brigandage : on les appelle désormais %s." % [CampaignState.cap_first(was), p.name]
	ow.report(c, text, p.pos, false)


# ---------------------------------------------------------------- Combats entre groupes

## Qui attaque qui : agresseur -> sortes de victimes.
const PREYS := {
	"bandits": ["villagers", "caravan", "deserters"],
	"patrol": ["bandits", "deserters"],
	"army": ["bandits", "deserters"],
}


## a veut-il en découdre avec b ? (patrouilles de deux factions en guerre comprises)
static func hostile_pair(c: CampaignState, a: Party, b: Party) -> bool:
	if b.kind in PREYS.get(a.kind, []):
		return true
	if a.kind in ["patrol", "army"] and b.kind == "patrol" and a.faction >= 0 and b.faction >= 0:
		return c.world.at_war(a.faction, b.faction)
	return false


## Combats entre les groupes de la carte qui se touchent (hors la compagnie) : résolution
## automatique. Appelé par Overworld.step après la marche.
static func skirmishes(c: CampaignState, ow: Overworld) -> void:
	var list: Array[Party] = []
	list.append_array(ow.parties)
	for a in c.world.armies:
		if a.force > 0:
			list.append(a)
	var r2 := Overworld.CONTACT_RANGE * Overworld.CONTACT_RANGE
	var n := list.size()
	for i in n:
		var a := list[i]
		if not PREYS.has(a.kind):
			continue
		var at := a.pos
		for j in n:
			var b := list[j]
			# La distance d'abord : c'est le test le moins cher, et presque toujours le dernier
			if i == j or at.distance_squared_to(b.pos) > r2:
				continue
			if not hostile_pair(c, a, b) or a.is_dead() or b.is_dead() or ow.truce.has(str(b.id)) or ow.truce.has(str(a.id)):
				continue
			if b is WorldArmy and not a is WorldArmy:
				continue # Une patrouille n'attaque pas une armée
			if a.strength() < b.strength() * FIGHT_DARE:
				continue
			fight(c, ow, a, b)


## Combat simulé entre deux groupes (a attaque b) : issue tirée au sort, pondérée par la force.
## Le vaincu perd l'essentiel de ses hommes et détale (ou se disperse), le vainqueur prend le butin.
## Renvoie le vainqueur.
static func fight(c: CampaignState, ow: Overworld, a: Party, b: Party) -> Party:
	var pa := a.strength() * ow.rng.randf_range(0.75, 1.25)
	var pb := b.strength() * ow.rng.randf_range(0.75, 1.25)
	var win := a if pa >= pb else b
	var lose := b if pa >= pb else a
	var ratio := minf(minf(pa, pb) / maxf(maxf(pa, pb), 1.0), 1.0)
	var lose_before := lose.men()
	var kept := int(lose_before * ow.rng.randf_range(LOSER_KEEP.x, LOSER_KEEP.y))
	if kept < MIN_MEN:
		kept = 0
	var win_loss := int(round(lose_before * 0.35 * ratio + win.men() * 0.03))
	lose_men(win, win_loss)
	lose_men(lose, lose_before - kept)
	# Butin
	var loot := lose.gold + lose.goods
	if not win is WorldArmy:
		win.gold += lose.gold + (lose.goods if win.kind != "caravan" else 0)
		if win.kind == "caravan":
			win.goods += lose.goods
	lose.gold = 0
	lose.goods = 0
	for r in win.troops:
		r["xp"] = minf(float(r.get("xp", 0.0)) + 10.0, 200.0)
	var where := str(CampaignState.TOWNS[MapData.nearest_town(win.pos)]["name"])
	var text := ""
	if lose.is_dead():
		text = "près de %s, %s %s %s." % [where, win.display_name(), "taille en pièces" if win.kind in ["patrol", "army"] else "massacre", lose.display_name()]
	else:
		text = "près de %s, %s met en fuite %s." % [where, win.display_name(), lose.display_name()]
		ow.truce[str(lose.id)] = TRUCE_HOURS
		if not lose is WorldArmy:
			ow.run_away(lose, win.pos)
			lose.hidden = false
	if loot > 0 and not win is WorldArmy:
		text += " Butin : %d écus." % loot
	# Le vainqueur s'arrête (pillage, soins), puis reprend sa route ; des bandits rentrent au repaire
	win.target_id = -1
	if not win is WorldArmy:
		win.path.clear()
		win.busy_hours = ow.rng.randf_range(1.0, 3.0)
		win.state = {"bandits": "return_loot", "patrol": "return"}.get(win.kind, "idle")
		if win.kind == "patrol" and win.home >= 0:
			win.path = MapData.find_path(win.pos, MapData.place_pos(win.home))
		elif win.kind == "bandits" and win.base.x >= 0.0:
			win.path = MapData.find_path(win.pos, win.base)
		elif win.kind == "caravan":
			win.state = "flee" # Reprend la route vers son but après la halte
	if a is WorldArmy:
		(a as WorldArmy).sync_troops()
	var important := not c.escort_for(a.id).is_empty() or not c.escort_for(b.id).is_empty() \
		or (lose.is_dead() and (lose.kind in ["caravan", "patrol"] or lose.name != ""))
	ow.report(c, text, win.pos, important)
	if lose.is_dead() and not lose is WorldArmy:
		ow.remove(c, lose) # Escorte manquée, s'il y en avait une
	return win


## Retire n hommes d'un groupe, régiment par régiment au prorata (une armée : sa force).
static func lose_men(p: Party, n: int) -> void:
	if n <= 0:
		return
	if p is WorldArmy:
		(p as WorldArmy).force = maxi(0, (p as WorldArmy).force - n)
		return
	var before := p.men()
	CampaignState.scale_troops(p, maxi(0, before - n), before)
