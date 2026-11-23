class_name Siege
extends RefCounted
## Mécanique d'un vrai siège (terrains « town_assault » et « town_defense », voir siege_terrain.gd) :
##  - l'assaillant porte un bélier et des échelles (donnés au déploiement à ses régiments à pied) ;
##    le bélier enfonce la porte, une échelle se dresse quand ses porteurs arrivent au pied du rempart ;
##  - on monte lentement à l'échelle ; la garnison au débouché la repousse si personne ne le tient
##    (les grimpeurs tombent, l'échelle peut se briser) ; les tours tirent sur l'assaillant ;
##  - sur le chemin de ronde, on tire plus loin, on frappe d'en haut et le parapet arrête des flèches
##    (via Terrain.height et Terrain.wall_shelters) ;
##  - le bélier avance lentement et ses porteurs, bras pris, craignent les flèches ; s'ils tombent,
##    le bélier reste sur place et un autre régiment à pied peut le reprendre ;
##  - au-dessus de la porte, la garnison (au moins DROP_GUARDS hommes) verse l'huile bouillante
##    (OIL_POTS chaudrons) et jette des pierres sur ceux qui frappent la porte ;
##  - frapper vers le haut (de l'échelle vers le chemin de ronde) porte moins (WALL_GUARD) ;
##  - victoire : l'assaillant prend la ville s'il tient la place HOLD_TIME secondes ; en défense,
##    le joueur gagne s'il tient DEFENSE_TIME secondes (ou s'il repousse l'assaut, règle ordinaire).
##
## Points d'appel (courts) : BattleSim.generate_world (création), Battle._ready (deploy), BattleSim.step,
## BattleSim.move_towards (route des porteurs), BattleSim.check_end (outcome), BattleSim.deploy_top,
## BattleRenderer._draw (draw_ground, add_items, draw_air, lift) et EnemyAI.think_siege.
## Brancher sur un système d'objectifs : outcome() renvoie déjà l'issue et reason la raison
## (« plaza » ou « time ») ; un objectif « prendre la ville » ou « tenir la ville » n'a qu'à l'appeler.

const ASSAULT := "town_assault"
const DEFENSE := "town_defense"
const KINDS := [ASSAULT, DEFENSE]
const GATE_HP := 100.0
const RAM_DPS := 3.4 ## Dégâts par seconde du bélier, porteurs au complet (10 hommes et plus)
const RAM_REACH := 64.0 ## Distance du bélier à la porte pour frapper
const LADDERS := 3 ## Échelles au plus (une par régiment porteur)
const RAISE_TIME := 3.0 ## Secondes pour dresser une échelle
const RERAISE_TIME := 6.0 ## Délai avant de redresser une échelle repoussée
const PLANT_DIST := 70.0 ## Les porteurs dressent l'échelle à cette distance de son pied
const PUSH_RATE := 0.1 ## Progression du repoussage par défenseur au débouché et par seconde (5 au plus)
const PUSH_REACH := 30.0
const BREAK_CHANCE := 0.35 ## Une échelle repoussée se brise une fois sur trois
const FALL_DAMAGE := 26.0 ## Dégâts d'une chute d'échelle
const TOWER_RANGE := 300.0
const TOWER_RELOAD := 2.0
const TOWER_DAMAGE := 2.4
const HOLD_TIME := 20.0 ## Secondes à tenir la place pour prendre la ville
const HOLD_MIN := 6 ## Soldats nécessaires sur la place
const DEFENSE_TIME := 300.0 ## Défense : la ville est sauvée après ce temps de bataille
const STAGING := 380.0 ## L'assaillant attend hors de portée des tours, à cette distance du rempart
const RAM_SPEED := 0.6 ## Vitesse des porteurs du bélier
const RAM_ARROW := 1.35 ## Dégâts des flèches sur les porteurs du bélier (pas de bouclier levé)
const RAM_PICKUP := 45.0 ## Distance pour reprendre un bélier abandonné
const WALL_GUARD := 0.4 ## Coups portés vers le haut : -40 % par unité de hauteur (Terrain.height_damage)
const GATE_POST := 44.0 ## Profondeur du poste de l'infanterie qui tient la porte (et le dessus de la porte)
const DROP_GUARDS := 3 ## Défenseurs au-dessus de la porte pour verser l'huile ou jeter des pierres
const GUARD_REACH := 120.0 ## Distance de la porte où ils doivent se tenir
const DROP_REACH := 70.0 ## Les assaillants à cette distance du point d'impact du bélier sont visés
const OIL_POTS := 2 ## Chaudrons d'huile bouillante
const OIL_RELOAD := 14.0
const OIL_DAMAGE := 22.0
const OIL_RADIUS := 34.0
const OIL_MORALE := 10.0
const STONE_RELOAD := 4.5
const STONE_DAMAGE := 11.0
const STONE_RADIUS := 14.0

var town: SiegeTerrain
var attacker := BattleSim.ENEMY ## Camp qui donne l'assaut
var defender := BattleSim.PLAYER
var gate_hp := GATE_HP
var ram_bearer: Regiment = null
var ram_swing := 0.0 ## Animation du bélier (temps simulé)
var ladders: Array[Dictionary] = [] ## {"owner", "x", "state", "t", "push", "falls"}
## state : « carried » (portée), « raising », « up » (dressée), « down » (repoussée), « broken », « lost »
var hold := 0.0 ## Prise de la place par l'assaillant, de 0 à 1
var tower_cd: Array[float] = []
var climbers := {} ## Soldats de l'assaillant arrivés en haut d'une échelle
var raised := 0 ## Échelles dressées (en tout)
var pushed := 0 ## Échelles repoussées
var reason := "" ## Raison de la fin : « plaza » (ville prise), « time » (défense tenue)
var sound_cd := 0.0
var ram_dropped := false ## Bélier abandonné devant la ville (ses porteurs sont morts ou en fuite)
var ram_pos := Vector2.ZERO ## Où se trouve le bélier (porté ou abandonné)
var machicolations := true ## Huile et pierres au-dessus de la porte
var oil_left := OIL_POTS
var oil_cd := 3.0
var stone_cd := 1.5
var oil_poured := 0
var stones_dropped := 0
var drops: Array[Dictionary] = [] ## Pour le dessin : {"at", "kind" (« oil »/« stone »), "t0" (battle_time)}

# Rendu (construit à la première image, hors de la simulation)
var ground_tex: ImageTexture = null
var face_tex: ImageTexture = null
var top_tex: ImageTexture = null
var merlon_tex: ImageTexture = null
var side_tex: ImageTexture = null


func _init(t: SiegeTerrain) -> void:
	town = t
	attacker = BattleSim.ENEMY if t.defense else BattleSim.PLAYER
	defender = 1 - attacker
	for i in t.towers.size():
		tower_cd.append(1.0 + i * 0.3)


static func is_siege_kind(kind: String) -> bool:
	return kind in KINDS


## Terrain d'un contrat de siège de la campagne (« assault » ou « defense »).
static func terrain_for(contract_kind: String) -> String:
	return DEFENSE if contract_kind == "defense" else ASSAULT


# ---------------------------------------------------------------- Déploiement

## Garnison postée (tireurs sur le chemin de ronde, infanterie derrière la porte et le rempart,
## montés sur la place) ; bélier et échelles donnés aux régiments à pied de l'assaillant.
func deploy(b: BattleSim) -> void:
	var shooters: Array[Regiment] = []
	var foot: Array[Regiment] = []
	var horse: Array[Regiment] = []
	var att_foot: Array[Regiment] = []
	for r in b.regiments:
		if r.team == attacker:
			if not r.stats["ranged"] and not r.stats["mounted"]:
				att_foot.append(r)
			continue
		if r.stats["mounted"]:
			horse.append(r)
		elif r.stats["ranged"]:
			shooters.append(r)
		else:
			foot.append(r)
	var face := Vector2(0, town.out_dir)
	var posts := town.walk_posts(shooters.size())
	shooters.sort_custom(func(a, c): return a.center.x < c.center.x)
	for k in shooters.size():
		place(shooters[k], posts[k], face)
	foot.sort_custom(func(a, c): return a.stats["hp"] > c.stats["hp"])
	for k in foot.size():
		var x := town.gate_x
		if k > 0:
			var side := -1.0 if k % 2 == 1 else 1.0
			@warning_ignore("integer_division")
			x = town.gate_x + side * (360.0 + ((k - 1) / 2) * 320.0)
		# Le premier (le plus solide) tient la porte et le dessus de la porte (huile, pierres)
		place(foot[k], town.at_depth(clampf(x, SiegeTerrain.X0 + 120.0, SiegeTerrain.X1 - 120.0), 100.0 if k > 0 else GATE_POST), face)
	for k in horse.size():
		place(horse[k], town.plaza + Vector2((k - (horse.size() - 1) * 0.5) * 110.0, 0), face)

	# Équipement de l'assaillant : le bélier au régiment le plus solide, les échelles aux suivants
	ram_bearer = null
	ram_dropped = false
	ladders.clear()
	att_foot.sort_custom(func(a, c): return float(a.stats["hp"]) * (1.5 if a.stats["armored"] else 1.0) > float(c.stats["hp"]) * (1.5 if c.stats["armored"] else 1.0))
	if att_foot.size() >= 2:
		ram_bearer = att_foot.pop_front()
		ram_pos = ram_bearer.center
	var by_x := att_foot.slice(0, LADDERS)
	by_x.sort_custom(func(a, c): return a.center.x < c.center.x)
	for r in by_x:
		ladders.append({"owner": r, "x": -1.0, "state": "carried", "t": 0.0, "push": 0.0, "falls": 0})
	if attacker == BattleSim.PLAYER:
		var names: Array[String] = []
		for l in ladders:
			names.append((l["owner"] as Regiment).display_name().to_lower())
		var txt := "Assaut : "
		if ram_bearer != null:
			txt += "vos %s portent le bélier (lents et exposés aux flèches : envoyez-les à la porte), " % ram_bearer.display_name().to_lower()
		if not names.is_empty():
			txt += "vos %s des échelles (menez-les au pied du rempart). " % ", ".join(names)
		b.message(txt + "Prenez la place de la ville et tenez-la %d s." % int(HOLD_TIME))
	else:
		b.message("Défense : garnissez les murs. Tenez %d min, ou repoussez l'assaut. Si l'ennemi tient la place %d s, la ville tombe." % [int(DEFENSE_TIME / 60.0), int(HOLD_TIME)])
		b.message("Gardez %d hommes au-dessus de la porte : ils versent l'huile et jettent des pierres sur le bélier." % DROP_GUARDS)


func place(r: Regiment, at: Vector2, face: Vector2) -> void:
	r.dest = at
	r.facing = face
	var alive := r.alive_soldiers()
	for i in alive.size():
		alive[i].pos = r.slot_position(i, alive.size())
	r.update_center()


## Limite haute de la zone de déploiement : en défense, juste derrière le rempart.
func deploy_top(default_top: float) -> float:
	if town.defense:
		return town.front_y + SiegeTerrain.WALL_T * 0.5 + 6.0
	return default_top


# ---------------------------------------------------------------- Requêtes

## Rôle de siège d'un régiment : « ram » (bélier, porte encore debout), « ladder » (échelle pas
## encore dressée) ou "".
func role(r: Regiment) -> String:
	if r != null and r == ram_bearer and not town.gate_open:
		return "ram"
	var l := ladder_of(r)
	if not l.is_empty() and l["state"] in ["carried", "raising", "down"]:
		return "ladder"
	return ""


func ladder_of(r: Regiment) -> Dictionary:
	for l in ladders:
		if l["owner"] == r:
			return l
	return {}


## Abscisse de l'échelle (choisie la première fois d'après la position des porteurs).
func ladder_x(l: Dictionary) -> float:
	if float(l["x"]) < 0.0:
		l["x"] = town.ladder_spot((l["owner"] as Regiment).center.x, taken_xs(l))
	return float(l["x"])


func taken_xs(except: Dictionary) -> Array:
	var out := []
	for l in ladders:
		if l != except and float(l["x"]) >= 0.0 and l["state"] not in ["broken", "lost"]:
			out.append(float(l["x"]))
	return out


## Facteur de vitesse d'un régiment (les porteurs du bélier sont lents).
func speed_factor(r: Regiment) -> float:
	return RAM_SPEED if r == ram_bearer and not town.gate_open else 1.0


## Facteur de dégâts d'une flèche sur un soldat du régiment r.
func arrow_factor(r: Regiment) -> float:
	return RAM_ARROW if r == ram_bearer and not town.gate_open else 1.0


## Régiment à pied de l'assaillant le mieux placé pour reprendre le bélier abandonné (null sinon).
func ram_claimant(b: BattleSim) -> Regiment:
	if not ram_dropped or town.gate_open:
		return null
	var best: Regiment = null
	var bd := INF
	for r in b.regiments:
		if r.team != attacker or not can_carry_ram(r):
			continue
		var d := r.center.distance_to(ram_pos)
		if d < bd:
			bd = d
			best = r
	return best


## Vrai si r peut reprendre le bélier (à pied, assez nombreux, sans échelle à porter).
func can_carry_ram(r: Regiment) -> bool:
	return alive_reg(r) and not r.stats["ranged"] and not r.stats["mounted"] and r.alive_n >= 4 and role(r) == ""


## Emplacement d'échelle choisi par l'IA pour les porteurs r : loin des autres échelles (on répartit
## l'assaut), là où la garnison est clairsemée sur le chemin de ronde, sans trop de détour.
func best_ladder_spot(b: BattleSim, r: Regiment) -> float:
	var l := ladder_of(r)
	var taken := taken_xs(l)
	var best := -1.0
	var bs := INF
	var x := SiegeTerrain.X0 + 60.0
	while x < SiegeTerrain.X1 - 60.0:
		if town.ladder_ok(x, taken):
			var score := absf(x - r.center.x) * 0.35
			for o in taken:
				score += maxf(300.0 - absf(x - float(o)), 0.0) * 2.0 # Pas deux échelles côte à côte
			for s in b.soldiers_near(town.ladder_top(x), 170.0):
				if s.regiment.team == defender and not s.regiment.routing:
					score += 14.0
			if score < bs:
				bs = score
				best = x
		x += 24.0
	return best if best >= 0.0 else town.ladder_spot(r.center.x, taken)


func ladders_up() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in ladders:
		if l["state"] == "up":
			out.append(l)
	return out


## Vrai s'il existe un passage dans le rempart (porte enfoncée ou échelle dressée).
func has_opening() -> bool:
	return not town.openings.is_empty()


static func alive_reg(r: Regiment) -> bool:
	return r != null and not r.is_dead() and not r.routing


## Porteurs du bélier ou d'une échelle : s'ils veulent entrer, ils vont d'abord à la porte ou au
## pied de leur échelle. Appelé par BattleSim.move_towards pour chaque soldat.
func route(s: Soldier, goal: Vector2) -> Vector2:
	var r := s.regiment
	if r.team != attacker or r.routing or not town.inside(goal) or town.inside(s.pos, SiegeTerrain.WALL_T):
		return goal
	var off := (s.slot_pos - r.dest).limit_length(30.0)
	match role(r):
		"ram":
			return town.ram_spot() + off.limit_length(14.0)
		"ladder":
			return town.ladder_foot(ladder_x(ladder_of(r))) + off
	return goal


## Décalage vertical du dessin d'un soldat en p (sur le chemin de ronde, à mi-échelle).
func lift(p: Vector2) -> float:
	return town.height(p) * SiegeTerrain.WALL_H


# ---------------------------------------------------------------- Pas de simulation

func step(b: BattleSim, dt: float) -> void:
	if b.state != BattleSim.State.BATTLE:
		return
	sound_cd -= dt
	var changed := false
	for l in ladders:
		changed = update_ladder(b, l, dt) or changed
	changed = update_ram(b, dt) or changed
	if changed:
		refresh(b)
	update_machicolations(b, dt)
	update_towers(b, dt)
	update_plaza(b, dt)


## Met à jour les ouvertures du rempart (et les obstacles du terrain).
func refresh(b: BattleSim) -> void:
	var xs := []
	for l in ladders_up():
		xs.append(float(l["x"]))
	town.set_openings(xs)
	b.terrain.refresh_obstacles()


## Renvoie vrai si l'échelle vient d'être dressée ou renversée.
func update_ladder(b: BattleSim, l: Dictionary, dt: float) -> bool:
	var owner: Regiment = l["owner"]
	var mine := attacker == BattleSim.PLAYER
	match str(l["state"]):
		"carried":
			if not alive_reg(owner):
				l["state"] = "lost"
				return false
			var foot := town.ladder_foot(ladder_x(l))
			var d := town.depth(owner.center)
			var at_wall := d > -PLANT_DIST - 20.0 and d < 0.0 and town.ladder_ok(owner.center.x, taken_xs(l))
			if at_wall and owner.center.distance_to(foot) > PLANT_DIST:
				l["x"] = town.ladder_spot(owner.center.x, taken_xs(l)) # Au pied du mur ailleurs : on la dresse là
				foot = town.ladder_foot(float(l["x"]))
			if owner.center.distance_to(foot) < PLANT_DIST:
				l["state"] = "raising"
				l["t"] = RAISE_TIME
		"raising":
			if not alive_reg(owner):
				l["state"] = "lost"
				return false
			if owner.center.distance_to(town.ladder_foot(float(l["x"]))) > PLANT_DIST + 50.0:
				l["state"] = "carried"
				return false
			l["t"] = float(l["t"]) - dt
			if float(l["t"]) <= 0.0:
				l["state"] = "up"
				l["push"] = 0.0
				raised += 1
				b.message(("Vos %s dressent une échelle contre le rempart !" if mine else "Les %s ennemis dressent une échelle contre le rempart !") % owner.display_name().to_lower())
				b.sound_played.emit("clash", town.ladder_foot(float(l["x"])))
				return true
		"up":
			return update_push(b, l, dt)
		"down":
			if not alive_reg(owner):
				return false
			l["t"] = float(l["t"]) - dt
			if float(l["t"]) <= 0.0 and owner.center.distance_to(town.ladder_foot(float(l["x"]))) < PLANT_DIST + 40.0:
				l["state"] = "raising"
				l["t"] = RAISE_TIME
	return false


## Échelle dressée : les grimpeurs arrivés en haut la tiennent ; sinon la garnison la repousse.
func update_push(b: BattleSim, l: Dictionary, dt: float) -> bool:
	var x := float(l["x"])
	var top := town.ladder_top(x)
	var defenders := 0
	var holders := 0
	for s in b.soldiers_near(top, PUSH_REACH):
		var r: Regiment = s.regiment
		if r.routing:
			continue
		if r.team == attacker:
			if town.depth(s.pos) > 0.0:
				holders += 1
				climbers[s] = true
		else:
			defenders += 1
	if defenders > 0 and holders == 0:
		l["push"] = float(l["push"]) + dt * PUSH_RATE * mini(defenders, 5)
	else:
		l["push"] = maxf(float(l["push"]) - dt * 0.5, 0.0)
	if float(l["push"]) < 1.0:
		return false
	# Repoussée : ceux qui grimpaient tombent
	for s in b.soldiers_near(Vector2(x, town.front_y), SiegeTerrain.WALL_T):
		if s.regiment.team == attacker and not town.ladder_at(s.pos).is_empty():
			b.damage(s, FALL_DAMAGE, null)
	pushed += 1
	l["falls"] = int(l["falls"]) + 1
	var broken := b.rng.randf() < BREAK_CHANCE
	l["state"] = "broken" if broken else "down"
	l["t"] = RERAISE_TIME
	var who := "La garnison" if attacker == BattleSim.ENEMY else "L'ennemi"
	b.message("%s repousse une échelle%s !" % [who, " et la brise" if broken else ""])
	b.cries_played.emit(Vector2(x, town.front_y), 2)
	return true


## Bélier : ses porteurs, arrivés devant la porte, la frappent jusqu'à ce qu'elle cède.
## Renvoie vrai quand la porte vient de céder.
func update_ram(b: BattleSim, dt: float) -> bool:
	if town.gate_open:
		return false
	var mine := attacker == BattleSim.PLAYER
	if ram_bearer == null:
		if ram_dropped:
			# Bélier abandonné : le premier régiment à pied qui le rejoint le reprend
			for r in b.regiments:
				if r.team == attacker and can_carry_ram(r) and r.center.distance_to(ram_pos) < RAM_PICKUP:
					ram_bearer = r
					ram_dropped = false
					b.message(("Vos %s reprennent le bélier !" if mine else "Les %s ennemis reprennent le bélier !") % r.display_name().to_lower())
					break
		return false
	if not alive_reg(ram_bearer):
		ram_bearer = null
		ram_dropped = true
		b.message("Le bélier est abandonné !" + (" Envoyez un régiment à pied le reprendre." if mine else ""))
		return false
	ram_pos = ram_position()
	var spot := town.ram_spot()
	if ram_bearer.center.distance_to(spot) > RAM_REACH or ram_bearer.alive_n < 3:
		return false
	ram_swing += dt
	gate_hp -= dt * RAM_DPS * minf(ram_bearer.alive_n / 10.0, 1.0)
	if sound_cd <= 0.0:
		sound_cd = 1.3
		b.sound_played.emit("clash", Vector2(town.gate_x, town.front_y))
		b.impact.emit(Vector2(town.gate_x, town.front_y), 0.02)
	if gate_hp > 0.0:
		return false
	gate_hp = 0.0
	town.gate_open = true
	b.message("La porte cède sous le bélier !")
	b.impact.emit(Vector2(town.gate_x, town.front_y), 0.08)
	b.cries_played.emit(Vector2(town.gate_x, town.front_y), 3)
	return true


## Mâchicoulis : si assez de défenseurs se tiennent au-dessus de la porte, ils versent l'huile
## bouillante (rare, en nappe) puis jettent des pierres (souvent, un homme ou deux) sur les assaillants
## massés devant la porte.
func update_machicolations(b: BattleSim, dt: float) -> void:
	var now := b.battle_time
	drops = drops.filter(func(d): return now - float(d["t0"]) < 1.6)
	oil_cd -= dt
	stone_cd -= dt
	if not machicolations or town.gate_open or (oil_cd > 0.0 and stone_cd > 0.0):
		return
	if gate_guards(b) < DROP_GUARDS:
		return
	var spot := town.ram_spot()
	var targets: Array[Soldier] = []
	for s in b.soldiers_near(spot, DROP_REACH):
		if s.regiment.team == attacker and town.depth(s.pos) < 0.0:
			targets.append(s)
	if targets.is_empty():
		return
	# Viser d'abord les porteurs du bélier
	var aim: Soldier = targets[b.rng.randi() % targets.size()]
	for s in targets:
		if s.regiment == ram_bearer:
			aim = s
			break
	if oil_left > 0 and oil_cd <= 0.0 and targets.size() >= 4:
		oil_left -= 1
		oil_cd = OIL_RELOAD
		stone_cd = maxf(stone_cd, 2.0)
		oil_poured += 1
		var hit := {}
		for s in b.soldiers_near(aim.pos, OIL_RADIUS):
			if s.regiment.team == attacker:
				b.damage(s, OIL_DAMAGE * b.rng.randf_range(0.8, 1.2), null)
				hit[s.regiment] = true
		for r: Regiment in hit:
			r.morale -= OIL_MORALE
		drops.append({"at": aim.pos, "kind": "oil", "t0": now})
		var mine := defender == BattleSim.PLAYER
		b.message("%s verse l'huile bouillante sur la porte !" % ("Votre garnison" if mine else "La garnison"))
		b.cries_played.emit(aim.pos, 3)
		return
	if stone_cd <= 0.0:
		stone_cd = STONE_RELOAD * b.rng.randf_range(0.85, 1.15)
		stones_dropped += 1
		var at := aim.pos + Vector2(b.rng.randf_range(-6.0, 6.0), b.rng.randf_range(-6.0, 6.0))
		for s in b.soldiers_near(at, STONE_RADIUS):
			if s.regiment.team == attacker:
				b.damage(s, STONE_DAMAGE * b.rng.randf_range(0.8, 1.2), null)
		drops.append({"at": at, "kind": "stone", "t0": now})
		b.sound_played.emit("clash", at)


## Défenseurs en état au-dessus de la porte (sur le chemin de ronde ou juste derrière la porte).
func gate_guards(b: BattleSim) -> int:
	var n := 0
	for s in b.soldiers_near(gate_top(), GUARD_REACH):
		if s.regiment.team == defender and not s.regiment.routing:
			var d := town.depth(s.pos)
			if d > 0.0 and d < SiegeTerrain.WALL_T * 0.5 + SiegeTerrain.WALK + 40.0:
				n += 1
	return n


## Dessus de la porte, côté ville.
func gate_top() -> Vector2:
	return town.at_depth(town.gate_x, SiegeTerrain.WALL_T * 0.5 + 22.0)


## Les tours tirent sur l'assaillant hors les murs, tant que la garnison les tient.
func update_towers(b: BattleSim, dt: float) -> void:
	for i in town.towers.size():
		tower_cd[i] -= dt
		if tower_cd[i] > 0.0:
			continue
		tower_cd[i] = TOWER_RELOAD * b.rng.randf_range(0.85, 1.15)
		var t := town.towers[i]
		var best: Soldier = null
		var bd := TOWER_RANGE * TOWER_RANGE
		var held := false
		var taken := false
		for s in b.soldiers_near(t, TOWER_RANGE):
			var r: Regiment = s.regiment
			if r.routing:
				continue
			var d: float = s.pos.distance_squared_to(t)
			if r.team == attacker:
				if town.depth(s.pos) > 0.0 and d < 3600.0:
					taken = true
				elif town.depth(s.pos) < -SiegeTerrain.WALL_T and not r.hidden and d < bd:
					bd = d
					best = s
			elif d < 3600.0:
				held = true
		if best == null or (taken and not held):
			continue
		var from := t + Vector2(0, -SiegeTerrain.WALL_H - 14.0)
		var dist := from.distance_to(best.pos)
		var spread := 10.0 * (0.5 + dist / 400.0)
		var aim := best.pos + Vector2(b.rng.randf_range(-spread, spread), b.rng.randf_range(-spread, spread))
		b.arrows.append({"from": from, "to": aim, "t": 0.0, "dur": 0.5 + dist / 440.0, "dmg": TOWER_DAMAGE,
			"src": null, "pierce": 0.0, "h": dist * 0.2})
		b.sound_played.emit("bow", from)


## Place de la ville : l'assaillant la prend s'il y est en force sans garnison pour la lui disputer.
func update_plaza(b: BattleSim, dt: float) -> void:
	var att := 0
	var def := 0
	for s in b.soldiers_near(town.plaza, SiegeTerrain.PLAZA_R):
		if s.regiment.routing:
			continue
		if s.regiment.team == attacker:
			att += 1
		else:
			def += 1
	if att >= HOLD_MIN and def * 3 < att:
		hold = minf(hold + dt / HOLD_TIME, 1.0)
	elif att == 0:
		hold = maxf(hold - dt / HOLD_TIME * 0.5, 0.0)


## Issue du siège, appelée par BattleSim.check_end : -1 (pas encore), sinon State.VICTORY ou
## State.DEFEAT du point de vue du joueur (reason dit pourquoi).
func outcome(b: BattleSim) -> int:
	if hold >= 1.0:
		reason = "plaza"
		if attacker == BattleSim.PLAYER:
			b.message("Vous tenez la place : la ville est prise. Victoire !")
			return BattleSim.State.VICTORY
		b.message("L'ennemi tient la place : la ville est tombée...")
		return BattleSim.State.DEFEAT
	if attacker == BattleSim.ENEMY and b.battle_time >= DEFENSE_TIME:
		reason = "time"
		b.message("Les murs ont tenu : l'ennemi lève le siège. Victoire !")
		return BattleSim.State.VICTORY
	return -1


## Ligne d'état pour le HUD.
func status_text(b: BattleSim) -> String:
	var parts: Array[String] = []
	if town.defense:
		var left := maxf(DEFENSE_TIME - b.battle_time, 0.0)
		parts.append("Tenir %d:%02d" % [floori(left / 60.0), int(left) % 60])
	if not town.gate_open:
		parts.append("Porte %d %%" % int(ceilf(gate_hp)))
		if ram_dropped:
			parts.append("Bélier abandonné")
	else:
		parts.append("Porte enfoncée")
	var up := ladders_up().size()
	if up > 0:
		parts.append("Échelles %d" % up)
	if machicolations and not town.gate_open:
		parts.append("Huile %d" % oil_left)
	if hold > 0.0:
		parts.append("Place %d %%" % int(hold * 100.0))
	return "  ".join(parts)


# ---------------------------------------------------------------- Rendu

const STONE_TOP := Color(0.66, 0.63, 0.57)
const STONE_FACE := Color(0.53, 0.5, 0.46)
const STONE_DARK := Color(0.34, 0.32, 0.3)
const MORTAR := Color(0.42, 0.4, 0.36)
const PLANK := Color(0.47, 0.31, 0.16)
const PLANK_DARK := Color(0.3, 0.19, 0.09)
const IRON := Color(0.3, 0.3, 0.33)
const TOWER_H := SiegeTerrain.WALL_H + 18.0


## Sol de la ville (pavés, grand-rue, place) et ombres des murs, sous tout le reste.
func draw_ground(rd: BattleRenderer) -> void:
	if ground_tex == null:
		build_textures()
	draw_tex(rd, ground_tex, interior_rect())
	# Ombre portée du rempart et des tours vers le bas
	var sh := Color(0, 0, 0, 0.18)
	var fy := town.front_y + SiegeTerrain.WALL_T * 0.5
	if town.defense:
		fy = town.front_y + SiegeTerrain.WALL_T * 0.5 + SiegeTerrain.WALK
	rd.draw_rect(Rect2(SiegeTerrain.X0, fy, SiegeTerrain.X1 - SiegeTerrain.X0, 8), sh)
	for r in town.side_rects:
		rd.draw_rect(Rect2(r.end.x, r.position.y, 6, r.size.y), sh)
	if town.gate_open:
		# Débris de la porte
		var g := Vector2(town.gate_x, town.front_y + town.out_dir * 18.0)
		for k in 7:
			var o := Vector2(sin(k * 7.1) * 26.0, cos(k * 3.3) * 8.0).round()
			rd.draw_rect(Rect2(g + o, Vector2(8 if k % 2 == 0 else 4, 2)), PLANK_DARK)


func interior_rect() -> Rect2:
	var y0 := -40.0 if not town.defense else town.front_y
	var y1 := town.front_y if not town.defense else town.world.y + 40.0
	return Rect2(SiegeTerrain.X0, y0, SiegeTerrain.X1 - SiegeTerrain.X0, y1 - y0)


## Dessine une texture à demi- ou quart de résolution sur rect (pixels agrandis).
static func draw_tex(rd: BattleRenderer, tex: ImageTexture, rect: Rect2) -> void:
	if tex != null:
		rd.draw_texture_rect(tex, rect, false)


## Morceaux de rempart à trier avec les soldats : [y de tri, Callable].
func add_items(items: Array, rd: BattleRenderer) -> void:
	if face_tex == null:
		build_textures()
	var f := town.front_y
	var t2 := SiegeTerrain.WALL_T * 0.5
	if town.defense:
		items.append([f - t2 - 0.5, draw_top.bind(rd)])
		items.append([f - t2 + 0.5, draw_gate.bind(rd)])
		items.append([f + t2 + SiegeTerrain.WALK, draw_face.bind(rd)])
	else:
		items.append([f - t2 - SiegeTerrain.WALK - 0.5, draw_top.bind(rd)])
		items.append([f + t2, draw_face.bind(rd)])
		items.append([f + t2 + 0.1, draw_gate.bind(rd)])
	for i in town.towers.size():
		items.append([town.towers[i].y + SiegeTerrain.TOWER_HALF, draw_tower.bind(rd, i)])
	for r in town.side_rects:
		var y := r.position.y
		while y < r.end.y:
			var h := minf(40.0, r.end.y - y)
			items.append([y + h, draw_side.bind(rd, Rect2(r.position.x, y, r.size.x, h))])
			y += h
	for l in ladders:
		var st := str(l["state"])
		if st in ["up", "raising", "down"] or (st == "broken" and float(l["x"]) >= 0.0):
			var key := f + t2 + 0.2 if not town.defense else f - t2 + 0.3
			if st != "up" and st != "raising":
				key = town.ladder_foot(float(l["x"])).y + town.out_dir * 14.0
			items.append([key, draw_ladder.bind(rd, l)])
		elif st == "carried" and alive_reg(l["owner"]):
			var o: Regiment = l["owner"]
			items.append([o.center.y + 1.0, draw_carried_ladder.bind(rd, o)])
	if ram_bearer != null and alive_reg(ram_bearer) and not town.gate_open:
		var at := ram_position()
		items.append([at.y + 6.0, draw_ram.bind(rd, at)])
	elif ram_dropped and not town.gate_open:
		items.append([ram_pos.y + 6.0, draw_ram.bind(rd, ram_pos)])


## Segments horizontaux du rempart, hors passage de la porte.
func wall_spans() -> Array:
	var a := SiegeTerrain.X0 - SiegeTerrain.WALL_T * 0.5
	var b := SiegeTerrain.X1 + SiegeTerrain.WALL_T * 0.5
	return [[a, town.gate_x - SiegeTerrain.GATE_HALF], [town.gate_x + SiegeTerrain.GATE_HALF, b]]


## Dessus du rempart (parapet et chemin de ronde), avec les merlons côté extérieur en défense.
func draw_top(rd: BattleRenderer) -> void:
	var f := town.front_y
	var t2 := SiegeTerrain.WALL_T * 0.5
	var h := SiegeTerrain.WALL_H
	var y0 := f - t2 - h if town.defense else f - t2 - SiegeTerrain.WALK - h
	var x0 := SiegeTerrain.X0 - t2
	for sp in wall_spans():
		var src := Rect2((sp[0] - x0) * 0.5, 0, (sp[1] - sp[0]) * 0.5, top_tex.get_height())
		rd.draw_texture_rect_region(top_tex, Rect2(sp[0], y0, sp[1] - sp[0], src.size.y * 2.0), src)
		if town.defense:
			var ms := Rect2((sp[0] - x0) * 0.5, 0, (sp[1] - sp[0]) * 0.5, merlon_tex.get_height())
			rd.draw_texture_rect_region(merlon_tex, Rect2(sp[0], y0 - ms.size.y * 2.0, sp[1] - sp[0], ms.size.y * 2.0), ms)


## Face visible du rempart : extérieure en assaut (avec merlons), intérieure en défense.
func draw_face(rd: BattleRenderer) -> void:
	var t2 := SiegeTerrain.WALL_T * 0.5
	var h := SiegeTerrain.WALL_H
	var base := town.front_y + t2 if not town.defense else town.front_y + t2 + SiegeTerrain.WALK
	var x0 := SiegeTerrain.X0 - t2
	for sp in wall_spans():
		var src := Rect2((sp[0] - x0) * 0.5, 0, (sp[1] - sp[0]) * 0.5, face_tex.get_height())
		rd.draw_texture_rect_region(face_tex, Rect2(sp[0], base - h, sp[1] - sp[0], h), src)
		if not town.defense:
			var ms := Rect2((sp[0] - x0) * 0.5, 0, (sp[1] - sp[0]) * 0.5, merlon_tex.get_height())
			rd.draw_texture_rect_region(merlon_tex, Rect2(sp[0], base - h - ms.size.y * 2.0, sp[1] - sp[0], ms.size.y * 2.0), ms)
	# Jambages de la porte
	for sx in [town.gate_x - SiegeTerrain.GATE_HALF - 4.0, town.gate_x + SiegeTerrain.GATE_HALF]:
		rd.draw_rect(Rect2(sx, base - h - 6.0, 4, h + 6.0), STONE_DARK)


## Porte : vantaux de bois cerclés de fer, de plus en plus fendus ; enfoncée, un passage sombre.
func draw_gate(rd: BattleRenderer) -> void:
	var t2 := SiegeTerrain.WALL_T * 0.5
	var h := SiegeTerrain.WALL_H
	var gx := town.gate_x - SiegeTerrain.GATE_HALF
	var w := SiegeTerrain.GATE_HALF * 2.0
	var base := town.front_y + t2 if not town.defense else town.front_y - t2
	if town.gate_open:
		rd.draw_rect(Rect2(gx, base - h, 6, h), PLANK_DARK) # Restes des vantaux
		rd.draw_rect(Rect2(gx + w - 6, base - h + 6, 6, h - 6), PLANK_DARK)
		return
	rd.draw_rect(Rect2(gx, base - h, w, h), PLANK)
	var x := gx
	while x < gx + w:
		rd.draw_rect(Rect2(x, base - h, 1, h), PLANK_DARK)
		x += 6.0
	rd.draw_rect(Rect2(gx, base - h + 4, w, 2), IRON)
	rd.draw_rect(Rect2(gx, base - 6, w, 2), IRON)
	rd.draw_rect(Rect2(town.gate_x - 1, base - h, 2, h), PLANK_DARK)
	# Fentes : une par tranche de 15 points perdus
	var cracks := int((GATE_HP - gate_hp) / 15.0)
	for k in cracks:
		var cx := gx + 6.0 + fmod(k * 23.0, w - 12.0)
		rd.draw_line(Vector2(cx, base - h + 3), Vector2(cx + (4 if k % 2 == 0 else -4), base - 4), Color(0.12, 0.07, 0.03), 1.0)
	if ram_swing > 0.0 and int(ram_swing * 2.0) % 2 == 0 and not town.defense:
		rd.draw_rect(Rect2(gx, base - h, w, h), Color(1, 1, 1, 0.08)) # Choc du bélier


## Tour carrée : face de briques avec archère, dessus dallé, merlons.
func draw_tower(rd: BattleRenderer, i: int) -> void:
	var c := town.towers[i]
	var th := SiegeTerrain.TOWER_HALF
	var side := th * 2.0
	var base := c.y + th
	var face := Rect2(c.x - th, base - TOWER_H, side, TOWER_H)
	rd.draw_rect(Rect2(face.position.x + 4, base - 2, side, 6), Color(0, 0, 0, 0.22))
	var src := Rect2(fmod(c.x, 200.0) * 0.5, 0, th, face_tex.get_height())
	rd.draw_texture_rect_region(face_tex, Rect2(face.position.x, base - TOWER_H, side, SiegeTerrain.WALL_H), src)
	rd.draw_texture_rect_region(face_tex, Rect2(face.position.x, base - SiegeTerrain.WALL_H, side, SiegeTerrain.WALL_H), src)
	rd.draw_rect(Rect2(c.x - 1, base - TOWER_H + 12, 2, 10), Color(0.1, 0.1, 0.12)) # Archère
	var top := Rect2(c.x - th, c.y - th - TOWER_H, side, side)
	rd.draw_rect(top, STONE_TOP)
	rd.draw_rect(top.grow(-6), STONE_TOP.darkened(0.12))
	rd.draw_rect(Rect2(top.position.x, top.end.y - 2, side, 2), STONE_DARK)
	# Merlons sur le pourtour
	var m := 0.0
	while m < side - 1.0:
		rd.draw_rect(Rect2(top.position.x + m, top.position.y - 4, 5, 4), STONE_FACE)
		rd.draw_rect(Rect2(top.position.x + m, top.end.y - 6, 5, 6), STONE_FACE)
		m += 9.0
	for sx in [top.position.x, top.end.x - 4]:
		var k := 0.0
		while k < side - 8.0:
			rd.draw_rect(Rect2(sx, top.position.y + 4 + k, 4, 5), STONE_FACE)
			k += 9.0


## Tronçon de mur latéral (vu d'en haut : son chemin de ronde et ses merlons).
func draw_side(rd: BattleRenderer, r: Rect2) -> void:
	var src := Rect2(0, fmod(r.position.y + 200.0, 200.0) * 0.5, side_tex.get_width(), r.size.y * 0.5)
	rd.draw_texture_rect_region(side_tex, Rect2(r.position.x, r.position.y - SiegeTerrain.WALL_H, r.size.x, r.size.y), src)
	rd.draw_rect(Rect2(r.position.x, r.position.y - SiegeTerrain.WALL_H, 2, r.size.y), STONE_DARK)


## Échelle dressée (contre la face, ou ses montants au-dessus des merlons en défense), en train
## d'être dressée, ou couchée au pied du mur.
func draw_ladder(rd: BattleRenderer, l: Dictionary) -> void:
	var x := float(l["x"])
	var st := str(l["state"])
	var t2 := SiegeTerrain.WALL_T * 0.5
	var h := SiegeTerrain.WALL_H
	if st == "down" or st == "broken":
		var y := town.ladder_foot(x).y + town.out_dir * 10.0
		var len := 22.0 if st == "broken" else 40.0
		rd.draw_rect(Rect2(x - len * 0.5, y - 3, len, 1), PLANK)
		rd.draw_rect(Rect2(x - len * 0.5, y + 2, len, 1), PLANK)
		var k := 0.0
		while k < len:
			rd.draw_rect(Rect2(x - len * 0.5 + k, y - 3, 1, 6), PLANK_DARK)
			k += 5.0
		return
	var k := 1.0
	if st == "raising":
		k = clampf(1.0 - float(l["t"]) / RAISE_TIME, 0.1, 1.0)
	var foot: Vector2
	var top: Vector2
	if town.defense:
		foot = Vector2(x, town.front_y - t2 - h + 4.0)
		top = Vector2(x, town.front_y - t2 - h - 10.0 * k)
	else:
		foot = Vector2(x, town.front_y + t2 + 14.0)
		top = foot.lerp(Vector2(x, town.front_y + t2 - h - 8.0), k)
	for dx in [-5.0, 4.0]:
		rd.draw_rect(Rect2(foot.x + dx, top.y, 1, foot.y - top.y), PLANK)
	var y := top.y + 2.0
	while y < foot.y:
		rd.draw_rect(Rect2(x - 5, y, 10, 1), PLANK_DARK)
		y += 5.0
	if st == "up" and float(l["push"]) > 0.05:
		rd.draw_rect(Rect2(x - 6, top.y - 4, 12 * float(l["push"]), 2), Color(1, 0.3, 0.2, 0.8)) # Repoussée en cours


## Échelle portée par un régiment en marche (sur l'épaule des premiers rangs).
func draw_carried_ladder(rd: BattleRenderer, r: Regiment) -> void:
	var p := (r.center + Vector2(0, -14)).round()
	var d := r.facing.normalized() * 22.0
	rd.draw_line(p - d + Vector2(-2, 0), p + d + Vector2(-2, 0), PLANK, 1.0)
	rd.draw_line(p - d + Vector2(2, 0), p + d + Vector2(2, 0), PLANK, 1.0)
	for k in 7:
		var q := p - d + d * 2.0 * (k / 6.0)
		rd.draw_rect(Rect2(q - Vector2(2, 0), Vector2(5, 1)), PLANK_DARK)


func ram_position() -> Vector2:
	var spot := town.ram_spot()
	if ram_bearer.center.distance_to(spot) < RAM_REACH:
		var swing := sin(ram_swing * TAU / 1.3) * 4.0
		return spot + Vector2(0, town.out_dir * (6.0 + swing))
	return ram_bearer.center


## Bélier sous son toit de planches (tortue), pointe ferrée vers la porte.
func draw_ram(rd: BattleRenderer, at: Vector2) -> void:
	var p := at.round()
	var dir := -town.out_dir # Vers la porte
	rd.draw_rect(Rect2(p.x - 11, p.y - 2, 24, 6), Color(0, 0, 0, 0.22))
	rd.draw_rect(Rect2(p.x - 3, p.y - 20, 6, 30), Color(0.4, 0.27, 0.14)) # Tronc
	rd.draw_rect(Rect2(p.x - 4, p.y - 6 + dir * 16.0, 8, 6), IRON) # Tête de fer
	rd.draw_rect(Rect2(p.x - 10, p.y - 24, 20, 22), PLANK) # Toit
	rd.draw_rect(Rect2(p.x - 10, p.y - 24, 20, 2), PLANK_DARK)
	rd.draw_rect(Rect2(p.x - 10, p.y - 12, 20, 1), PLANK_DARK)
	rd.draw_rect(Rect2(p.x - 10, p.y - 3, 20, 1), PLANK_DARK)


## Par-dessus tout : avancée de la prise de la place, temps à tenir.
func draw_air(rd: BattleRenderer) -> void:
	var col: Color = BattleRenderer.TEAM_COLORS[attacker]
	var p := town.plaza
	rd.draw_arc(p, SiegeTerrain.PLAZA_R, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
	if hold > 0.0:
		rd.draw_arc(p, SiegeTerrain.PLAZA_R, -PI * 0.5, -PI * 0.5 + TAU * hold, 48, Color(col, 0.85), 4.0)
	draw_drops(rd)
	if ram_dropped and not town.gate_open:
		rd.draw_arc(ram_pos, 26.0, 0, TAU, 24, Color(1, 0.85, 0.4, 0.5), 1.0) # Bélier à reprendre


## Huile qui coule et pierres qui tombent du haut de la porte, puis éclaboussure au sol.
func draw_drops(rd: BattleRenderer) -> void:
	var now := rd.sim.battle_time
	var from_y := town.front_y - SiegeTerrain.WALL_H - 6.0
	for d in drops:
		var age := now - float(d["t0"])
		var at: Vector2 = d["at"]
		var fall := clampf(age / 0.35, 0.0, 1.0)
		if str(d["kind"]) == "oil":
			if fall < 1.0:
				var y := lerpf(from_y, at.y, fall)
				rd.draw_rect(Rect2(at.x - 3, from_y, 6, y - from_y), Color(0.55, 0.38, 0.08, 0.85))
			else:
				var k := clampf((age - 0.35) / 1.2, 0.0, 1.0)
				rd.draw_circle(at, OIL_RADIUS * (0.5 + 0.5 * k), Color(0.45, 0.3, 0.06, 0.55 * (1.0 - k)))
				rd.draw_circle(at, OIL_RADIUS * 0.4, Color(0.95, 0.9, 0.8, 0.25 * (1.0 - k))) # Vapeur
		else:
			if fall < 1.0:
				var p := Vector2(at.x, lerpf(from_y, at.y, fall * fall)).round()
				rd.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 5)), STONE_FACE)
				rd.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 1)), STONE_TOP)
			else:
				var k := clampf((age - 0.35) / 1.0, 0.0, 1.0)
				rd.draw_rect(Rect2(at.round() - Vector2(3, 1), Vector2(6, 4)), Color(STONE_FACE, 1.0 - k * 0.6))
				rd.draw_circle(at, 6.0 + 8.0 * k, Color(0.6, 0.55, 0.45, 0.35 * (1.0 - k))) # Poussière


func build_textures() -> void:
	var rng := RandomNumberGenerator.new() # Hasard propre au dessin : ne touche pas la simulation
	rng.seed = 7331
	var t2 := SiegeTerrain.WALL_T * 0.5
	var w := int((SiegeTerrain.X1 - SiegeTerrain.X0 + SiegeTerrain.WALL_T) * 0.5) + 2
	# Face de briques (demi-résolution) : rangs de 3 px, briques de 6 px, joints décalés
	var fh := int(SiegeTerrain.WALL_H * 0.5)
	var face := Image.create_empty(w, fh, false, Image.FORMAT_RGBA8)
	for y in fh:
		for x in w:
			var row := floori(y / 3.0)
			var c := STONE_FACE.darkened(0.04 * ((floori(x / 6.0) + row * 3) % 3))
			if y % 3 == 2 or (x + (3 if row % 2 == 1 else 0)) % 6 == 0:
				c = MORTAR
			if y >= fh - 2:
				c = c.darkened(0.18) # Pied du mur, sali
			face.set_pixel(x, y, c)
	face_tex = ImageTexture.create_from_image(face)
	# Merlons : créneaux de 3 px sur 5 de pas
	var merl := Image.create_empty(w, 3, false, Image.FORMAT_RGBA8)
	for y in 3:
		for x in w:
			merl.set_pixel(x, y, (STONE_FACE.lightened(0.08) if y == 0 else STONE_FACE) if x % 5 < 3 else Color(0, 0, 0, 0))
	merlon_tex = ImageTexture.create_from_image(merl)
	# Dessus : parapet (épaisseur du mur) côté extérieur, dalles du chemin de ronde côté ville
	var th := int((SiegeTerrain.WALL_T + SiegeTerrain.WALK) * 0.5)
	var top := Image.create_empty(w, th, false, Image.FORMAT_RGBA8)
	var para := int(t2)
	for y in th:
		for x in w:
			var c := STONE_TOP
			var from_out := th - 1 - y # Distance au bord extérieur (en bas en assaut)
			if from_out < para:
				c = STONE_TOP.lightened(0.06)
				if from_out == para - 1:
					c = STONE_DARK
			else:
				var fy := floori((from_out - para) / 4.0)
				if (from_out - para) % 4 == 3 or (x + fy * 5) % 9 == 0:
					c = MORTAR.lightened(0.1)
				elif rng.randf() < 0.08:
					c = c.darkened(0.06)
			if y == 0:
				c = STONE_DARK # Bord côté ville
			top.set_pixel(x, y, c)
	if town.defense:
		top.flip_y()
	top_tex = ImageTexture.create_from_image(top)
	# Murs latéraux (vus d'en haut), motif de 200 px qui se répète
	var side := Image.create_empty(int(t2), 200, false, Image.FORMAT_RGBA8)
	for y in 200:
		for x in int(t2):
			var c := STONE_TOP
			if x == 0 or x == int(t2) - 1:
				c = STONE_FACE if y % 5 < 3 else STONE_DARK # Merlons des deux côtés
			elif y % 6 == 5:
				c = MORTAR.lightened(0.1)
			side.set_pixel(x, y, c)
	side_tex = ImageTexture.create_from_image(side)
	# Sol de la ville (quart de résolution) : terre battue, pavés, grand-rue et place dallée
	var ir := interior_rect()
	var gw := int(ir.size.x / 4.0)
	var gh := int(ir.size.y / 4.0)
	var g := Image.create_empty(gw, gh, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.05
	for y in gh:
		for x in gw:
			var wp := ir.position + Vector2(x + 0.5, y + 0.5) * 4.0
			var n := noise.get_noise_2d(x, y)
			var c := Color(0.5, 0.45, 0.37).lerp(Color(0.43, 0.38, 0.31), n * 0.5 + 0.5)
			if (x + y * 3) % 7 == 0:
				c = c.lightened(0.07)
			var street := absf(wp.x - town.gate_x) < 34.0 and town.depth(wp) < town.depth(town.plaza)
			var dp := wp.distance_to(town.plaza)
			if dp < SiegeTerrain.PLAZA_R:
				c = Color(0.64, 0.6, 0.53)
				if x % 5 == 0 or y % 4 == 0:
					c = Color(0.52, 0.48, 0.42)
				if dp < 14.0:
					c = Color(0.35, 0.45, 0.55) if dp < 8.0 else Color(0.45, 0.44, 0.42) # Puits
			elif street:
				c = Color(0.6, 0.55, 0.47) if (x + y) % 3 != 0 else Color(0.5, 0.46, 0.4)
			g.set_pixel(x, y, c)
	ground_tex = ImageTexture.create_from_image(g)
