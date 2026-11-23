extends SceneTree
## Test headless de la météo de bataille et de la relève :
##   godot --headless --path . -s tests/weather_test.gd
## - pluie : portée et dégâts des arcs réduits, moins pour les arbalètes ; boue : cavalerie et charges
##   ralenties (vitesse mesurée sur le champ) ; vent : tir vent arrière plus long que vent de face ;
## - brouillard : un ennemi lointain est invisible (ni ciblé, ni visé par les archers, IA comprise),
##   estompé à mi-distance, net de près ;
## - météo de campagne : déterministe, jamais de brouillard sous la pluie, transmise à la bataille ;
## - usure au contact (la fatigue s'accélère en mêlée), relève (les positions s'échangent, le relevé
##   récupère endurance et moral), repli simple, relève de l'IA (normal oui, facile non), touche E.
## Code de sortie : 0 si tout va bien, 1 sinon.

const STEP := 0.05

var fails: Array[String] = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)


func _process(_delta: float) -> bool:
	rain_and_mud()
	wind()
	fog()
	campaign_weather()
	contact_wear()
	relief_swap()
	fall_back()
	ai_relief()
	relief_key()
	if fails.is_empty():
		print("WEATHER TEST OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : " + f)
		print("WEATHER TEST ÉCHOUÉ")
		quit(1)
	return true


## Champ plat, sans bois ni arbres, bataille lancée, IA ennemie endormie.
func new_sim() -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = 7
	sim.generate_world("plain")
	sim.forests.clear()
	sim.trees.clear()
	sim.objective.setup(sim)
	sim.state = BattleSim.State.BATTLE
	sim.ai.timer = 1.0e9
	return sim


func run(sim: BattleSim, seconds: float) -> void:
	for i in int(seconds / STEP):
		sim.step(STEP)


## Comme run, mais personne ne meurt ni ne flanche : la mêlée dure (mesures d'usure et de relève).
## Le moral n'est rendu qu'aux régiments au contact (celui d'un régiment au repos remonte seul).
func run_melee(sim: BattleSim, seconds: float) -> void:
	for i in int(seconds / STEP):
		for r in sim.regiments:
			if r.engaged:
				r.morale = r.max_morale
			for so in r.soldiers:
				so.hp = so.max_hp
		sim.step(STEP)


# ---------------------------------------------------------------- Pluie et boue

func rain_and_mud() -> void:
	var sim := new_sim()
	var bow := sim.add_regiment(BattleSim.PLAYER, "archer", Vector2(1000, 1600), Vector2.UP)
	var xbow := sim.add_regiment(BattleSim.PLAYER, "crossbow", Vector2(1600, 1600), Vector2.UP)
	var to_b := bow.center + Vector2(0, -100)
	var to_x := xbow.center + Vector2(0, -100)
	var bow_dry := sim.shot_range(bow, to_b)
	var xbow_dry := sim.shot_range(xbow, to_x)
	BattleWeather.apply(sim, {"rain": true})
	var bow_k := sim.shot_range(bow, to_b) / bow_dry
	var xbow_k := sim.shot_range(xbow, to_x) / xbow_dry
	check(bow_k < 0.8, "pluie : la portée des arcs ne baisse pas assez (x%.2f)" % bow_k)
	check(xbow_k < 1.0 and xbow_k > bow_k, "pluie : les arbalètes devraient moins souffrir que les arcs (x%.2f / x%.2f)" % [xbow_k, bow_k])
	check(BattleWeather.damage_factor(sim, bow) < BattleWeather.damage_factor(sim, xbow) and BattleWeather.damage_factor(sim, xbow) < 1.0,
		"pluie : dégâts des traits mal réduits")
	check(sim.mud >= 1.0, "pluie de campagne : le sol n'est pas détrempé d'emblée")
	check(BattleWeather.label(sim).contains("Pluie"), "barre du haut : pas de pluie affichée")
	check(not BattleWeather.effects(sim).is_empty(), "pluie : aucun effet affiché")

	# Trait réellement tiré : dégâts plus faibles sous la pluie
	var foe := sim.add_regiment(BattleSim.ENEMY, "spear", Vector2(1000, 1350), Vector2.DOWN)
	var s: Soldier = bow.soldiers[0]
	sim.raining = false
	sim.fire_arrow(s, foe)
	var dry_dmg: float = sim.arrows[-1]["dmg"]
	sim.raining = true
	sim.fire_arrow(s, foe)
	check(float(sim.arrows[-1]["dmg"]) < dry_dmg, "pluie : la flèche tirée frappe aussi fort")

	# Boue : la cavalerie avance nettement moins vite, les fantassins un peu
	var horse := distance_run("cavalry", 0.0)
	var horse_mud := distance_run("cavalry", 1.0)
	var foot := distance_run("spear", 0.0)
	var foot_mud := distance_run("spear", 1.0)
	print("Boue : cavalerie %.0f → %.0f px, piquiers %.0f → %.0f px" % [horse, horse_mud, foot, foot_mud])
	check(horse_mud < horse * 0.8, "boue : la cavalerie n'est pas ralentie")
	check(foot_mud < foot and foot_mud > foot * 0.8, "boue : les fantassins devraient être un peu ralentis")
	check(horse_mud / horse < foot_mud / foot, "boue : la cavalerie devrait souffrir plus que l'infanterie")
	sim.mud = 1.0
	check(BattleWeather.charge_factor(sim) < 0.75, "boue : la charge garde tout son élan")
	# La boue monte sous la pluie en escarmouche, puis sèche
	var sk := new_sim()
	sk.raining = true
	run(sk, 10.0)
	check(sk.mud > 0.1 and sk.mud < 1.0, "escarmouche : la boue ne monte pas progressivement (%.2f)" % sk.mud)
	sk.raining = false
	var m := sk.mud
	run(sk, 5.0)
	check(sk.mud < m, "la boue ne sèche pas")
	sim.clear()
	sk.clear()


## Distance parcourue en 4 s de marche par un régiment de type, dans une boue de niveau mud.
func distance_run(type: String, mud: float) -> float:
	var sim := new_sim()
	sim.mud = mud
	var r := sim.add_regiment(BattleSim.PLAYER, type, Vector2(1600, 1700), Vector2.UP)
	var start := r.center
	r.dest = start + Vector2(0, -800)
	for i in int(4.0 / STEP):
		sim.mud = mud # Pas de séchage pendant la mesure
		sim.step(STEP)
	var d := r.center.distance_to(start)
	sim.clear()
	return d


# ---------------------------------------------------------------- Vent

func wind() -> void:
	var sim := new_sim()
	var bow := sim.add_regiment(BattleSim.PLAYER, "archer", Vector2(1600, 1600), Vector2.UP)
	var calm := sim.shot_range(bow, bow.center + Vector2(0, -100))
	BattleWeather.apply(sim, {"wind": -1.0}) # Souffle vers le nord : dans le dos du joueur
	var down := sim.shot_range(bow, bow.center + Vector2(0, -100))
	var up := sim.shot_range(bow, bow.center + Vector2(0, 100))
	check(down > calm and up < calm, "vent : portées %.0f (vent arrière) / %.0f (calme) / %.0f (vent de face)" % [down, calm, up])
	check(BattleWeather.label(sim).contains("dos"), "vent : la barre n'indique pas le sens du vent")
	sim.clear()


# ---------------------------------------------------------------- Brouillard

func fog() -> void:
	var sim := new_sim()
	BattleWeather.apply(sim, {"fog": true})
	var bow := sim.add_regiment(BattleSim.PLAYER, "archer", Vector2(1600, 1600), Vector2.UP)
	var foe := sim.add_regiment(BattleSim.ENEMY, "spear", Vector2(1600, 1600 - 600), Vector2.DOWN)
	var foe_archers := sim.add_regiment(BattleSim.ENEMY, "archer", Vector2(1900, 1600 - 600), Vector2.DOWN)
	bow.hold_position = true
	foe.hold_position = true
	foe_archers.hold_position = true
	sim.step(STEP)
	check(foe.fogged and sim.unseen(foe), "brouillard : un ennemi à 600 pas reste visible")
	check(bow.fogged, "brouillard : l'ennemi voit vos archers à 600 pas")
	check(sim.regiment_at(foe.soldiers[0].pos, BattleSim.ENEMY) == null, "brouillard : on peut cliquer un ennemi invisible")
	check(not Minimap.shows(foe), "brouillard : l'ennemi invisible paraît sur la mini-carte")
	# Sans brouillard, le même ennemi (à 340 pas : portée des arcs) serait visé ; dans la brume, non
	place(foe, Vector2(1600, 1600 - 330))
	place(foe_archers, Vector2(1900, 1600 - 330))
	run(sim, 0.5)
	check(foe.fog_alpha > 0.0 and foe.fog_alpha < 1.0, "brouillard : à 330 pas l'ennemi devrait être estompé (%.2f)" % foe.fog_alpha)
	sim.fog = false
	run(sim, 0.5)
	check(bow.fire_target != null, "temps clair : les archers ne tirent pas à 330 pas (témoin)")
	sim.fog = true
	place(foe, Vector2(1600, 1600 - 600))
	place(foe_archers, Vector2(1900, 1600 - 600))
	run(sim, 0.5)
	check(bow.fire_target == null, "brouillard : les archers tirent sur un ennemi invisible")
	check(foe_archers.fire_target == null, "brouillard : les archers ennemis tirent sur ce qu'ils ne voient pas")
	# L'IA ne voit pas non plus : ses archers ne prennent pas de cible hors de vue... mais avancent
	sim.ai.timer = 0.0
	sim.ai.advance = true
	run(sim, 2.0)
	check(foe_archers.fire_target == null or not sim.unseen(foe_archers.fire_target), "brouillard : l'IA vise un régiment invisible")
	place(foe, Vector2(1600, 1600 - 150))
	sim.ai.timer = 1.0e9
	sim.step(STEP)
	check(not foe.fogged and is_equal_approx(foe.fog_alpha, 1.0), "brouillard : un ennemi à 150 pas n'est pas net")
	check(BattleWeather.label(sim).contains("Brouillard"), "barre du haut : pas de brouillard affiché")
	sim.clear()


## Pose un régiment en at (soldats compris), sans le faire marcher.
func place(r: Regiment, at: Vector2) -> void:
	r.dest = at
	var alive := r.alive_soldiers()
	for i in alive.size():
		alive[i].pos = r.slot_position(i, alive.size())
	r.update_center()


# ---------------------------------------------------------------- Campagne

func campaign_weather() -> void:
	var w := WorldSim.create(5)
	var a := w.battle_weather(3, "river", 2)
	var b := w.battle_weather(3, "river", 2)
	check(a == b, "météo de campagne non déterministe")
	var fog_days := 0
	for day in range(1, 121):
		w.raining = day % 3 == 0
		var d := w.battle_weather(day, "river", 1)
		if d["rain"] and d["fog"]:
			fails.append("brouillard sous la pluie (jour %d)" % day)
			break
		if d["fog"]:
			fog_days += 1
	check(fog_days > 5, "presque jamais de brouillard au bord de l'eau (%d jours sur 120)" % fog_days)
	check(w.weather_text(1) != "", "texte de météo vide")
	# Transmise à la bataille de campagne
	var sim := new_sim()
	BattleWeather.apply(sim, {"rain": false, "fog": true, "wind": 0.7})
	check(sim.fog and sim.wind.y > 0.5 and not sim.raining, "météo de campagne mal appliquée")
	check(BattleWeather.briefing(sim).contains("brouillard"), "pas de message de météo en début de bataille")
	sim.clear()


# ---------------------------------------------------------------- Usure et relève

## Deux régiments au contact : renvoie [sim, joueur, ennemi].
func melee_pair() -> Array:
	var sim := new_sim()
	var mine := sim.add_regiment(BattleSim.PLAYER, "men_at_arms", Vector2(1600, 1300), Vector2.UP)
	var foe := sim.add_regiment(BattleSim.ENEMY, "foot_knight", Vector2(1600, 1255), Vector2.DOWN)
	mine.target = foe
	foe.target = mine
	return [sim, mine, foe]


func contact_wear() -> void:
	var p := melee_pair()
	var sim: BattleSim = p[0]
	var mine: Regiment = p[1]
	run_melee(sim, 5.0)
	check(mine.engaged, "usure : les régiments ne sont pas au contact")
	var s0 := mine.stamina
	run_melee(sim, 10.0)
	var early := s0 - mine.stamina
	run_melee(sim, 20.0)
	var s1 := mine.stamina
	run_melee(sim, 10.0)
	var late := s1 - mine.stamina
	print("Usure : %.3f d'endurance perdue en 10 s au début, %.3f après 35 s de mêlée (x%.2f)" % [early, late, sim.wear_factor(mine)])
	check(late > early * 1.4, "usure : la fatigue ne s'accélère pas en mêlée longue")
	sim.clear()


func relief_swap() -> void:
	var p := melee_pair()
	var sim: BattleSim = p[0]
	var mine: Regiment = p[1]
	var foe: Regiment = p[2]
	var fresh := sim.add_regiment(BattleSim.PLAYER, "spear", Vector2(1600, 1560), Vector2.UP)
	fresh.hold_position = true
	run_melee(sim, 30.0)
	check(mine.engaged, "relève : pas de mêlée à relever")
	var front := mine.center
	var tired_stamina := mine.stamina
	var tired_morale := mine.morale
	check(sim.relieve(mine, fresh), "relève refusée")
	check(fresh.target == foe, "relève : le régiment frais ne reprend pas l'ennemi du relevé")
	check(mine.relief > 0.0 and mine.target == null, "relève : le relevé ne décroche pas")
	run_melee(sim, 3.0)
	var still_fighting := 0
	for s in mine.soldiers:
		if s.alive and s.foe != null:
			still_fighting += 1
	check(still_fighting == 0, "relève : %d soldats du relevé restent au contact" % still_fighting)
	run_melee(sim, 12.0)
	var d_fresh := fresh.center.distance_to(foe.center)
	var d_tired := mine.center.distance_to(foe.center)
	print("Relève : frais à %.0f px de l'ennemi, relevé à %.0f px (front de départ à %.0f px)" % [d_fresh, d_tired, front.distance_to(foe.center)])
	check(d_fresh < d_tired, "relève : les positions ne sont pas échangées")
	check(fresh.engaged or d_fresh < 60.0, "relève : le régiment frais n'a pas pris le contact")
	check(d_tired > 150.0, "relève : le relevé n'a pas reculé derrière la ligne")
	run_melee(sim, 10.0)
	check(mine.stamina > tired_stamina + 0.1, "relève : le relevé ne récupère pas d'endurance (%.2f → %.2f)" % [tired_stamina, mine.stamina])
	check(mine.morale > tired_morale or mine.morale >= mine.max_morale, "relève : le relevé ne récupère pas de moral")
	sim.clear()


func fall_back() -> void:
	var p := melee_pair()
	var sim: BattleSim = p[0]
	var mine: Regiment = p[1]
	var foe: Regiment = p[2]
	run_melee(sim, 20.0)
	var d0 := mine.center.distance_to(foe.center)
	mine.stamina = 0.3 # Usé par la mêlée
	mine.morale = mine.max_morale * 0.5
	sim.fall_back(mine)
	check(mine.dest.distance_to(foe.center) > d0 + 150.0, "repli : le point de repli n'est pas à l'écart de l'ennemi")
	foe.target = null # L'ennemi ne poursuit pas
	foe.hold_position = true
	foe.dest = foe.center
	run_melee(sim, 12.0)
	check(mine.center.distance_to(foe.center) > d0 + 150.0, "repli : le régiment n'a pas reculé")
	var st := mine.stamina
	var mo := mine.morale
	run_melee(sim, 8.0)
	print("Repli : endurance %.2f → %.2f, moral %.0f → %.0f, à %.0f px, au contact : %s" % [st, mine.stamina, mo, mine.morale, mine.center.distance_to(foe.center), mine.engaged])
	check(mine.stamina > st and (mine.morale > mo or mine.morale >= mine.max_morale), "repli : pas de récupération hors combat")
	sim.clear()


func ai_relief() -> void:
	for level in ["normal", "easy"]:
		var sim := new_sim()
		sim.ai.configure(level)
		var tired := sim.add_regiment(BattleSim.ENEMY, "spear", Vector2(1600, 900), Vector2.DOWN)
		var fresh := sim.add_regiment(BattleSim.ENEMY, "men_at_arms", Vector2(1600, 650), Vector2.DOWN)
		var player := sim.add_regiment(BattleSim.PLAYER, "men_at_arms", Vector2(1600, 945), Vector2.UP)
		player.target = tired
		tired.target = player
		run(sim, 3.0)
		tired.stamina = 0.1
		tired.engaged = true
		var mine: Array[Regiment] = [tired, fresh]
		var done: bool = sim.ai.use_relief and sim.ai.plan_relief(sim, mine)
		if level == "normal":
			check(done and fresh.target == player and tired.relief > 0.0, "IA (normal) : le régiment épuisé n'est pas relevé")
		else:
			check(not done, "IA (facile) : l'IA ne devrait pas relever")
		sim.clear()


## Touche E en bataille : sélection + régiment ami survolé (order_relief) ; sans désignation, repli.
func relief_key() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var b := scene.instantiate()
	b.set("seed_override", 11)
	b.set("terrain_override", "plain")
	root.add_child(b)
	b.start_battle()
	var mine: Array[Regiment] = b.sim.player_regiments()
	var a: Regiment = mine[0]
	var c: Regiment = mine[1]
	for r in b.sim.regiments:
		r.selected = false
	a.selected = true
	b.orders.order_relief(c)
	check(c.dest.distance_to(a.dest) > 100.0 and a.relief > 0.0, "touche E : la relève désignée n'a pas lieu")
	check(c.selected and not a.selected, "touche E : la sélection ne passe pas au régiment qui relève")
	for r in b.sim.regiments:
		r.selected = false
	c.selected = true
	b.orders.order_relief(null)
	check(c.relief > 0.0, "touche E : sans désignation, le régiment ne se replie pas")
	check(GameOptions.key_label("relief") != "", "touche de relève absente des Options")
	check(" ".join(Hud.help_lines()).contains("relever"), "aide sans la relève")
	check(b.hud.shown_help_lines().size() == Hud.help_lines().size() + BattleWeather.effects(b.sim).size(), "aide : effets de la météo absents")
	root.remove_child(b)
	b.free()
