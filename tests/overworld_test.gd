extends SceneTree
## Test headless de la carte du monde en temps réel (map_data.gd, overworld.gd, party_ai.gd,
## world_army.gd et campaign_map.gd) :
##   godot --headless --path . -s tests/overworld_test.gd
## - MapData : grande carte (deux fois l'ancienne), lieux, routes et ponts, montagnes, régions,
##   terrain, chemins qui contournent l'eau et les montagnes, tout lieu accessible ;
## - déplacement de la compagnie, vitesse sur la route et hors route, hiver plus lent ;
## - le jour qui passe (solde, monde vivant), registre des groupes et comportement par défaut ;
## - contact : poursuite d'un groupe, groupe hostile qui rattrape la compagnie, choix et bataille ;
## - sauvegarde (position, chemin, heure, groupes) et migration d'une sauvegarde de version 8 ;
## - la scène de la carte : clic, rencontre, retour de bataille à l'endroit du combat.
## N'écrit que dans user://test_carte_*.json. Code de sortie : 0 si tout va bien, 1 sinon.


class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s:%d (%s) %s" % [file, line, function, rationale if rationale != "" else code])
		mutex.unlock()


var counter := ErrorCounter.new()
var fails: Array[String] = []
var frame := 0
var map: Node
var fought_id := -1


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.slot_prefix = "user://test_carte"
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.use_slot(1)
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	_test_map_data()
	_test_movement()
	_test_day()
	_test_registry()
	_test_contact()
	_test_save()


## Campagne riche, sans groupes errants (pour des marches sans rencontre).
func quiet(seed_value: int) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.gold = 1.0e6
	c.overworld.parties.clear()
	c.world.armies.clear()
	return c


# ---------------------------------------------------------------- MapData

func _test_map_data() -> void:
	check(MapData.SIZE.x * MapData.SIZE.y >= 2.0 * 2640.0 * 2160.0, "carte : pas deux fois plus grande que l'ancienne")
	check(CampaignState.TOWNS == MapData.TOWNS and MapData.place_count() >= 35, "carte : villes ou lieux (%d)" % MapData.place_count())
	# Les lieux de l'ancienne carte gardent leur indice (sauvegardes) : le dernier est Fort-Lisière
	check(MapData.place_named("Fort-Lisière") == 20 and MapData.place_named("Les Aulnes") == 7, "carte : anciens lieux déplacés")
	var kinds_seen := {}
	for i in MapData.place_count():
		var pl := MapData.place(i)
		kinds_seen[pl["kind"]] = true
		check(int(pl["id"]) == i and MapData.KIND_NAMES.has(str(pl["kind"])), "lieu %d mal décrit" % i)
		check(MapData.walkable(pl["pos"]) and MapData.place_at(pl["pos"]) == i, "lieu %s dans l'eau ou introuvable" % pl["name"])
		if i < CampaignState.TOWNS.size():
			check(pl["kind"] == "town" and pl["pos"] == CampaignState.TOWNS[i]["pos"], "ville %d différente de TOWNS" % i)
		# Un lieu appartient au seigneur de sa région (les repaires et les ruines à personne)
		var reg := MapData.region_at(pl["pos"])
		if not str(pl["kind"]) in ["lair", "ruins"]:
			check(int(MapData.REGIONS[reg]["faction"]) == int(pl["faction"]), "lieu %s : faction %d dans %s" % [pl["name"], pl["faction"], MapData.REGIONS[reg]["name"]])
		for j in range(i + 1, MapData.place_count()):
			check(MapData.place_pos(j).distance_to(pl["pos"]) > MapData.PLACE_RADIUS * 2.5, "lieux trop proches : %s, %s" % [pl["name"], MapData.place(j)["name"]])
	check(kinds_seen.size() >= 9, "carte : sortes de lieux %s" % str(kinds_seen.keys()))
	# Routes : jamais dans un lac ; des ponts sur les rivières ; les trois sortes de routes
	var classes := {}
	for k in MapData.roads().size():
		classes[MapData.road_class(k)] = true
		var pts := MapData.road_points(k)
		var r: Array = MapData.roads()[k]
		check(pts[0] == MapData.place_pos(r[0]) and pts[-1] == MapData.place_pos(r[1]), "route %d : ne relie pas ses lieux" % k)
		for p in pts:
			if MapData.lake_factor(p) < 1.0:
				check(false, "route %s - %s dans un lac" % [MapData.place(r[0])["name"], MapData.place(r[1])["name"]])
				break
	check(classes.size() == 3 and MapData.roads().size() >= MapData.place_count(), "routes : réseau secondaire")
	check(MapData.bridges().size() >= 10, "ponts : %d" % MapData.bridges().size())
	for b in MapData.bridges():
		var mid: Vector2 = (b["a"] + b["b"]) * 0.5
		check(MapData.walkable(mid) and MapData.ground_name(mid) in ["pont", "route"], "pont infranchissable en %s" % str(mid))
	# Régions : chacune a des terres à son centre, et toutes les factions en ont
	var factions := {}
	for i in MapData.REGIONS.size():
		factions[int(MapData.REGIONS[i]["faction"])] = true
	check(factions.size() == CampaignState.FACTIONS.size() + 1 and MapData.REGIONS.size() >= 10, "régions : factions %s" % str(factions.keys()))
	# Tous les lieux sont accessibles depuis Valombre
	for i in range(1, MapData.place_count()):
		var path := MapData.find_path(MapData.place_pos(0), MapData.place_pos(i))
		check(not path.is_empty() and path[-1].distance_to(MapData.place_pos(i)) < 1.0, "lieu inaccessible : %s" % MapData.place(i)["name"])
	# Montagnes : infranchissables hors des cols ; un chemin les contourne ou passe le col
	var peak := Vector2.ZERO
	var g := MapData.grid_size()
	for y in g.y:
		for x in g.x:
			if MapData.ground_cell(Vector2i(x, y)) == MapData.Ground.MOUNTAIN and not MapData.is_road_cell(Vector2i(x, y)):
				peak = MapData.cell_center(Vector2i(x, y))
	check(peak != Vector2.ZERO and not MapData.walkable(peak) and MapData.battle_terrain_at(peak) == "hills", "montagne : praticable ou absente")
	var over := MapData.find_path(Vector2(2700, 560), Vector2(3250, 560)) # Par-dessus les Monts de Fer
	var at0 := Vector2(2700, 560)
	var blocked := 0
	for q in over:
		for k in 10:
			if not MapData.walkable(at0.lerp(q, k / 10.0)):
				blocked += 1
		at0 = q
	check(not over.is_empty() and blocked <= 2, "montagne : le chemin passe à travers (%d)" % blocked)
	# Terrain : une route est plus rapide que la plaine, la forêt et le marais plus lents
	var rp := MapData.road_points(0)
	var road := rp[rp.size() / 2]
	check(MapData.is_road(road) and is_equal_approx(MapData.speed_at(road), MapData.ROAD_SPEED), "route : vitesse %.2f" % MapData.speed_at(road))
	var kinds := {}
	for y in range(8, int(MapData.SIZE.y), 32):
		for x in range(8, int(MapData.SIZE.x), 32):
			var p := Vector2(x, y)
			if not MapData.is_road(p):
				kinds[MapData.ground_at(p)] = MapData.speed_at(p)
			var bt := MapData.battle_terrain_at(p)
			check(bt in MapData.BATTLE_TERRAINS, "terrain de bataille %s" % bt)
	for gr in [MapData.Ground.PLAIN, MapData.Ground.FOREST, MapData.Ground.HILLS, MapData.Ground.MARSH, MapData.Ground.WATER, MapData.Ground.MOUNTAIN]:
		check(kinds.has(gr), "carte : aucun terrain %s" % MapData.GROUND_NAMES[gr])
	check(float(kinds.get(MapData.Ground.FOREST, 9.0)) < 1.0 and float(kinds.get(MapData.Ground.MARSH, 9.0)) < float(kinds.get(MapData.Ground.FOREST, 0.0)), "vitesses de terrain")
	check(MapData.battle_terrain_at(MapData.place_pos(8)) == "village", "terrain de bataille d'un village")
	check(MapData.battle_terrain_at(MapData.place_pos(MapData.place_named("Gué-aux-Saules"))) == "river", "terrain de bataille d'un gué")
	var seen := {}
	for p in [MapData.place_pos(0), MapData.place_pos(3), MapData.place_pos(5), Vector2(MapData.river_x(300) + 60, 300)]:
		seen[MapData.battle_terrain_at(p)] = true
	# Chemin : traverse la rivière par un pont, jamais dans l'eau
	var west := Vector2(MapData.river_x(3020) - 200, 3020) # Loin des ponts et des gués
	var east := Vector2(MapData.river_x(3020) + 200, 3020)
	var path := MapData.find_path(west, east)
	check(not path.is_empty() and path[-1].distance_to(east) < 1.0, "chemin : n'arrive pas")
	var at := west
	var wet := 0
	for q in path:
		for k in 20:
			if not MapData.walkable(at.lerp(q, k / 20.0)):
				wet += 1
		at = q
	check(wet <= 2, "chemin : %d points dans l'eau" % wet)
	check(MapData.path_length(west, path) > west.distance_to(east) * 1.2, "chemin : traverse la rivière sans pont")
	check(not MapData.walkable(Vector2(MapData.river_x(1500), 1500)) or MapData.is_road(Vector2(MapData.river_x(1500), 1500)), "rivière praticable")
	print("Carte (MapData) : OK")


# ---------------------------------------------------------------- Déplacements

## Heures de marche de la compagnie de a à b en ligne droite (path forcé), ou par les points via.
func hours_between(c: CampaignState, a: Vector2, b: Vector2, via: Array[Vector2] = []) -> float:
	var ow := c.overworld
	ow.inside = -1
	ow.player.pos = a
	var path: Array[Vector2] = via.duplicate()
	path.append(b)
	ow.player.go(path)
	var h := 0.0
	while not ow.player.path.is_empty() and h < 500.0:
		ow.tick(c, 0.25)
		h += 0.25
	return h


func _test_movement() -> void:
	var c := quiet(3)
	var ow := c.overworld
	check(ow.inside == 0 and ow.player.pos == MapData.place_pos(0) and is_equal_approx(ow.hour, Overworld.START_HOUR), "départ : la compagnie n'est pas à Valombre au matin")
	# Clic sur Saint-Aubin : la compagnie y marche par la route et y entre
	check(ow.go_to_place(c, 1) == "" and not ow.player.path.is_empty() and ow.inside == -1 and ow.enter_goal == 1, "marche : ordre refusé")
	var hours := 0.0
	var e := {}
	while hours < 200.0:
		e = ow.tick(c, 1.0)
		hours += 1.0
		if e.has("event"):
			break
	check(str(e.get("event", "")) == "enter" and int(e["place"]) == 1 and ow.inside == 1 and c.location == 1, "marche : pas d'arrivée à Saint-Aubin (%s)" % str(e))
	check(hours >= 24.0 and hours <= 72.0 and c.day >= 2, "marche : %d heures pour Saint-Aubin" % int(hours))
	print("  Valombre → Saint-Aubin : %d heures, jour %d" % [int(hours), c.day])
	# Vitesse : la route est plus rapide qu'à travers champs
	# Le long de la grande route Valombre - Saint-Aubin (elle ondule : on suit son tracé)
	var rp := MapData.road_points(0)
	var i0 := rp.size() / 5
	var i1 := rp.size() * 3 / 5
	var a := rp[i0]
	var b := rp[i1]
	var via: Array[Vector2] = []
	for k in range(i0 + 1, i1):
		via.append(rp[k])
	var on_road := hours_between(c, a, b, via)
	var plain := Vector2(-1, -1)
	for y in range(100, int(MapData.SIZE.y) - 400, 40): # Une étendue de plaine assez longue
		for x in range(100, int(MapData.SIZE.x) - 400, 40):
			var ok := true
			for k in 11:
				var p := Vector2(x + k * 30, y)
				if MapData.is_road(p) or MapData.ground_at(p) != MapData.Ground.PLAIN:
					ok = false
					break
			if ok:
				plain = Vector2(x, y)
				break
		if plain.x >= 0:
			break
	check(plain.x >= 0, "vitesse : pas de plaine sur la carte")
	var d := MapData.path_length(a, via) + via[-1].distance_to(b)
	var off_road := hours_between(c, plain, plain + Vector2(d, 0))
	check(off_road > on_road * 1.15, "vitesse : hors route %.1f h, sur la route %.1f h" % [off_road, on_road])
	# Hiver : plus lent
	c.day = 95
	var winter := hours_between(c, a, b, via)
	check(winter > on_road * 1.2, "vitesse : l'hiver n'est pas plus lent (%.1f h contre %.1f h)" % [winter, on_road])
	print("  %d px : route %.1f h, plaine %.1f h, route en hiver %.1f h" % [int(d), on_road, off_road, winter])
	print("Déplacements : OK")


# ---------------------------------------------------------------- Le jour passe

func _test_day() -> void:
	var c := quiet(4)
	c.gold = 1000.0
	var ow := c.overworld
	var wage := c.daily_wage()
	var day := c.day
	ow.tick(c, 24.0 - ow.hour + 0.5) # Jusqu'au lendemain matin, 0 h 30
	check(c.day == day + 1 and absf(c.gold - (1000.0 - wage)) < 0.01 and ow.hour < 1.0, "jour : solde ou date (jour %d, %.1f écus, %.2f h)" % [c.day, c.gold, ow.hour])
	ow.tick(c, 48.0)
	check(c.day == day + 3, "jour : deux jours de plus")
	# Le monde vivant continue : une armée marche en temps réel
	c.world.declare_war(c, 0, 1)
	var army := c.world.add_army(1, 2, 1, 600, "march")
	var p0 := army.pos
	ow.tick(c, 3.0)
	check(army.pos.distance_to(p0) > 10.0 and army.pos.distance_to(p0) < 120.0, "armée : %.1f px en 3 heures" % army.pos.distance_to(p0))
	var seen_siege := false
	for i in 40 * 24:
		ow.tick(c, 1.0)
		ow.inside = 0 # La compagnie reste à l'abri : pas de rencontre
		if c.town_besieged(1):
			seen_siege = true
		if c.town_owner(1) == 1:
			break
	check(seen_siege and c.town_owner(1) == 1, "monde : pas de siège ni de prise en temps réel")
	# Évènements de route : une journée de marche peut amener une embuscade sur le terrain de l'endroit
	var e := quiet(5)
	CampaignState.forced_event = "ambush"
	e.overworld.go_to_place(e, 3)
	var out := e.overworld.tick(e, 30.0)
	CampaignState.forced_event = ""
	check(str(out.get("event", "")) == "battle" and bool(e.pending.get("ambush", false)) and str(e.pending.get("terrain", "")) in MapData.BATTLE_TERRAINS, "jour : embuscade de la route (%s)" % str(out))
	print("Jour qui passe : OK")


# ---------------------------------------------------------------- Registre et comportements

func _test_registry() -> void:
	var c := CampaignState.new_game(6)
	var ow := c.overworld
	for kind in ["villagers", "bandits", "caravan", "patrol"]:
		check(ow.count(kind) == ow.population_cap(c, kind) and ow.count(kind) > 0, "population de départ : %d %s" % [ow.count(kind), kind])
	var ids := {}
	for p in ow.all(c):
		check(not ids.has(p.id), "identifiant %d en double" % p.id)
		ids[p.id] = true
	check(ow.all(c).size() == 1 + ow.parties.size() + c.world.armies.size(), "registre : tous les groupes")
	var army := c.world.armies[0]
	check(army is Party and army.kind == "army" and army.men() == army.force and ow.by_id(c, army.id) == army, "registre : armée = Party « army »")
	check(not army.troops.is_empty(), "armée sans régiments")
	var v := ow.parties[0]
	check(ow.by_id(c, v.id) == v and ow.near(c, v.pos, 1.0).has(v), "registre : recherche par id ou proximité")
	var extra := Party.new()
	extra.kind = "deserters"
	extra.pos = MapData.place_pos(2)
	extra.troops = [{"type": "spear", "men": 10, "xp": 0.0}]
	ow.add(c, extra)
	check(extra.id > 0 and ow.by_id(c, extra.id) == extra, "registre : ajout")
	ow.remove(c, extra)
	check(ow.by_id(c, extra.id) == null, "registre : retrait")
	# Comportement par défaut : errer de lieu en lieu
	var starts := {}
	for p in ow.parties:
		starts[p.id] = p.pos
	c.gold = 1.0e6
	ow.inside = 0
	for i in 72:
		ow.tick(c, 1.0)
		ow.inside = 0
	var moved := 0
	for p in ow.parties:
		if starts.has(p.id) and p.pos.distance_to(starts[p.id]) > 50.0:
			moved += 1
		check(p.state in PartyAI.STATES and (MapData.walkable(p.pos) or MapData.is_road(p.pos)), "groupe %s égaré (%s, %s)" % [p.kind, p.state, str(p.pos)])
	check(moved >= 4, "comportement : %d groupes seulement ont bougé en 3 jours" % moved)
	print("Registre et comportements : OK")


# ---------------------------------------------------------------- Contact

func _test_contact() -> void:
	# Poursuite d'un groupe paisible : la rencontre a lieu au contact
	var c := quiet(7)
	var ow := c.overworld
	var v := Party.new()
	v.kind = "villagers"
	v.troops = [{"type": "spear", "men": 12, "xp": 0.0}]
	v.pos = MapData.place_pos(0) + Vector2(150, -40)
	v.busy_hours = 100.0
	ow.add(c, v)
	check(ow.chase(c, v.id) == "" and ow.player.target_id == v.id and ow.inside == -1, "poursuite : ordre refusé")
	var e := ow.tick(c, 30.0)
	check(str(e.get("event", "")) == "contact" and int(e["id"]) == v.id and ow.player.pos.distance_to(v.pos) <= Overworld.CONTACT_RANGE, "poursuite : pas de contact (%s)" % str(e))
	var opts := ow.options(c, v)
	check(opts.size() >= 2, "rencontre : choix")
	var out := ow.resolve(c, v, "leave")
	check(not bool(out.get("battle", true)) and not c.in_battle(), "rencontre : passer son chemin lance une bataille")
	check(str(ow.tick(c, 1.0).get("event", "")) != "contact", "rencontre : le même groupe vous arrête aussitôt")
	# Un groupe hostile rattrape la compagnie à l'arrêt en rase campagne
	var b := Party.new()
	b.kind = "bandits"
	b.troops = [{"type": "spear", "men": 40, "xp": 0.0}, {"type": "archer", "men": 20, "xp": 0.0}]
	ow.player.pos = MapData.walkable_point(Vector2(1800, 1200))
	ow.halt()
	ow.inside = -1
	b.pos = MapData.walkable_point(ow.player.pos + Vector2(120, 0))
	b.gold = 90
	ow.add(c, b)
	e = ow.tick(c, 20.0)
	check(str(e.get("event", "")) == "contact" and int(e.get("id", -1)) == b.id, "bandits : ils ne rattrapent pas la compagnie (%s)" % str(e))
	# Dans les murs d'une ville, on est à l'abri
	ow.cooldown.clear()
	ow.inside = 1
	b.pos = ow.player.pos
	check(ow.contact(c) == null, "rencontre dans les murs d'une ville")
	ow.inside = -1
	# Attaquer : la bataille est en attente sur le terrain de l'endroit, contre les régiments du groupe
	out = ow.resolve(c, b, "attack")
	check(bool(out["battle"]) and c.in_battle() and int(c.pending["party"]) == b.id and c.pending.has("site") and str(c.pending["terrain"]) == str(c.pending["site"]["kind"]) and str(c.pending["terrain"]) in MapData.BATTLE_TERRAINS, "bandits : bataille mal préparée")
	var foes := 0
	for r in c.pending["enemy"]:
		foes += int(r["men"])
	check(c.pending["enemy"].size() >= 2 and foes == b.men(), "bandits : armée ennemie")
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(back != null and int(back.pending.get("party", -1)) == b.id and back.overworld.by_id(back, b.id) != null, "bataille contre un groupe perdue à la sauvegarde")
	var gold := c.gold
	var before_men := b.men()
	var res := c.finish_battle(true, [], [])
	check((ow.by_id(c, b.id) == null or b.men() <= int(before_men * CampaignState.PARTY_REGROUP)) and c.gold > gold, "bandits : vaincus mais toujours aussi forts (%s ; %d/%d hommes, or %d -> %d)" % [res["text"], b.men(), before_men, gold, c.gold])
	# Une armée hostile : bataille de WorldSim (dispersée si on gagne)
	c.world.declare_war(c, 0, 1)
	c.reputation[0] = 30
	c.reputation[1] = -10
	var a := c.world.add_army(1, 2, 1, 300, "march")
	a.pos = ow.player.pos + Vector2(5, 0)
	a.route.clear()
	a.mode = "siege" # Immobile
	a.target = 1
	check(ow.contact(c) == a, "armée hostile : pas de contact")
	ow.resolve(c, a, "attack")
	check(int(c.pending.get("world_army", -1)) == a.id and str(c.pending["terrain"]) in MapData.BATTLE_TERRAINS, "armée : bataille mal préparée")
	c.finish_battle(true, [], [])
	check(not c.world.armies.has(a), "armée : non dispersée")
	print("Contact et rencontres : OK")


# ---------------------------------------------------------------- Sauvegarde

func _test_save() -> void:
	var c := quiet(8)
	var ow := c.overworld
	ow.populate(c)
	ow.go_to_place(c, 5)
	ow.tick(c, 7.25)
	check(c.save(), "sauvegarde : écriture")
	var l := CampaignState.load_game()
	check(l != null, "sauvegarde : relecture")
	if l == null:
		return
	var lo := l.overworld
	check(lo.player.pos.distance_to(ow.player.pos) < 0.01 and lo.player.path.size() == ow.player.path.size() and lo.enter_goal == 5 and lo.inside == -1, "sauvegarde : position ou chemin perdus")
	check(is_equal_approx(lo.hour, ow.hour) and lo.parties.size() == ow.parties.size() and l.day == c.day, "sauvegarde : heure ou groupes perdus")
	# Après relecture, la marche continue pareil
	ow.tick(c, 10.0)
	lo.tick(l, 10.0)
	check(lo.player.pos.distance_to(ow.player.pos) < 0.5, "sauvegarde : la marche ne reprend pas pareil")
	# Version 8 (petite carte, sans temps réel) : la compagnie dans sa ville, armées agrandies
	var old := c.to_dict()
	old["version"] = 8
	old.erase("overworld")
	old["location"] = 4
	for x in old["world"]["armies"]:
		x["x"] = float(x["x"]) / MapData.SCALE
		x["y"] = float(x["y"]) / MapData.SCALE
	var o := CampaignState.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(o != null and o.overworld.inside == 4 and o.overworld.player.pos == MapData.place_pos(4) and o.overworld.player.path.is_empty(), "migration : compagnie pas dans sa ville")
	if o != null:
		for i in o.world.armies.size():
			check(o.world.armies[i].pos.distance_to(c.world.armies[i].pos) < 1.0, "migration : armée mal placée")
		check(not o.overworld.parties.is_empty(), "migration : aucun groupe")
	CampaignState.delete_slot(1)
	print("Sauvegarde : OK")


# ---------------------------------------------------------------- Scène de la carte

func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			var c := quiet(9)
			c.save()
			CampaignState.current = c
			map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
			map.auto_launch = false
			root.add_child(map)
		3:
			var c: CampaignState = map.state
			check(map.town_open and map.time_stopped() and _any(_texts(map.box), "Lever un régiment"), "scène : la ville n'est pas ouverte au départ")
			var h: float = c.overworld.hour
			map._process(1.0)
			check(is_equal_approx(c.overworld.hour, h), "scène : le temps passe dans la ville")
			# Clic sur un point de la carte : la compagnie part, le temps reprend
			map.click_map(MapData.walkable_point(MapData.place_pos(0) + Vector2(300, 0)))
			check(not map.town_open and not c.overworld.player.path.is_empty(), "scène : clic sans marche")
			map._process(1.0)
			check(c.overworld.hour > h, "scène : le temps ne passe pas")
			map.toggle_pause()
			h = c.overworld.hour
			map._process(1.0)
			check(is_equal_approx(c.overworld.hour, h), "scène : la pause n'arrête pas le temps")
			map.set_speed(2)
			map._process(1.0)
			check(absf(c.overworld.hour - h - map.HOURS_PER_SECOND * 4.0) < 0.01, "scène : vitesse x4")
			# Un groupe sur la route : clic pour le poursuivre, rencontre au contact
			var v := Party.new()
			v.kind = "villagers"
			v.troops = [{"type": "spear", "men": 8, "xp": 0.0}]
			v.pos = c.overworld.player.pos + Vector2(60, 0)
			v.busy_hours = 50.0
			c.overworld.add(c, v)
			map.click_map(v.pos)
			check(c.overworld.player.target_id == v.id, "scène : clic sur un groupe sans poursuite")
			for i in 40:
				if map.contact != null:
					break
				map.advance_time(0.5)
			check(map.contact == v and map.time_stopped() and _texts(map.box).any(func(t: String) -> bool: return "attaquer" in t.to_lower()), "scène : pas de rencontre affichée")
			map.choose("attack")
			check(map.ambushed and c.in_battle() and int(c.pending["party"]) == v.id, "scène : attaquer ne lance pas la bataille")
			fought_id = v.id
			map.queue_redraw()
			root.remove_child(map)
			map.free()
			# Retour de bataille : la carte reprend à l'endroit du combat
			c.finish_battle(true, [], [])
			map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
			map.auto_launch = false
			root.add_child(map)
		5:
			var c: CampaignState = map.state
			check(c.overworld.inside == -1 and not map.town_open and c.overworld.by_id(c, fought_id) == null, "scène : retour de bataille")
			check(not map.time_stopped(), "scène : temps arrêté au retour")
			map.zoom_at(1.5, Vector2(300, 300))
			check(map.cam.zoom.x > 1.4, "scène : zoom")
			map.queue_redraw()
			map.minimap.redraw()
		7:
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			for i in range(1, CampaignState.SLOT_COUNT + 1):
				CampaignState.delete_slot(i)
			check(counter.errors.is_empty(), "erreurs : %s" % str(counter.errors))
			if fails.is_empty():
				print("Carte en temps réel : tout est OK")
			else:
				print("Carte en temps réel : %d échec(s)" % fails.size())
				for f in fails:
					print("  - ", f)
			quit(0 if fails.is_empty() else 1)
	return false


func _texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	for ch in n.get_children():
		if ch is Label:
			out.append((ch as Label).text)
		elif ch is Button:
			out.append((ch as Button).text)
		out.append_array(_texts(ch))
	return out


func _any(texts: Array[String], part: String) -> bool:
	for s in texts:
		if s.contains(part):
			return true
	return false
