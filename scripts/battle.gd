class_name Battle
extends Node2D
## Nœud de la bataille (scenes/main.tscn) : il assemble et orchestre les morceaux.
##   sim      (battle_sim.gd)      simulation sans rendu : monde, armées, combat, moral, flèches, fin ;
##   renderer (battle_renderer.gd) rendu pixel art (nœud enfant, un seul _draw) ;
##   orders   (battle_orders.gd)   saisie et ordres du joueur (souris, clavier, groupes, ligne de front) ;
##   camera   (battle_camera.gd)   défilement, zoom, bornes, secousse ;
##   hud, audio, menu pause et bilan de fin de bataille.
## Il gère aussi le temps (pause, vitesse, ralenti de fin), la campagne (contrat, pertes reportées)
## et le bilan. tutorial.gd en hérite (generate_world, spawn_armies, _unhandled_input).
##
## Les variables et fonctions de la section « Raccourcis » renvoient vers sim, orders ou camera :
## elles gardent l'interface d'avant le découpage (HUD, menus, tutoriel, tests).

const WORLD_SIZE := BattleSim.WORLD_SIZE
const PLAYER := BattleSim.PLAYER
const ENEMY := BattleSim.ENEMY
const CELL := BattleSim.CELL
const DEPLOY_Y := BattleSim.DEPLOY_Y
const ROAD_HALF := BattleSim.ROAD_HALF
const HIT_FRONT := BattleSim.HIT_FRONT
const HIT_FLANK := BattleSim.HIT_FLANK
const HIT_REAR := BattleSim.HIT_REAR
const MAX_DUST := BattleSim.MAX_DUST
const PX := BattleRenderer.PX
const SIM_STEP := 0.05 ## Pas de simulation maximal (secondes simulées)
const SLOWMO_SCALE := 0.3 ## Vitesse du ralenti de fin de bataille
const SLOWMO_HOLD := 2.0 ## Durée du ralenti à pleine intensité (secondes réelles)
const SLOWMO_FADE := 1.5 ## Retour progressif à la vitesse normale (secondes réelles)
const REPORT_DELAY := 1.5 ## Le bilan s'affiche après ce temps réel de ralenti (secondes)
const MESSAGE_LIFE := 5.0 ## Durée d'affichage d'un message (secondes)
const MAX_MESSAGES := 5

const State := BattleSim.State

var sim := BattleSim.new()
var orders: BattleOrders = null
var renderer: BattleRenderer = null
var camera: BattleCamera
var hud: Hud
var audio: BattleAudio

var paused := false
var show_help := false ## Aide F1 dépliée (état mémorisé dans GameOptions.show_help)
var messages: Array = [] ## Messages du HUD : [texte, temps restant]
var game_speed := 1.0 ## Vitesse de la simulation (options, touche V)
var slowmo := -1.0 ## Temps réel écoulé depuis le début du ralenti de fin (-1 = pas de ralenti)

var seed_override := 0 ## Graine fixe pour les tests (0 = aléatoire)
var terrain_override := "" ## Terrain imposé (tests) ; vide = au hasard ou d'après le contrat
var campaign: CampaignState = null ## Bataille d'un contrat de campagne (null = escarmouche)
var campaign_report := "" ## Compte rendu de fin de bataille en campagne (texte du journal)
var campaign_result: Dictionary = {} ## Bilan structuré renvoyé par CampaignState.finish_battle
var end_report: Dictionary = {} ## Bilan de fin de bataille (build_end_report), vide pendant la bataille
var report_panel: BattleReport = null ## Panneau du bilan (caché pendant REPORT_DELAY)
var report_clock := 0.0 ## Temps réel écoulé depuis la fin de la bataille
var is_tutorial := false ## Bataille du tutoriel (bilan simplifié, Entrée recommence)
var pause_menu: PauseMenu = null ## Menu pause (Échap), créé à la première ouverture
var stats_watch: Achievements.Watch = null ## Statistiques et succès de la bataille


# ---------------------------------------------------------------- Mise en place

func _init() -> void:
	orders = BattleOrders.new(self)
	sim.difficulty = "" # Vide = celle de la campagne ou des options (fixée dans _ready)


func _ready() -> void:
	GameOptions.ensure_loaded()
	game_speed = GameOptions.speed
	show_help = GameOptions.show_help
	if CampaignState.current != null and CampaignState.current.in_battle():
		campaign = CampaignState.current
	if seed_override != 0:
		sim.rng.seed = seed_override
	elif campaign != null:
		sim.rng.seed = int(campaign.pending["seed"])
	else:
		sim.rng.randomize()
	if sim.difficulty == "":
		sim.difficulty = campaign.difficulty if campaign != null else GameOptions.difficulty
	sim.difficulty = Difficulty.sanitize(sim.difficulty)
	sim.ai.configure(sim.difficulty)
	sim.message_posted.connect(add_message)
	sim.sound_played.connect(_on_sound)
	sim.cries_played.connect(_on_cries)
	sim.impact.connect(_on_impact)
	sim.ended.connect(_on_battle_ended)
	stats_watch = Achievements.watch(self) # Après _on_battle_ended : lit le bilan de fin

	renderer = BattleRenderer.new(self)
	add_child(renderer)
	generate_world()
	if campaign != null:
		spawn_army(PLAYER, campaign.battle_army())
		spawn_army(ENEMY, campaign.pending["enemy"])
	else:
		spawn_armies()
	if sim.terrain.kind == "siege":
		sim.setup_siege()
	Captain.enter_battle(self) # Capitaine sur le champ (ni au tutoriel, ni blessé)

	camera = BattleCamera.new()
	add_child(camera)
	camera.make_current()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.battle = self
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hud)

	audio = BattleAudio.new()
	audio.battle = self
	add_child(audio)

	if campaign != null:
		add_message("Contrat : %s" % campaign.pending["title"])
	if sim.terrain.kind != "plain":
		add_message("Terrain : %s. %s" % [sim.terrain.display_name(), sim.terrain.hint()])
	add_message("Placez vos troupes, puis appuyez sur Espace pour lancer la bataille.")


func _exit_tree() -> void:
	if sim.captain != null:
		sim.captain.leave_field()
	sim.clear()
	orders.groups.clear()


## Monde (simulation) puis sol dessiné : l'ordre des tirages de rng compte.
## Le tutoriel remplace cette fonction.
func generate_world() -> void:
	sim.generate_world(choose_terrain())
	if not build_tiled_ground():
		build_procedural_ground()
	renderer.terrain_tex = sim.terrain.build_overlay(sim.rng)


## Terrain de la bataille : imposé par les tests, d'après la ville du contrat, sinon vide
## (tiré au sort par la simulation, après la graine de la route).
func choose_terrain() -> String:
	if terrain_override != "":
		return terrain_override
	if campaign != null:
		return Terrain.for_contract(int(campaign.pending.get("town", -1)), int(campaign.pending.get("difficulty", 1)), CampaignState.TOWNS)
	return ""


## Armées de l'escarmouche (le tutoriel remplace cette fonction).
func spawn_armies() -> void:
	sim.spawn_default_armies()


func start_battle() -> void:
	sim.start()


# ---------------------------------------------------------------- Boucle

func _process(delta: float) -> void:
	if menu_open():
		# Menu pause : rien ne bouge, ni la simulation ni la caméra
		renderer.queue_redraw()
		hud.queue_redraw()
		return
	camera.update_view(delta)
	if not paused:
		# Vitesse x1,5 / x2 (options, touche V) et ralenti de fin : plusieurs pas d'au plus SIM_STEP
		var tf := time_factor(delta)
		if report_panel != null and report_panel.visible:
			tf = SLOWMO_SCALE # Le champ de bataille reste au ralenti derrière le bilan
		var dt := minf(delta, SIM_STEP) * tf * game_speed
		var steps := maxi(1, ceili(dt / SIM_STEP - 0.001))
		for i in steps:
			simulate(dt / steps)
	if report_panel != null and not report_panel.visible:
		report_clock += delta
		if report_clock >= REPORT_DELAY:
			show_report()
	for m in messages:
		m[1] -= delta
	messages = messages.filter(func(m): return m[1] > 0.0)
	renderer.update_effects(delta)
	renderer.queue_redraw()
	hud.queue_redraw()


## Ralenti de fin de bataille : facteur appliqué au temps simulé (1 = vitesse normale).
## real_delta : temps réel écoulé depuis l'image précédente.
func time_factor(real_delta: float) -> float:
	if slowmo < 0.0:
		return 1.0
	slowmo += real_delta
	if slowmo < SLOWMO_HOLD:
		return SLOWMO_SCALE
	var k := (slowmo - SLOWMO_HOLD) / SLOWMO_FADE
	if k >= 1.0:
		slowmo = -1.0
		return 1.0
	return lerpf(SLOWMO_SCALE, 1.0, k * k)


## Un pas de simulation, puis le bruit de galop qui en dépend.
func simulate(dt: float) -> void:
	sim.step(dt)
	update_gallop()


## Bruit de galop : proportionnel au nombre de cavaliers visibles qui avancent, près de la caméra.
func update_gallop() -> void:
	if audio == null:
		return
	var n := 0.0
	for r in sim.regiments:
		if not r.stats["mounted"] or r.is_dead() or (r.team == ENEMY and r.hidden):
			continue
		var moving := 0
		for s in r.soldiers:
			if s.alive and s.moving:
				moving += 1
		if moving > 0:
			n += moving * pow(10.0, audio.attenuation(r.center) / 20.0)
	audio.gallop_level = clampf(n / 12.0, 0.0, 1.0)


func _on_sound(sound: String, at: Vector2) -> void:
	if audio != null:
		audio.play(sound, at)


func _on_cries(at: Vector2, count: int) -> void:
	if audio != null:
		audio.play_cries(at, count)
	if hud != null:
		hud.caption("rout") # Sous-titre (option d'accessibilité)


func _on_impact(at: Vector2, amount: float) -> void:
	if camera != null:
		camera.add_shake(at, amount)
	if hud != null and amount >= 0.05:
		hud.caption("cavalry")


func add_message(text: String) -> void:
	if hud != null and text.begins_with("Embuscade"):
		hud.caption("ambush")
	messages.append([text, MESSAGE_LIFE])
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()


func add_marker(p: Vector2, col: Color) -> void:
	if renderer != null:
		renderer.add_marker(p, col)


# ---------------------------------------------------------------- Fin de bataille

## La simulation vient de finir (victoire, défaite ou retraite) : ralenti, campagne, bilan.
func _on_battle_ended() -> void:
	slowmo = 0.0 # Ralenti de quelques secondes sur la fin de la bataille
	if campaign != null:
		finish_campaign()
	open_report()


## Touche R : un premier appui demande confirmation, un second (dans les 3 s) sonne la retraite.
func request_retreat() -> void:
	orders.request_retreat()


## Retraite ordonnée (touche R confirmée ou menu pause) : voir BattleSim.order_retreat.
func order_retreat() -> void:
	sim.order_retreat()


## Reporte les pertes sur la compagnie : les hommes debout et ceux qui ont fui survivent.
func finish_campaign() -> void:
	var tally := sim.company_tally(campaign.battle_army().size())
	campaign_result = campaign.finish_battle(sim.state == State.VICTORY, tally["survivors"], tally["kills"], sim.retreated)
	campaign_report = str(campaign_result["text"])
	campaign.save()


## Bilan de fin de bataille : issue, contrat, durée, une ligne par régiment du joueur
## (effectif avant → après, morts, fuyards revenus, blessés relevés, ennemis tués, expérience,
## promotion) et les totaux des deux camps ; « campaign » reprend le bilan de finish_battle.
func build_end_report() -> Dictionary:
	var outcome := "victory" if sim.state == State.VICTORY else ("retreat" if sim.retreated else "defeat")
	var title := "Escarmouche"
	if is_tutorial:
		title = "Tutoriel"
	elif campaign != null:
		title = str(campaign_result.get("title", "Contrat"))
		if bool(campaign_result.get("ambush", false)):
			title = "Embuscade sur la route"
	var camp_rows: Array = campaign_result.get("regiments", [])
	var cas := sim.casualties()
	var rows: Array[Dictionary] = cas["rows"]
	var t: Dictionary = cas["totals"]
	for row in rows:
		var ci: int = row["company_index"]
		row.erase("company_index")
		if ci >= 0 and ci < camp_rows.size():
			var c: Dictionary = camp_rows[ci]
			row["healed"] = int(c["healed"])
			row["dead"] = int(row["dead"]) - int(c["healed"])
			row["after"] = int(c["after"])
			row["xp"] = float(c["xp_after"]) - float(c["xp_before"])
			row["rank_after"] = int(c["rank_after"])
			row["promoted"] = bool(c["promoted"])
		t["player_before"] += row["before"]
		t["player_after"] += row["after"]
		t["player_dead"] += row["dead"]
		t["player_fled"] += row["fled"]
		t["player_healed"] += row["healed"]
	return {"outcome": outcome, "title": title, "terrain": sim.terrain.display_name(), "duration": sim.battle_time,
		"tutorial": is_tutorial, "rows": rows, "totals": t, "campaign": campaign_result}


## Fin de bataille : calcule le bilan et prépare son panneau (affiché après REPORT_DELAY).
func open_report() -> void:
	end_report = build_end_report()
	if hud == null:
		return
	report_panel = BattleReport.new()
	report_panel.setup(end_report, self)
	report_panel.visible = false
	report_clock = 0.0
	var layer := CanvasLayer.new()
	layer.layer = 5 # Au-dessus du HUD et du panneau du tutoriel
	add_child(layer)
	layer.add_child(report_panel)


func show_report() -> void:
	if report_panel == null or report_panel.visible:
		return
	report_panel.visible = true
	report_panel.modulate.a = 0.0
	report_panel.create_tween().tween_property(report_panel, "modulate:a", 1.0, 0.35)


## Entrée ou bouton principal du bilan : carte de campagne, sinon on rejoue.
func continue_after_battle() -> void:
	if sim.state != State.VICTORY and sim.state != State.DEFEAT:
		return
	if campaign != null:
		get_tree().change_scene_to_file("res://scenes/campaign.tscn")
	else:
		get_tree().reload_current_scene()


## Échap : retour au menu principal (sauf contrat de campagne, qui se joue jusqu'au bout).
func back_to_menu() -> void:
	if campaign == null:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


# ---------------------------------------------------------------- Saisie et menu pause

func menu_open() -> bool:
	return pause_menu != null and pause_menu.is_open()


## Échap pendant le déploiement ou la bataille : ouvre le menu pause (la simulation s'arrête).
func open_pause_menu() -> void:
	orders.cancel_gestures()
	if pause_menu == null:
		var layer := CanvasLayer.new()
		layer.layer = 10 # Au-dessus du HUD et du panneau du tutoriel
		add_child(layer)
		pause_menu = PauseMenu.new()
		pause_menu.battle = self
		layer.add_child(pause_menu)
	pause_menu.open()


func _unhandled_input(event: InputEvent) -> void:
	orders.handle_input(event)


## Position de la souris dans le monde pour un évènement donné.
func event_world_pos(event: InputEventMouse) -> Vector2:
	return get_canvas_transform().affine_inverse() * event.position


# ---------------------------------------------------------------- Raccourcis (sim, orders, camera, renderer)

var state: BattleSim.State:
	get: return sim.state
	set(v): sim.state = v
var raining: bool:
	get: return sim.raining
	set(v): sim.raining = v
var battle_time: float:
	get: return sim.battle_time
	set(v): sim.battle_time = v
var difficulty: String: ## Difficulté imposée (tests) avant _ready ; vide = campagne ou options
	get: return sim.difficulty
	set(v): sim.difficulty = v
var regiments: Array[Regiment]:
	get: return sim.regiments
	set(v): sim.regiments = v
var soldiers: Array:
	get: return sim.soldiers
	set(v): sim.soldiers = v
var arrows: Array:
	get: return sim.arrows
	set(v): sim.arrows = v
var corpses: Array:
	get: return sim.corpses
	set(v): sim.corpses = v
var forests: Array:
	get: return sim.forests
	set(v): sim.forests = v
var trees: Array:
	get: return sim.trees
	set(v): sim.trees = v
var dust: Array:
	get: return sim.dust
	set(v): sim.dust = v
var grid: Dictionary:
	get: return sim.grid
var initial_strength: Array:
	get: return sim.initial_strength
var rng: RandomNumberGenerator:
	get: return sim.rng
var road_noise: FastNoiseLite:
	get: return sim.road_noise
var terrain: Terrain:
	get: return sim.terrain
var ai: EnemyAI:
	get: return sim.ai
var retreated: bool:
	get: return sim.retreated
var retreat_caught: int:
	get: return sim.retreat_caught
var groups: Dictionary:
	get: return orders.groups
var shake: float:
	get: return camera.shake if camera != null else 0.0
var sprites: SpriteBank:
	get: return renderer.sprites if renderer != null else null


func build_tiled_ground() -> bool:
	return renderer.build_tiled_ground(sim.rng)


func build_procedural_ground() -> void:
	renderer.build_procedural_ground(sim.rng)


func add_regiment(team: int, type: String, at: Vector2, facing: Vector2, men := -1) -> Regiment:
	return sim.add_regiment(team, type, at, facing, men)


func spawn_army(team: int, list: Array) -> void:
	sim.spawn_army(team, list)


func deploy_top() -> float:
	return sim.deploy_top()


func road_y(x: float) -> float:
	return sim.road_y(x)


func on_road(p: Vector2, half: float) -> bool:
	return sim.on_road(p, half)


func is_in_forest(p: Vector2) -> bool:
	return sim.is_in_forest(p)


func rebuild_grid() -> void:
	sim.rebuild_grid()


func soldiers_near(p: Vector2, radius: float) -> Array:
	return sim.soldiers_near(p, radius)


func move_towards(s: Soldier, goal: Vector2, speed: float, dt: float) -> void:
	sim.move_towards(s, goal, speed, dt)


func hit_side(attacker_pos: Vector2, victim_pos: Vector2, br: Regiment) -> int:
	return sim.hit_side(attacker_pos, victim_pos, br)


func arrow_impact(a: Dictionary) -> void:
	sim.arrow_impact(a)


func nearest_enemy_regiment(r: Regiment, max_dist: float, visible_only: bool) -> Regiment:
	return sim.nearest_enemy_regiment(r, max_dist, visible_only)


func team_strength(team: int) -> int:
	return sim.team_strength(team)


func player_regiments() -> Array[Regiment]:
	return sim.player_regiments()


## Tous les régiments du joueur, numérotation fixe (morts et fuyards compris) : voir BattleOrders.roster.
func player_roster() -> Array[Regiment]:
	return orders.roster()


func selected_regiments() -> Array[Regiment]:
	return sim.selected_regiments()


func issue_order(wp: Vector2, run := false) -> void:
	orders.issue_order(wp, run)


func issue_line_order(a: Vector2, b: Vector2, run := false) -> void:
	orders.issue_line_order(a, b, run)


func line_layout(sel: Array[Regiment], a: Vector2, b: Vector2) -> Array[Dictionary]:
	return orders.line_layout(sel, a, b)


func is_line_drag(a: Vector2, b: Vector2) -> bool:
	return orders.is_line_drag(a, b)


func group_label(r: Regiment) -> String:
	return orders.group_label(r)


func clamp_camera() -> void:
	camera.clamp_to_world()
