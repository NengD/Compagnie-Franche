extends Node2D
## Gère la bataille : terrain, armées, simulation, ordres du joueur et rendu pixel art.

const WORLD_SIZE := Vector2(3200, 2000)
const PLAYER := 0
const ENEMY := 1
const CELL := 32.0
const TEAM_COLORS := [Color(0.22, 0.38, 0.85), Color(0.78, 0.16, 0.14)]
const TEAM_DARK := [Color(0.12, 0.18, 0.42), Color(0.42, 0.08, 0.07)]
const SKIN := Color(0.93, 0.76, 0.6)
const STEEL := Color(0.72, 0.74, 0.78)
const WOOD := Color(0.48, 0.32, 0.17)
const HORSE := Color(0.42, 0.27, 0.15)
const HORSE_DARK := Color(0.28, 0.17, 0.09)
const DEPLOY_Y := 1400.0 ## Limite haute de la zone de déploiement du joueur
const PX := 2.0 ## Taille d'un « pixel » des dessins en code (repli quand un sprite manque)
const ROAD_HALF := 18.0 ## Demi-largeur de la route
const HIT_FRONT := 0
const HIT_FLANK := 1
const HIT_REAR := 2
const LINE_DRAG_MIN_PX := 12.0 ## En dessous, un clic droit glissé reste un simple clic
const LINE_GAP := 20.0 ## Espace entre deux régiments sur une ligne

enum State { DEPLOY, BATTLE, VICTORY, DEFEAT }

var state: State = State.DEPLOY
var paused := false
var raining := false
var show_help := true
var battle_time := 0.0

var regiments: Array[Regiment] = []
var soldiers: Array = []
var arrows: Array = []
var corpses: Array = []
var forests: Array = []
var trees: Array = []
var markers: Array = []
var messages: Array = []
var grid := {}
var initial_strength := [0, 0]

var camera: Camera2D
var hud: Hud
var ai := EnemyAI.new()
var ground_tex: ImageTexture
var ground_scale := 1.0 ## Taille d'un pixel de ground_tex dans le monde
var sprites := SpriteBank.new()
var audio: BattleAudio
var road_noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

var dragging := false
var drag_start := Vector2.ZERO
var drag_now := Vector2.ZERO
var panning := false
var line_double := false ## Le clic droit en cours est un double clic (ordre de course)
var line_dragging := false ## Clic droit maintenu : tracé d'une ligne de formation
var line_start := Vector2.ZERO
var line_now := Vector2.ZERO
var cleanup_timer := 0.0
var seed_override := 0 ## Graine fixe pour les tests (0 = aléatoire)
var campaign: CampaignState = null ## Bataille d'un contrat de campagne (null = escarmouche)
var campaign_report := "" ## Compte rendu de fin de bataille en campagne


# ---------------------------------------------------------------- Mise en place

func _ready() -> void:
	if CampaignState.current != null and CampaignState.current.in_battle():
		campaign = CampaignState.current
	if seed_override != 0:
		rng.seed = seed_override
	elif campaign != null:
		rng.seed = int(campaign.pending["seed"])
	else:
		rng.randomize()
	generate_world()
	if campaign != null:
		spawn_army(PLAYER, campaign.battle_army())
		spawn_army(ENEMY, campaign.pending["enemy"])
	else:
		spawn_armies()

	camera = Camera2D.new()
	camera.zoom = Vector2(1, 1)
	camera.position = Vector2(WORLD_SIZE.x * 0.5, 1560)
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
	add_message("Placez vos troupes, puis appuyez sur Espace pour lancer la bataille.")


func _exit_tree() -> void:
	# Régiments et soldats se référencent mutuellement (RefCounted) :
	# on casse les cycles pour éviter les fuites mémoire à la fermeture.
	for r in regiments:
		for s in r.soldiers:
			s.regiment = null
			s.foe = null
		r.soldiers.clear()
		r.target = null
		r.fire_target = null
	regiments.clear()
	soldiers.clear()
	grid.clear()


func generate_world() -> void:
	# Forêts (pour les embuscades)
	for i in 6:
		var c := Vector2(rng.randf_range(300, WORLD_SIZE.x - 300), rng.randf_range(560, WORLD_SIZE.y - 560))
		var r := rng.randf_range(100, 190)
		forests.append([c, r])
		var n := int(r * r / 150.0)
		for j in n:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r
			trees.append(c + Vector2(cos(a), sin(a)) * d)
	# Quelques arbres isolés
	for i in 40:
		var p := Vector2(rng.randf_range(0, WORLD_SIZE.x), rng.randf_range(0, WORLD_SIZE.y))
		if p.y > 460 and p.y < WORLD_SIZE.y - 460 and absf(p.y - road_y(p.x)) > ROAD_HALF + 12.0:
			trees.append(p)
	trees.sort_custom(func(a, b): return a.y < b.y)

	road_noise.seed = rng.randi()
	road_noise.frequency = 0.0075
	if not build_tiled_ground():
		build_procedural_ground()


## Hauteur de la route qui traverse le champ de bataille.
func road_y(x: float) -> float:
	return WORLD_SIZE.y * 0.5 + sin(x * 0.003125) * 112.0 + road_noise.get_noise_1d(x) * 64.0


## Sol en tuiles MiniWorld (16 px). Renvoie false si les tuiles ne sont pas disponibles.
func build_tiled_ground() -> bool:
	var grass := tile_images("res://assets/sprites/ground/TexturedGrass.png", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	var plain := tile_images("res://assets/sprites/ground/Grass.png", [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	if grass.size() < 6 or plain.size() < 3:
		return false
	var sand: Image = plain[2]
	var dark: Array[Image] = []
	for t in grass:
		var d: Image = t.duplicate()
		d.adjust_bcs(0.72, 1.0, 0.95)
		dark.append(d)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.004
	var tw := int(WORLD_SIZE.x) / 16
	var th := int(WORLD_SIZE.y) / 16
	var img := Image.create_empty(tw * 16, th * 16, false, Image.FORMAT_RGBA8)
	var r16 := Rect2i(0, 0, 16, 16)
	for ty in th:
		for tx in tw:
			var c := Vector2(tx * 16 + 8, ty * 16 + 8)
			var t: Image
			if absf(c.y - road_y(c.x)) < ROAD_HALF:
				t = sand
			elif is_in_forest(c):
				t = dark[rng.randi() % dark.size()]
			else:
				# Surtout de l'herbe rase, des touffes plus nombreuses par endroits
				var tufts := 0.25 + noise.get_noise_2d(c.x, c.y) * 0.35
				t = grass[rng.randi() % 6] if rng.randf() < tufts else grass[0]
			img.blit_rect(t, r16, Vector2i(tx * 16, ty * 16))
	ground_tex = ImageTexture.create_from_image(img)
	ground_scale = 1.0
	return true


## Découpe des tuiles 16x16 d'une planche (vide si l'image n'est pas lisible).
func tile_images(path: String, cells: Array[Vector2i]) -> Array[Image]:
	var out: Array[Image] = []
	if not ResourceLoader.exists(path):
		return out
	var tex := load(path) as Texture2D
	if tex == null:
		return out
	var full := tex.get_image()
	if full == null or full.is_empty():
		return out # Pas d'accès aux pixels (ex. mode sans affichage) : repli
	if full.is_compressed():
		full.decompress()
	full.convert(Image.FORMAT_RGBA8)
	for c in cells:
		if (c.x + 1) * 16 <= full.get_width() and (c.y + 1) * 16 <= full.get_height():
			out.append(full.get_region(Rect2i(c.x * 16, c.y * 16, 16, 16)))
	return out


## Sol de repli dessiné en code : une petite image agrandie 8x pour l'effet pixel.
func build_procedural_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.03
	ground_scale = 8.0
	var w := int(WORLD_SIZE.x / ground_scale)
	var h := int(WORLD_SIZE.y / ground_scale)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var grass_a := Color(0.38, 0.56, 0.25)
	var grass_b := Color(0.27, 0.44, 0.19)
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := grass_a.lerp(grass_b, n)
			if rng.randf() < 0.07:
				c = c.lightened(0.08)
			var wp := Vector2(x + 0.5, y + 0.5) * ground_scale
			if is_in_forest(wp):
				c = c.darkened(0.3)
			var dy := absf(wp.y - road_y(wp.x))
			if dy < ROAD_HALF:
				c = Color(0.58, 0.47, 0.31).darkened(rng.randf() * 0.08)
			elif dy < ROAD_HALF + ground_scale:
				c = Color(0.46, 0.42, 0.27)
			img.set_pixel(x, y, c)
	ground_tex = ImageTexture.create_from_image(img)


func spawn_armies() -> void:
	var cx := WORLD_SIZE.x * 0.5
	# Armée du joueur (en bas)
	add_regiment(PLAYER, "spear", Vector2(cx - 480, 1600), Vector2.UP)
	add_regiment(PLAYER, "men_at_arms", Vector2(cx - 160, 1600), Vector2.UP)
	add_regiment(PLAYER, "men_at_arms", Vector2(cx + 160, 1600), Vector2.UP)
	add_regiment(PLAYER, "spear", Vector2(cx + 480, 1600), Vector2.UP)
	add_regiment(PLAYER, "archer", Vector2(cx - 320, 1730), Vector2.UP)
	add_regiment(PLAYER, "archer", Vector2(cx + 320, 1730), Vector2.UP)
	add_regiment(PLAYER, "cavalry", Vector2(cx - 840, 1660), Vector2.UP)
	add_regiment(PLAYER, "cavalry", Vector2(cx + 840, 1660), Vector2.UP)
	# Armée ennemie (en haut)
	add_regiment(ENEMY, "spear", Vector2(cx - 600, 400), Vector2.DOWN)
	add_regiment(ENEMY, "men_at_arms", Vector2(cx - 220, 400), Vector2.DOWN)
	add_regiment(ENEMY, "spear", Vector2(cx + 120, 400), Vector2.DOWN)
	add_regiment(ENEMY, "men_at_arms", Vector2(cx + 460, 400), Vector2.DOWN)
	add_regiment(ENEMY, "spear", Vector2(cx + 760, 400), Vector2.DOWN)
	add_regiment(ENEMY, "archer", Vector2(cx - 360, 270), Vector2.DOWN)
	add_regiment(ENEMY, "archer", Vector2(cx + 360, 270), Vector2.DOWN)
	add_regiment(ENEMY, "cavalry", Vector2(cx + 1040, 340), Vector2.DOWN)


## Déploie une armée de campagne (liste de {"type", "men"}) : infanterie devant, archers derrière,
## cavalerie sur les ailes. Les régiments du joueur gardent leur indice dans la liste.
func spawn_army(team: int, list: Array) -> void:
	var cx := WORLD_SIZE.x * 0.5
	var front_y := 1600.0 if team == PLAYER else 400.0
	var back := 130.0 if team == PLAYER else -130.0
	var face := Vector2.UP if team == PLAYER else Vector2.DOWN
	var front: Array[int] = []
	var rear: Array[int] = []
	var wings: Array[int] = []
	for i in list.size():
		match str(list[i]["type"]):
			"archer":
				rear.append(i)
			"cavalry":
				wings.append(i)
			_:
				front.append(i)
	var placed := {}
	for k in front.size():
		placed[front[k]] = Vector2(cx + (k - (front.size() - 1) * 0.5) * 320.0, front_y)
	for k in rear.size():
		placed[rear[k]] = Vector2(cx + (k - (rear.size() - 1) * 0.5) * 400.0, front_y + back)
	var wing_x := maxf(front.size(), 2) * 160.0 + 260.0
	for k in wings.size():
		var side := -1.0 if k % 2 == 0 else 1.0
		@warning_ignore("integer_division")
		var x := cx + side * (wing_x + (k / 2) * 220.0)
		placed[wings[k]] = Vector2(clampf(x, 120, WORLD_SIZE.x - 120), front_y + back * 0.45)
	for i in list.size():
		var r := add_regiment(team, str(list[i]["type"]), placed[i], face, int(list[i]["men"]))
		r.set_rank(CampaignState.rank_of(list[i]))
		if team == PLAYER:
			r.company_index = i


func add_regiment(team: int, type: String, at: Vector2, facing: Vector2, men := -1) -> Regiment:
	var r := Regiment.new()
	r.id = regiments.size()
	r.team = team
	r.type = type
	r.stats = UnitTypes.STATS[type]
	r.dest = at
	r.facing = facing
	r.max_morale = r.stats["morale"]
	r.morale = r.max_morale
	var count: int = r.stats["count"]
	if men > 0:
		count = mini(men, count)
	for i in count:
		var s := Soldier.new()
		s.regiment = r
		s.max_hp = r.stats["hp"]
		s.hp = s.max_hp
		s.pos = r.slot_position(i, count) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		s.move_dir = facing
		s.cooldown = rng.randf()
		r.soldiers.append(s)
		soldiers.append(s)
	initial_strength[team] += count
	r.update_center()
	regiments.append(r)
	return r


func start_battle() -> void:
	state = State.BATTLE
	add_message("La bataille commence !")


# ---------------------------------------------------------------- Boucle

func _process(delta: float) -> void:
	update_camera(delta)
	if not paused:
		simulate(minf(delta, 0.05))
	for m in messages:
		m[1] -= delta
	messages = messages.filter(func(m): return m[1] > 0.0)
	for m in markers:
		m[2] -= delta
	markers = markers.filter(func(m): return m[2] > 0.0)
	queue_redraw()
	hud.queue_redraw()


func simulate(dt: float) -> void:
	if state == State.BATTLE:
		battle_time += dt
		ai.think(self, dt)
	rebuild_grid()
	for r in regiments:
		update_regiment(r, dt)
	for s in soldiers:
		if s.alive:
			update_soldier(s, dt)
	update_arrows(dt)
	update_gallop()
	cleanup_timer -= dt
	if cleanup_timer <= 0.0:
		cleanup_timer = 1.0
		soldiers = soldiers.filter(func(s): return s.alive)
	check_end()


## Bruit de galop : proportionnel au nombre de cavaliers visibles qui avancent, près de la caméra.
func update_gallop() -> void:
	if audio == null:
		return
	var n := 0.0
	for r in regiments:
		if r.type != "cavalry" or r.is_dead() or (r.team == ENEMY and r.hidden):
			continue
		var moving := 0
		for s in r.soldiers:
			if s.alive and s.moving:
				moving += 1
		if moving > 0:
			n += moving * pow(10.0, audio.attenuation(r.center) / 20.0)
	audio.gallop_level = clampf(n / 12.0, 0.0, 1.0)


func rebuild_grid() -> void:
	grid.clear()
	for s in soldiers:
		if not s.alive:
			continue
		var k := Vector2i(floori(s.pos.x / CELL), floori(s.pos.y / CELL))
		if grid.has(k):
			grid[k].append(s)
		else:
			grid[k] = [s]


func soldiers_near(p: Vector2, radius: float) -> Array:
	var out := []
	var cr := int(ceil(radius / CELL))
	var cx := floori(p.x / CELL)
	var cy := floori(p.y / CELL)
	var r2 := radius * radius
	for x in range(cx - cr, cx + cr + 1):
		for y in range(cy - cr, cy + cr + 1):
			var k := Vector2i(x, y)
			if grid.has(k):
				for s in grid[k]:
					if s.alive and s.pos.distance_squared_to(p) <= r2:
						out.append(s)
	return out


func is_in_forest(p: Vector2) -> bool:
	for f in forests:
		var c: Vector2 = f[0]
		var r: float = f[1]
		if p.distance_squared_to(c) < r * r:
			return true
	return false


# ---------------------------------------------------------------- Régiments

func update_regiment(r: Regiment, dt: float) -> void:
	r.update_center()
	if r.is_dead():
		r.selected = false
		return
	r.engaged = r.engaged_flag
	r.engaged_flag = false
	r.revealed = maxf(r.revealed - dt, 0.0)
	update_stamina(r, dt)

	# Visibilité : un régiment en forêt est invisible tant qu'aucun ennemi n'est proche
	r.in_forest = is_in_forest(r.center)
	if r.in_forest and r.revealed <= 0.0:
		var spotted := false
		for o in soldiers_near(r.center, 120.0):
			if o.regiment.team != r.team:
				spotted = true
				break
		r.hidden = not spotted
	else:
		r.hidden = false

	if r.target != null and (r.target.is_dead() or (r.target.routing and r.type != "cavalry")):
		r.target = null

	# Moral
	if r.routing:
		var enemy_close := nearest_enemy_regiment(r, 220.0, false) != null
		if not enemy_close:
			r.morale += UnitTypes.MORALE_RALLY_REGEN * dt
		if r.morale >= r.max_morale * 0.45 and not r.rallied_once:
			r.routing = false
			r.rallied_once = true
			r.dest = r.center
			r.target = null
			add_message("%s se rallient !" % team_label(r))
		r.morale = minf(r.morale, r.max_morale * 0.45)
	else:
		if not r.engaged:
			r.morale = minf(r.morale + UnitTypes.MORALE_REGEN * dt, r.max_morale)
		if r.morale <= 0.0:
			start_rout(r)
			return

	# Placement des soldats dans la formation
	var alive := r.alive_soldiers()
	var n := alive.size()
	for i in n:
		var s: Soldier = alive[i]
		s.slot_pos = r.slot_position(i, n)

	if r.routing:
		return

	r.think -= dt
	if r.stats["ranged"]:
		update_archers(r, dt)
	elif r.target != null:
		if r.think <= 0.0:
			r.think = 0.3
			r.dest = r.target.center
			if not r.engaged:
				var dir := r.target.center - r.center
				if dir.length() > 1.0:
					r.facing = dir.normalized()
	elif r.center.distance_to(r.dest) < 24.0:
		# Au repos : défend sa position si un ennemi s'approche
		var e := nearest_enemy_regiment(r, 110.0, true)
		if e != null and state == State.BATTLE:
			r.target = e


## Endurance : la course et la mêlée fatiguent, la marche et le repos reposent.
func update_stamina(r: Regiment, dt: float) -> void:
	var marching := r.target != null or r.center.distance_to(r.dest) > 24.0
	if r.running and not r.routing:
		r.stamina -= UnitTypes.RUN_DRAIN * dt
	elif r.engaged:
		r.stamina -= UnitTypes.FIGHT_DRAIN * dt
	elif marching or r.routing:
		r.stamina += UnitTypes.WALK_REGEN * dt
	else:
		r.stamina += UnitTypes.REST_REGEN * dt
	r.stamina = clampf(r.stamina, 0.0, 1.0)
	if not r.running:
		return
	if r.stamina <= 0.0:
		r.running = false
		if r.team == PLAYER:
			add_message("%s sont épuisés et reprennent le pas." % team_label(r))
	elif r.routing or r.engaged or r.holding or (r.target == null and r.center.distance_to(r.dest) < 24.0):
		r.running = false # Arrivé, au contact ou à portée de tir


func update_archers(r: Regiment, dt: float) -> void:
	var range_px: float = r.stats["range"]
	if raining:
		range_px *= 0.75
	r.fire_target = null
	if r.target != null:
		var d := r.center.distance_to(r.target.center)
		if d <= range_px:
			r.fire_target = r.target
			if not r.holding:
				r.holding = true
				r.dest = r.center
				r.facing = (r.target.center - r.center).normalized()
		else:
			r.holding = false
			if r.think <= 0.0:
				r.think = 0.5
				var dir := (r.target.center - r.center).normalized()
				r.dest = r.target.center - dir * range_px * 0.85
				r.facing = dir
	elif not r.engaged and r.center.distance_to(r.dest) < 24.0 and state == State.BATTLE:
		# Tir automatique sur l'ennemi visible le plus proche (pas sur une mêlée)
		var best: Regiment = null
		var bd := range_px
		for o in regiments:
			if o.team == r.team or o.is_dead() or o.hidden or o.engaged:
				continue
			var d := r.center.distance_to(o.center)
			if d < bd:
				bd = d
				best = o
		r.fire_target = best


func nearest_enemy_regiment(r: Regiment, max_dist: float, visible_only: bool) -> Regiment:
	var best: Regiment = null
	var bd := max_dist
	for o in regiments:
		if o.team == r.team or o.is_dead():
			continue
		if visible_only and o.hidden:
			continue
		var d := r.center.distance_to(o.center)
		if d < bd:
			bd = d
			best = o
	return best


func start_rout(r: Regiment) -> void:
	r.routing = true
	r.target = null
	r.fire_target = null
	r.selected = false
	r.morale = 0.0
	if r.team == PLAYER:
		add_message("Vos %s fuient le champ de bataille !" % r.display_name().to_lower())
	else:
		add_message("Des %s ennemis prennent la fuite !" % r.display_name().to_lower())
	for o in regiments:
		if o != r and o.team == r.team and not o.is_dead() and o.center.distance_to(r.center) < 260.0:
			o.morale -= UnitTypes.MORALE_ROUT_NEARBY


func team_label(r: Regiment) -> String:
	if r.team == PLAYER:
		return "Vos " + r.display_name().to_lower()
	return "Les " + r.display_name().to_lower() + " ennemis"


# ---------------------------------------------------------------- Soldats

func update_soldier(s: Soldier, dt: float) -> void:
	var r := s.regiment
	s.cooldown -= dt
	s.retarget -= dt
	s.flash = maxf(s.flash - dt, 0.0)
	s.attack_anim = maxf(s.attack_anim - dt, 0.0)
	s.moving = false

	var speed: float = r.stats["speed"] * UnitTypes.FORMATION_SPEED[r.formation]
	speed *= UnitTypes.fatigue_factor(r.stamina, UnitTypes.EXHAUSTED_SPEED)
	if r.running:
		speed *= UnitTypes.RUN_SPEED
	if is_in_forest(s.pos):
		speed *= 0.4 if r.type == "cavalry" else 0.65
	if raining:
		speed *= 0.9

	if r.routing:
		var edge_y := WORLD_SIZE.y + 80.0 if r.team == PLAYER else -80.0
		move_towards(s, Vector2(s.pos.x, edge_y), speed * 1.15, dt)
		if s.pos.y > WORLD_SIZE.y + 40.0 or s.pos.y < -40.0:
			s.alive = false
			s.fled = true
		separate(s)
		return

	if s.foe != null and not s.foe.alive:
		s.foe = null
	if s.retarget <= 0.0:
		s.retarget = 0.25 + rng.randf() * 0.15
		var radius := 24.0
		if r.target != null and not r.stats["ranged"]:
			radius = 80.0
		s.foe = find_foe(s, radius)

	if s.foe != null:
		var d := s.pos.distance_to(s.foe.pos)
		var reach: float = r.stats["reach"]
		if d > reach:
			move_towards(s, s.foe.pos, speed, dt)
			s.momentum = minf(s.momentum + dt * 0.8, 1.0)
		else:
			r.engaged_flag = true
			if s.cooldown <= 0.0:
				strike(s, s.foe)
				s.cooldown = float(r.stats["cooldown"]) * rng.randf_range(0.85, 1.15)
	else:
		var d := s.pos.distance_to(s.slot_pos)
		if d > 2.0:
			move_towards(s, s.slot_pos, speed, dt)
			s.momentum = minf(s.momentum + dt * 0.8, 1.0)
		else:
			s.momentum = maxf(s.momentum - dt, 0.0)
		if r.stats["ranged"] and r.fire_target != null and s.cooldown <= 0.0 and d < 12.0:
			fire_arrow(s, r.fire_target)
			s.cooldown = float(r.stats["reload"]) * rng.randf_range(0.8, 1.25)
	separate(s)


func move_towards(s: Soldier, goal: Vector2, speed: float, dt: float) -> void:
	var v := goal - s.pos
	var l := v.length()
	if l < 0.01:
		return
	var step := minf(speed * dt, l)
	s.move_dir = v / l
	s.pos += s.move_dir * step
	s.moving = true
	s.anim += dt * (8.0 * UnitTypes.RUN_SPEED if s.regiment.running else 8.0)


func separate(s: Soldier) -> void:
	var rad: float = s.regiment.stats["radius"]
	for o in soldiers_near(s.pos, 18.0):
		if o == s:
			continue
		var orad: float = o.regiment.stats["radius"]
		var min_d := rad + orad
		var v: Vector2 = s.pos - o.pos
		var d := v.length()
		if d < min_d:
			if d < 0.01:
				v = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				d = v.length()
			s.pos += v / d * (min_d - d) * 0.5
	s.pos = s.pos.clamp(Vector2(-120, -120), WORLD_SIZE + Vector2(120, 120))


func find_foe(s: Soldier, radius: float) -> Soldier:
	var best: Soldier = null
	var bd := INF
	var prefer := s.regiment.target
	for o in soldiers_near(s.pos, radius):
		if o.regiment.team == s.regiment.team:
			continue
		var d: float = s.pos.distance_squared_to(o.pos)
		if prefer != null and o.regiment == prefer:
			d *= 0.5
		if d < bd:
			bd = d
			best = o
	return best


## Côté par lequel arrive un coup porté depuis attacker_pos sur un soldat (en victim_pos) du régiment br.
func hit_side(attacker_pos: Vector2, victim_pos: Vector2, br: Regiment) -> int:
	if br.routing or br.formation == Regiment.Formation.SQUARE:
		return HIT_FRONT
	var dot := (attacker_pos - victim_pos).normalized().dot(br.facing)
	if dot < -0.35:
		return HIT_REAR
	if dot < 0.35:
		return HIT_FLANK
	return HIT_FRONT


func strike(a: Soldier, b: Soldier) -> void:
	var ar := a.regiment
	var br := b.regiment
	var dmg: float = float(ar.stats["damage"]) * UnitTypes.bonus(ar.type, br.type)

	# Embuscade : la première attaque d'un régiment caché terrifie la cible
	if ar.hidden:
		ar.hidden = false
		ar.revealed = 5.0
		br.morale -= UnitTypes.MORALE_AMBUSH
		add_message("Embuscade !")

	# Attaque de flanc ou de dos (un carré n'a ni flanc ni dos)
	match hit_side(a.pos, b.pos, br):
		HIT_REAR:
			dmg *= 2.0
			br.morale -= UnitTypes.MORALE_REAR_HIT
		HIT_FLANK:
			dmg *= 1.4
			br.morale -= UnitTypes.MORALE_FLANK_HIT

	# Charge de cavalerie
	if ar.type == "cavalry":
		dmg *= 1.0 + a.momentum * UnitTypes.CHARGE_BONUS
		if a.momentum > 0.5:
			br.morale -= UnitTypes.MORALE_CHARGE_HIT * (0.5 if br.type == "spear" else 1.0)
			var push := (b.pos - a.pos).normalized() * 6.0
			b.pos += push
			# Les piques plantées blessent les chevaux qui chargent
			if br.type == "spear":
				damage(a, UnitTypes.BRACE_DAMAGE, b)
		a.momentum = 0.0

	if br.routing:
		dmg *= 1.5
	dmg *= UnitTypes.fatigue_factor(ar.stamina, UnitTypes.EXHAUSTED_DAMAGE) * ar.rank_damage()
	dmg *= rng.randf_range(0.7, 1.3)
	a.attack_dur = 0.3
	a.attack_anim = a.attack_dur
	if not (ar.team == ENEMY and ar.hidden):
		audio.play("clash" if (br.type == "men_at_arms" or br.type == "cavalry") and rng.randf() < 0.6 else "sword", b.pos)
	damage(b, dmg, a)


func damage(s: Soldier, amount: float, source: Soldier) -> void:
	if not s.alive:
		return
	s.hp -= amount
	s.flash = 0.12
	s.regiment.revealed = maxf(s.regiment.revealed, 3.0)
	if source != null:
		source.regiment.revealed = maxf(source.regiment.revealed, 3.0)
	if s.hp <= 0.0:
		s.alive = false
		var r := s.regiment
		if source != null and source.regiment.team != r.team:
			source.regiment.kills += 1
		corpses.append([s.pos.round(), r.team, r.type, 1 if rng.randf() < 0.5 else -1])
		if corpses.size() > 2000:
			corpses.pop_front()
		if not (r.team == ENEMY and r.hidden):
			audio.play("death", s.pos)
		if not r.routing:
			r.morale -= UnitTypes.MORALE_PER_DEATH / float(r.stats["count"])


# ---------------------------------------------------------------- Flèches

func fire_arrow(s: Soldier, target: Regiment) -> void:
	var alive := target.alive_soldiers()
	if alive.is_empty():
		return
	var t: Soldier = alive[rng.randi() % alive.size()]
	var dist := s.pos.distance_to(t.pos)
	var spread := 12.0 * (0.5 + dist / 400.0)
	if raining:
		spread *= 1.8
	var aim := t.pos + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
	arrows.append({
		"from": s.pos + Vector2(0, -8), "to": aim, "t": 0.0, "dur": 0.5 + dist / 440.0,
		"dmg": float(s.regiment.stats["ranged_damage"]) * UnitTypes.fatigue_factor(s.regiment.stamina, UnitTypes.EXHAUSTED_DAMAGE) * s.regiment.rank_damage(),
		"src": s.regiment, # Pour compter les ennemis tués par les flèches
		"h": dist * 0.25,
	})
	s.regiment.revealed = maxf(s.regiment.revealed, 2.0)
	s.attack_dur = 0.35
	s.attack_anim = s.attack_dur
	if not (s.regiment.team == ENEMY and s.regiment.hidden):
		audio.play("bow", s.pos)


func update_arrows(dt: float) -> void:
	var keep := []
	for a in arrows:
		a["t"] += dt
		if a["t"] >= a["dur"]:
			arrow_impact(a)
		else:
			keep.append(a)
	arrows = keep


func arrow_impact(a: Dictionary) -> void:
	var hits := soldiers_near(a["to"], 6.0)
	if hits.is_empty():
		return
	var victim: Soldier = hits[0]
	if is_in_forest(victim.pos) and rng.randf() < 0.5:
		return # Les arbres arrêtent la flèche
	var dmg: float = a["dmg"] * float(victim.regiment.stats["arrow_armor"])
	victim.regiment.morale -= UnitTypes.MORALE_ARROW_HIT
	damage(victim, dmg * rng.randf_range(0.7, 1.3), null)
	var src: Regiment = a.get("src")
	if src != null and not victim.alive and src.team != victim.regiment.team:
		src.kills += 1


# ---------------------------------------------------------------- Fin de partie

func check_end() -> void:
	if state != State.BATTLE:
		return
	var p_alive := false
	var e_alive := false
	for r in regiments:
		if r.is_dead() or r.routing:
			continue
		if r.team == PLAYER:
			p_alive = true
		else:
			e_alive = true
	if not e_alive:
		state = State.VICTORY
		add_message("L'ennemi est en déroute. Victoire !")
	elif not p_alive:
		state = State.DEFEAT
		add_message("Votre compagnie est brisée...")
	else:
		return
	if campaign != null:
		finish_campaign()


## Reporte les pertes sur la compagnie : les hommes debout et ceux qui ont fui survivent.
func finish_campaign() -> void:
	var survivors := []
	survivors.resize(campaign.battle_army().size())
	survivors.fill(0)
	var kills := survivors.duplicate()
	for r in regiments:
		if r.team != PLAYER or r.company_index < 0:
			continue
		kills[r.company_index] += r.kills
		for s in r.soldiers:
			if s.alive or s.fled:
				survivors[r.company_index] += 1
	campaign_report = campaign.finish_battle(state == State.VICTORY, survivors, kills)
	campaign.save()
	add_message(campaign_report)


func team_strength(team: int) -> int:
	var n := 0
	for r in regiments:
		if r.team == team and not r.routing:
			n += r.alive_n
	return n


func add_message(text: String) -> void:
	messages.append([text, 5.0])
	if messages.size() > 5:
		messages.pop_front()


# ---------------------------------------------------------------- Commandes

func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		var wp := event_world_pos(mb)
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					dragging = true
					drag_start = wp
					drag_now = wp
				elif dragging:
					dragging = false
					finish_selection(drag_start, wp, mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					line_dragging = true
					line_double = mb.double_click
					line_start = wp
					line_now = wp
				elif line_dragging:
					line_dragging = false
					if is_line_drag(line_start, wp):
						issue_line_order(line_start, wp, line_double)
					else:
						# Simple clic : déplacement ou attaque ; double clic : la même chose en courant
						issue_order(line_start, line_double)
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				panning = mb.pressed
		return

	var mm := event as InputEventMouseMotion
	if mm != null:
		if panning:
			camera.position -= mm.relative / camera.zoom
		if dragging:
			drag_now = event_world_pos(mm)
		if line_dragging:
			line_now = event_world_pos(mm)
		return

	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_A and k.ctrl_pressed:
		for r in player_regiments():
			r.selected = true
		return
	match k.keycode:
		KEY_SPACE:
			if state == State.DEPLOY:
				start_battle()
			else:
				paused = not paused
		KEY_T:
			raining = not raining
			add_message("Il pleut : les archers tirent moins loin et moins juste." if raining else "La pluie cesse.")
		KEY_H:
			for r in selected_regiments():
				r.target = null
				r.holding = false
				r.running = false
				r.dest = r.center
		KEY_F1:
			show_help = not show_help
		KEY_F:
			cycle_formation()
		KEY_M:
			audio.set_enabled(not audio.enabled)
			add_message("Son activé." if audio.enabled else "Son coupé.")
		KEY_ENTER, KEY_KP_ENTER:
			if state == State.VICTORY or state == State.DEFEAT:
				if campaign != null:
					get_tree().change_scene_to_file("res://scenes/campaign.tscn")
				else:
					get_tree().reload_current_scene()
		KEY_ESCAPE:
			# Escarmouche : retour à la carte de campagne (un contrat se joue jusqu'au bout)
			if campaign == null:
				get_tree().change_scene_to_file("res://scenes/campaign.tscn")
	# Touches 1 à 9 (position physique, fonctionne en AZERTY)
	var idx: int = int(k.physical_keycode) - int(KEY_1)
	if idx >= 0 and idx < 9:
		var list := player_regiments()
		if idx < list.size():
			if not k.shift_pressed:
				for r in regiments:
					r.selected = false
			list[idx].selected = true


## Position de la souris dans le monde pour un évènement donné.
func event_world_pos(event: InputEventMouse) -> Vector2:
	return get_canvas_transform().affine_inverse() * event.position


## Vrai si le clic droit a assez glissé (en pixels écran) pour tracer une ligne.
func is_line_drag(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) * camera.zoom.x >= LINE_DRAG_MIN_PX


## Touche F : ligne → colonne → carré pour les régiments sélectionnés.
func cycle_formation() -> void:
	var sel := selected_regiments()
	if sel.is_empty():
		return
	var f := sel[0].next_formation()
	for r in sel:
		r.formation = f
	var hint := ""
	match f:
		Regiment.Formation.COLUMN:
			hint = " (plus rapide)"
		Regiment.Formation.SQUARE:
			hint = " (lent, ni flanc ni dos)"
	add_message("Formation : %s%s" % [Regiment.FORMATION_NAMES[f], hint])


func player_regiments() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.team == PLAYER and not r.is_dead() and not r.routing:
			out.append(r)
	return out


func selected_regiments() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.selected and not r.is_dead() and not r.routing:
			out.append(r)
	return out


func regiment_at(p: Vector2, team: int) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for s in soldiers_near(p, 18.0):
		var r: Regiment = s.regiment
		if r.team != team or r.routing:
			continue
		if team == ENEMY and r.hidden:
			continue
		var d: float = s.pos.distance_squared_to(p)
		if d < bd:
			bd = d
			best = r
	return best


func finish_selection(a: Vector2, b: Vector2, add: bool) -> void:
	if not add:
		for r in regiments:
			r.selected = false
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	if rect.size.length() < 8.0:
		var r := regiment_at(b, PLAYER)
		if r != null:
			r.selected = true
		return
	for r in player_regiments():
		for s in r.soldiers:
			if s.alive and rect.has_point(s.pos):
				r.selected = true
				break


## Ordre de course : seuls les régiments assez reposés obéissent.
func set_running(sel: Array[Regiment], run: bool) -> void:
	var refused := false
	for r in sel:
		r.running = run and r.stamina >= UnitTypes.RUN_MIN_STAMINA
		if run and not r.running:
			refused = true
	if refused:
		add_message("Trop fatigués pour courir !")


func issue_order(wp: Vector2, run := false) -> void:
	var sel := selected_regiments()
	if sel.is_empty():
		return
	set_running(sel, run)
	var enemy: Regiment = null
	if state == State.BATTLE:
		enemy = regiment_at(wp, ENEMY)
	if enemy != null:
		for r in sel:
			r.target = enemy
			r.holding = false
			r.think = 0.0
		markers.append([enemy.center, Color(1, 0.3, 0.2), 0.6])
		return

	# Déplacement : les régiments se placent côte à côte, face à la direction du mouvement
	var gc := Vector2.ZERO
	for r in sel:
		gc += r.center
	gc /= sel.size()
	var dir := wp - gc
	var facing: Vector2 = sel[0].facing
	if dir.length() > 40.0:
		facing = dir.normalized()
	var right := Vector2(-facing.y, facing.x)
	sel.sort_custom(func(x, y): return x.center.dot(right) < y.center.dot(right))
	var widths := []
	var total := 0.0
	for r in sel:
		var w := r.width() + LINE_GAP
		widths.append(w)
		total += w
	var x := -total * 0.5
	for i in sel.size():
		var r: Regiment = sel[i]
		var w: float = widths[i]
		r.dest = (wp + right * (x + w * 0.5)).clamp(Vector2(20, 20), WORLD_SIZE - Vector2(20, 20))
		r.facing = facing
		r.target = null
		r.holding = false
		x += w
	markers.append([wp, Color(1, 1, 1), 0.6])


## Calcule la disposition des régiments le long d'une ligne tracée de a vers b (comme dans
## Total War). Renvoie pour chacun : {"reg", "dest", "facing", "cols"}. Ne modifie rien.
func line_layout(sel: Array[Regiment], a: Vector2, b: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sel.is_empty() or a.distance_to(b) < 0.5:
		return out
	var dir := (b - a).normalized()
	var length := a.distance_to(b)

	# Orientation : perpendiculaire à la ligne, du côté opposé à la position actuelle des troupes.
	var gc := Vector2.ZERO
	for r in sel:
		gc += r.center
	gc /= sel.size()
	var facing := Vector2(dir.y, -dir.x) # Par défaut : tracé gauche → droite = face vers le haut
	var side := ((a + b) * 0.5 - gc).dot(facing)
	if side < -16.0:
		facing = -facing

	# Les régiments gardent leur ordre le long de la ligne (donc leur ordre gauche-droite).
	var order: Array[Regiment] = sel.duplicate()
	order.sort_custom(func(x, y): return x.center.dot(dir) < y.center.dot(dir))

	# La longueur est partagée en proportion de la taille de chaque régiment,
	# pour que tous aient à peu près la même profondeur.
	var natural := 0.0
	for r in order:
		natural += r.alive_n * float(r.stats["spacing"])
	var usable := maxf(length - LINE_GAP * (order.size() - 1), 1.0)
	var x := 0.0
	for r in order:
		var sp: float = r.stats["spacing"]
		var share := usable * r.alive_n * sp / natural
		var cols := clampi(roundi(share / sp), r.min_columns(), r.max_columns())
		var w := cols * sp
		var dest := (a + dir * (x + w * 0.5)).clamp(Vector2(20, 20), WORLD_SIZE - Vector2(20, 20))
		out.append({"reg": r, "dest": dest, "facing": facing, "cols": cols})
		x += w + LINE_GAP
	return out


## Ordre de formation : place les régiments sélectionnés sur la ligne tracée.
func issue_line_order(a: Vector2, b: Vector2, run := false) -> void:
	var sel := selected_regiments()
	var layout := line_layout(sel, a, b)
	if layout.is_empty():
		return
	set_running(sel, run)
	for e in layout:
		var r: Regiment = e["reg"]
		r.dest = e["dest"]
		r.facing = e["facing"]
		r.cols_override = e["cols"]
		r.formation = Regiment.Formation.LINE
		r.target = null
		r.holding = false
	markers.append([(a + b) * 0.5, Color(1, 1, 1), 0.6])


# ---------------------------------------------------------------- Caméra

func update_camera(delta: float) -> void:
	var v := Vector2.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
	camera.position += v * 450.0 * delta / camera.zoom.x
	clamp_camera()


func clamp_camera() -> void:
	var half := get_viewport_rect().size / camera.zoom * 0.5
	var p := camera.position
	if half.x * 2.0 >= WORLD_SIZE.x:
		p.x = WORLD_SIZE.x * 0.5
	else:
		p.x = clampf(p.x, half.x, WORLD_SIZE.x - half.x)
	if half.y * 2.0 >= WORLD_SIZE.y:
		p.y = WORLD_SIZE.y * 0.5
	else:
		p.y = clampf(p.y, half.y, WORLD_SIZE.y - half.y)
	camera.position = p


func zoom_at(factor: float) -> void:
	var vs := get_viewport_rect().size
	var m := get_viewport().get_mouse_position() - vs * 0.5
	var world := camera.position + m / camera.zoom
	var z := clampf(camera.zoom.x * factor, 0.5, 2.5)
	camera.zoom = Vector2(z, z)
	camera.position = world - m / camera.zoom
	clamp_camera()


# ---------------------------------------------------------------- Rendu

func _draw() -> void:
	draw_texture_rect(ground_tex, Rect2(Vector2.ZERO, WORLD_SIZE), false)

	if state == State.DEPLOY:
		draw_rect(Rect2(0, DEPLOY_Y, WORLD_SIZE.x, WORLD_SIZE.y - DEPLOY_Y), Color(0.3, 0.5, 1.0, 0.08))
		draw_line(Vector2(0, DEPLOY_Y), Vector2(WORLD_SIZE.x, DEPLOY_Y), Color(0.6, 0.75, 1.0, 0.4), 2.0)

	for c in corpses:
		draw_corpse(c)

	# Ordres des régiments sélectionnés
	for r in regiments:
		if not r.selected or r.is_dead():
			continue
		for s in r.soldiers:
			if s.alive:
				draw_rect(Rect2(s.pos.x - 6, s.pos.y - 1, 12, 3), Color(1, 0.95, 0.4, 0.55))
		if r.target != null:
			draw_dashed_line(r.center, r.target.center, Color(1, 0.35, 0.25, 0.6), 2.0, 8.0)
		elif r.center.distance_to(r.dest) > 24.0:
			draw_dashed_line(r.center, r.dest, Color(1, 0.6, 0.15, 0.75) if r.running else Color(1, 1, 1, 0.4), 2.0, 8.0)
			draw_rect(Rect2(r.dest - Vector2(2, 2), Vector2(6, 6)), Color(1, 1, 1, 0.7))

	# Flèche d'orientation de chaque régiment du joueur (plus visible s'il est sélectionné)
	for r in regiments:
		if r.team != PLAYER or r.is_dead() or r.routing:
			continue
		var acol := Color(1, 0.95, 0.4, 0.9) if r.selected else Color(1, 1, 1, 0.45)
		# Vers sa destination s'il marche, sinon sur place
		var at := r.dest if r.center.distance_to(r.dest) > 24.0 and r.target == null else r.center
		draw_facing_arrow(r, at, r.facing, 0, acol, 14.0)

	# Soldats et arbres triés par hauteur pour la profondeur
	var items := []
	for s in soldiers:
		if not s.alive:
			continue
		if s.regiment.team == ENEMY and s.regiment.hidden:
			continue
		items.append([s.pos.y, s])
	for t in trees:
		items.append([t.y, t])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if it[1] is Vector2:
			draw_tree(it[1])
		else:
			draw_soldier(it[1])

	draw_arrows()

	for r in regiments:
		if r.is_dead() or (r.team == ENEMY and r.hidden):
			continue
		draw_banner(r)

	for m in markers:
		var p: Vector2 = m[0]
		var col: Color = m[1]
		var k: float = m[2] / 0.6
		col.a = k
		draw_arc(p, 6.0 + (1.0 - k) * 16.0, 0, TAU, 20, col, 2.0)

	if line_dragging and is_line_drag(line_start, line_now):
		draw_line_preview()

	if dragging and drag_start.distance_to(drag_now) > 2.0:
		var rect := Rect2(drag_start, Vector2.ZERO).expand(drag_now)
		draw_rect(rect, Color(1, 1, 1, 0.12), true)
		draw_rect(rect, Color(1, 1, 1, 0.7), false, 1.0 / camera.zoom.x)


## Aperçu fantôme pendant le tracé : place de chaque soldat et flèche d'orientation.
func draw_line_preview() -> void:
	var ghost := Color(1, 0.95, 0.4, 0.55)
	var lw := 1.0 / camera.zoom.x
	draw_line(line_start, line_now, Color(1, 1, 1, 0.35), lw)
	for e in line_layout(selected_regiments(), line_start, line_now):
		var r: Regiment = e["reg"]
		var at: Vector2 = e["dest"]
		var face: Vector2 = e["facing"]
		var cols: int = e["cols"]
		var n := r.alive_n
		for i in n:
			var p := r.formation_slot(i, n, cols, at, face)
			draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), ghost)
		draw_facing_arrow(r, at, face, cols, Color(1, 1, 1, 0.85), 24.0)


## Petite flèche devant le premier rang, qui montre où le régiment fait face.
## cols <= 0 : utilise la formation actuelle du régiment.
func draw_facing_arrow(r: Regiment, at: Vector2, face: Vector2, cols: int, col: Color, length: float) -> void:
	var n := maxi(r.alive_n, 1)
	var rows := r.depth_rows(n) if cols <= 0 else ceili(float(n) / float(clampi(cols, 1, n)))
	var sp: float = r.stats["spacing"]
	var tail := at + face * (rows * 0.5 * sp + 4.0)
	var tip := tail + face * length
	var head := minf(length * 0.45, 8.0)
	var wing := Vector2(-face.y, face.x) * head * 0.8
	draw_line(tail, tip, col, 2.0)
	draw_line(tip, tip - face * head + wing, col, 2.0)
	draw_line(tip, tip - face * head - wing, col, 2.0)


func px(p: Vector2, fx: int, x: float, y: float, w: float, h: float, c: Color) -> void:
	var xx := x if fx > 0 else -x - w
	draw_rect(Rect2(p.x + xx, p.y + y, w, h), c)


## Direction dans laquelle le soldat regarde : son adversaire, sinon sa marche, sinon le front.
func soldier_look(s: Soldier) -> Vector2:
	if s.foe != null:
		return s.foe.pos - s.pos
	if s.regiment.fire_target != null and s.regiment.stats["ranged"]:
		return s.regiment.fire_target.center - s.pos
	if s.moving:
		return s.move_dir
	if s.regiment.formation == Regiment.Formation.SQUARE:
		var out := s.slot_pos - s.regiment.dest
		if out.length() > 1.0:
			return out # Le carré fait face de tous les côtés
	return s.regiment.facing


func draw_soldier(s: Soldier) -> void:
	var r := s.regiment
	var hidden_alpha := 0.55 if (r.team == PLAYER and r.hidden) else 1.0
	if sprites.has_unit(r.type, r.team):
		var look := soldier_look(s)
		var dir := SpriteBank.dir_of(look)
		var anim := "idle"
		var t := s.anim
		if s.attack_anim > 0.0:
			anim = "attack"
			t = 1.0 - s.attack_anim / s.attack_dur
		elif s.moving:
			anim = "walk"
		var f := sprites.frame(r.type, r.team, dir, anim, t)
		var p := s.pos.round()
		if s.attack_anim > 0.0 and r.type == "spear":
			p += look.normalized().round() * 3.0 # Coup de pique : petite fente vers l'avant
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		draw_rect(Rect2(p.x - 5, p.y - 1, 10, 3), Color(0, 0, 0, 0.22))
		var mod := Color(1, 1, 1, hidden_alpha)
		if s.flash > 0.0:
			mod = Color(2.5, 2.5, 2.5, hidden_alpha) # Éclair blanc quand il est touché
		draw_texture_rect_region(f["tex"], Rect2(p - foot, src.size), src, mod)
		return
	draw_soldier_code(s)


## Corps au sol : le sprite couché et assombri, ou un petit dessin en code.
func draw_corpse(c: Array) -> void:
	var p: Vector2 = c[0]
	var team: int = c[1]
	var type: String = c[2]
	var side: int = c[3]
	if sprites.has_unit(type, team):
		var f := sprites.frame(type, team, SpriteBank.DOWN, "idle", 0.0)
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		draw_set_transform(p, side * PI * 0.5)
		draw_texture_rect_region(f["tex"], Rect2(Vector2(-src.size.x * 0.5, -foot.y * 0.5), src.size), src, Color(0.55, 0.45, 0.42, 0.85))
		draw_set_transform(Vector2.ZERO)
		return
	draw_set_transform(p, 0.0, Vector2(PX, PX))
	if type == "cavalry":
		draw_rect(Rect2(-3, -2, 7, 2), HORSE_DARK)
	draw_rect(Rect2(-2, -1, 4, 1), TEAM_DARK[team])
	draw_rect(Rect2(-1, 0, 2, 1), Color(0.45, 0.07, 0.05, 0.8))
	draw_set_transform(Vector2.ZERO)


## Repli : soldat dessiné en code (si son sprite manque), agrandi PX fois.
func draw_soldier_code(s: Soldier) -> void:
	var r := s.regiment
	draw_set_transform(s.pos.round(), 0.0, Vector2(PX, PX))
	var p := Vector2.ZERO
	var fx := 1 if r.facing.x >= 0.0 else -1
	if s.foe != null:
		fx = 1 if s.foe.pos.x >= s.pos.x else -1
	if s.attack_anim > 0.0:
		p.x += fx
	var col: Color = TEAM_COLORS[r.team]
	var dark: Color = TEAM_DARK[r.team]
	if s.flash > 0.0:
		col = Color.WHITE
	var step := 0.0
	if s.moving and int(s.anim) % 2 == 0:
		step = 1.0
	var alpha := 0.55 if (r.team == PLAYER and r.hidden) else 1.0
	if alpha < 1.0:
		col.a = alpha
		dark.a = alpha

	draw_rect(Rect2(p.x - 2, p.y - 0.5, 5, 1.5), Color(0, 0, 0, 0.28))

	if r.type == "cavalry":
		var horse := HORSE
		horse.a = alpha
		px(p, fx, -3, -5, 7, 3, horse)
		px(p, fx, 3, -7, 2, 3, horse)
		px(p, fx, 4, -6, 1, 1, HORSE_DARK)
		px(p, fx, -4, -5, 1, 3, HORSE_DARK)
		px(p, fx, -3, -2, 1, 2 - step, HORSE_DARK)
		px(p, fx, 2, -2, 1, 1 + step, HORSE_DARK)
		px(p, fx, -1, -2, 1, 1 + step, HORSE_DARK)
		px(p, fx, 0, -2, 1, 2 - step, HORSE_DARK)
		px(p, fx, -1, -6, 1, 2, dark)
		px(p, fx, -1, -9, 3, 3, col)
		px(p, fx, -1, -11, 2, 2, STEEL)
		if s.momentum > 0.5:
			px(p, fx, 2, -8, 6, 1, WOOD)
		else:
			px(p, fx, 2, -13, 1, 7, WOOD)
		draw_set_transform(Vector2.ZERO)
		return

	# Fantassin : jambes, corps, tête
	px(p, fx, -1, -2, 1, 2 - step, dark)
	px(p, fx, 1, -2, 1, 1 + step, dark)
	px(p, fx, -1, -5, 3, 3, col)
	match r.type:
		"men_at_arms":
			px(p, fx, -1, -7, 3, 2, STEEL)
			px(p, fx, 1, -7, 1, 1, SKIN)
			px(p, fx, 2, -5, 2, 3, dark.lightened(0.2))
			px(p, fx, 2, -4, 1, 1, Color(0.9, 0.8, 0.3))
		"spear":
			px(p, fx, -1, -7, 3, 2, SKIN)
			px(p, fx, -1, -7, 3, 1, STEEL)
			if s.foe != null:
				px(p, fx, 1, -5, 7, 1, WOOD)
				px(p, fx, 8, -5, 1, 1, STEEL)
			else:
				px(p, fx, 2, -10, 1, 9, WOOD)
				px(p, fx, 2, -11, 1, 1, STEEL)
		"archer":
			px(p, fx, -1, -7, 3, 2, Color(0.33, 0.42, 0.2))
			px(p, fx, 1, -6, 1, 1, SKIN)
			px(p, fx, 2, -7, 1, 5, WOOD)
			if s.attack_anim > 0.0:
				px(p, fx, 1, -5, 1, 1, Color(0.9, 0.9, 0.8))
	draw_set_transform(Vector2.ZERO)


func draw_tree(t: Vector2) -> void:
	if sprites.has_trees():
		var tr := sprites.tree_at(t)
		var src: Rect2 = tr["src"]
		var tp := t.round()
		draw_rect(Rect2(tp.x - 7, tp.y - 1, 14, 3), Color(0, 0, 0, 0.22))
		draw_texture_rect_region(tr["tex"], Rect2(tp - Vector2(8, 15), src.size), src)
		return
	draw_set_transform(t.round(), 0.0, Vector2(PX, PX))
	var p := Vector2.ZERO
	draw_rect(Rect2(p.x - 4, p.y - 1, 9, 2), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(p.x - 1, p.y - 4, 2, 4), Color(0.35, 0.22, 0.12))
	draw_rect(Rect2(p.x - 4, p.y - 11, 9, 7), Color(0.12, 0.29, 0.12, 0.93))
	draw_rect(Rect2(p.x - 3, p.y - 13, 7, 2), Color(0.15, 0.35, 0.14, 0.93))
	draw_rect(Rect2(p.x - 2, p.y - 11, 3, 2), Color(0.22, 0.45, 0.18, 0.93))
	draw_set_transform(Vector2.ZERO)


func draw_arrows() -> void:
	for a in arrows:
		var k: float = a["t"] / a["dur"]
		var k2 := minf(k + 0.05, 1.0)
		var from: Vector2 = a["from"]
		var to: Vector2 = a["to"]
		var h: float = a["h"]
		var p1 := from.lerp(to, k) - Vector2(0, h * 4.0 * k * (1.0 - k))
		var p2 := from.lerp(to, k2) - Vector2(0, h * 4.0 * k2 * (1.0 - k2))
		var dir := (p2 - p1).normalized() * 5.0
		draw_line(p1 - dir, p1 + dir, Color(0.35, 0.25, 0.15), 1.0)
		draw_line(p1 + dir * 0.6, p1 + dir, Color(0.85, 0.87, 0.9), 1.0)


## Étendard au-dessus du régiment (dessiné en code, agrandi PX fois).
func draw_banner(r: Regiment) -> void:
	var lift := 34.0 if r.type == "cavalry" else 26.0
	draw_set_transform((r.center + Vector2(0, -lift)).round(), 0.0, Vector2(PX, PX))
	draw_banner_shape(r, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO)


func draw_banner_shape(r: Regiment, base: Vector2) -> void:
	var col: Color = TEAM_COLORS[r.team]
	if r.routing:
		col = col.darkened(0.5)
	draw_line(base, base + Vector2(0, -10), WOOD, 1.0)
	draw_rect(Rect2(base.x, base.y - 10, 7, 5), col)
	draw_rect(Rect2(base.x, base.y - 10, 7, 5), Color(0, 0, 0, 0.6), false, 0.5)
	# Pictogramme du type
	var ic := Color(1, 1, 0.85)
	match r.type:
		"men_at_arms":
			draw_rect(Rect2(base.x + 3, base.y - 9, 1, 3), ic)
			draw_rect(Rect2(base.x + 2, base.y - 8, 3, 1), ic)
		"spear":
			draw_line(base + Vector2(1.5, -6), base + Vector2(5.5, -9.5), ic, 1.0)
		"archer":
			draw_arc(base + Vector2(3, -7.5), 1.8, -PI / 2, PI / 2, 6, ic, 1.0)
		"cavalry":
			draw_rect(Rect2(base.x + 2, base.y - 8, 3, 2), ic)
	# Barre de moral
	var k := clampf(r.morale / r.max_morale, 0.0, 1.0)
	draw_rect(Rect2(base.x - 4, base.y + 1, 14, 2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(base.x - 4, base.y + 1, 14 * k, 2), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
	if r.selected:
		draw_rect(Rect2(base.x - 1, base.y - 11, 9, 7), Color(1, 0.95, 0.4), false, 0.7)
	if r.team == PLAYER and r.hidden:
		draw_rect(Rect2(base.x + 8, base.y - 9, 2, 2), Color(0.3, 1, 0.4))
