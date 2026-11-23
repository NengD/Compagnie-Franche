class_name Overworld
extends RefCounted
## Carte du monde en temps réel, sans rendu : l'heure qui passe, la compagnie du joueur (Party
## « player ») et le registre de tous les groupes qui se déplacent (villageois, bandits,
## caravanes... et les armées de faction de world_sim.gd, qui sont des Party « army »).
##
## CampaignState en possède un (« overworld ») ; la carte (campaign_map.gd) appelle tick(c, heures)
## tant que le temps s'écoule. Chaque fin de journée appelle CampaignState.pass_day (solde,
## désertions, contrats, saisons, météo et monde vivant) puis march_day si la compagnie a marché.
##
## Registre : all(), by_id(), add(), remove(), near(). Les armées restent rangées dans
## world.armies (le monde vivant les lève et les disperse) ; les autres groupes dans parties.
## Comportements : PartyAI.think(c, ow, party, heures) pour chaque groupe autre que les armées.
## Rencontres : encounter.gd (autre module) s'il existe, sinon un choix minimal (attaquer / passer).

const HOURS_PER_DAY := 24.0
const START_HOUR := 8.0 ## Heure du premier matin
const MAX_STEP := 0.5 ## Pas de simulation, en heures (un tick plus long est découpé)
const CONTACT_RANGE := 22.0 ## Distance (carte) à laquelle deux groupes se touchent
const SIGHT := 180.0 ## Distance à laquelle un groupe hostile repère la compagnie
const COOLDOWN_HOURS := 10.0 ## Après une rencontre, le même groupe ne vous arrête plus pendant ce temps
const REPATH_DIST := 40.0 ## Poursuite : on recalcule le chemin quand la cible s'en écarte de tant
const FLEE_DIST := 220.0 ## Un groupe qui détale part à peu près de tant
## Densité de la population entretenue chaque jour (population_cap) : villageois par village,
## caravanes et patrouilles par ville, bandits par million de pixels² de carte, déserteurs par
## guerre en cours. Les saisons et les guerres la font varier (voir population_cap).
const POPULATION := {"villagers": 0.7, "caravan": 0.6, "patrol": 0.8, "bandits": 1.6, "deserters": 2.0}
const WINTER_CARAVANS := 0.5 ## En hiver, moins de caravanes...
const WAR_BANDITS := 1.5 ## ... en guerre, plus de bandits
const PEACE_DESERTERS := 1 ## Déserteurs tolérés en paix
const MAX_DESERTERS := 8
const SPAWNS_PER_DAY := 2 ## Réapparitions par sorte et par jour, au moins (voir spawns_per_day)
const SPAWN_DAYS := 5.0 ## Une sorte vidée retrouve son plafond en à peu près tant de jours
const WAR_DESERTER_CHANCE := 0.3 ## Chaque jour de guerre, chance que des soldats désertent (par guerre)
const BANDIT_NAMES := ["les Écorcheurs", "les Loups de Valfrène", "la bande du Borgne", "les Coupe-Bourses", "les Tard-Venus", "les Malandrins du Gué"]
const ENCOUNTER_SCRIPT := "res://scripts/encounter.gd"
const ALLY_RANGE := 120.0 ## Un groupe ami à moins de tant (carte) du combat se bat aux côtés de la compagnie
const JOIN_RANGE := ALLY_RANGE ## « Se joindre à eux » : la compagnie est assez près pour prendre part au combat
const MAX_ALLY_GROUPS := 2 ## Groupes alliés au plus dans une bataille
const WALLED := ["town", "castle"] ## Lieux à l'abri des murs : on n'y est jamais attaqué

var hour := START_HOUR ## Heure du jour (0 à 24)
var player := Party.new() ## La compagnie sur la carte (ses régiments : CampaignState.company)
var parties: Array[Party] = [] ## Groupes autres que la compagnie et les armées de faction
var inside := 0 ## Lieu (MapData.places) où la compagnie est entrée, -1 : en campagne
var enter_goal := -1 ## Lieu où entrer en arrivant au bout du chemin (-1 : aucun)
var marched := false ## La compagnie a marché aujourd'hui (évènements de route, froid)
var cooldown := {} ## id de groupe -> heures pendant lesquelles il ne provoque plus de rencontre
var truce := {} ## id de groupe -> heures pendant lesquelles aucun autre groupe ne l'attaque (vaincu qui détale)
var rng := RandomNumberGenerator.new()
var steps := 0 ## Pas de simulation écoulés (les groupes regardent autour d'eux un pas sur deux)
var spawning := true ## Faux : plus aucune réapparition (tests de comportement ; non sauvegardé)
## Bataille commune proposée : le groupe que suit la compagnie (« Se joindre à eux ») engage un
## ennemi à portée. {"ally": id, "enemy": id} ; vide sinon (non sauvegardé).
var joint := {}


func _init() -> void:
	player.kind = "player"
	player.id = 0
	player.name = "votre compagnie"


## Carte d'une campagne neuve (ou d'une sauvegarde d'avant le temps réel) : la compagnie dans sa
## ville, les premiers groupes sur les chemins.
static func create(c: CampaignState) -> Overworld:
	var ow := Overworld.new()
	ow.rng.seed = hash([c.rng.seed, "overworld"])
	ow.player.pos = MapData.place_pos(c.location)
	ow.inside = c.location
	ow.populate(c, true) # Toute la population dès le premier jour
	return ow


# ---------------------------------------------------------------- Registre des groupes

## Tous les groupes de la carte : la compagnie, les autres groupes, les armées de faction.
func all(c: CampaignState) -> Array[Party]:
	var out: Array[Party] = [player]
	out.append_array(parties)
	for a in c.world.armies:
		out.append(a)
	return out


func by_id(c: CampaignState, id: int) -> Party:
	for p in all(c):
		if p.id == id:
			return p
	return null


## Ajoute un groupe (il reçoit un identifiant unique, partagé avec les armées).
func add(c: CampaignState, p: Party) -> Party:
	p.id = c.world.next_id
	c.world.next_id += 1
	parties.append(p)
	return p


## Retire un groupe (une armée : du monde vivant).
func remove(c: CampaignState, p: Party) -> void:
	if p is WorldArmy:
		c.world.armies.erase(p)
	else:
		parties.erase(p)
		if not c.escort_for(p.id).is_empty(): # Caravane escortée disparue : escorte manquée
			var msg := c.finish_escort(p.id, false)
			if msg != "":
				c.add_log("Jour %d : %s" % [c.day, msg])
	cooldown.erase(str(p.id))
	truce.erase(str(p.id))


## Groupes à moins de radius de pos (sans la compagnie ni exclude), du plus proche au plus loin.
func near(c: CampaignState, pos: Vector2, radius: float, exclude := -1) -> Array[Party]:
	var out: Array[Party] = []
	for p in all(c):
		if p != player and p.id != exclude and not p.is_dead() and p.pos.distance_to(pos) <= radius:
			out.append(p)
	out.sort_custom(func(a: Party, b: Party) -> bool: return a.pos.distance_to(pos) < b.pos.distance_to(pos))
	return out


## Nombre de groupes d'une sorte.
func count(kind: String) -> int:
	var n := 0
	for p in parties:
		if p.kind == kind:
			n += 1
	return n


## Ce groupe attaque-t-il la compagnie ? (bandits ; armées d'après le monde vivant ; tout groupe
## qui la poursuit pour l'attaquer, comme une patrouille d'une faction hostile)
func hostile(c: CampaignState, p: Party) -> bool:
	if p is WorldArmy:
		return c.world.hostile_to_player(c, p)
	if p.kind == "bandits":
		return true
	return p.target_id == player.id and p.state in PartyAI.ATTACK_STATES


## Vitesse d'un groupe à sa position (pixels par heure) : sorte, terrain ou route, saison.
static func speed_of(c: CampaignState, p: Party) -> float:
	return p.base_speed() * MapData.speed_at(p.pos) * c.world.march_speed(c.day)


# ---------------------------------------------------------------- Ordres de la compagnie

## Marcher vers un point (un lieu sous ce point : on y entrera en arrivant). Renvoie une erreur ou "".
func go_to(c: CampaignState, pos: Vector2) -> String:
	if c.is_over():
		return "La campagne est terminée."
	if c.is_destroyed():
		return "Sans troupes, la compagnie ne peut plus marcher."
	var place := MapData.place_at(pos)
	var dest := MapData.place_pos(place) if place >= 0 else pos
	player.go(MapData.find_path(player.pos, dest))
	player.state = "idle" # Un nouvel ordre met fin à une marche à la suite d'un autre groupe
	enter_goal = place
	if player.path.is_empty():
		if place >= 0:
			enter(c, place)
		return ""
	inside = -1
	return ""


## Marcher vers un lieu et y entrer.
func go_to_place(c: CampaignState, i: int) -> String:
	return go_to(c, MapData.place_pos(i))


## Poursuivre un groupe (le contact déclenche la rencontre). Renvoie une erreur ou "".
func chase(c: CampaignState, id: int) -> String:
	var t := by_id(c, id)
	if t == null or t == player:
		return "Ce groupe n'est plus là."
	var err := go_to(c, t.pos)
	if err != "":
		return err
	enter_goal = -1
	player.target_id = id
	cooldown.erase(str(id)) # On le cherche : la rencontre aura lieu
	inside = -1
	return ""


## Halte : la compagnie s'arrête où elle est.
func halt() -> void:
	player.path.clear()
	player.target_id = -1
	player.state = "idle"
	enter_goal = -1


## La compagnie entre dans un lieu (une ville : on y signe, on y recrute).
func enter(c: CampaignState, i: int) -> void:
	inside = i
	enter_goal = -1
	player.path.clear()
	player.target_id = -1
	player.pos = MapData.place_pos(i)
	if i < CampaignState.TOWNS.size() and c.location != i:
		c.location = i
		c.refresh_contracts(i)
		c.add_log("Jour %d : arrivée à %s." % [c.day, CampaignState.TOWNS[i]["name"]])
	elif i < CampaignState.TOWNS.size():
		c.location = i


## Image de la compagnie en régiments (pour les rencontres, qui lisent n'importe quel groupe).
func sync_player(c: CampaignState) -> void:
	player.troops.clear()
	for r in c.company:
		player.troops.append({"type": str(r["type"]), "men": int(r["men"]), "xp": float(r.get("xp", 0.0))})


# ---------------------------------------------------------------- Le temps passe

## Fait passer hours heures de jeu. S'arrête plus tôt sur un évènement, renvoyé en dictionnaire :
## {"event": "enter", "place"} (arrivée dans un lieu), {"event": "contact", "id"} (rencontre),
## {"event": "battle"} (embuscade de la route), {"event": "over"} (fin de campagne) ; {} sinon.
## « day » : vrai si une journée s'est achevée pendant ce temps.
func tick(c: CampaignState, hours: float) -> Dictionary:
	var left := hours
	var days := false
	while left > 0.0001:
		var h := minf(MAX_STEP, left)
		left -= h
		var out := step(c, h)
		if out.get("day", false):
			days = true
		if out.has("event"):
			out["day"] = days
			return out
	return {"day": days}


func step(c: CampaignState, h: float) -> Dictionary:
	var out := {}
	steps += 1
	sync_player(c)
	# La compagnie
	if player.target_id >= 0:
		var t := by_id(c, player.target_id)
		if t == null or t.is_dead():
			player.target_id = -1
			player.path.clear()
		elif player.path.is_empty() or player.path[-1].distance_to(t.pos) > REPATH_DIST:
			player.path = MapData.find_path(player.pos, t.pos)
	if player.busy_hours > 0.0:
		player.busy_hours = maxf(0.0, player.busy_hours - h)
	elif not player.path.is_empty() and not c.is_destroyed():
		marched = true
		if player.advance(speed_of(c, player) * Supplies.pace(c) * h) and enter_goal >= 0 and player.target_id < 0:
			var place := enter_goal
			enter(c, place)
			out = {"event": "enter", "place": place}
	# Les autres groupes : leur comportement, puis leur marche
	for p in parties.duplicate():
		PartyAI.think(c, self, p, h)
		if p.busy_hours > 0.0:
			p.busy_hours = maxf(0.0, p.busy_hours - h)
		elif not p.path.is_empty():
			if p.advance(speed_of(c, p) * h):
				arrived(c, p)
	Supplies.tick(c, self, h) # Fatigue, repos, camp ; l'éclaireur repère les bandits cachés
	c.world.tick(c, h) # Les armées de faction
	PartyAI.skirmishes(c, self) # Combats entre groupes qui se touchent
	parties = parties.filter(func(p: Party) -> bool: return not p.is_dead())
	for k in cooldown.keys():
		cooldown[k] = float(cooldown[k]) - h
		if float(cooldown[k]) <= 0.0:
			cooldown.erase(k)
	for k in truce.keys():
		truce[k] = float(truce[k]) - h
		if float(truce[k]) <= 0.0:
			truce.erase(k)
	if out.is_empty() and not joint.is_empty():
		out = {"event": "contact", "id": int(joint["enemy"])} # Le groupe suivi engage le combat
	if out.is_empty():
		var who := contact(c)
		if who != null:
			if who.id == player.target_id:
				halt() # But atteint ; rattrapée par un groupe hostile, la compagnie garde son chemin
			out = {"event": "contact", "id": who.id}
	hour += h
	if hour >= HOURS_PER_DAY:
		hour -= HOURS_PER_DAY
		end_of_day(c)
		out["day"] = true
		if c.is_over():
			out["event"] = "over"
		elif c.in_battle() and not out.has("event"):
			out["event"] = "battle"
	return out


## Groupe qui touche la compagnie : celui qu'elle poursuit, ou un groupe hostile qui la rattrape
## (jamais dans les murs d'un lieu, ni pendant une bataille). null sinon.
func contact(c: CampaignState) -> Party:
	if sheltered() or c.in_battle() or c.is_over() or c.is_destroyed() or c.world.has_encounter():
		return null
	for p in near(c, player.pos, CONTACT_RANGE):
		if p.hidden or cooldown.has(str(p.id)):
			continue
		if p.id == player.target_id and player.state == "follow":
			continue # La compagnie marche avec ce groupe (« Se joindre à eux »)
		if p.id == player.target_id or hostile(c, p):
			return p
	return null


## La compagnie est-elle à l'abri des murs (ville, château) ? Dans un village, on peut l'attaquer.
func sheltered() -> bool:
	return inside >= 0 and str(MapData.place(inside)["kind"]) in WALLED


## Fin de journée : le jour de campagne passe, puis les évènements de la marche s'il y en a eu.
func end_of_day(c: CampaignState) -> void:
	c.travel_events.clear()
	c.pass_day()
	if marched and not c.is_destroyed() and not c.is_over():
		var to := MapData.nearest_town(player.path[-1] if not player.path.is_empty() else player.pos)
		c.march_day(to, self)
	marched = false
	populate(c)
	c.check_ruin()


# ---------------------------------------------------------------- Population

## Nombre de groupes d'une sorte que la carte entretient (POPULATION) : d'après le nombre de
## villages et de villes et la taille de la carte, moins de caravanes en hiver, plus de bandits et
## de déserteurs en guerre.
func population_cap(c: CampaignState, kind: String) -> int:
	var k := float(POPULATION.get(kind, 0.0))
	var wars := c.world.wars.size()
	match kind:
		"villagers":
			return ceili(PartyAI.places_of(["village"]).size() * k)
		"caravan":
			var n := PartyAI.places_of(["town"]).size() * k
			if c.world.season(c.day) == WorldSim.WINTER:
				n *= WINTER_CARAVANS
			return maxi(1, ceili(n))
		"patrol":
			return ceili(PartyAI.places_of(["town"]).size() * k)
		"bandits":
			var n := MapData.SIZE.x * MapData.SIZE.y / 1.0e6 * k
			if wars > 0:
				n *= WAR_BANDITS
			return maxi(1, ceili(n))
		"deserters":
			return mini(MAX_DESERTERS, PEACE_DESERTERS + ceili(wars * k))
	return 0


## Entretient la population de groupes (population_cap) : SPAWNS_PER_DAY nouveaux groupes par
## sorte et par jour au plus (fill : jusqu'au plafond, pour une carte neuve). Les batailles du
## monde vivant (WorldSim.aftermath) et les guerres jettent des déserteurs sur les chemins.
## Réapparitions par jour pour un plafond : SPAWNS_PER_DAY au moins, et assez pour que la grande
## carte se repeuple en SPAWN_DAYS jours environ.
static func spawns_per_day(cap: int) -> int:
	return maxi(SPAWNS_PER_DAY, ceili(cap / SPAWN_DAYS))


func populate(c: CampaignState, fill := false) -> void:
	if not spawning:
		c.world.aftermath.clear()
		return
	for kind in POPULATION:
		if kind == "deserters":
			continue
		var cap := population_cap(c, kind)
		var n := 0
		while count(kind) < cap and (fill or n < spawns_per_day(cap)):
			if spawn(c, kind) == null:
				break
			n += 1
	# Déserteurs : après les batailles du monde vivant, et chaque jour de guerre
	var cap_d := population_cap(c, "deserters")
	for e in c.world.aftermath:
		if count("deserters") < cap_d and rng.randf() < 0.7:
			var at: Vector2 = e.get("pos", Vector2.ZERO)
			spawn_deserters(c, PartyAI.random_point(self, at, 150.0), int(e.get("faction", -1)), int(e.get("men", 0)))
	c.world.aftermath.clear()
	for k in c.world.wars.keys():
		if count("deserters") >= cap_d or rng.randf() >= WAR_DESERTER_CHANCE:
			continue
		var pair := str(k).split("-")
		var f := int(pair[rng.randi() % pair.size()])
		var towns := c.world.towns_of(f)
		if towns.is_empty():
			continue
		var t := towns[rng.randi() % towns.size()]
		spawn_deserters(c, PartyAI.far_point(self, MapData.place_pos(t)), f, 0)
	if fill and count("deserters") < cap_d:
		spawn(c, "deserters")


## Fait apparaître un groupe d'une sorte : villageois dans un village, caravane dans une ville,
## patrouille dans une ville de sa faction, bandits dans un bois loin des villes, déserteurs loin
## des villes. null si aucun endroit ne convient.
func spawn(c: CampaignState, kind: String) -> Party:
	var p := Party.new()
	p.kind = kind
	match kind:
		"villagers":
			var villages := PartyAI.places_of(["village"])
			if villages.is_empty():
				return null
			# De préférence un village qui n'a pas déjà ses villageois sur les chemins
			var free: Array[int] = []
			for v in villages:
				var taken := false
				for q in parties:
					if q.kind == "villagers" and q.home == v:
						taken = true
						break
				if not taken:
					free.append(v)
			var pool := free if not free.is_empty() else villages
			p.home = pool[rng.randi() % pool.size()]
			p.pos = MapData.place_pos(p.home)
			p.faction = PartyAI.place_owner(c, p.home)
			p.troops = [{"type": "spear", "men": rng.randi_range(8, 16), "xp": 0.0}]
			p.state = "home"
			p.busy_hours = rng.randf_range(0.0, 12.0) # Pas tous au marché à la même heure
		"caravan":
			var towns := PartyAI.places_of(["town"])
			if towns.is_empty():
				return null
			p.home = towns[rng.randi() % towns.size()]
			p.pos = MapData.place_pos(p.home)
			p.faction = PartyAI.place_owner(c, p.home)
			p.troops = [{"type": "spear", "men": rng.randi_range(6, 10), "xp": 50.0}, {"type": "crossbow", "men": rng.randi_range(4, 8), "xp": 50.0}]
			p.goods = rng.randi_range(20, 50) * 10
			p.gold = rng.randi_range(2, 8) * 10
		"patrol":
			var towns: Array[int] = []
			for t in PartyAI.places_of(["town"]):
				if PartyAI.place_owner(c, t) >= 0 and not (t < CampaignState.TOWNS.size() and c.world.besieged(t)):
					towns.append(t)
			if towns.is_empty():
				return null
			p.home = towns[rng.randi() % towns.size()]
			p.pos = MapData.place_pos(p.home)
			p.faction = PartyAI.place_owner(c, p.home)
			var k := 1.5 if c.world.at_war_any(p.faction) else 1.0
			p.troops = [{"type": "spear", "men": int(rng.randi_range(10, 18) * k), "xp": rng.randf_range(60.0, 120.0)},
				{"type": "crossbow", "men": int(rng.randi_range(6, 10) * k), "xp": rng.randf_range(60.0, 120.0)},
				{"type": "cavalry", "men": int(rng.randi_range(4, 8) * k), "xp": rng.randf_range(60.0, 120.0)}]
			p.gold = rng.randi_range(2, 6) * 10
			p.speed_bonus = 1.4 # Sergents montés : ils rattrapent les brigands
			p.state = "garrison"
			p.busy_hours = rng.randf_range(0.0, 8.0)
		"bandits":
			p.base = lair(c)
			p.pos = p.base
			p.home = MapData.nearest_place(p.pos)
			p.name = bandit_name()
			p.troops = [{"type": "spear", "men": rng.randi_range(12, 24), "xp": rng.randf_range(0.0, 80.0)},
				{"type": "archer", "men": rng.randi_range(6, 14), "xp": rng.randf_range(0.0, 80.0)}]
			p.gold = rng.randi_range(3, 15) * 10
			p.state = "lurk"
			p.busy_hours = rng.randf_range(2.0, 12.0)
			p.hidden = MapData.ground_at(p.pos) == MapData.Ground.FOREST
		"deserters":
			var towns := PartyAI.places_of(["town"])
			if towns.is_empty():
				return null
			var t := towns[rng.randi() % towns.size()]
			return spawn_deserters(c, PartyAI.far_point(self, MapData.place_pos(t)), PartyAI.place_owner(c, t), 0)
		_:
			p.pos = MapData.place_pos(rng.randi() % MapData.place_count())
			p.troops = [{"type": "spear", "men": 10, "xp": 0.0}]
	return add(c, p)


## Des déserteurs (anciens soldats de la faction f) apparaissent en pos ; men : hommes perdus dans
## la bataille d'où ils viennent (0 : inconnu), dont une petite part déserte.
func spawn_deserters(c: CampaignState, pos: Vector2, f: int, men: int) -> Party:
	var p := Party.new()
	p.kind = "deserters"
	p.faction = f
	p.pos = MapData.walkable_point(pos)
	var n := clampi(int(men * 0.1), 8, 30) if men > 0 else rng.randi_range(8, 20)
	@warning_ignore("integer_division")
	var archers := n / 3
	p.troops = [{"type": "men_at_arms" if rng.randf() < 0.3 else "spear", "men": n - archers, "xp": rng.randf_range(40.0, 100.0)},
		{"type": "crossbow" if rng.randf() < 0.5 else "archer", "men": archers, "xp": rng.randf_range(40.0, 100.0)}]
	p.state = "idle"
	p.gold = rng.randi_range(0, 4) * 10
	return add(c, p)


## Nom d'une bande de brigands (tiré par rng).
func bandit_name() -> String:
	return str(BANDIT_NAMES[rng.randi() % BANDIT_NAMES.size()])


## Nouvelle d'un combat ou d'un évènement entre groupes de la carte : aux nouvelles du monde, et
## au journal de la compagnie si c'est près d'elle ou important.
func report(c: CampaignState, text: String, pos: Vector2, important: bool) -> void:
	if important or pos.distance_to(player.pos) <= PartyAI.LOG_RANGE:
		c.add_log("Jour %d : %s" % [c.day, CampaignState.cap_first(text)])
	c.world.post(c, text)


## Repaire de bandits : un point praticable, de préférence en forêt, loin des villes et de la compagnie.
func lair(c: CampaignState) -> Vector2:
	var best := Vector2(MapData.SIZE * 0.5)
	for i in 30:
		var p := Vector2(rng.randf_range(60, MapData.SIZE.x - 60), rng.randf_range(60, MapData.SIZE.y - 60))
		if not MapData.walkable(p) or p.distance_to(player.pos) < 500.0:
			continue
		var town := MapData.nearest_town(p)
		if p.distance_to(MapData.place_pos(town)) < 250.0:
			continue
		best = p
		if MapData.ground_at(p) == MapData.Ground.FOREST:
			break
	return MapData.walkable_point(best)


# ---------------------------------------------------------------- Rencontres

## Script des rencontres (encounter.gd, autre module) s'il existe, null sinon.
static func encounter_script() -> Script:
	if ResourceLoader.exists(ENCOUNTER_SCRIPT):
		return load(ENCOUNTER_SCRIPT) as Script
	return null


static func _has_static(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if str(m["name"]) == method:
			return true
	return false


## Choix proposés quand la compagnie touche other : ceux d'encounter.gd (Encounter.options), sinon
## « Attaquer » et « Passer son chemin » (fuir, s'il est hostile). Chaque choix : {"id", "text"}.
func options(c: CampaignState, other: Party) -> Array[Dictionary]:
	if is_joint(other):
		var ally := by_id(c, int(joint["ally"]))
		var who := ally.display_name() if ally != null else "vos alliés"
		return [
			{"id": "join_battle", "text": "Combattre aux côtés de %s" % who, "hint": "Ils se battent avec vous, menés par leurs chefs."},
			{"id": "stand_aside", "text": "Les laisser se battre seuls", "hint": ""},
		] as Array[Dictionary]
	var enc := encounter_script()
	if enc != null and _has_static(enc, "options"):
		var got: Variant = enc.call("options", c, player, other)
		var out: Array[Dictionary] = []
		if got is Array:
			for o in got:
				if o is Dictionary:
					out.append(o)
		if not out.is_empty():
			return out
	var leave := "Passer son chemin"
	if hostile(c, other):
		leave = "Fuir (abandonner %d écus de bagages)" % int(floor(c.gold * WorldSim.FLEE_GOLD))
	return [{"id": "attack", "text": "Attaquer"}, {"id": "leave", "text": leave}] as Array[Dictionary]


## Applique un choix de rencontre : Encounter.resolve s'il existe, sinon le choix minimal.
## Renvoie {"battle": bool, "contract": Dictionary, "text": String, "remove_other": bool}. Une
## bataille est mise en attente (c.pending) ; le groupe ne vous arrête plus un moment.
func resolve(c: CampaignState, other: Party, option_id: String) -> Dictionary:
	var out := {}
	var logged := false # encounter.gd tient déjà le journal
	var enc := encounter_script()
	if is_joint(other):
		out = resolve_joint(c, other, option_id)
		logged = true
		if out.is_empty():
			return {"battle": false, "contract": {}, "text": "", "remove_other": false}
	elif enc != null and _has_static(enc, "resolve"):
		var got: Variant = enc.call("resolve", c, player, other, option_id)
		if got is Dictionary:
			out = got
			logged = true
	if out.is_empty():
		out = default_resolve(c, other, option_id)
	cooldown[str(other.id)] = COOLDOWN_HOURS
	if bool(out.get("other_flees", false)):
		run_away(other, player.pos)
	if bool(out.get("player_flees", false)):
		cooldown[str(other.id)] = COOLDOWN_HOURS * 2.0 # Distancé : il ne vous retrouve pas de sitôt
	if bool(out.get("battle", false)):
		var k: Dictionary = out.get("contract", {})
		if k.is_empty() or other is WorldArmy:
			k = party_battle(c, other) # Une armée de faction : bataille du monde vivant (dispersée si vaincue)
		k["party"] = other.id
		if not k.has("siege"):
			var site := battle_site(other)
			k["site"] = site # L'endroit exact du contact (battle_site.gd)
			k["terrain"] = str(site["kind"])
			var allies := allies_for(c, other)
			if not allies.is_empty():
				k["allies"] = allies
		out["contract"] = k
		c.pending = k
	if bool(out.get("remove_other", false)):
		remove(c, other)
	var text := str(out.get("text", ""))
	if text != "" and not logged:
		c.add_log("Jour %d : %s" % [c.day, text])
	return out


## Un groupe détale loin de from (sur un point praticable) et cesse toute poursuite.
func run_away(p: Party, from: Vector2) -> void:
	var dir := (p.pos - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(rng.randf() * TAU)
	var to := MapData.walkable_point((p.pos + dir * FLEE_DIST).clamp(Vector2(20, 20), MapData.SIZE - Vector2(20, 20)))
	p.go(MapData.find_path(p.pos, to))
	p.target_id = -1
	p.state = "flee"
	p.busy_hours = 0.0


## Un groupe arrive au bout de son chemin : une caravane escortée jusqu'à son but paie l'escorte.
func arrived(c: CampaignState, p: Party) -> void:
	var e := c.escort_for(p.id)
	if e.is_empty():
		return
	var goal := int(e.get("goal", -1))
	if goal < 0 or p.pos.distance_to(MapData.place_pos(goal)) <= MapData.PLACE_RADIUS:
		var msg := c.finish_escort(p.id, true)
		if msg != "":
			c.add_log("Jour %d : %s" % [c.day, CampaignState.cap_first(msg)])


func default_resolve(c: CampaignState, other: Party, option_id: String) -> Dictionary:
	var who := other.display_name()
	if option_id == "attack":
		return {"battle": true, "contract": party_battle(c, other), "text": "La compagnie attaque %s." % who, "remove_other": false}
	if hostile(c, other):
		var lost := int(floor(c.gold * WorldSim.FLEE_GOLD))
		c.gold -= lost
		return {"battle": false, "contract": {}, "text": "La compagnie se dérobe devant %s et abandonne %d écus de bagages." % [who, lost], "remove_other": false}
	return {"battle": false, "contract": {}, "text": "La compagnie croise %s et passe son chemin." % who, "remove_other": false}


## Bataille contre un groupe de la carte, sur le terrain de l'endroit : une armée de faction
## (WorldSim.make_battle), CampaignState.party_contract s'il existe (module des rencontres), sinon
## l'armée tirée des régiments du groupe (ni prime ni faction : le butin).
func party_battle(c: CampaignState, other: Party) -> Dictionary:
	var land := str(battle_site(other)["kind"])
	var town := MapData.nearest_town(player.pos)
	if other is WorldArmy:
		return c.world.make_battle(c, other as WorldArmy, town, land)
	if c.has_method("party_contract"):
		var k: Variant = c.call("party_contract", other, land)
		if k is Dictionary and not (k as Dictionary).is_empty():
			return k
	var enemy: Array[Dictionary] = []
	for r in other.troops:
		if int(r.get("men", 0)) > 0:
			enemy.append({"type": str(r["type"]), "men": maxi(3, int(r["men"])), "rank": CampaignState.rank_from_xp(float(r.get("xp", 0.0)))})
	if enemy.is_empty():
		enemy.append({"type": "spear", "men": 5, "rank": 0})
	var who := other.display_name()
	return {
		"town": town, "faction": -1, "party": other.id, "terrain": land,
		"title": "Combat contre %s près de %s" % [who, CampaignState.TOWNS[town]["name"]],
		"text": "Sur la carte, la compagnie a rattrapé %s. Pas de prime : seulement le butin." % who,
		"foe": who, "difficulty": clampi(ceili(enemy.size() / 2.0), 1, CampaignState.MAX_LEVEL),
		"enemy": enemy, "reward": 0, "expires": c.day, "seed": c.rng.randi_range(1, 1 << 30),
		"objective": {"kind": "destroy"}, "enemy_faction": -1,
	}


## Fin d'une bataille contre un groupe de la carte (finish_battle, pending encore en place) :
## CampaignState.apply_party_battle s'il existe, sinon le groupe vaincu disparaît et son or va au
## butin ; vainqueur, il reste en place (et ne vous arrête plus un moment). Renvoie une note.
func after_battle(c: CampaignState, victory: bool, result: Dictionary) -> String:
	if not c.pending.has("party") or c.pending.has("world_army"):
		return ""
	var other := by_id(c, int(c.pending["party"]))
	if other == null or other is WorldArmy:
		return ""
	if c.has_method("apply_party_battle"):
		var r := result.duplicate()
		r["victory"] = victory # Le bilan n'est pas encore complet (finish_report vient après)
		var note := str(c.call("apply_party_battle", other, r))
		cooldown[str(other.id)] = COOLDOWN_HOURS
		if other.is_dead():
			remove(c, other)
		return (" " + note) if note != "" else ""
	cooldown[str(other.id)] = COOLDOWN_HOURS
	if not victory:
		return ""
	var loot := other.gold + other.goods / 2
	c.gold += loot
	c.gold_earned += loot
	remove(c, other)
	return " %s : le groupe est dispersé%s." % [CampaignState.cap_first(other.display_name()), (", %d écus repris" % loot) if loot > 0 else ""]


# ---------------------------------------------------------------- Champ de bataille et alliés

## Champ de bataille de l'endroit exact où la compagnie rencontre other (battle_site.gd) ;
## dans un village où elle se trouvait, on se bat dans le village.
func battle_site(other: Party) -> Dictionary:
	return BattleSite.describe(player.pos, other.pos if other != null else player.pos, inside)


## Groupe qui se battrait aux côtés de la compagnie contre foe : patrouille ou armée d'une faction
## qui ne lui est pas hostile et qu'elle suit (« Se joindre à eux »), qui sert la faction du
## contrat, ou qui combat foe (bandits et déserteurs sont les ennemis de toutes les patrouilles ;
## sinon, une faction en guerre contre celle de foe).
func friendly_to(c: CampaignState, p: Party, foe: Party) -> bool:
	if p == null or p == foe or p == player or p.is_dead() or not p.kind in ["patrol", "army"] or p.faction < 0:
		return false
	if hostile(c, p) or c.faction_closed(p.faction) or c.reputation[p.faction] < 0:
		return false
	if p.id == player.target_id and player.state == "follow":
		return true
	if foe == null:
		return false
	if p.faction == int(c.pending.get("faction", -2)):
		return true
	if foe.kind in ["bandits", "deserters"]:
		return true
	return foe.faction >= 0 and foe.faction != p.faction and c.world.at_war(p.faction, foe.faction)


## Groupes amis à portée du combat contre other, pour le contrat (« allies ») : {party, name,
## faction, troops} ; au plus MAX_ALLY_GROUPS, les plus proches d'abord.
func allies_for(c: CampaignState, other: Party) -> Array:
	var list: Array[Party] = []
	for p in near(c, player.pos, ALLY_RANGE, other.id if other != null else -1):
		if friendly_to(c, p, other):
			list.append(p)
	list.sort_custom(func(a: Party, b: Party) -> bool: return a.pos.distance_to(player.pos) < b.pos.distance_to(player.pos))
	var out: Array = []
	for p in list:
		if out.size() >= MAX_ALLY_GROUPS:
			break
		if p is WorldArmy:
			(p as WorldArmy).sync_troops()
		var troops: Array = []
		for r in p.troops:
			var type := str(r.get("type", ""))
			var men := int(r.get("men", 0))
			if not UnitTypes.STATS.has(type) or men <= 0:
				continue
			var full := int(UnitTypes.STATS[type]["count"])
			while men > 0: # En régiments complets
				troops.append({"type": type, "men": mini(men, full), "rank": CampaignState.rank_from_xp(float(r.get("xp", 0.0)))})
				men -= full
		if not troops.is_empty():
			out.append({"party": p.id, "name": p.display_name(), "faction": p.faction, "troops": troops})
	return out


## Noms des groupes amis qui combattraient aux côtés de la compagnie contre other ("" : aucun).
func allies_line(c: CampaignState, other: Party) -> String:
	var names: Array[String] = []
	for g in allies_for(c, other):
		names.append(str(g["name"]))
	return " et ".join(names)


## Le groupe que suit la compagnie (« Se joindre à eux ») va combattre a ou b : si la compagnie
## est à portée, la bataille lui est proposée au lieu d'être résolue d'office (PartyAI.skirmishes,
## WorldSim.clashes). Renvoie vrai si la proposition est faite (le combat attend la réponse).
func offer_joint(c: CampaignState, a: Party, b: Party) -> bool:
	if not joint.is_empty():
		return int(joint["ally"]) in [a.id, b.id] or int(joint["enemy"]) in [a.id, b.id]
	if player.state != "follow" or player.target_id < 0 or sheltered() or c.in_battle() or c.is_destroyed() or c.is_over():
		return false
	var ally: Party = null
	if a.id == player.target_id:
		ally = a
	elif b.id == player.target_id:
		ally = b
	if ally == null:
		return false
	var foe := b if ally == a else a
	if cooldown.has(str(foe.id)) or player.pos.distance_to(ally.pos) > JOIN_RANGE:
		return false
	joint = {"ally": ally.id, "enemy": foe.id}
	for p in [a, b]:
		if not p is WorldArmy:
			(p as Party).busy_hours = maxf((p as Party).busy_hours, 0.5) # Ils se font face
	return true


func is_joint(other: Party) -> bool:
	return other != null and not joint.is_empty() and int(joint["enemy"]) == other.id


## Réponse à une bataille commune : « join_battle » (la compagnie combat aux côtés du groupe
## suivi, et de tout autre ami à portée) ou « stand_aside » (le combat se résout sans elle).
func resolve_joint(c: CampaignState, other: Party, option_id: String) -> Dictionary:
	var ally := by_id(c, int(joint["ally"]))
	joint = {}
	if ally == null or ally.is_dead():
		return {}
	if option_id == "join_battle":
		var k := party_battle(c, other)
		var who := ally.display_name()
		k["title"] = "Aux côtés de %s contre %s" % [who, other.display_name()]
		k["text"] = "%s engage %s ; la compagnie se jette dans la mêlée." % [CampaignState.cap_first(who), other.display_name()]
		var text := "La compagnie combat aux côtés de %s contre %s." % [who, other.display_name()]
		c.add_log("Jour %d : %s" % [c.day, text])
		return {"battle": true, "contract": k, "text": text, "remove_other": false}
	cooldown[str(other.id)] = COOLDOWN_HOURS # On ne propose plus ce combat
	if other is WorldArmy and ally is WorldArmy:
		c.world.clashes(c) # Les deux armées se battent sans la compagnie
	else:
		PartyAI.fight(c, self, ally, other)
	var text := "La compagnie regarde %s se battre contre %s." % [ally.display_name(), other.display_name()]
	c.add_log("Jour %d : %s" % [c.day, text])
	return {"battle": false, "contract": {}, "text": text, "remove_other": false}


# ---------------------------------------------------------------- Sauvegarde

func to_dict() -> Dictionary:
	var list: Array = []
	for p in parties:
		list.append(p.to_dict())
	return {
		"hour": hour, "player": player.to_dict(), "parties": list,
		"inside": inside, "enter_goal": enter_goal, "marched": marched, "steps": steps,
		"cooldown": cooldown.duplicate(), "truce": truce.duplicate(), "rng_seed": str(rng.seed), "rng_state": str(rng.state),
	}


## Relit la carte sauvegardée ; d vide (sauvegarde d'avant le temps réel) : la compagnie est placée
## dans sa ville (c.location), de nouveaux groupes apparaissent.
static func from_dict(d: Variant, c: CampaignState) -> Overworld:
	if not d is Dictionary or (d as Dictionary).is_empty():
		return create(c)
	var ow := Overworld.new()
	ow.hour = fposmod(float(d.get("hour", START_HOUR)), HOURS_PER_DAY)
	var pl := Party.from_dict(d.get("player", {}))
	if pl != null and pl.kind == "player":
		ow.player = pl
		ow.player.id = 0
		ow.player.pos = ow.player.pos.clamp(Vector2.ZERO, MapData.SIZE)
	else:
		ow.player.pos = MapData.place_pos(c.location)
	for x in d.get("parties", []):
		var p := Party.from_dict(x)
		if p != null and p.kind != "player" and p.kind != "army":
			ow.parties.append(p)
	ow.inside = clampi(int(d.get("inside", -1)), -1, MapData.place_count() - 1)
	ow.enter_goal = clampi(int(d.get("enter_goal", -1)), -1, MapData.place_count() - 1)
	ow.marched = bool(d.get("marched", false))
	ow.steps = maxi(0, int(d.get("steps", 0)))
	var cd: Variant = d.get("cooldown", {})
	if cd is Dictionary:
		for k in cd:
			ow.cooldown[str(k)] = float(cd[k])
	var tr: Variant = d.get("truce", {})
	if tr is Dictionary:
		for k in tr:
			ow.truce[str(k)] = float(tr[k])
	ow.rng.seed = str(d.get("rng_seed", "1")).to_int()
	ow.rng.state = str(d.get("rng_state", "1")).to_int()
	return ow
