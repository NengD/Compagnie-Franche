extends SceneTree
## Test des vrais sièges (siege.gd, siege_terrain.gd), sans fenêtre :
##   godot --headless --path . -s tests/siege_test.gd [-- --seed=N]
##  1. Rempart : bloqué sans ouverture, passage par une échelle (lentement) et par la porte enfoncée.
##  2. Bélier : il enfonce la porte ; échelle sans personne en haut : la garnison la repousse.
##  3. Assaut gagné : le camp du joueur, joué par l'IA, dresse ses échelles, monte aux murs et prend la place.
##  4. Défense tenue : l'IA ennemie monte aux murs mais la garnison (IA du joueur) tient la ville.
##  5. Hauteur et bélier : on frappe mal vers le haut, le bélier est lent et craint les flèches.
##  6. Mâchicoulis : la garnison au-dessus de la porte verse l'huile et jette des pierres (pas sans elle).
##  7. Bélier abandonné : l'IA assaillante envoie un autre régiment le reprendre.
##  8. Fiefs : l'assaut et la défense d'un château se jouent sur la ville fortifiée.
##  9. Campagne : contrats de siège rares, mieux payés, sauvegardés, terrain de ville en bataille,
##     vraie ligne d'objectif, et rencontre sur la route jamais jouée sur la palissade.
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05

var scene: PackedScene
var seed_value := 4242
var fails: Array[String] = []


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
	scene = load("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	walls_scenario()
	ram_and_push_scenario()
	assault_scenario()
	defense_scenario()
	height_and_ram_rules()
	machicolation_scenario()
	ram_pickup_scenario()
	fief_scenario()
	campaign_scenario()
	if fails.is_empty():
		print("SIEGE TEST OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : " + f)
		print("SIEGE TEST ÉCHOUÉ")
		quit(1)
	return true


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func new_battle(terrain: String, s := 0) -> Node:
	var b := scene.instantiate()
	b.set("seed_override", s if s != 0 else seed_value)
	b.set("terrain_override", terrain)
	b.set("difficulty", "normal")
	root.add_child(b)
	return b


func end_battle(b: Node) -> void:
	root.remove_child(b)
	b.free()


## Retire tous les régiments d'un camp (ou seulement ceux qui ne sont pas dans keep).
func remove_team(b: Node, team: int, keep: Array = []) -> void:
	for r: Regiment in b.regiments:
		if r.team == team and not r in keep:
			for s in r.soldiers:
				s.alive = false
			r.update_center()


## Retire la garnison sauf un régiment d'archers, posté au fond de la ville (sans lui, la bataille
## serait gagnée au premier pas).
func clear_garrison(b: Node) -> void:
	var keep := first_of(b, BattleSim.ENEMY, "archer")
	remove_team(b, BattleSim.ENEMY, [keep])
	var t: SiegeTerrain = b.sim.siege.town
	b.sim.siege.place(keep, t.at_depth(SiegeTerrain.X0 + 120.0, 650.0), Vector2.DOWN)


func first_of(b: Node, team: int, type: String) -> Regiment:
	for r: Regiment in b.regiments:
		if r.team == team and r.type == type and not r.is_dead():
			return r
	return null


## Fait marcher un régiment vers goal pendant secs secondes ; renvoie le temps mis (INF s'il n'arrive pas).
func march(b: Node, r: Regiment, goal: Vector2, secs: float) -> float:
	r.dest = goal
	var t := 0.0
	while t < secs:
		b.simulate(STEP)
		t += STEP
		if r.center.distance_to(goal) < 30.0:
			return t
	return INF


# ---------------------------------------------------------------- 1. Rempart

func walls_scenario() -> void:
	var b := new_battle("town_assault")
	var sg: Siege = b.sim.siege
	check(sg != null and b.terrain.town != null, "rempart : pas de siège sur le terrain town_assault")
	if sg == null:
		end_battle(b)
		return
	var t: SiegeTerrain = sg.town
	check(t.towers.size() == 6 and not t.gate_open, "rempart : %d tours" % t.towers.size())
	var outside := Vector2(t.gate_x + 400.0, t.front_y + 120.0)
	var inner := Vector2(t.gate_x + 400.0, t.front_y - 160.0)
	check(b.terrain.wall_blocks(outside, inner), "rempart : wall_blocks ne bloque pas le mur")
	check(not b.terrain.wall_blocks(outside, outside + Vector2(200, 0)), "rempart : wall_blocks bloque hors du mur")
	check(b.terrain.height(Vector2(t.gate_x + 300.0, t.front_y - 32.0)) == 1.0, "rempart : chemin de ronde sans hauteur")
	check(b.terrain.range_factor(Vector2(t.gate_x + 300.0, t.front_y - 32.0)) > 1.2, "rempart : pas de bonus de portée sur le mur")
	# Un régiment seul, sans ouverture : il reste dehors
	clear_garrison(b)
	var spear := first_of(b, BattleSim.PLAYER, "spear")
	remove_team(b, BattleSim.PLAYER, [spear])
	sg.place(spear, outside, Vector2.UP)
	sg.ladders.clear()
	sg.ram_bearer = null
	b.start_battle()
	march(b, spear, inner, 25.0)
	var inside_n := 0
	for s in spear.alive_soldiers():
		if t.inside(s.pos, -SiegeTerrain.WALL_T * 0.5):
			inside_n += 1
	check(inside_n == 0, "rempart : %d soldats ont traversé un mur plein" % inside_n)
	# Échelle dressée près de lui : il monte (lentement) et entre
	sg.ladders.append({"owner": spear, "x": t.ladder_spot(spear.center.x, []), "state": "up", "t": 0.0, "push": 0.0, "falls": 0})
	sg.refresh(b.sim)
	var climb := march(b, spear, inner, 90.0)
	print("Rempart : entrée par l'échelle en %.1f s, %d grimpeurs" % [climb, sg.climbers.size()])
	check(climb < 90.0, "rempart : le régiment n'entre pas par l'échelle")
	check(sg.climbers.size() >= 10, "rempart : grimpeurs comptés %d" % sg.climbers.size())
	end_battle(b)


# ---------------------------------------------------------------- 2. Bélier et échelle repoussée

func ram_and_push_scenario() -> void:
	var b := new_battle("town_assault")
	var sg: Siege = b.sim.siege
	var t: SiegeTerrain = sg.town
	b.start_battle()
	# Le bélier seul devant la porte (la garnison est retirée) : elle cède
	clear_garrison(b)
	var ram := sg.ram_bearer
	check(ram != null, "bélier : aucun porteur")
	if ram == null:
		end_battle(b)
		return
	var time := march(b, ram, t.ram_spot() + Vector2(0, 16), 60.0)
	var t0: float = b.battle_time
	while not t.gate_open and b.battle_time - t0 < 60.0:
		b.simulate(STEP)
	print("Bélier : arrivé en %.1f s, porte enfoncée en %.1f s" % [time, b.battle_time - t0])
	check(t.gate_open, "bélier : la porte n'a pas cédé (%.0f points)" % sg.gate_hp)
	check(time + b.battle_time - t0 < 90.0, "bélier : porte enfoncée trop lentement (%.0f s)" % (time + b.battle_time - t0))
	check(b.battle_time - t0 > 15.0, "bélier : porte enfoncée trop vite (%.0f s)" % (b.battle_time - t0))
	check(not b.terrain.wall_blocks(t.ram_spot(), t.ram_spot() + Vector2(0, -80)), "bélier : la porte enfoncée bloque encore")
	end_battle(b)

	# Échelle dressée, garnison au débouché, personne pour la tenir : repoussée
	b = new_battle("town_assault")
	sg = b.sim.siege
	t = sg.town
	b.start_battle()
	var lad: Dictionary = sg.ladders[0]
	var owner: Regiment = lad["owner"]
	remove_team(b, BattleSim.PLAYER, [owner])
	var x := t.ladder_spot(owner.center.x, [])
	lad["x"] = x
	lad["state"] = "up"
	sg.refresh(b.sim)
	var guard := first_of(b, BattleSim.ENEMY, "spear")
	remove_team(b, BattleSim.ENEMY, [guard])
	sg.place(guard, t.ladder_top(x) - Vector2(0, 6), Vector2.DOWN)
	guard.hold_position = true
	b.ai.plan_override = "defensive"
	var t1: float = b.battle_time
	while sg.pushed == 0 and b.battle_time - t1 < 30.0:
		b.simulate(STEP)
	print("Échelle repoussée en %.1f s (état : %s)" % [b.battle_time - t1, lad["state"]])
	check(sg.pushed > 0 and lad["state"] in ["down", "broken"], "échelle : la garnison ne la repousse pas")
	end_battle(b)


# ---------------------------------------------------------------- 3. Assaut gagné

## Bataille complète jouée par l'IA des deux côtés ; renvoie la bataille finie (à libérer).
func play(b: Node, max_time: float) -> Node:
	var player := TestPlayer.new("ai")
	b.start_battle()
	while b.state == b.State.BATTLE and b.battle_time < max_time:
		player.update(b)
		b.simulate(STEP)
	return b


func assault_scenario() -> void:
	var b := new_battle("town_assault")
	var sg: Siege = b.sim.siege
	# Garnison réduite (à forces égales, la garnison tient) : piquiers, hommes d'armes et archers
	var keep: Array = []
	for type in ["spear", "men_at_arms", "archer"]:
		keep.append(first_of(b, BattleSim.ENEMY, type))
	remove_team(b, BattleSim.ENEMY, keep)
	sg.deploy(b.sim) # Replace la garnison restante (le bélier et les échelles restent attribués)
	play(b, 420.0)
	print("Assaut : %s en %.0f s, raison « %s », échelles dressées %d, repoussées %d, grimpeurs %d, porte %s" % [
		"victoire" if b.state == b.State.VICTORY else "pas de victoire", b.battle_time, sg.reason, sg.raised, sg.pushed,
		sg.climbers.size(), "enfoncée" if sg.town.gate_open else "debout (%.0f)" % sg.gate_hp])
	check(b.state == b.State.VICTORY, "assaut : pas de victoire (état %d, %.0f s)" % [b.state, b.battle_time])
	check(sg.reason == "plaza", "assaut : la ville n'est pas prise par la place (raison « %s »)" % sg.reason)
	check(sg.raised > 0, "assaut : aucune échelle dressée")
	check(sg.climbers.size() > 0, "assaut : personne n'est monté aux murs")
	end_battle(b)


# ---------------------------------------------------------------- 4. Défense tenue

func defense_scenario() -> void:
	var b := new_battle("town_defense")
	var sg: Siege = b.sim.siege
	check(sg.attacker == BattleSim.ENEMY, "défense : l'assaillant n'est pas l'ennemi")
	check(b.deploy_top() > sg.town.front_y, "défense : zone de déploiement hors de la ville")
	play(b, Siege.DEFENSE_TIME + 30.0)
	print("Défense : %s en %.0f s, raison « %s », échelles ennemies dressées %d, repoussées %d, grimpeurs %d, place %.0f %%" % [
		"victoire" if b.state == b.State.VICTORY else "pas de victoire", b.battle_time, sg.reason, sg.raised, sg.pushed,
		sg.climbers.size(), sg.hold * 100.0])
	check(b.state == b.State.VICTORY, "défense : la ville n'a pas tenu (état %d, %.0f s)" % [b.state, b.battle_time])
	check(sg.raised > 0, "défense : l'IA ne dresse aucune échelle")
	check(sg.climbers.size() > 0, "défense : l'IA ne monte pas aux murs")
	check(sg.gate_hp < Siege.GATE_HP or sg.town.gate_open, "défense : le bélier ennemi n'a jamais frappé la porte")
	var xs: Array[float] = []
	for l in sg.ladders:
		if float(l["x"]) >= 0.0:
			xs.append(float(l["x"]))
	var gap := INF
	for i in xs.size():
		for j in range(i + 1, xs.size()):
			gap = minf(gap, absf(xs[i] - xs[j]))
	print("Défense : échelles en %s (écart minimal %.0f), huile versée %d, pierres %d" % [str(xs), gap, sg.oil_poured, sg.stones_dropped])
	check(xs.size() >= 2 and gap >= 200.0, "défense : l'IA ne répartit pas ses échelles (%s)" % str(xs))
	end_battle(b)


# ---------------------------------------------------------------- 5. Hauteur et bélier

func height_and_ram_rules() -> void:
	var b := new_battle("town_defense")
	var sg: Siege = b.sim.siege
	var t: SiegeTerrain = sg.town
	var walk := t.at_depth(t.gate_x + 300.0, SiegeTerrain.WALL_T * 0.5 + 20.0)
	var below := t.ladder_foot(t.gate_x + 300.0)
	var up: float = b.terrain.height_damage(below, walk)
	var down: float = b.terrain.height_damage(walk, below)
	print("Hauteur : coup vers le haut x%.2f, vers le bas x%.2f, portée sur le mur x%.2f" % [up, down, b.terrain.range_factor(walk)])
	check(up < 0.8, "hauteur : frapper vers le chemin de ronde n'est pas plus dur (x%.2f)" % up)
	check(down > 1.2, "hauteur : frapper du haut du mur ne porte pas plus (x%.2f)" % down)
	check(b.terrain.range_factor(walk) > b.terrain.range_factor(below) + 0.2, "hauteur : les archers du mur ne tirent pas plus loin")
	check(b.terrain.wall_shelters(below + Vector2(0, 200.0 * t.out_dir), walk), "hauteur : le parapet n'abrite pas le chemin de ronde")
	var ram := sg.ram_bearer
	check(ram != null, "bélier : l'IA assaillante n'a pas de bélier")
	if ram != null:
		var other: Regiment = null
		for r: Regiment in b.regiments:
			if r.team == sg.attacker and r != ram:
				other = r
				break
		check(sg.speed_factor(ram) < 0.8 and sg.speed_factor(other) == 1.0, "bélier : les porteurs ne sont pas ralentis")
		check(sg.arrow_factor(ram) > 1.2 and sg.arrow_factor(other) == 1.0, "bélier : les porteurs ne craignent pas plus les flèches")
		t.gate_open = true
		check(sg.speed_factor(ram) == 1.0, "bélier : toujours lent une fois la porte enfoncée")
	end_battle(b)


# ---------------------------------------------------------------- 6. Mâchicoulis

## Le bélier du joueur frappe la porte ; garde : un régiment ennemi au-dessus de la porte (ou personne).
func drops_at_gate(guarded: bool) -> Siege:
	var b := new_battle("town_assault")
	var sg: Siege = b.sim.siege
	var t: SiegeTerrain = sg.town
	b.start_battle()
	var ram := sg.ram_bearer
	remove_team(b, BattleSim.PLAYER, [ram])
	var guard := first_of(b, BattleSim.ENEMY, "spear")
	var far := first_of(b, BattleSim.ENEMY, "archer")
	var keep: Array = [far] # Sans personne, la bataille serait gagnée
	if guarded:
		keep.append(guard)
	remove_team(b, BattleSim.ENEMY, keep)
	sg.place(far, t.at_depth(SiegeTerrain.X0 + 120.0, 650.0), Vector2.DOWN)
	if guarded:
		sg.place(guard, sg.gate_top(), Vector2(0, t.out_dir))
		guard.hold_position = true
	b.ai.plan_override = "defensive"
	var hp0 := ram.alive_n
	march(b, ram, t.ram_spot() + Vector2(0, 16), 60.0)
	var t0: float = b.battle_time
	var guards := 0
	while b.battle_time - t0 < 30.0 and b.state == b.State.BATTLE and not t.gate_open:
		b.simulate(STEP)
		guards = maxi(guards, sg.gate_guards(b.sim))
	print("Mâchicoulis (%s) : gardes %d, huile %d, pierres %d, porteurs %d -> %d" % ["gardée" if guarded else "sans garde",
		guards, sg.oil_poured, sg.stones_dropped, hp0, ram.alive_n])
	end_battle(b)
	return sg


func machicolation_scenario() -> void:
	var sg := drops_at_gate(true)
	check(sg.oil_poured > 0, "mâchicoulis : pas d'huile versée sur le bélier")
	check(sg.stones_dropped > 0, "mâchicoulis : pas de pierres jetées")
	check(sg.oil_left == Siege.OIL_POTS - sg.oil_poured, "mâchicoulis : chaudrons mal comptés")
	var bare := drops_at_gate(false)
	check(bare.oil_poured == 0 and bare.stones_dropped == 0, "mâchicoulis : huile ou pierres sans personne au-dessus de la porte")


# ---------------------------------------------------------------- 7. Bélier abandonné

func ram_pickup_scenario() -> void:
	var b := new_battle("town_defense")
	var sg: Siege = b.sim.siege
	var t: SiegeTerrain = sg.town
	var player := TestPlayer.new("ai")
	b.start_battle()
	var first := sg.ram_bearer
	while b.battle_time < 60.0 and first.center.distance_to(t.ram_spot()) > 500.0:
		player.update(b)
		b.simulate(STEP)
	for s in first.soldiers: # Les porteurs tombent
		s.alive = false
	first.update_center()
	var t0: float = b.battle_time
	while b.state == b.State.BATTLE and b.battle_time - t0 < 60.0 and (sg.ram_bearer == null or sg.ram_bearer == first):
		player.update(b)
		b.simulate(STEP)
	var taker := sg.ram_bearer
	print("Bélier abandonné : repris en %.1f s par %s" % [b.battle_time - t0, taker.display_name() if taker != null else "personne"])
	check(taker != null and taker != first and taker.team == BattleSim.ENEMY, "bélier : l'IA ne reprend pas le bélier abandonné")
	end_battle(b)


# ---------------------------------------------------------------- 8. Fiefs

func fief_scenario() -> void:
	var c := CampaignState.new_game(91)
	var castle := -1
	for i in MapData.place_count():
		if Fiefs.is_castle(i):
			castle = i
			break
	check(castle >= 0, "fief : aucun château sur la carte")
	if castle < 0:
		return
	CampaignState.current = c
	c.pending = c.fiefs.make_assault(c, castle)
	var b := scene.instantiate()
	root.add_child(b)
	check(b.terrain.kind == Siege.ASSAULT and b.sim.siege != null and b.sim.siege.ram_bearer != null, "fief : assaut du château joué sur %s" % b.terrain.kind)
	end_battle(b)
	c.fiefs.grant(c, castle, -1)
	var e: Dictionary = c.fiefs.fief(castle)
	e["siege"] = {"faction": 1, "men": 200, "days": 2}
	c.pending = c.fiefs.make_defense(c, e)
	b = scene.instantiate()
	root.add_child(b)
	check(b.terrain.kind == Siege.DEFENSE and b.sim.siege != null and b.sim.siege.attacker == BattleSim.ENEMY, "fief : défense du château jouée sur %s" % b.terrain.kind)
	check(b.sim.siege.ram_bearer != null and not b.sim.siege.ladders.is_empty(), "fief : l'assaillant n'a ni bélier ni échelles")
	end_battle(b)
	CampaignState.current = null


# ---------------------------------------------------------------- 9. Campagne

func campaign_scenario() -> void:
	var c := CampaignState.new_game(77)
	c.fame = CampaignState.FAME_STEP * 3
	var n := 0
	var sieges := 0
	var kinds := {}
	for i in 400:
		c.contracts.clear()
		c.refresh_contracts(i % CampaignState.TOWNS.size())
		for k in c.contracts:
			n += 1
			if k.has("siege"):
				sieges += 1
				kinds[k["siege"]] = true
	var share := float(sieges) / maxf(n, 1)
	print("Campagne : %d sièges sur %d contrats (%.0f %%), sortes %s" % [sieges, n, share * 100.0, str(kinds.keys())])
	check(share > 0.03 and share < 0.25, "campagne : part des sièges %.2f" % share)
	check(kinds.size() == 2, "campagne : il manque l'assaut ou la défense")
	# Mieux payé, plus d'ennemis, sauvegardé
	var base := c.make_contract(2)
	var plain_reward := int(base["reward"])
	var men := int(base["enemy"].size())
	var k := c.make_siege(base.duplicate(true), "defense")
	check(int(k["reward"]) > plain_reward * 1.4, "campagne : siège mal payé (%d contre %d)" % [int(k["reward"]), plain_reward])
	check(k["enemy"].size() == men + 1, "campagne : l'assaillant n'a pas de régiment en plus")
	var back := CampaignState.contract_from_dict(JSON.parse_string(JSON.stringify(CampaignState.contract_to_dict(k))))
	check(str(back.get("siege", "")) == "defense", "campagne : la sorte de siège n'est pas sauvegardée")
	# En bataille : le terrain vient du contrat
	c.location = int(k["town"])
	check(c.accept(k) == "", "campagne : contrat de siège refusé")
	CampaignState.current = c
	var b := scene.instantiate()
	root.add_child(b)
	check(b.terrain.kind == "town_defense" and b.sim.siege != null, "campagne : terrain %s au lieu de town_defense" % b.terrain.kind)
	end_battle(b)
	# Ligne d'objectif de la carte : le vrai objectif du siège, pas « détruire l'armée ennemie » (B5)
	var line_d := CampaignState.objective_line(k)
	var line_a := CampaignState.objective_line(c.make_siege(c.make_contract(2), "assault"))
	check(line_d.contains("tenir les murs") and not line_d.contains("détruire"), "campagne : objectif de défense « %s »" % line_d)
	check(line_a.contains("tenir sa place") and not line_a.contains("détruire"), "campagne : objectif d'assaut « %s »" % line_a)
	# Rencontre d'une armée sur la route de Hautemure (ville à palissade) : jamais la palissade (B6)
	c.pending = {}
	var army := c.world.add_army(1, 4, 5, 600, "march")
	c.pending = c.world.make_battle(c, army, 5)
	check(Terrain.for_contract(5, int(c.pending["difficulty"]), CampaignState.TOWNS) == "siege", "campagne : la rencontre n'est pas assez dure pour tester la palissade")
	b = scene.instantiate()
	root.add_child(b)
	check(b.terrain.kind in WorldSim.ROAD_TERRAINS and b.sim.siege == null, "campagne : rencontre sur la route jouée sur le terrain %s" % b.terrain.kind)
	end_battle(b)
	CampaignState.current = null
