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
## Population entretenue chaque jour (sorte -> nombre de groupes). Les sessions suivantes en
## ajouteront d'autres (patrouilles, déserteurs) avec leurs comportements.
const POPULATION := {"villagers": 4, "bandits": 3, "caravan": 2}
const BANDIT_NAMES := ["les Écorcheurs", "les Loups de Valfrène", "la bande du Borgne", "les Coupe-Bourses", "les Tard-Venus", "les Malandrins du Gué"]
const ENCOUNTER_SCRIPT := "res://scripts/encounter.gd"

var hour := START_HOUR ## Heure du jour (0 à 24)
var player := Party.new() ## La compagnie sur la carte (ses régiments : CampaignState.company)
var parties: Array[Party] = [] ## Groupes autres que la compagnie et les armées de faction
var inside := 0 ## Lieu (MapData.places) où la compagnie est entrée, -1 : en campagne
var enter_goal := -1 ## Lieu où entrer en arrivant au bout du chemin (-1 : aucun)
var marched := false ## La compagnie a marché aujourd'hui (évènements de route, froid)
var cooldown := {} ## id de groupe -> heures pendant lesquelles il ne provoque plus de rencontre
var rng := RandomNumberGenerator.new()


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
	for i in 4: # Toute la population dès le premier jour
		ow.populate(c)
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
	cooldown.erase(str(p.id))


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


## Ce groupe attaque-t-il la compagnie ? (bandits ; armées d'après le monde vivant)
func hostile(c: CampaignState, p: Party) -> bool:
	if p is WorldArmy:
		return c.world.hostile_to_player(c, p)
	return p.kind == "bandits"


## Vitesse d'un groupe à sa position (pixels par heure) : sorte, terrain ou route, saison.
static func speed_of(c: CampaignState, p: Party) -> float:
	return p.base_speed() * MapData.speed_at(p.pos) * WorldSim.march_factor(c.day)


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
		if player.advance(speed_of(c, player) * h) and enter_goal >= 0 and player.target_id < 0:
			var place := enter_goal
			enter(c, place)
			out = {"event": "enter", "place": place}
	# Les autres groupes : leur comportement, puis leur marche
	for p in parties.duplicate():
		PartyAI.think(c, self, p, h)
		if p.busy_hours > 0.0:
			p.busy_hours = maxf(0.0, p.busy_hours - h)
		elif not p.path.is_empty():
			p.advance(speed_of(c, p) * h)
	parties = parties.filter(func(p: Party) -> bool: return not p.is_dead())
	c.world.tick(c, h) # Les armées de faction
	for k in cooldown.keys():
		cooldown[k] = float(cooldown[k]) - h
		if float(cooldown[k]) <= 0.0:
			cooldown.erase(k)
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
	if inside >= 0 or c.in_battle() or c.is_over() or c.is_destroyed() or c.world.has_encounter():
		return null
	for p in near(c, player.pos, CONTACT_RANGE):
		if p.hidden or cooldown.has(str(p.id)):
			continue
		if p.id == player.target_id or hostile(c, p):
			return p
	return null


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

## Entretient la population de groupes (POPULATION), un nouveau groupe par sorte et par jour au plus.
func populate(c: CampaignState) -> void:
	for kind in POPULATION:
		if count(kind) < int(POPULATION[kind]):
			spawn(c, kind)


## Fait apparaître un groupe d'une sorte : villageois près d'un village, caravane dans une ville,
## bandits dans un bois loin des villes.
func spawn(c: CampaignState, kind: String) -> Party:
	var p := Party.new()
	p.kind = kind
	var villages: Array[int] = []
	for pl in MapData.places():
		if pl["kind"] == "village":
			villages.append(int(pl["id"]))
	match kind:
		"villagers":
			p.home = villages[rng.randi() % villages.size()]
			p.pos = MapData.place_pos(p.home)
			p.faction = int(MapData.place(p.home)["faction"])
			p.troops = [{"type": "spear", "men": rng.randi_range(8, 16), "xp": 0.0}]
			p.goods = rng.randi_range(4, 12) * 10
		"caravan":
			p.home = rng.randi() % CampaignState.TOWNS.size()
			p.pos = MapData.place_pos(p.home)
			p.faction = c.town_owner(p.home)
			p.troops = [{"type": "spear", "men": rng.randi_range(6, 10), "xp": 50.0}, {"type": "crossbow", "men": rng.randi_range(4, 8), "xp": 50.0}]
			p.goods = rng.randi_range(20, 50) * 10
		"bandits":
			p.pos = lair(c)
			p.home = MapData.nearest_place(p.pos)
			p.name = str(BANDIT_NAMES[rng.randi() % BANDIT_NAMES.size()])
			p.troops = [{"type": "spear", "men": rng.randi_range(12, 24), "xp": rng.randf_range(0.0, 80.0)},
				{"type": "archer", "men": rng.randi_range(6, 14), "xp": rng.randf_range(0.0, 80.0)}]
			p.gold = rng.randi_range(3, 15) * 10
		_:
			p.pos = MapData.place_pos(rng.randi() % MapData.place_count())
			p.troops = [{"type": "spear", "men": 10, "xp": 0.0}]
	return add(c, p)


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
	var enc := encounter_script()
	if enc != null and _has_static(enc, "resolve"):
		var got: Variant = enc.call("resolve", c, player, other, option_id)
		if got is Dictionary:
			out = got
	if out.is_empty():
		out = default_resolve(c, other, option_id)
	cooldown[str(other.id)] = COOLDOWN_HOURS
	if bool(out.get("battle", false)):
		var k: Dictionary = out.get("contract", {})
		if k.is_empty():
			k = party_battle(c, other)
		k["party"] = other.id
		if not k.has("terrain"):
			k["terrain"] = MapData.battle_terrain_at(player.pos)
		out["contract"] = k
		c.pending = k
	if bool(out.get("remove_other", false)):
		remove(c, other)
	var text := str(out.get("text", ""))
	if text != "":
		c.add_log("Jour %d : %s" % [c.day, text])
	return out


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
	var land := MapData.battle_terrain_at(player.pos)
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
		c.call("apply_party_battle", other, result)
		if other.is_dead():
			remove(c, other)
		return ""
	cooldown[str(other.id)] = COOLDOWN_HOURS
	if not victory:
		return ""
	var loot := other.gold + other.goods / 2
	c.gold += loot
	c.gold_earned += loot
	remove(c, other)
	return " %s : le groupe est dispersé%s." % [CampaignState.cap_first(other.display_name()), (", %d écus repris" % loot) if loot > 0 else ""]


# ---------------------------------------------------------------- Sauvegarde

func to_dict() -> Dictionary:
	var list: Array = []
	for p in parties:
		list.append(p.to_dict())
	return {
		"hour": hour, "player": player.to_dict(), "parties": list,
		"inside": inside, "enter_goal": enter_goal, "marched": marched,
		"cooldown": cooldown.duplicate(), "rng_seed": str(rng.seed), "rng_state": str(rng.state),
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
	var cd: Variant = d.get("cooldown", {})
	if cd is Dictionary:
		for k in cd:
			ow.cooldown[str(k)] = float(cd[k])
	ow.rng.seed = str(d.get("rng_seed", "1")).to_int()
	ow.rng.state = str(d.get("rng_state", "1")).to_int()
	return ow
