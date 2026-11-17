extends SceneTree
## Test headless des comportements des groupes de la carte en temps réel (party_ai.gd) et du
## peuplement (overworld.gd : population_cap, populate, spawn) :
##   godot --headless --path . -s tests/party_ai_test.gd
## - villageois : du village au marché, vente, retour ; fuite devant des bandits ;
## - bandits : chasse d'une proie faible (et de la compagnie si elle est faible), fuite devant plus
##   fort, cachette en forêt, retour au repaire et recrues après un coup réussi ;
## - caravanes : commerce à l'arrivée, détour devant des bandits, escorte payée à l'arrivée ;
## - patrouilles : elles battent des bandits, et pourchassent la compagnie si leur faction lui est
##   hostile ;
## - déserteurs : ils tournent au brigandage ; ils naissent des batailles du monde vivant ;
## - peuplement : plafonds, réapparitions, saisons et guerres ; déterminisme à graine égale (et
##   après sauvegarde) ; performances avec une soixantaine de groupes.
## N'écrit rien sur le disque. Code de sortie : 0 si tout va bien, 1 sinon.


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


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	_test_villagers()
	_test_bandits()
	_test_caravans()
	_test_patrols()
	_test_deserters()
	_test_population()
	_test_determinism()
	_test_performance()
	check(counter.errors.is_empty(), "erreurs : %s" % str(counter.errors))
	if fails.is_empty():
		print("Groupes de la carte : tout est OK")
	else:
		print("Groupes de la carte : %d échec(s)" % fails.size())
		for f in fails:
			print("  - ", f)


func _process(_delta: float) -> bool:
	quit(0 if fails.is_empty() else 1)
	return true


## Campagne calme : riche, sans groupes ni armées ni guerres, sans réapparitions, la compagnie à
## l'abri dans sa ville.
func quiet(seed_value: int) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.gold = 1.0e6
	c.overworld.parties.clear()
	c.overworld.spawning = false
	c.world.armies.clear()
	c.world.wars.clear()
	c.overworld.inside = 0
	return c


## Fait passer le temps heure par heure tant que cond est faux (au plus max_hours). Les armées du
## monde vivant sont retirées à chaque heure (elles n'ont rien à faire ici). Renvoie les heures.
func run_until(c: CampaignState, max_hours: float, cond: Callable) -> float:
	var h := 0.0
	while h < max_hours and not cond.call():
		c.world.armies.clear()
		c.world.wars.clear()
		c.overworld.tick(c, 1.0)
		c.overworld.inside = 0
		h += 1.0
	return h


func make(c: CampaignState, kind: String, pos: Vector2, men: int, xp := 0.0) -> Party:
	var p := Party.new()
	p.kind = kind
	p.pos = MapData.walkable_point(pos)
	p.troops = [{"type": "spear", "men": men, "xp": xp}]
	return c.overworld.add(c, p)


# ---------------------------------------------------------------- Villageois

func _test_villagers() -> void:
	var c := quiet(11)
	var ow := c.overworld
	var village := PartyAI.places_of(["village"])[0]
	var market := PartyAI.market_of(village)
	check(market >= 0 and MapData.place(market)["kind"] in PartyAI.MARKET_KINDS, "villageois : pas de marché pour %s" % MapData.place(village)["name"])
	var v := make(c, "villagers", MapData.place_pos(village), 12)
	v.home = village
	v.state = "home"
	var h := run_until(c, 72.0, func() -> bool: return v.state == "market")
	check(v.state == "market" and PartyAI.at_place(v, market) and v.goods == 0 and v.gold > 0, "villageois : pas arrivés au marché (%s, %.0f h)" % [v.state, h])
	print("  Villageois : %s → %s en %.0f h, %d écus de vente" % [MapData.place(village)["name"], MapData.place(market)["name"], h, v.gold])
	h = run_until(c, 96.0, func() -> bool: return v.state == "home")
	check(v.state == "home" and PartyAI.at_place(v, village) and v.gold == 0, "villageois : pas rentrés au village (%s, %.0f h)" % [v.state, h])
	# Ils fuient des bandits qu'ils voient en chemin
	h = run_until(c, 48.0, func() -> bool: return v.state == "market_bound" and v.pos.distance_to(MapData.place_pos(village)) > 60.0)
	check(v.state == "market_bound", "villageois : ne repartent pas au marché")
	var dir := (v.path[-1] - v.pos).normalized() if not v.path.is_empty() else Vector2.RIGHT
	var b := make(c, "bandits", v.pos + dir * 110.0, 10) # Trop peu pour les attaquer : ils restent
	b.busy_hours = 100.0
	b.base = b.pos
	b.state = "lurk"
	run_until(c, 2.0, func() -> bool: return false)
	check(v.state == "flee" and v.pos.distance_to(b.pos) > 110.0, "villageois : ne fuient pas les bandits (%s, %.0f px)" % [v.state, v.pos.distance_to(b.pos)])
	ow.remove(c, b)
	h = run_until(c, 120.0, func() -> bool: return v.state == "market")
	check(v.state == "market", "villageois : ne reprennent pas la route du marché après la fuite (%s, %s, %d points, à %.0f px du marché)" % [v.state, str(v.pos), v.path.size(), v.pos.distance_to(MapData.place_pos(market))])
	print("Villageois : OK")


# ---------------------------------------------------------------- Bandits

func _test_bandits() -> void:
	var c := quiet(12)
	var ow := c.overworld
	var spot := MapData.walkable_point(Vector2(1300, 1700))
	var b := make(c, "bandits", spot, 30)
	b.base = spot
	b.state = "lurk"
	b.busy_hours = 50.0
	# Une proie faible en vue : ils fondent dessus
	var v := make(c, "villagers", spot + Vector2(140, 0), 8)
	v.state = "market"
	v.gold = 100
	v.busy_hours = 100.0 # Au marché, ils ne regardent pas (et ne bougent pas)
	run_until(c, 2.0, func() -> bool: return b.state == "chase")
	check(b.state == "chase" and b.target_id == v.id and not b.hidden, "bandits : ne chassent pas les villageois (%s)" % b.state)
	var vid := v.id
	var before := b.men()
	run_until(c, 24.0, func() -> bool: return ow.by_id(c, vid) == null or v.men() < 8)
	check(ow.by_id(c, vid) == null or v.men() < 8, "bandits : la proie n'est pas attaquée")
	check(b.state == "return_loot" and b.gold > 0, "bandits : ne rentrent pas avec le butin (%s, %d écus)" % [b.state, b.gold])
	var after_fight := b.men()
	run_until(c, 48.0, func() -> bool: return b.state == "lurk")
	check(b.state == "lurk" and b.pos.distance_to(b.base) < 40.0 and b.men() > after_fight, "bandits : pas de recrues au repaire (%d → %d → %d hommes)" % [before, after_fight, b.men()])
	print("  Bandits : %d hommes, %d après le coup, %d au repaire" % [before, after_fight, b.men()])
	# En forêt, tapis au repaire, ils sont cachés
	var forest := Vector2(-1, -1)
	for y in range(100, int(MapData.SIZE.y) - 100, 32):
		for x in range(100, int(MapData.SIZE.x) - 100, 32):
			if forest.x < 0.0 and MapData.ground_at(Vector2(x, y)) == MapData.Ground.FOREST:
				forest = Vector2(x, y)
	if forest.x >= 0.0:
		b.pos = forest
		b.base = forest
		PartyAI.lurk(ow, b, 5.0, 6.0)
		check(b.hidden, "bandits : pas cachés en forêt")
		PartyAI.think(c, ow, b, 0.5)
		check(b.hidden and ow.contact(c) == null, "bandits : la cachette ne tient pas")
	# Plus fort qu'eux en vue : ils fuient
	b.pos = spot
	b.base = spot
	b.hidden = false
	PartyAI.lurk(ow, b, 50.0, 50.0)
	var pat := ow.spawn(c, "patrol")
	pat.troops = [{"type": "spear", "men": 120, "xp": 100.0}]
	pat.pos = MapData.walkable_point(spot + Vector2(-150, 0))
	pat.state = "garrison"
	pat.busy_hours = 100.0
	run_until(c, 2.0, func() -> bool: return b.state == "flee")
	check(b.state == "flee" and not b.path.is_empty() or b.pos.distance_to(pat.pos) > 160.0, "bandits : ne fuient pas une forte patrouille (%s)" % b.state)
	ow.remove(c, pat)
	# La compagnie, faible, est une proie ; forte, ils la laissent passer
	var c2 := quiet(13)
	var ow2 := c2.overworld
	ow2.inside = -1
	ow2.player.pos = MapData.walkable_point(Vector2(1800, 1200))
	var weak := make(c2, "bandits", ow2.player.pos + Vector2(120, 0), 20)
	weak.base = weak.pos
	PartyAI.think(c2, ow2, weak, 1.0)
	check(weak.state != "chase", "bandits : une petite bande attaque une forte compagnie")
	ow2.remove(c2, weak)
	var strong := make(c2, "bandits", ow2.player.pos + Vector2(120, 0), 300)
	strong.base = strong.pos
	PartyAI.think(c2, ow2, strong, 1.0)
	check(strong.state == "chase" and strong.target_id == ow2.player.id and ow2.hostile(c2, strong), "bandits : ne chassent pas une compagnie faible (%s)" % strong.state)
	print("Bandits : OK")


# ---------------------------------------------------------------- Caravanes

func _test_caravans() -> void:
	var c := quiet(14)
	var ow := c.overworld
	var k := ow.spawn(c, "caravan")
	var start_gold := k.gold
	var start_goods := k.goods
	run_until(c, 2.0, func() -> bool: return k.state == "travel")
	check(k.state == "travel" and k.goal >= 0 and k.goal != k.home and MapData.place(k.goal)["kind"] == "town", "caravane : pas de route vers une autre ville (%s)" % k.state)
	# Escorte : payée à l'arrivée
	c.start_escort(k, 100)
	var goal := k.goal
	var h := run_until(c, 24.0 * 8, func() -> bool: return k.state == "trade")
	check(k.state == "trade" and PartyAI.at_place(k, goal), "caravane : pas arrivée (%s, %.0f h)" % [k.state, h])
	var paid := c.log_lines.any(func(s: String) -> bool: return "bon port" in s)
	check(c.escort_for(k.id).is_empty() and paid, "caravane : escorte non payée à l'arrivée (%s)" % str(c.log_lines))
	check(k.gold + k.goods > start_gold + start_goods, "caravane : pas de bénéfice (%d+%d → %d+%d)" % [start_gold, start_goods, k.gold, k.goods])
	print("  Caravane : %s → %s en %.0f h, %d → %d écus" % [MapData.place(k.home)["name"] if k.home != goal else "?", MapData.place(goal)["name"], h, start_gold + start_goods, k.gold + k.goods])
	# Des bandits repérés sur la route : détour
	run_until(c, 24.0, func() -> bool: return k.state == "travel" and k.path.size() > 0 and k.pos.distance_to(MapData.place_pos(goal)) > 80.0)
	check(k.state == "travel", "caravane : ne repart pas")
	var ahead := k.pos + (k.path[-1] - k.pos).normalized() * 120.0 if not k.path.is_empty() else k.pos + Vector2(120, 0)
	var b := make(c, "bandits", ahead, 60)
	b.base = b.pos
	PartyAI.lurk(ow, b, 100.0, 100.0)
	b.hidden = false
	PartyAI.think(c, ow, k, 1.0) # Un pas d'une heure : elle regarde autour d'elle
	check(k.state == "flee", "caravane : n'évite pas les bandits (%s)" % k.state)
	ow.remove(c, b)
	h = run_until(c, 48.0, func() -> bool: return k.state == "travel")
	check(k.state == "travel" and k.goal >= 0, "caravane : ne reprend pas la route après le détour (%s)" % k.state)
	print("Caravanes : OK")


# ---------------------------------------------------------------- Patrouilles

func _test_patrols() -> void:
	var c := quiet(15)
	var ow := c.overworld
	var p := ow.spawn(c, "patrol")
	check(p.faction >= 0 and p.home >= 0 and p.speed_bonus > 1.0, "patrouille : mal levée")
	p.busy_hours = 0.0
	var home := p.home
	run_until(c, 48.0, func() -> bool: return p.state == "patrol")
	check(p.state == "patrol" and p.goal >= 0 and PartyAI.place_owner(c, p.goal) == p.faction, "patrouille : ne part pas en tournée (%s)" % p.state)
	check(not p.path.is_empty() and p.path[-1].distance_to(MapData.place_pos(home)) < MapData.PLACE_RADIUS, "patrouille : la tournée ne revient pas à la ville")
	var far := [0.0]
	var h := run_until(c, 24.0 * 8, func() -> bool:
		far[0] = maxf(far[0], p.pos.distance_to(MapData.place_pos(home)))
		return far[0] > 100.0 and p.state == "garrison")
	check(far[0] > 100.0 and p.state == "garrison" and PartyAI.at_place(p, home), "patrouille : pas de boucle sur son territoire (%.0f px, %s)" % [far[0], p.state])
	print("  Patrouille : tournée de %.0f h, jusqu'à %.0f px de %s" % [h, far[0], MapData.place(home)["name"]])
	# Des bandits en vue : la patrouille les pourchasse et les bat
	p.troops = [{"type": "spear", "men": 40, "xp": 120.0}, {"type": "cavalry", "men": 20, "xp": 120.0}]
	p.pos = MapData.walkable_point(MapData.place_pos(home) + Vector2(0, 160))
	p.state = "rest"
	p.busy_hours = 0.0
	p.path.clear()
	var b := make(c, "bandits", p.pos + Vector2(100, 0), 20)
	b.base = b.pos
	b.state = "prowl"
	var bid := b.id
	var men_before := b.men()
	h = run_until(c, 48.0, func() -> bool: return ow.by_id(c, bid) == null or b.men() < men_before)
	check(ow.by_id(c, bid) == null or b.men() < men_before, "patrouille : les bandits lui échappent (%s / %s)" % [p.state, b.state])
	check(not p.is_dead() and p.gold > 0, "patrouille : pas de butin")
	print("  Patrouille : bandits battus en %.0f h (%d → %d hommes)" % [h, men_before, b.men() if ow.by_id(c, bid) != null else 0])
	# Combat simulé : le plus fort l'emporte, le vaincu détale ou se disperse
	var x := make(c, "bandits", p.pos + Vector2(10, 0), 8)
	var w := PartyAI.fight(c, ow, p, x)
	check(w == p and (x.is_dead() or x.state == "flee") and (x.is_dead() == (ow.by_id(c, x.id) == null)), "combat : le fort ne bat pas le faible")
	# Faction hostile à la compagnie : la patrouille fond sur elle
	var c2 := quiet(16)
	var ow2 := c2.overworld
	var q := ow2.spawn(c2, "patrol")
	q.troops = [{"type": "spear", "men": 400, "xp": 100.0}]
	q.busy_hours = 0.0
	ow2.inside = -1
	ow2.player.pos = MapData.walkable_point(q.pos + Vector2(140, 40))
	PartyAI.think(c2, ow2, q, 1.0)
	check(q.state != "chase", "patrouille : attaque une compagnie amie")
	c2.reputation[q.faction] = CampaignState.REP_CLOSED - 10
	PartyAI.think(c2, ow2, q, 1.0)
	check(q.state == "chase" and q.target_id == ow2.player.id and ow2.hostile(c2, q), "patrouille : ne pourchasse pas la compagnie haïe (%s)" % q.state)
	check(Encounter.attitude(c2, ow2.player, q) == Encounter.ATTACKING, "patrouille : rencontre pas hostile")
	var e := {}
	for i in 24:
		e = ow2.tick(c2, 1.0)
		if e.has("event"):
			break
	check(str(e.get("event", "")) == "contact" and int(e.get("id", -1)) == q.id, "patrouille : pas de rencontre (%s)" % str(e))
	print("Patrouilles : OK")


# ---------------------------------------------------------------- Déserteurs

func _test_deserters() -> void:
	var c := quiet(17)
	var ow := c.overworld
	var d := ow.spawn_deserters(c, Vector2(1300, 900), 1, 200)
	check(d.kind == "deserters" and d.men() >= 8 and d.faction == 1, "déserteurs : mal levés")
	run_until(c, 12.0, func() -> bool: return false)
	check(d.kind == "deserters" and d.pos.distance_to(MapData.place_pos(MapData.nearest_town(d.pos))) > 150.0, "déserteurs : près d'une ville")
	var h := run_until(c, 24.0 * 6, func() -> bool: return d.kind == "bandits")
	check(d.kind == "bandits" and d.name != "" and d.faction == -1 and d.base.x >= 0.0, "déserteurs : ne tournent pas au brigandage (%.0f h)" % h)
	print("  Déserteurs : brigands au bout de %.1f jours (%s)" % [(h + 12.0) / 24.0, d.name])
	# Les batailles du monde vivant jettent des déserteurs sur les chemins
	var c2 := CampaignState.new_game(18)
	var ow2 := c2.overworld
	c2.world.declare_war(c2, 0, 1)
	var cap := ow2.population_cap(c2, "deserters")
	check(cap > Overworld.PEACE_DESERTERS, "déserteurs : pas plus nombreux en guerre")
	for p in ow2.parties.duplicate():
		if p.kind == "deserters":
			ow2.remove(c2, p)
	for i in 6:
		c2.world.aftermath.append({"pos": MapData.place_pos(1), "faction": 0, "men": 150})
	ow2.populate(c2)
	check(ow2.count("deserters") >= 2 and c2.world.aftermath.is_empty(), "déserteurs : aucun après les batailles (%d)" % ow2.count("deserters"))
	print("Déserteurs : OK")


# ---------------------------------------------------------------- Peuplement

func _test_population() -> void:
	var c := CampaignState.new_game(19)
	var ow := c.overworld
	c.world.wars.clear()
	for kind in ["villagers", "caravan", "patrol", "bandits"]:
		var cap := ow.population_cap(c, kind)
		check(cap >= 2 and ow.count(kind) == cap, "peuplement : %d %s pour un plafond de %d" % [ow.count(kind), kind, cap])
	var total := ow.parties.size()
	print("  Population de départ : %d groupes (%s)" % [total, str(_census(ow))])
	check(total >= 20 and total <= 60, "peuplement : %d groupes sur la carte" % total)
	# Saisons et guerres
	var summer := ow.population_cap(c, "caravan")
	var bandits := ow.population_cap(c, "bandits")
	var day := c.day
	c.day = WorldSim.WINTER * WorldSim.SEASON_DAYS + 2
	check(ow.population_cap(c, "caravan") < summer, "peuplement : autant de caravanes en hiver")
	c.day = day
	c.world.declare_war(c, 0, 2)
	check(ow.population_cap(c, "bandits") > bandits and ow.population_cap(c, "deserters") > Overworld.PEACE_DESERTERS, "peuplement : la guerre ne jette pas plus de brigands")
	c.world.wars.clear()
	# Réapparitions : la carte se repeuple, quelques groupes par jour
	for p in ow.parties.duplicate():
		if p.kind in ["villagers", "bandits"]:
			ow.remove(c, p)
	ow.inside = 0
	ow.tick(c, 24.0)
	check(ow.count("villagers") > 0 and ow.count("villagers") <= Overworld.SPAWNS_PER_DAY + 1, "peuplement : réapparitions (%d villageois en un jour)" % ow.count("villagers"))
	for i in 6:
		ow.tick(c, 24.0)
		ow.inside = 0
		c.gold = maxi(c.gold, 100000)
	for kind in ["villagers", "bandits"]:
		check(ow.count(kind) >= ow.population_cap(c, kind) - 1, "peuplement : %s pas entretenus (%d / %d)" % [kind, ow.count(kind), ow.population_cap(c, kind)])
	print("  Après une semaine : %s" % str(_census(ow)))
	print("Peuplement : OK")


func _census(ow: Overworld) -> Dictionary:
	var out := {}
	for p in ow.parties:
		out[p.kind] = int(out.get(p.kind, 0)) + 1
	return out


# ---------------------------------------------------------------- Déterminisme

func _test_determinism() -> void:
	var a := CampaignState.new_game(21)
	var b := CampaignState.new_game(21)
	for c in [a, b]:
		c.gold = 100000
		c.overworld.inside = 0
	for i in 5 * 24:
		for c in [a, b]:
			c.overworld.tick(c, 1.0)
			c.overworld.inside = 0
	check(JSON.stringify(a.overworld.to_dict()) == JSON.stringify(b.overworld.to_dict()), "déterminisme : deux simulations de même graine divergent")
	# Après une sauvegarde relue, la suite est la même (au flottant près : le JSON de la sauvegarde
	# arrondit les nombres, comme dans overworld_test)
	var l := CampaignState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check(l != null, "déterminisme : sauvegarde illisible")
	if l == null:
		return
	l.overworld.inside = 0
	check(_ids(a.overworld) == _ids(l.overworld), "déterminisme : groupes perdus à la relecture")
	for p in a.overworld.parties:
		var q := PartyAI.lookup(l, l.overworld, p.id)
		if q != null and (q.base.distance_to(p.base) > 0.01 or absf(q.age - p.age) > 0.01 or q.state != p.state):
			check(false, "sauvegarde : %s %d mal relu (repaire, âge ou état)" % [p.kind, p.id])
			break
	for i in 12:
		for c in [a, l]:
			c.overworld.tick(c, 1.0)
			c.overworld.inside = 0
	var off := 0
	for p in a.overworld.parties:
		var q := PartyAI.lookup(l, l.overworld, p.id)
		if q == null or q.kind != p.kind or q.state != p.state or q.pos.distance_to(p.pos) > 2.0:
			off += 1
	check(off == 0, "déterminisme : %d groupes divergent après relecture" % off)
	print("Déterminisme : OK (%d groupes après 5 jours)" % a.overworld.parties.size())


func _ids(ow: Overworld) -> Array:
	var out: Array = []
	for p in ow.parties:
		out.append(p.id)
	return out


# ---------------------------------------------------------------- Performances

func _test_performance() -> void:
	var c := CampaignState.new_game(22)
	var ow := c.overworld
	c.gold = 100000
	ow.inside = 0
	var kinds := ["villagers", "bandits", "caravan", "patrol", "deserters"]
	var i := 0
	while ow.parties.size() < 60:
		ow.spawn(c, kinds[i % kinds.size()])
		i += 1
	var t0 := Time.get_ticks_usec()
	for h in 48:
		ow.tick(c, 1.0)
		ow.inside = 0
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var per_hour := ms / 48.0
	print("  Performances : %d groupes, %.2f ms par heure de jeu" % [ow.parties.size(), per_hour])
	# À vitesse x4, la carte fait passer 6 heures de jeu par seconde : 25 ms par heure en prennent 15 %
	check(per_hour < 25.0, "performances : %.1f ms par heure de jeu avec %d groupes" % [per_hour, ow.parties.size()])
	print("Performances : OK")
