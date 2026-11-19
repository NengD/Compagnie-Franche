class_name BattleSim
extends RefCounted
## Simulation de la bataille, sans rendu ni nœud : monde (forêts, route, terrain), armées,
## déplacements, mêlée, moral, flèches, endurance et fin de bataille.
##
## Elle ne connaît ni la caméra, ni le son, ni le HUD : elle les prévient par des signaux
## (message_posted, sound_played, cries_played, impact, hit, ended), que battle.gd relaie.
## On peut donc la faire tourner seule (tests, banc d'équilibrage) en appelant step(dt).
##
## Points d'extension :
## - nouvelle unité : ses statistiques et ses capacités (« mounted », « braces », « armored »,
##   « forest_speed », « ranged »…) se lisent uniquement dans UnitTypes.STATS ; la simulation
##   ne teste jamais le nom d'un type ;
## - objectif de contrat : une classe de battle_objectives.gd (objective), que check_end() interroge ;
## - nouvel effet (son, secousse, particules) : émettre un signal ici, le brancher dans battle.gd.
##
## Attention : l'ordre des tirages de rng compte (graines fixes des tests et du banc).

signal message_posted(text: String) ## Message pour le joueur (journal du HUD)
signal sound_played(sound: String, at: Vector2) ## Bruitage localisé (« sword », « clash », « bow », « death », « swish »)
signal cries_played(at: Vector2, count: int) ## Cris d'un régiment qui fuit
signal impact(at: Vector2, amount: float) ## Choc visible (charge) : secousse de caméra
signal hit(at: Vector2, from: Vector2) ## Soldat touché en at, depuis from (from == at : flèche) : effets visuels
signal ended ## La bataille vient de se terminer (state vaut VICTORY ou DEFEAT)
signal feat(kind: String, by: Regiment, against: Regiment) ## Fait d'armes pour les succès (« ambush », « charge_on_square »)

const WORLD_SIZE := Vector2(3200, 2000)
const PLAYER := 0
const ENEMY := 1
const CELL := 32.0 ## Taille d'une case de la grille de voisinage
const DEPLOY_Y := 1400.0 ## Limite haute de la zone de déploiement du joueur
const ROAD_HALF := 18.0 ## Demi-largeur de la route
const HIT_FRONT := 0
const HIT_FLANK := 1
const HIT_REAR := 2
const MAX_DUST := 240 ## Particules de poussière au maximum

enum State { DEPLOY, BATTLE, VICTORY, DEFEAT }

var state: State = State.DEPLOY
var raining := false
var battle_time := 0.0 ## Temps simulé depuis le début de la bataille (hors déploiement)
var difficulty := "normal" ## Difficulté (voir difficulty.gd), appliquée aux régiments ennemis

var regiments: Array[Regiment] = []
var soldiers: Array = [] ## Tous les soldats (les morts sont retirés chaque seconde)
var arrows: Array = [] ## Flèches en vol : {"from", "to", "t", "dur", "dmg", "src", "h"}
var corpses: Array = [] ## Corps au sol : [position, camp, type, côté]
var forests: Array = [] ## [centre, rayon]
var trees: Array = [] ## Positions des arbres, triées par y
var dust: Array = [] ## Poussière (purement visuelle) : [position, vitesse, vie restante, vie totale, taille]
var grid := {} ## Grille de voisinage : Vector2i -> soldats
var initial_strength := [0, 0]
var cleanup_timer := 0.0

var rng := RandomNumberGenerator.new()
var road_noise := FastNoiseLite.new()
var terrain := Terrain.new() ## Collines, rivière, village, palissade (voir terrain.gd)
var ai := EnemyAI.new()
var ally_ai: AlliedAI = null ## IA des alliés (null sans alliés, voir spawn_allies)
var allies: Array = [] ## Groupes alliés de la carte : {"party", "name", "faction", "troops"}
var siege: Siege = null ## Vrai siège (ville fortifiée, voir siege.gd), null sinon

var retreated := false ## La bataille s'est terminée par une retraite
var retreat_caught := 0 ## Hommes au contact rattrapés pendant la retraite
var captain: Captain = null ## Capitaine du joueur sur le champ (voir captain.gd), null sans capitaine
var objective: BattleObjectives.Objective = BattleObjectives.create("destroy") ## Condition de victoire (battle_objectives.gd)


## Casse les références croisées régiments ↔ soldats (RefCounted) pour éviter les fuites.
func clear() -> void:
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


# ---------------------------------------------------------------- Monde

## Route, terrain (kind : voir Terrain.KINDS ; vide = tiré au sort), forêts et arbres isolés.
## Le sol dessiné (battle_renderer.gd) se construit juste après, avec le même rng.
## site : champ tiré de l'endroit de la carte (BattleSite.describe) ; ses bois sont plantés d'abord.
func generate_world(kind := "", site: Dictionary = {}) -> void:
	road_noise.seed = rng.randi()
	road_noise.frequency = 0.0075
	if kind == "":
		kind = Terrain.KINDS[rng.randi() % Terrain.KINDS.size()]
	terrain.setup(kind, rng, WORLD_SIZE, road_y, site)
	if terrain.town != null:
		siege = Siege.new(terrain.town)

	# Forêts (pour les embuscades) : celles de la carte, puis quelques bosquets
	var want := terrain.forest_count()
	if not terrain.site.is_empty():
		for f in terrain.site["forests"]:
			if f is Array and (f as Array).size() >= 3:
				plant_forest(Vector2(float(f[0]), float(f[1])), float(f[2]))
		want = (8 - forests.size()) if terrain.kind == "forest" else (1 if forests.size() > 0 else 3)
	var placed := 0
	var tries := 0
	while placed < want and tries < 200:
		tries += 1
		var c := Vector2(rng.randf_range(300, WORLD_SIZE.x - 300), rng.randf_range(560, WORLD_SIZE.y - 560))
		var r := rng.randf_range(100, 190)
		if not terrain.forest_ok(c, r):
			continue
		placed += 1
		plant_forest(c, r)
	# Quelques arbres isolés
	for i in 40:
		var p := Vector2(rng.randf_range(0, WORLD_SIZE.x), rng.randf_range(0, WORLD_SIZE.y))
		if p.y > 460 and p.y < WORLD_SIZE.y - 460 and absf(p.y - road_y(p.x)) > ROAD_HALF + 12.0 and terrain.tree_ok(p):
			trees.append(p)
	trees.sort_custom(func(a, b): return a.y < b.y)


## Un bois de centre c et de rayon r, et ses arbres (même ordre de tirages qu'avant le site).
func plant_forest(c: Vector2, r: float) -> void:
	forests.append([c, r])
	var n := int(r * r / 150.0)
	for j in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var t := c + Vector2(cos(a), sin(a)) * d
		if terrain.tree_ok(t) and not terrain.on_extra_road(t, Terrain.EXTRA_ROAD_HALF + 4.0):
			trees.append(t)


## Vrai si p est sur la route (pas de route quand la rivière la remplace), ou sur une des routes
## de la carte qui croisent le champ (site).
func on_road(p: Vector2, half: float) -> bool:
	if terrain.has_road() and absf(p.y - road_y(p.x)) < half:
		return true
	return not terrain.extra_roads.is_empty() and terrain.on_extra_road(p, half - ROAD_HALF + Terrain.EXTRA_ROAD_HALF)


## Hauteur de la route qui traverse le champ de bataille (ou de la rivière qui la remplace) ;
## celle de la carte quand le champ en vient (site).
func road_y(x: float) -> float:
	if not terrain.line.is_empty():
		return BattleSite.line_y(terrain.line, x)
	return WORLD_SIZE.y * 0.5 + sin(x * 0.003125) * 112.0 + road_noise.get_noise_1d(x) * 64.0


func is_in_forest(p: Vector2) -> bool:
	for f in forests:
		var c: Vector2 = f[0]
		var r: float = f[1]
		if p.distance_squared_to(c) < r * r:
			return true
	return false


## Limite haute de la zone de déploiement. En siège, on peut se poster juste derrière la palissade.
func deploy_top() -> float:
	if terrain.kind == "siege":
		return minf(DEPLOY_Y, Terrain.WALL_Y + 40.0)
	if siege != null:
		return siege.deploy_top(DEPLOY_Y)
	return DEPLOY_Y


# ---------------------------------------------------------------- Armées

## Armées par défaut de l'escarmouche.
func spawn_default_armies() -> void:
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


## Siège : l'assaillant amène des renforts (sinon la défense serait trop facile),
## puis le joueur se poste derrière la palissade.
func setup_siege() -> void:
	for k in Terrain.SIEGE_REINFORCEMENTS.size():
		add_regiment(ENEMY, Terrain.SIEGE_REINFORCEMENTS[k], Vector2(WORLD_SIZE.x * (0.5 + 0.3 * k), 230.0), Vector2.DOWN)
	deploy_siege_defense()


## Défense de palissade : l'infanterie du joueur encadre chaque brèche (ce qui la franchit est pris
## en tenaille), les archers tirent abrités derrière les pieux, la cavalerie attend en réserve.
func deploy_siege_defense() -> void:
	var foot: Array[Regiment] = []
	var archers: Array[Regiment] = []
	var horse: Array[Regiment] = []
	for r in regiments:
		if r.team != PLAYER:
			continue
		if r.stats["mounted"]: # Les archers montés attendent avec la cavalerie
			horse.append(r)
		elif r.stats["ranged"]:
			archers.append(r)
		else:
			foot.append(r)
	var br := terrain.breaches
	var wy := Terrain.WALL_Y
	var mid := (br[0] + br[1]) * 0.5
	var place := func(r: Regiment, at: Vector2) -> void:
		r.dest = at
		r.facing = Vector2.UP
		var alive := r.alive_soldiers()
		for i in alive.size():
			alive[i].pos = r.slot_position(i, alive.size())
		r.update_center()
	foot.sort_custom(func(a, b): return a.center.x < b.center.x)
	for k in foot.size():
		@warning_ignore("integer_division")
		var group := k * br.size() / maxi(foot.size(), 1) # Moitié gauche → brèche gauche
		var members: Array[int] = []
		for j in foot.size():
			@warning_ignore("integer_division")
			if j * br.size() / maxi(foot.size(), 1) == group:
				members.append(j)
		var pos_in := members.find(k)
		var x: float = br[group] + (pos_in - (members.size() - 1) * 0.5) * 240.0
		place.call(foot[k], Vector2(x, wy + 110.0))
	for k in archers.size():
		place.call(archers[k], Vector2(mid + (k - (archers.size() - 1) * 0.5) * 360.0, wy + 70.0))
	for k in horse.size():
		var x: float = lerpf(br[0], br[1], 0.25 if k % 2 == 0 else 0.75)
		@warning_ignore("integer_division")
		place.call(horse[k], Vector2(x + (k / 2) * 60.0, wy + 300.0))


## Déploie une armée de campagne (liste de {"type", "men"}) : infanterie devant, tireurs derrière,
## montés (archers montés compris) sur les ailes. Les régiments du joueur gardent leur indice dans la liste.
func spawn_army(team: int, list: Array) -> void:
	var cx := WORLD_SIZE.x * 0.5
	var front_y := 1600.0 if team == PLAYER else 400.0
	var back := 130.0 if team == PLAYER else -130.0
	var face := Vector2.UP if team == PLAYER else Vector2.DOWN
	var front: Array[int] = []
	var rear: Array[int] = []
	var wings: Array[int] = []
	for i in list.size():
		var st: Dictionary = UnitTypes.STATS[str(list[i]["type"])]
		if st["mounted"]:
			wings.append(i)
		elif st["ranged"]:
			rear.append(i)
		else:
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
		Traits.apply_to(r, list[i]) # Traits et équipement, avant le rang (moral maximal)
		r.set_rank(CampaignState.rank_of(list[i]))
		if team == PLAYER:
			r.company_index = i


const MAX_ALLY_REGIMENTS := 4 ## Régiments alliés au plus sur le champ
const ALLY_Y := 1720.0 ## Les alliés se déploient derrière les ailes de la compagnie
const ALLY_X := 1250.0 ## ... à cette distance du centre, de part et d'autre


## Régiments des groupes alliés de la carte (contrat « allies » : {"party", "name", "faction",
## "troops": [{"type", "men", "rank"}]}), au plus MAX_ALLY_REGIMENTS, sur les ailes, derrière la
## compagnie. Camp du joueur, marqués « allied » : menés par AlliedAI, pas commandables.
func spawn_allies(list: Array) -> void:
	var placed := 0
	for g in list:
		if not g is Dictionary:
			continue
		var gi := allies.size()
		allies.append(g)
		for t in g.get("troops", []):
			if placed >= MAX_ALLY_REGIMENTS or not t is Dictionary or not UnitTypes.STATS.has(str(t.get("type", ""))):
				continue
			var men := int(t.get("men", 0))
			if men <= 0:
				continue
			var side := -1.0 if placed % 2 == 0 else 1.0
			@warning_ignore("integer_division")
			var x := WORLD_SIZE.x * 0.5 + side * (ALLY_X + (placed / 2) * 240.0)
			var r := add_regiment(PLAYER, str(t["type"]), Vector2(clampf(x, 140.0, WORLD_SIZE.x - 140.0), ALLY_Y), Vector2.UP, men)
			r.allied = true
			r.ally_group = gi
			r.set_rank(clampi(int(t.get("rank", 0)), 0, 2))
			placed += 1
	if placed > 0:
		ally_ai = AlliedAI.new()
		ally_ai.configure(difficulty)


## Nombre de régiments alliés sur le champ.
func allies_count() -> int:
	var n := 0
	for r in regiments:
		if r.allied:
			n += 1
	return n


## Noms des groupes alliés (« la patrouille du Comté et ... »).
func allies_names() -> String:
	var names: Array[String] = []
	for g in allies:
		names.append(str(g.get("name", "des alliés")))
	return " et ".join(names) if not names.is_empty() else "des alliés"


## Bilan de chaque groupe allié : {"party", "before", "survivors", "kills"} (survivants : debout
## ou enfuis), dans l'ordre de allies.
func ally_tally() -> Array:
	var out: Array = []
	for g in allies:
		out.append({"party": int(g.get("party", -1)), "before": 0, "survivors": 0, "kills": 0})
	for r in regiments:
		if not r.allied or r.ally_group < 0 or r.ally_group >= out.size():
			continue
		var t: Dictionary = out[r.ally_group]
		t["before"] += r.soldiers.size()
		t["kills"] += r.kills
		for s in r.soldiers:
			if s.alive or s.fled:
				t["survivors"] += 1
	return out


## Crée un régiment de type (clé de UnitTypes.STATS) ; men > 0 limite son effectif.
func add_regiment(team: int, type: String, at: Vector2, facing: Vector2, men := -1) -> Regiment:
	var r := Regiment.new()
	r.id = regiments.size()
	r.team = team
	r.type = type
	r.stats = UnitTypes.STATS[type]
	r.dest = at
	r.facing = facing
	var count: int = r.stats["count"]
	if men > 0:
		count = mini(men, count)
	if team == ENEMY:
		count = Difficulty.enemy_men(difficulty, count)
		r.morale_mult = Difficulty.value(difficulty, "enemy_morale")
		r.damage_mult = Difficulty.value(difficulty, "enemy_damage")
	r.max_morale = r.stats["morale"] * r.morale_mult
	r.morale = r.max_morale
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


# ---------------------------------------------------------------- Pas de simulation

## Avance la simulation de dt secondes (au plus 0,05 s par appel pour rester stable).
func step(dt: float) -> void:
	if state == State.BATTLE:
		battle_time += dt
		ai.think(self, dt)
		if ally_ai != null:
			ally_ai.think(self, dt)
	rebuild_grid()
	for r in regiments:
		update_regiment(r, dt)
	for s in soldiers:
		if s.alive:
			update_soldier(s, dt)
	if captain != null:
		captain.step(self, dt)
	if siege != null:
		siege.step(self, dt) # Échelles, bélier, tours, place de la ville
	update_arrows(dt)
	update_dust(dt)
	if state == State.BATTLE:
		objective.step(self, dt) # Chronomètre, zone tenue, chariots, fuyards
	cleanup_timer -= dt
	if cleanup_timer <= 0.0:
		cleanup_timer = 1.0
		soldiers = soldiers.filter(func(s): return s.alive)
	check_end()


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


# ---------------------------------------------------------------- Requêtes

func player_regiments() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.team == PLAYER and not r.allied and not r.is_dead() and not r.routing:
			out.append(r)
	return out


func selected_regiments() -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in regiments:
		if r.selected and not r.is_dead() and not r.routing:
			out.append(r)
	return out


## Régiment de team dont un soldat est le plus proche de p (ennemis cachés exclus).
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


func team_strength(team: int) -> int:
	var n := 0
	for r in regiments:
		if r.team == team and not r.routing:
			n += r.alive_n
	return n


func team_label(r: Regiment) -> String:
	if r.allied:
		return "Les " + r.display_name().to_lower() + " alliés"
	if r.team == PLAYER:
		return "Vos " + r.display_name().to_lower()
	return "Les " + r.display_name().to_lower() + " ennemis"


## Vrai si les actions de r doivent rester discrètes (ennemi en embuscade) : ni son ni secousse.
func is_secret(r: Regiment) -> bool:
	return r.team == ENEMY and r.hidden


func message(text: String) -> void:
	message_posted.emit(text)


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

	# On ne poursuit pas les fuyards (sauf les montés, s'ils n'ont pas l'ordre de tenir)
	if r.target != null and (r.target.is_dead() or (r.target.routing and (not r.stats["mounted"] or r.hold_position))):
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
			message("%s se rallient !" % team_label(r))
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

	if state == State.DEPLOY:
		# Déploiement : on se place, on n'attaque personne (et les archers ne tirent pas)
		r.target = null
		r.fire_target = null
		r.holding = false
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
	elif r.center.distance_to(r.dest) < 24.0 and not r.hold_position:
		# Au repos : défend sa position si un ennemi s'approche (sauf ordre de tenir la position)
		var e := nearest_enemy_regiment(r, 110.0, true)
		if e != null and state == State.BATTLE and (siege == null or not terrain.wall_blocks(r.center, e.center)):
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
			message("%s sont épuisés et reprennent le pas." % team_label(r))
	elif r.routing or r.engaged or r.holding or (r.target == null and r.center.distance_to(r.dest) < 24.0):
		r.running = false # Arrivé, au contact ou à portée de tir


## Tireurs : s'arrêtent à portée de leur cible, sinon s'en approchent ; tir à volonté sinon.
func update_archers(r: Regiment, dt: float) -> void:
	var range_px: float = r.stats["range"] * terrain.range_factor(r.center) # Plus loin en hauteur
	if raining:
		range_px *= 0.75
	r.fire_target = null
	if r.stats["skirmish"]:
		update_skirmish(r, dt)
	var evading := r.evading > 0.0 # Décrochage en cours : on tire sans s'arrêter
	if r.target != null:
		var d := r.center.distance_to(r.target.center)
		if d <= range_px:
			r.fire_target = r.target
			if not r.holding and not evading:
				r.holding = true
				r.dest = r.center
				r.facing = (r.target.center - r.center).normalized()
		elif r.hold_position:
			r.holding = false # Cible hors de portée : on ne quitte pas sa place pour la rejoindre
		else:
			r.holding = false
			if r.think <= 0.0 and not evading:
				r.think = 0.5
				var dir := (r.target.center - r.center).normalized()
				r.dest = r.target.center - dir * range_px * 0.85
				r.facing = dir
	elif r.fire_at_will and (evading or (not r.engaged and r.center.distance_to(r.dest) < 24.0)) and state == State.BATTLE:
		# Tir à volonté : sur l'ennemi visible le plus proche (pas sur une mêlée)
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


## Tirailleurs montés (« skirmish ») : quand une troupe de mêlée approche à moins de SKIRMISH_DIST,
## ils décrochent au galop en continuant de tirer (sauf ordre de tenir la position).
func update_skirmish(r: Regiment, dt: float) -> void:
	r.evading = maxf(r.evading - dt, 0.0)
	if r.evading > 0.0 or r.hold_position or state != State.BATTLE:
		return
	var threat: Regiment = null
	var td := UnitTypes.SKIRMISH_DIST
	for o in regiments:
		if o.team == r.team or o.is_dead() or o.routing or o.hidden or o.stats["ranged"]:
			continue
		var d := r.center.distance_to(o.center)
		if d < td:
			td = d
			threat = o
	if threat == null:
		return
	var away := (r.center - threat.center).normalized()
	if away == Vector2.ZERO:
		away = -r.facing
	r.evading = UnitTypes.SKIRMISH_TIME
	r.holding = false
	r.facing = -away
	r.dest = (r.center + away * UnitTypes.SKIRMISH_DIST * 1.2).clamp(Vector2(40, 40), WORLD_SIZE - Vector2(40, 40))


## Facteur des traits reçus de face : le pavois ne protège qu'un régiment qui tient sa place.
func pavise_factor(r: Regiment) -> float:
	var f: float = r.stats["pavise"]
	if f >= 1.0 or r.routing or r.engaged:
		return 1.0
	if r.holding or (r.target == null and r.center.distance_to(r.dest) < 24.0):
		return f
	return 1.0


func start_rout(r: Regiment) -> void:
	r.routing = true
	r.target = null
	r.fire_target = null
	r.selected = false
	r.morale = 0.0
	if r.team == PLAYER:
		message("Vos %s fuient le champ de bataille !" % r.display_name().to_lower())
	else:
		message("Des %s ennemis prennent la fuite !" % r.display_name().to_lower())
	cries_played.emit(r.center, 4)
	for o in regiments:
		if o != r and o.team == r.team and not o.is_dead() and o.center.distance_to(r.center) < 260.0:
			o.morale -= UnitTypes.MORALE_ROUT_NEARBY


# ---------------------------------------------------------------- Soldats

func update_soldier(s: Soldier, dt: float) -> void:
	var r := s.regiment
	s.cooldown -= dt
	s.retarget -= dt
	s.flash = maxf(s.flash - dt, 0.0)
	s.attack_anim = maxf(s.attack_anim - dt, 0.0)
	s.moving = false

	var speed: float = r.stats["speed"] * UnitTypes.FORMATION_SPEED[r.formation] * r.speed_mult
	speed *= UnitTypes.fatigue_factor(r.stamina, UnitTypes.EXHAUSTED_SPEED)
	if r.running:
		speed *= UnitTypes.RUN_SPEED
	if is_in_forest(s.pos):
		speed *= float(r.stats["forest_speed"])
	if raining:
		speed *= 0.9

	if r.routing:
		var edge_y := WORLD_SIZE.y + 80.0 if r.team == PLAYER else -80.0
		move_towards(s, Vector2(s.pos.x, edge_y), speed * 1.15, dt)
		kick_dust(s, dt)
		if s.pos.y > WORLD_SIZE.y + 40.0 or s.pos.y < -40.0:
			s.alive = false
			s.fled = true
		separate(s)
		return

	if s.foe != null and not s.foe.alive:
		s.foe = null
	if state == State.DEPLOY:
		s.foe = null # Déploiement : aucun coup, même au contact de l'ennemi
	elif s.retarget <= 0.0:
		s.retarget = 0.25 + rng.randf() * 0.15
		var radius := 24.0
		if r.target != null and not r.stats["ranged"]:
			radius = 80.0
		s.foe = find_foe(s, radius)
	if r.evading > 0.0:
		s.foe = null # Les tirailleurs qui décrochent ne s'attardent pas au contact

	# Tenir la position : on frappe ce qui est à portée, sans quitter le rang pour aller au-devant
	var stay := r.hold_position and r.target == null
	if s.foe != null and stay and s.pos.distance_to(s.foe.pos) > float(r.stats["reach"]):
		s.foe = null

	if s.foe != null:
		var d := s.pos.distance_to(s.foe.pos)
		var reach: float = r.stats["reach"]
		if d > reach:
			move_towards(s, s.foe.pos, speed, dt)
			s.momentum = minf(s.momentum + dt * 0.8, 1.0)
			kick_dust(s, dt)
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
			kick_dust(s, dt)
		else:
			s.momentum = maxf(s.momentum - dt, 0.0)
		# Les tirailleurs montés tirent aussi en marchant (moins précis, voir fire_arrow)
		if r.stats["ranged"] and r.fire_target != null and s.cooldown <= 0.0 and (d < 12.0 or r.stats["skirmish"]) and state != State.DEPLOY:
			fire_arrow(s, r.fire_target)
			s.cooldown = float(r.stats["reload"]) * rng.randf_range(0.8, 1.25)
	separate(s)


func move_towards(s: Soldier, goal: Vector2, speed: float, dt: float) -> void:
	var rad: float = s.regiment.stats["radius"]
	if siege != null:
		goal = siege.route(s, goal) # Porteurs du bélier et des échelles
	goal = terrain.route(s.pos, goal, rad) # Brèche à franchir, ou but ramené hors d'une maison
	var v := goal - s.pos
	var l := v.length()
	if l < 0.01:
		return
	var dir := v / l
	speed *= terrain.speed_factor(s.pos, dir, s.regiment.type) # Eau, montée
	var step_len := minf(speed * dt, l)
	s.move_dir = terrain.steer(s.pos, dir, rad, goal) # Longe maisons et pieux
	s.pos += s.move_dir * step_len
	s.moving = true
	s.anim += dt * (8.0 * UnitTypes.RUN_SPEED if s.regiment.running else 8.0)


## Poussière sous les sabots d'un cavalier au galop (ou à la course, ou en fuite).
## Utilise le hasard global pour ne pas modifier les jets de dés de la simulation.
func kick_dust(s: Soldier, dt: float) -> void:
	var r := s.regiment
	if not r.stats["mounted"] or dust.size() >= MAX_DUST:
		return
	if not (r.running or r.routing or s.momentum > 0.5):
		return
	if r.hidden or is_in_forest(s.pos):
		return # Pas de nuage qui trahirait une embuscade
	if randf() > dt * 5.0:
		return
	var back := -s.move_dir
	var p := s.pos + back * randf_range(3.0, 7.0) + Vector2(randf_range(-4, 4), randf_range(-1, 1))
	var v := back * randf_range(6.0, 16.0) + Vector2(randf_range(-6, 6), randf_range(-10, -3))
	var life := randf_range(0.5, 0.9)
	dust.append([p, v, life, life, 2.0 if randf() < 0.6 else 3.0])


func update_dust(dt: float) -> void:
	var keep := []
	for d in dust:
		d[2] -= dt
		if d[2] > 0.0:
			d[0] += d[1] * dt
			d[1] *= 1.0 - minf(dt * 2.5, 1.0) # Freinée par l'air
			keep.append(d)
	dust = keep


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
	s.pos = terrain.push_out(s.pos.clamp(Vector2(-120, -120), WORLD_SIZE + Vector2(120, 120)), rad)


func find_foe(s: Soldier, radius: float) -> Soldier:
	var best: Soldier = null
	var bd := INF
	var prefer := s.regiment.target
	for o in soldiers_near(s.pos, radius):
		if o.regiment.team == s.regiment.team:
			continue
		if terrain.wall_blocks(s.pos, o.pos):
			continue # De l'autre côté de la palissade
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


## Coup de mêlée de a sur b : type contre type, hauteur, embuscade, flanc ou dos, charge, fatigue.
func strike(a: Soldier, b: Soldier) -> void:
	var ar := a.regiment
	var br := b.regiment
	var dmg: float = float(ar.stats["damage"]) * UnitTypes.bonus(ar.type, br.type)
	dmg *= terrain.height_damage(a.pos, b.pos) # Frapper d'en haut

	# Embuscade : la première attaque d'un régiment caché terrifie la cible
	if ar.hidden:
		ar.hidden = false
		ar.revealed = 5.0
		br.morale -= UnitTypes.MORALE_AMBUSH
		message("Embuscade !")
		feat.emit("ambush", ar, br)

	# Attaque de flanc ou de dos (un carré n'a ni flanc ni dos) ; les inébranlables s'en émeuvent moins
	var calm := 0.5 if br.stats["steadfast"] else 1.0
	match hit_side(a.pos, b.pos, br):
		HIT_REAR:
			dmg *= 2.0
			br.morale -= UnitTypes.MORALE_REAR_HIT * calm
		HIT_FLANK:
			dmg *= 1.4
			br.morale -= UnitTypes.MORALE_FLANK_HIT * calm

	# Charge des montés (pas des tirailleurs, qui n'ont pas de lance)
	if ar.stats["mounted"] and not ar.stats["skirmish"]:
		dmg *= 1.0 + a.momentum * UnitTypes.CHARGE_BONUS
		if a.momentum > 0.5:
			if br.formation == Regiment.Formation.SQUARE:
				feat.emit("charge_on_square", ar, br)
			br.morale -= UnitTypes.MORALE_CHARGE_HIT * (0.5 if br.stats["braces"] else 1.0) * calm
			if not br.stats["steadfast"]:
				b.pos += (b.pos - a.pos).normalized() * 6.0 # Le choc fait reculer (sauf les inébranlables)
			if not is_secret(ar):
				impact.emit(b.pos, 0.07 * a.momentum)
			# Les piques plantées blessent les chevaux qui chargent
			if br.stats["braces"]:
				damage(a, UnitTypes.BRACE_DAMAGE, b)
		a.momentum = 0.0

	if br.routing:
		dmg *= 1.5
	dmg *= UnitTypes.fatigue_factor(ar.stamina, UnitTypes.EXHAUSTED_DAMAGE) * ar.rank_damage()
	dmg *= rng.randf_range(0.7, 1.3)
	a.attack_dur = 0.3
	a.attack_anim = a.attack_dur
	if not is_secret(ar):
		sound_played.emit("clash" if br.stats["armored"] and rng.randf() < 0.6 else "sword", b.pos)
	damage(b, dmg, a)


func damage(s: Soldier, amount: float, source: Soldier) -> void:
	if not s.alive:
		return
	s.hp -= amount
	s.flash = 0.12
	if not is_secret(s.regiment) and (source == null or not is_secret(source.regiment)):
		hit.emit(s.pos, s.pos if source == null else source.pos)
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
		if not is_secret(r):
			sound_played.emit("death", s.pos)
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
	if s.moving and s.regiment.stats["skirmish"]:
		spread *= UnitTypes.SKIRMISH_SPREAD # Tir en marchant (tirailleurs montés)
	var aim := t.pos + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
	arrows.append({
		"from": s.pos + Vector2(0, -8), "to": aim, "t": 0.0, "dur": 0.5 + dist / 440.0,
		"dmg": float(s.regiment.stats["ranged_damage"]) * UnitTypes.fatigue_factor(s.regiment.stamina, UnitTypes.EXHAUSTED_DAMAGE) * s.regiment.rank_damage(),
		"src": s.regiment, # Pour compter les ennemis tués par les flèches
		"pierce": float(s.regiment.stats["pierce"]), # Carreaux d'arbalète : ignorent une part de l'armure
		"h": dist * 0.25,
	})
	s.regiment.revealed = maxf(s.regiment.revealed, 2.0)
	s.attack_dur = 0.35
	s.attack_anim = s.attack_dur
	if not is_secret(s.regiment):
		sound_played.emit("bow", s.pos)


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
		sound_played.emit("swish", a["to"]) # Flèche perdue : sifflement
		return
	var victim: Soldier = hits[0]
	if is_in_forest(victim.pos) and rng.randf() < 0.5:
		return # Les arbres arrêtent la flèche
	if terrain.wall_shelters(a.get("from", a["to"]), victim.pos) and rng.randf() < Terrain.WALL_COVER:
		return # Les pieux de la palissade arrêtent la flèche
	var vr := victim.regiment
	var armor := lerpf(float(vr.stats["arrow_armor"]), 1.0, float(a.get("pierce", 0.0)))
	var dmg: float = a["dmg"] * armor
	var morale_hit := UnitTypes.MORALE_ARROW_HIT
	var from: Vector2 = a.get("from", a["to"])
	var shield := pavise_factor(vr)
	if shield < 1.0 and hit_side(from, victim.pos, vr) == HIT_FRONT:
		dmg *= shield # Le trait se fiche dans le pavois
		morale_hit *= 0.5
	vr.morale -= morale_hit
	damage(victim, dmg * rng.randf_range(0.7, 1.3), null)
	var src: Regiment = a.get("src")
	if src != null and not victim.alive and src.team != victim.regiment.team:
		src.kills += 1


# ---------------------------------------------------------------- Fin de bataille

## Lance la bataille (fin du déploiement).
func start() -> void:
	state = State.BATTLE
	message("La bataille commence !")


## Fin de bataille d'après l'objectif (battle_objectives.gd) : par défaut, victoire quand l'ennemi
## n'a plus de régiment debout, défaite dans le cas inverse ; sinon tenir, escorter, prendre, poursuivre.
func check_end() -> void:
	if state != State.BATTLE:
		return
	var siege_end := siege.outcome(self) if siege != null else -1 # Ville prise, ou défense tenue
	if siege_end >= 0:
		state = siege_end as State
		ended.emit()
		return
	match objective.check(self):
		BattleObjectives.WON:
			state = State.VICTORY
		BattleObjectives.LOST:
			state = State.DEFEAT
		_:
			return
	message(objective.end_message)
	ended.emit()


## Retraite ordonnée : la bataille est perdue, mais seuls les hommes au contact de l'ennemi
## risquent d'être rattrapés (un sur deux) ; tous les autres rejoignent la compagnie.
## Possible dès le déploiement (menu pause). Renvoie false si la bataille est déjà finie.
func order_retreat() -> bool:
	if state != State.BATTLE and state != State.DEPLOY:
		return false
	retreated = true
	retreat_caught = 0
	for r in regiments:
		if r.team != PLAYER or r.routing or r.allied:
			continue
		for s in r.soldiers:
			if s.alive and s.foe != null and s.foe.alive and s.pos.distance_to(s.foe.pos) < 30.0 and rng.randf() < 0.5:
				s.alive = false
				retreat_caught += 1
		r.update_center()
	state = State.DEFEAT
	message("Vous sonnez la retraite : la compagnie décroche (%d hommes rattrapés)." % retreat_caught)
	ended.emit()
	return true


## Pertes de la bataille : une ligne par régiment du joueur (effectif avant, debout, en fuite, morts,
## ennemis tués) et les totaux des deux camps. Voir Battle.build_end_report pour le bilan complet.
func casualties() -> Dictionary:
	var rows: Array[Dictionary] = []
	var t := {"player_before": 0, "player_after": 0, "player_dead": 0, "player_fled": 0, "player_healed": 0,
		"enemy_before": 0, "enemy_dead": 0, "enemy_fled": 0, "enemy_standing": 0, "ally_before": 0, "ally_dead": 0}
	for r in regiments:
		var standing := 0
		var fled := 0
		var dead := 0
		for s in r.soldiers:
			if s.alive and not r.routing:
				standing += 1
			elif s.alive or s.fled:
				fled += 1 # En fuite ou sorti du champ : il rejoint sa compagnie
			else:
				dead += 1
		if r.team == ENEMY:
			t["enemy_before"] += r.soldiers.size()
			t["enemy_dead"] += dead
			t["enemy_fled"] += fled
			t["enemy_standing"] += standing
			continue
		if r.allied: # Les alliés ont leur propre bilan (ally_tally)
			t["ally_before"] += r.soldiers.size()
			t["ally_dead"] += dead
			continue
		rows.append({"index": rows.size(), "name": r.display_name(), "type": r.type, "rank": r.rank, "rank_after": r.rank,
			"before": r.soldiers.size(), "standing": standing, "fled": fled, "dead": dead, "healed": 0,
			"after": standing + fled, "kills": r.kills, "xp": 0.0, "promoted": false,
			"company_index": r.company_index})
	return {"rows": rows, "totals": t}


## Survivants (debout ou enfuis) et ennemis tués par régiment de la compagnie (indices de campagne).
func company_tally(size: int) -> Dictionary:
	var survivors := []
	survivors.resize(size)
	survivors.fill(0)
	var kills := survivors.duplicate()
	for r in regiments:
		if r.team != PLAYER or r.company_index < 0:
			continue
		kills[r.company_index] += r.kills
		for s in r.soldiers:
			if s.alive or s.fled:
				survivors[r.company_index] += 1
	return {"survivors": survivors, "kills": kills}
