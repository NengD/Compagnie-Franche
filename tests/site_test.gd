extends SceneTree
## Test headless du champ de bataille tiré de la carte (battle_site.gd, terrain.gd) et des
## batailles livrées aux côtés d'alliés (allied_ai.gd, battle_sim.gd, overworld.gd,
## campaign_state.gd) :
##   godot --headless --path . -s tests/site_test.gd
## - un contact au bord de la rivière donne une rivière sur le champ, avec le pont de la carte ;
## - un contact sur une route donne une route qui traverse le champ (celle de la carte) ;
## - un village, la lisière d'une forêt, des collines ; le descripteur passe par la sauvegarde ;
## - sans descripteur, l'ancien terrain (mêmes tirages) ;
## - rencontre près d'une patrouille amie : elle se bat à vos côtés (IA alliée, pas commandable,
##   absente des cartes de régiments), ses pertes sont reportées sur son groupe ;
## - « Se joindre à eux » : le combat du groupe suivi est proposé à la compagnie.
## N'écrit que dans user://test_site_*.json. Code de sortie : 0 si tout va bien, 1 sinon.


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
var battle: Node = null
var camp: CampaignState = null
var patrol: Party = null
var patrol_men := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.slot_prefix = "user://test_site"
	CampaignState.use_slot(1)
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	_test_river()
	_test_road()
	_test_village_forest_hills()
	_test_old_terrain()
	_test_joint_offer()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			_start_allied_battle()
		3:
			_test_allied_battle()
			_end_battle()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			for e in counter.errors:
				fails.append("erreur moteur : " + e)
			if fails.is_empty():
				print("Site et alliés : tous les tests passent.")
			else:
				print("Site et alliés : %d échec(s)" % fails.size())
				for f in fails:
					print("  - " + f)
			quit(0 if fails.is_empty() else 1)
			return true
	return false


# ---------------------------------------------------------------- Outils

## Simulation seule sur le champ du site.
func sim_for(site: Dictionary, seed_value := 5) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = seed_value
	sim.generate_world(str(site["kind"]), site)
	return sim


## Point de la carte sous un point du champ (même repère que BattleSite.describe).
func to_map(site: Dictionary, b: Vector2) -> Vector2:
	var ax := Vector2.from_angle(float(site["angle"]))
	var ay := ax.rotated(PI / 2.0)
	var o := Vector2(site["origin"][0], site["origin"][1])
	var d := (b - BattleSite.CENTER) / BattleSite.SCALE
	return o + ax * d.x + ay * d.y


func near_settled(pos: Vector2, dist: float) -> bool:
	for p in MapData.places():
		if str(p["kind"]) in BattleSite.SETTLED and pos.distance_to(p["pos"]) < dist:
			return true
	return false


## Un point de la carte loin de l'eau, des lieux et des autres routes, sur la route k.
func quiet_road_point() -> Vector2:
	for k in MapData.roads().size():
		if MapData.road_class(k) != MapData.RoadClass.MAIN:
			continue
		var pts := MapData.road_points(k)
		for j in range(pts.size() / 4, pts.size() * 3 / 4):
			var p := pts[j]
			if MapData.river_distance(p) < 260.0 or MapData.lake_factor(p) < 2.5 or near_settled(p, 220.0):
				continue
			if MapData.ground_at(p) == MapData.Ground.MOUNTAIN:
				continue
			if int(BattleSite.nearest_road(p)["index"]) == k:
				return p
	return Vector2(-1, -1)


# ---------------------------------------------------------------- Rivière et pont

func _test_river() -> void:
	# Un pont de la carte loin des lieux habités ; la compagnie sur la route, sur une rive
	var found := false
	for b in MapData.bridges():
		var mid: Vector2 = (b["a"] + b["b"]) * 0.5
		if near_settled(mid, 150.0):
			continue
		var dir: Vector2 = (b["b"] - b["a"]).normalized()
		var pos: Vector2 = b["b"] + dir * 30.0
		var site := BattleSite.describe(pos, pos + dir * 60.0)
		found = true
		check(bool(site["river"]) and str(site["kind"]) == "river", "pont : pas de rivière sur le champ (%s)" % str(site["kind"]))
		var bridge := -1.0
		for c in site["crossings"]:
			if str(c[1]) == "bridge" and (bridge < 0.0 or absf(float(c[0]) - 1600.0) < absf(bridge - 1600.0)):
				bridge = float(c[0])
		check(bridge > 0.0 and absf(bridge - 1600.0) < 700.0, "pont : le pont de la carte n'est pas au milieu du champ (%s)" % str(site["crossings"]))
		check("pont" in str(site["label"]), "pont : libellé « %s »" % str(site["label"]))
		var sim := sim_for(site)
		var t := sim.terrain
		check(t.has_river() and not t.has_road(), "pont : terrain sans rivière")
		var ry := sim.road_y(1600.0)
		check(ry > 600.0 and ry < 1400.0, "pont : la rivière ne passe pas entre les armées (%.0f)" % ry)
		check(t.is_river(Vector2(1600.0, ry)), "pont : pas d'eau sur la ligne de la rivière")
		# La rivière du champ est celle de la carte
		var m := to_map(site, Vector2(1600.0, ry))
		check(MapData.river_distance(m) < MapData.RIVER_HALF * 2.0 + 25.0, "pont : la ligne de la rivière n'est pas sur la rivière de la carte (%.0f)" % MapData.river_distance(m))
		if bridge > 0.0:
			var on := Vector2(bridge, sim.road_y(bridge))
			check(t.is_bridge(on) and not t.is_deep_water(on), "pont : on ne passe pas à pied sec sur le pont")
			var road_near := false
			for dx in range(-300, 301, 10):
				for dy in [-140.0, 140.0]:
					if sim.on_road(on + Vector2(dx, dy), BattleSim.ROAD_HALF):
						road_near = true
			check(road_near, "pont : pas de route qui y mène")
			var far := -1.0
			for x in [300.0, 900.0, 2300.0, 2900.0]:
				if not t.is_ford(Vector2(x, sim.road_y(x))):
					far = x
			check(far > 0.0 and t.is_deep_water(Vector2(far, sim.road_y(far))), "pont : la rivière se traverse partout")
		check(t.build_overlay(sim.rng) != null, "pont : pas de couche de rivière")
		break
	check(found, "aucun pont de la carte loin des lieux habités")
	# Bord de la Vionne, hors des routes : rivière, et des passages quand même (gués ou hauts-fonds)
	var y := 1900.0
	var bank := Vector2(MapData.river_x(y) + 55.0, y)
	var s2 := BattleSite.describe(bank, bank + Vector2(-100, 0))
	check(bool(s2["river"]) and not (s2["crossings"] as Array).is_empty(), "bord de la Vionne : pas de rivière ou aucun passage")
	var sim2 := sim_for(s2)
	check(sim2.terrain.has_river() and not sim2.terrain.fords.is_empty(), "bord de la Vionne : terrain sans gué")
	# Loin de toute eau : pas de rivière
	var dry := quiet_road_point()
	check(not bool(BattleSite.describe(dry, dry + Vector2(0, -50))["river"]), "loin de l'eau : une rivière sur le champ")
	print("Rivière et pont : OK")


# ---------------------------------------------------------------- Route

func _test_road() -> void:
	var pos := quiet_road_point()
	check(pos.x >= 0.0, "aucun point tranquille sur une grande route")
	if pos.x < 0.0:
		return
	var site := BattleSite.describe(pos, pos + Vector2(0, -60))
	check(bool(site["road"]) and not bool(site["river"]), "route : le champ n'a pas de route (%s)" % str(site["kind"]))
	check("route" in str(site["label"]), "route : libellé « %s »" % str(site["label"]))
	var sim := sim_for(site)
	var ry := sim.road_y(1600.0)
	check(sim.terrain.has_road() and sim.on_road(Vector2(1600.0, ry), BattleSim.ROAD_HALF), "route : pas de route au milieu du champ")
	check(ry > 800.0 and ry < 1200.0, "route : la route ne passe pas entre les armées (%.0f)" % ry)
	# La route du champ est celle de la carte, d'un bord à l'autre
	for x in [400.0, 1600.0, 2800.0]:
		var m := to_map(site, Vector2(x, sim.road_y(x)))
		check(MapData.road_distance(m) < 14.0, "route : à x=%.0f, la route du champ n'est pas sur la route de la carte (%.1f)" % [x, MapData.road_distance(m)])
	# Loin de toute route : pas de route
	var off := pos
	for k in 40:
		var cand := pos + Vector2.from_angle(k * 0.7) * (140.0 + k * 6.0)
		if MapData.walkable(cand) and MapData.road_distance(cand) > 160.0 and MapData.river_distance(cand) > 200.0 and MapData.lake_factor(cand) > 2.0 and not near_settled(cand, 150.0):
			off = cand
			break
	check(off != pos, "pas de point loin des routes")
	var s2 := BattleSite.describe(off, off + Vector2(50, 0))
	var sim2 := sim_for(s2)
	check(not sim2.terrain.has_road() and not sim2.on_road(Vector2(1600.0, sim2.road_y(1600.0)), BattleSim.ROAD_HALF), "loin des routes : une route au milieu du champ")
	print("Route : OK")


# ---------------------------------------------------------------- Village, forêt, collines, sauvegarde

func _test_village_forest_hills() -> void:
	# Le village où se trouvait la compagnie
	var vil := MapData.place_named("Saulieu")
	var vp := MapData.place_pos(vil)
	var site := BattleSite.describe(vp, vp + Vector2(0, -40), vil)
	check(str(site["kind"]) == "village" and int(site["place"]) == vil and "Saulieu" in str(site["label"]), "village : pas de village de Saulieu (%s)" % str(site["label"]))
	var sim := sim_for(site)
	check(sim.terrain.houses.size() >= 6 and sim.terrain.village_rect.has_point(Vector2(site["village"][0], site["village"][1])), "village : pas de maisons autour du village")
	# Lisière d'une forêt : les bois du champ sont sur les bois de la carte
	var fo: Dictionary = MapData.FORESTS[0]
	var edge: Vector2 = fo["center"] + Vector2(fo["radius"].x * 1.15, 0)
	var s2 := BattleSite.describe(edge, edge + Vector2(60, 0))
	var ok := 0
	for f in s2["forests"]:
		if MapData.ground_at(to_map(s2, Vector2(f[0], f[1]))) == MapData.Ground.FOREST:
			ok += 1
	check((s2["forests"] as Array).size() >= 3 and ok >= int((s2["forests"] as Array).size() * 0.8), "lisière : %d bois dont %d sur la forêt de la carte" % [(s2["forests"] as Array).size(), ok])
	var sim2 := sim_for(s2)
	check(sim2.forests.size() >= (s2["forests"] as Array).size(), "lisière : bois du site non plantés")
	# Collines : là où la carte en a
	var hill := Vector2(-1, -1)
	var g := MapData.grid_size()
	for cy in range(10, g.y - 10, 7):
		for cx in range(10, g.x - 10, 7):
			var c := Vector2i(cx, cy)
			if MapData.ground_cell(c) == MapData.Ground.HILLS and MapData.river_distance(MapData.cell_center(c)) > 200.0 \
					and MapData.road_distance(MapData.cell_center(c)) > 80.0 and not near_settled(MapData.cell_center(c), 150.0):
				hill = MapData.cell_center(c)
				break
		if hill.x >= 0.0:
			break
	check(hill.x >= 0.0, "aucune colline sur la carte")
	if hill.x >= 0.0:
		var s3 := BattleSite.describe(hill, hill + Vector2(0, -60))
		check(not (s3["hills"] as Array).is_empty(), "collines : aucun relief sur le champ")
		var sim3 := sim_for(s3)
		var top := sim3.terrain.hill_tops()
		check(not top.is_empty() and sim3.terrain.height(top[0]) > 0.4, "collines : pas de sommet")
		if not (s3["hills"] as Array).is_empty():
			var h: Array = s3["hills"][0]
			var gm := MapData.ground_at(to_map(s3, Vector2(h[0], h[1])))
			check(gm == MapData.Ground.HILLS or gm == MapData.Ground.MOUNTAIN, "collines : le sommet n'est pas sur les collines de la carte")
	# Le descripteur et les alliés passent par la sauvegarde (contrat en cours)
	var c := CampaignState.new_game(3)
	var k: Dictionary = c.party_contract(Party.new(), "plain")
	k["site"] = site
	k["allies"] = [{"party": 7, "name": "une patrouille", "faction": 0, "troops": [{"type": "spear", "men": 18, "rank": 1}]}]
	c.pending = k
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(back != null and back.pending.has("site") and str(back.pending["site"]["kind"]) == "village", "sauvegarde : descripteur perdu")
	check(back != null and back.pending.has("allies") and int(back.pending["allies"][0]["troops"][0]["men"]) == 18, "sauvegarde : alliés perdus")
	if back != null:
		var a := sim_for(back.pending["site"])
		check(a.terrain.houses.size() == sim.terrain.houses.size(), "sauvegarde : le champ relu diffère")
	check(BattleSite.sanitize({"kind": "siege"}).is_empty() and BattleSite.sanitize("x").is_empty(), "descripteur invalide accepté")
	print("Village, forêt, collines, sauvegarde : OK")


## Sans descripteur : exactement l'ancien terrain (mêmes tirages, mêmes forêts).
func _test_old_terrain() -> void:
	for kind in ["plain", "river", "village", "hills"]:
		var a := BattleSim.new()
		a.rng.seed = 77
		a.generate_world(kind)
		check(a.terrain.site.is_empty() and a.terrain.has_river() == (kind == "river") and a.terrain.has_road() == (kind != "river"), "%s : ancien terrain changé" % kind)
		check(a.forests.size() == a.terrain.forest_count(), "%s : nombre de forêts changé" % kind)
		if kind == "river":
			check(a.terrain.fords.size() >= 2 and a.terrain.bridges.is_empty(), "rivière : gués de l'ancien terrain changés")
	print("Ancien terrain : OK")


# ---------------------------------------------------------------- « Se joindre à eux »

func _make_party(c: CampaignState, kind: String, faction: int, pos: Vector2, troops: Array) -> Party:
	var p := Party.new()
	p.kind = kind
	p.faction = faction
	p.pos = pos
	for t in troops:
		p.troops.append(t)
	return c.overworld.add(c, p)


## Campagne sans autre groupe, la compagnie en rase campagne sur une route tranquille.
func quiet_campaign(seed_value: int) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.overworld.parties.clear()
	c.overworld.spawning = false
	c.world.armies.clear()
	c.overworld.inside = -1
	c.overworld.player.pos = quiet_road_point()
	return c


func _test_joint_offer() -> void:
	for answer in ["join_battle", "stand_aside"]:
		var c := quiet_campaign(11)
		var ow := c.overworld
		var at := ow.player.pos
		var pat := _make_party(c, "patrol", 0, at + Vector2(30, 0), [{"type": "cavalry", "men": 10, "xp": 60.0}, {"type": "spear", "men": 20, "xp": 60.0}])
		var ban := _make_party(c, "bandits", -1, at + Vector2(40, 8), [{"type": "spear", "men": 12, "xp": 0.0}])
		ow.player.target_id = pat.id
		ow.player.state = "follow"
		PartyAI.skirmishes(c, ow)
		check(ow.joint.get("ally", -1) == pat.id and ow.joint.get("enemy", -1) == ban.id and ban.men() == 12, "rejoindre : le combat du groupe suivi n'est pas proposé")
		var opts := ow.options(c, ban)
		check(opts.size() == 2 and str(opts[0]["id"]) == "join_battle", "rejoindre : choix proposés %s" % str(opts))
		var out := ow.resolve(c, ban, answer)
		check(ow.joint.is_empty(), "rejoindre : proposition restée en place")
		if answer == "join_battle":
			check(bool(out.get("battle", false)) and c.in_battle(), "rejoindre : pas de bataille commune")
			var allies: Array = c.pending.get("allies", [])
			check(allies.size() == 1 and int(allies[0]["party"]) == pat.id and (allies[0]["troops"] as Array).size() == 2, "rejoindre : la patrouille n'est pas alliée (%s)" % str(allies))
			check(c.pending.has("site") and c.pending.has("party"), "rejoindre : contrat sans site")
		else:
			check(not c.in_battle() and ban.men() < 12, "laisser faire : le combat n'est pas résolu")
	# Un groupe que la compagnie ne suit pas : combat résolu d'office
	var c2 := quiet_campaign(12)
	var at2 := c2.overworld.player.pos
	var p2 := _make_party(c2, "patrol", 0, at2 + Vector2(30, 0), [{"type": "cavalry", "men": 30, "xp": 60.0}])
	var b2 := _make_party(c2, "bandits", -1, at2 + Vector2(40, 8), [{"type": "spear", "men": 12, "xp": 0.0}])
	PartyAI.skirmishes(c2, c2.overworld)
	check(c2.overworld.joint.is_empty() and b2.men() < 12 and p2.men() > 0, "sans le suivre : combat non résolu")
	print("Se joindre à eux : OK")


# ---------------------------------------------------------------- Bataille avec alliés (scène)

func _start_allied_battle() -> void:
	camp = quiet_campaign(21)
	var ow := camp.overworld
	var at := ow.player.pos
	patrol = _make_party(camp, "patrol", 0, at + Vector2(40, 10),
		[{"type": "cavalry", "men": 10, "xp": 120.0}, {"type": "men_at_arms", "men": 16, "xp": 120.0}, {"type": "spear", "men": 20, "xp": 120.0}])
	patrol.name = "la patrouille de Valombre"
	patrol_men = patrol.men()
	var ban := _make_party(camp, "bandits", -1, at + Vector2(20, -10), [{"type": "spear", "men": 30, "xp": 0.0}, {"type": "archer", "men": 16, "xp": 0.0}])
	var line := ow.allies_line(camp, ban)
	check("patrouille" in line, "rencontre : la patrouille n'est pas annoncée à vos côtés (« %s »)" % line)
	var out := ow.resolve(camp, ban, "attack")
	check(bool(out.get("battle", false)) and camp.in_battle(), "rencontre : pas de bataille contre les bandits")
	check((camp.pending.get("allies", []) as Array).size() == 1, "rencontre : la patrouille voisine n'est pas alliée")
	check(not (camp.pending.get("site", {}) as Dictionary).is_empty(), "rencontre : pas de descripteur de site")
	camp.save()
	CampaignState.current = CampaignState.load_slot(1) # Comme au retour du jeu : relu depuis la sauvegarde
	camp = CampaignState.current
	patrol = camp.overworld.by_id(camp, patrol.id)
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(battle)


func _test_allied_battle() -> void:
	var sim: BattleSim = battle.sim
	var allied: Array[Regiment] = []
	for r in sim.regiments:
		if r.allied:
			allied.append(r)
	check(allied.size() == 3, "bataille : %d régiments alliés (3 attendus)" % allied.size())
	check(sim.ally_ai != null, "bataille : pas d'IA alliée")
	check(not sim.terrain.site.is_empty(), "bataille : le champ ne vient pas de la carte")
	for r in allied:
		check(r.team == BattleSim.PLAYER and not battle.player_roster().has(r) and not sim.player_regiments().has(r), "bataille : un allié est sur vos cartes de régiments")
	if allied.is_empty():
		return
	battle.orders.finish_selection(allied[0].center, allied[0].center, false)
	check(not allied[0].selected, "bataille : un allié se sélectionne")
	check(battle.player_roster().size() == camp.battle_army().size(), "bataille : cartes des régiments faussées")
	var start_y := allied[0].center.y
	battle.start_battle()
	var moved := false
	var t := 0.0
	while sim.state == BattleSim.State.BATTLE and t < 900.0:
		sim.step(0.05)
		t += 0.05
		for r in allied:
			if r.center.y < start_y - 250.0:
				moved = true
		if t > 90.0 and int(t * 20.0) % 200 == 0:
			for r in sim.player_regiments(): # La compagnie finit par charger aussi
				if r.target == null:
					r.target = sim.nearest_enemy_regiment(r, 1e9, false)
	check(moved, "bataille : les alliés n'ont pas marché sur l'ennemi")
	check(sim.state == BattleSim.State.VICTORY, "bataille : pas de victoire (état %d après %.0f s)" % [sim.state, t])
	var tally := sim.ally_tally()
	check(tally.size() == 1 and int(tally[0]["kills"]) > 0, "bataille : les alliés n'ont tué personne (%s)" % str(tally))
	var lost := int(tally[0]["before"]) - int(tally[0]["survivors"])
	var res: Dictionary = battle.campaign_result
	check(not res.is_empty(), "bataille : pas de bilan de campagne")
	var p := camp.overworld.by_id(camp, int(tally[0]["party"]))
	if lost >= patrol_men:
		check(p == null, "après-bataille : la patrouille anéantie existe encore")
	else:
		check(p != null and p.men() == patrol_men - lost, "après-bataille : pertes alliées non reportées (%d hommes, %d attendus)" % [p.men() if p != null else -1, patrol_men - lost])
	check("Vos alliés" in str(res.get("text", "")), "après-bataille : pas de note sur les alliés (%s)" % str(res.get("text", "")))
	check(int(res.get("ally_loot", 0)) > 0, "après-bataille : les alliés n'ont pas leur part du butin")
	check(camp.reputation[0] >= CampaignState.REP_ALLY, "après-bataille : pas de réputation auprès de la faction alliée")
	var cas: Dictionary = sim.casualties()
	check(int(cas["totals"]["ally_before"]) == int(tally[0]["before"]), "bilan : alliés comptés avec la compagnie")
	print("Bataille avec alliés : OK (%.0f s, %d alliés perdus, %d tués par eux)" % [t, lost, int(tally[0]["kills"])])


func _end_battle() -> void:
	if battle != null:
		root.remove_child(battle)
		battle.free()
		battle = null
