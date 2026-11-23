class_name WorldSim
extends RefCounted
## Monde de campagne vivant (I8), sans rendu : saisons et météo, guerres et trêves entre les
## factions, armées qui marchent, assiègent, se battent entre elles et prennent des villes,
## rencontres avec la compagnie et nouvelles du monde.
##
## CampaignState en possède un (« world ») et l'appelle :
## - advance(c) à chaque jour qui passe (pass_day) ;
## - on_march_day(c, ...) à chaque jour de marche (froid de l'hiver, rencontre d'une armée) ;
## - adjust_contract / extra_contracts pour les contrats (une ville en guerre embauche plus et paie mieux) ;
## - after_battle(c, victory) à la fin d'une bataille : armée rencontrée dispersée, siège levé
##   (défense gagnée d'une ville assiégée) ou ville prise pour le patron (assaut gagné).
## Le monde a son propre générateur aléatoire : il ne change pas les tirages de la campagne.
##
## Pour les sièges (autres sessions) : besieged(town), siege_info(town) et, côté campagne,
## CampaignState.town_besieged(town) / town_siege(town).

const SEASONS := ["printemps", "été", "automne", "hiver"]
const WINTER := 3
const SEASON_DAYS := 30 ## Durée d'une saison, en jours (le jour 1 est le premier du printemps)
const RAIN_CHANCE := [0.25, 0.1, 0.5, 0.3] ## Chance de pluie chaque jour, par saison (l'automne est pluvieux)
const FOG_CHANCE := [0.15, 0.05, 0.25, 0.2] ## Chance de brouillard (temps sec), par saison
const LOCAL_FOG_CHANCE := 0.25 ## En plus, près de l'eau ou dans les bois (FOGGY_TERRAINS)
const FOGGY_TERRAINS := ["river", "forest"]
const WIND_CHANCE := 0.25 ## Chance de vent fort chaque jour
const MARCH_FACTOR := [1.0, 1.0, 1.0, 0.7] ## Vitesse de marche (compagnie et armées), par saison
const COLD_CHANCE := 0.5 ## En hiver, chance par jour de marche que le froid emporte des hommes
const COLD_RATE := 0.02 ## ... part des hommes de chaque régiment
const ATTRITION := [0.005, 0.005, 0.01, 0.025] ## Pertes quotidiennes d'une armée en campagne, par saison

const ARMY_SPEED := 100.0 * MapData.SCALE ## Pixels de carte parcourus par jour par une armée (marche abstraite ; en temps réel : Party.BASE_SPEED)
const STRENGTH := [170, 210, 150] ## Taille de base d'une armée, par faction (la Baronnie est la plus guerrière)
const WAR_SIZE := 1.6 ## Facteur de taille d'une armée en guerre...
const PEACE_SIZE := 0.5 ## ... et d'une patrouille en temps de paix
const MIN_ARMY := 30 ## Sous cet effectif, une armée se disperse
const ARMY_TYPES := [ ## Régiments d'une armée de faction quand la compagnie l'affronte
	["spear", "men_at_arms", "archer", "spear", "cavalry", "foot_knight", "archer", "men_at_arms", "cavalry"],
	["archer", "cavalry", "men_at_arms", "horse_archer", "spear", "cavalry", "archer", "horse_archer", "men_at_arms"],
	["spear", "crossbow", "spear", "archer", "men_at_arms", "crossbow", "spear", "archer", "men_at_arms"],
]

const GARRISON := 180 ## Garnison pleine d'une ville
const GARRISON_CAPITAL := 300 ## ... d'une capitale
const GARRISON_REGEN := 6 ## Hommes rendus chaque jour à une garnison (hors siège)
const SIEGE_HIT := 0.04 ## Part de l'armée assiégeante qui abat chaque jour autant de défenseurs
const SIEGE_LOSS := 0.05 ## Part de la garnison qui abat chaque jour autant d'assiégeants

const FIRST_WAR_DAY := 6 ## Aucune guerre avant ce jour
const WAR_MIN_DAYS := 20 ## Durée minimale d'une guerre avant une trêve
const PEACE_MIN_DAYS := 12 ## Durée minimale d'une trêve avant une nouvelle guerre
const WAR_CHANCE_RIVAL := 0.03 ## Chance quotidienne d'une guerre entre rivales...
const WAR_CHANCE_OTHER := 0.01 ## ... et entre deux autres factions
const TRUCE_CHANCE := 0.03 ## Chance quotidienne d'une trêve après WAR_MIN_DAYS...
const TRUCE_GROWTH := 0.003 ## ... qui grandit chaque jour de guerre en plus
const REP_BOLD := 50 ## Une faction alliée de la compagnie (réputation >= 50) est plus belliqueuse
const REP_FRIEND := 20 ## Les armées ennemies d'une faction amie (>= 20) attaquent la compagnie si elles s'en méfient

const WAR_REWARD := 1.3 ## Prime des contrats d'une ville en guerre
const REP_ARMY := 5 ## Disperser une armée : réputation -5 auprès d'elle, +5 auprès de ses ennemis
const FLEE_GOLD := 0.08 ## Fuir une armée : part de l'or abandonnée avec les bagages
const ENCOUNTER_RANGE := 40.0 * MapData.SCALE ## Distance (carte) à laquelle une armée hostile croise la compagnie
const CLASH_RANGE := 30.0 * MapData.SCALE ## Distance à laquelle deux armées ennemies se livrent bataille
const NEWS_MAX := 10
const SIEGE_BROKEN := 0.4 ## Défense gagnée par la compagnie : part de l'armée assiégeante qui repart
const ROAD_TERRAINS := ["plain", "forest", "hills"] ## Terrains d'une rencontre sur la route

var owner: Array[int] = [] ## Faction qui tient chaque ville
var garrison: Array[int] = [] ## Défenseurs de chaque ville
var wars: Dictionary = {} ## "a-b" (a < b) -> jour de la déclaration de guerre
var last_change: Dictionary = {} ## "a-b" -> jour de la dernière déclaration ou trêve
var armies: Array[WorldArmy] = []
var next_id := 1
var raining := false ## Météo du jour (elle s'impose à la bataille)
var news: Array[String] = [] ## Nouvelles du monde, de la plus récente à la plus ancienne
var encounter: Dictionary = {} ## Rencontre en attente : {"army": id, "town": destination de la marche}
var captures := 0 ## Villes prises depuis le début de la campagne
## Batailles du jour (non sauvegardé) : {"pos", "faction" (le vaincu), "men" (hommes perdus)}.
## La carte en temps réel (Overworld.populate) y fait naître des déserteurs, puis la vide.
var aftermath: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
## Temps réel (overworld.gd) : les armées avancent à chaque instant (tick) et plus d'un bond par
## jour dans advance. Non sauvegardé : la carte en temps réel le remet en marche.
var realtime := false
## Défi « Hiver éternel » (challenges.gd) : la saison reste l'hiver. Non sauvegardé ici : la
## campagne le remet d'après ses défis (CampaignState.new_game, from_dict).
var eternal_winter := false


func _init() -> void:
	for t in CampaignState.TOWNS:
		owner.append(int(t["faction"]))
	for i in CampaignState.TOWNS.size():
		garrison.append(garrison_max(i))


## Monde neuf d'une campagne (en paix, une patrouille par faction).
static func create(seed_value: int, winter_forever := false) -> WorldSim:
	var w := WorldSim.new()
	w.eternal_winter = winter_forever
	w.rng.seed = hash(str(seed_value) + "monde")
	w.roll_weather(1)
	for f in CampaignState.FACTIONS.size():
		w.raise_army(null, f)
	return w


# ---------------------------------------------------------------- Saisons et météo

static func season_of(day: int) -> int:
	@warning_ignore("integer_division")
	return (maxi(day, 1) - 1) / SEASON_DAYS % SEASONS.size()


static func season_name(day: int) -> String:
	return str(SEASONS[season_of(day)])


## Jour dans la saison (1 à SEASON_DAYS).
static func season_day(day: int) -> int:
	return (maxi(day, 1) - 1) % SEASON_DAYS + 1


## Saison de cette campagne au jour day : toujours l'hiver avec le défi « Hiver éternel ».
## Les règles du monde passent par elle (season_of ne connaît que le calendrier).
func season(day: int) -> int:
	return WINTER if eternal_winter else season_of(day)


## Vitesse de marche de cette campagne au jour day (défi « Hiver éternel » compris).
func march_speed(day: int) -> float:
	return float(MARCH_FACTOR[season(day)])


## Vitesse de marche de la saison (1 hors de l'hiver).
static func march_factor(day: int) -> float:
	return float(MARCH_FACTOR[season_of(day)])


func roll_weather(day: int) -> void:
	raining = rng.randf() < float(RAIN_CHANCE[season(day)])


## Tirage de météo du jour (0 à 1) pour what : déduit de la graine, sans toucher au générateur du
## monde (les tirages de la campagne ne changent pas, rien de plus à sauvegarder).
func weather_roll(day: int, what: String) -> float:
	var lr := RandomNumberGenerator.new()
	lr.seed = hash("%s-%s-%d" % [str(rng.seed), what, day])
	return lr.randf()


## Brouillard du jour sur tout le pays (jamais sous la pluie).
func fog_today(day: int) -> bool:
	return not raining and weather_roll(day, "brume") < float(FOG_CHANCE[season(day)])


## Vent du jour : 0 par temps calme, sinon de 0,6 à 1, signé (> 0 : vers le sud).
func wind_today(day: int) -> float:
	if weather_roll(day, "vent") >= WIND_CHANCE:
		return 0.0
	var k := weather_roll(day, "vent-force")
	return (0.6 + 0.4 * k) * (1.0 if weather_roll(day, "vent-sens") < 0.5 else -1.0)


## Météo d'une bataille livrée ce jour, sur ce terrain (Terrain.KINDS), près de cette ville :
## {"rain", "fog", "wind"} pour BattleWeather.apply. La brume traîne plus près de l'eau et des bois.
func battle_weather(day: int, kind: String, town := -1) -> Dictionary:
	var fog := fog_today(day)
	if not fog and not raining and kind in FOGGY_TERRAINS:
		fog = weather_roll(day, "brume-%s-%d" % [kind, town]) < LOCAL_FOG_CHANCE
	return {"rain": raining, "fog": fog, "wind": wind_today(day)}


## « pluie », « temps clair », « froid sec », « brouillard, vent fort »...
func weather_text(day: int) -> String:
	var t: String
	if fog_today(day):
		t = "brouillard"
	elif season(day) == WINTER:
		t = "pluie glacée" if raining else "froid sec"
	else:
		t = "pluie" if raining else "temps clair"
	if wind_today(day) != 0.0:
		t += ", vent fort"
	return t


## « Automne, jour 12 : pluie ».
func calendar_text(day: int) -> String:
	if eternal_winter:
		return "Hiver éternel, jour %d : %s" % [day, weather_text(day)]
	return "%s, jour %d : %s" % [CampaignState.cap_first(season_name(day)), season_day(day), weather_text(day)]


# ---------------------------------------------------------------- Un jour passe

func advance(c: CampaignState) -> void:
	aftermath.clear()
	if season_day(c.day) == 1 and not eternal_winter:
		post(c, season_intro(c.day), true)
	roll_weather(c.day)
	update_wars(c)
	spawn_armies(c)
	move_armies(c)
	clashes(c)
	armies = armies.filter(func(a: WorldArmy) -> bool: return a.force >= MIN_ARMY)
	for t in owner.size():
		if not besieged(t):
			garrison[t] = mini(garrison_max(t), garrison[t] + GARRISON_REGEN)


func season_intro(day: int) -> String:
	match season_of(day):
		0: return "le printemps revient, les routes sèchent."
		1: return "l'été commence : la saison des campagnes."
		2: return "l'automne arrive avec ses pluies."
	return "l'hiver tombe sur le pays : marches lentes et froid mordant."


## Ajoute une nouvelle du monde ; major : aussi au journal de la compagnie.
func post(c: CampaignState, text: String, major := false) -> void:
	var day := c.day if c != null else 1
	var line := "Jour %d : %s" % [day, text]
	news.push_front(line)
	if news.size() > NEWS_MAX:
		news.pop_back()
	if major and c != null:
		c.add_log(line)


# ---------------------------------------------------------------- Villes et factions

static func is_capital(town: int) -> bool:
	for f in CampaignState.FACTIONS:
		if int(f["capital"]) == town:
			return true
	return false


static func garrison_max(town: int) -> int:
	return GARRISON_CAPITAL if is_capital(town) else GARRISON


static func short(f: int) -> String:
	return str(CampaignState.FACTIONS[f]["short"])


static func town_name(t: int) -> String:
	return str(CampaignState.TOWNS[t]["name"])


func owner_of(town: int) -> int:
	return owner[town]


func towns_of(f: int) -> Array[int]:
	var out: Array[int] = []
	for t in owner.size():
		if owner[t] == f:
			out.append(t)
	return out


static func pair_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


static func rivals(a: int, b: int) -> bool:
	return int(CampaignState.FACTIONS[a]["rival"]) == b or int(CampaignState.FACTIONS[b]["rival"]) == a


func at_war(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b and wars.has(pair_key(a, b))


func at_war_any(f: int) -> bool:
	return not enemies_of(f).is_empty()


func enemies_of(f: int) -> Array[int]:
	var out: Array[int] = []
	for g in CampaignState.FACTIONS.size():
		if at_war(f, g):
			out.append(g)
	return out


## « le Comté contre la Baronnie ; la Ligue contre la Baronnie » ou « paix ».
func wars_text() -> String:
	var parts: Array[String] = []
	for k in wars:
		var ab: PackedStringArray = str(k).split("-")
		parts.append("%s contre %s" % [short(int(ab[0])), short(int(ab[1]))])
	return "paix" if parts.is_empty() else " ; ".join(parts)


## Un monde favorable : 1 + réputation / 400 (de x0,75 à x1,25). Une faction qui estime la
## compagnie a le cœur à la guerre et lève de plus grandes armées.
func rep_factor(c: CampaignState, f: int) -> float:
	if c == null:
		return 1.0
	return 1.0 + clampf(c.reputation[f] / 400.0, -0.25, 0.25)


# ---------------------------------------------------------------- Guerres et trêves

func update_wars(c: CampaignState) -> void:
	var n := CampaignState.FACTIONS.size()
	for a in n:
		for b in range(a + 1, n):
			var k := pair_key(a, b)
			if wars.has(k):
				var dur := c.day - int(wars[k])
				var chance := 0.0
				if towns_of(a).is_empty() or towns_of(b).is_empty():
					chance = 0.3 # Une faction sans ville demande grâce
				elif dur >= WAR_MIN_DAYS:
					chance = TRUCE_CHANCE + TRUCE_GROWTH * (dur - WAR_MIN_DAYS)
				if rng.randf() < chance:
					make_peace(c, a, b)
			elif c.day >= FIRST_WAR_DAY and c.day - int(last_change.get(k, 0)) >= PEACE_MIN_DAYS:
				if towns_of(a).is_empty() or towns_of(b).is_empty():
					continue
				var chance := WAR_CHANCE_RIVAL if rivals(a, b) else WAR_CHANCE_OTHER
				# La réputation du joueur pèse : une faction alliée de la compagnie ose davantage
				for f in [a, b]:
					if c.reputation[f] >= REP_BOLD:
						chance *= 1.5
				if rng.randf() < chance:
					declare_war(c, a, b)


## Guerre entre a et b (a déclare la guerre à b).
func declare_war(c: CampaignState, a: int, b: int) -> void:
	var k := pair_key(a, b)
	if wars.has(k) or a == b:
		return
	var day := c.day if c != null else 1
	wars[k] = day
	last_change[k] = day
	post(c, "%s déclare la guerre à %s ! Ses villes embauchent." % [CampaignState.cap_first(short(a)), short(b)], true)


func make_peace(c: CampaignState, a: int, b: int) -> void:
	var k := pair_key(a, b)
	if not wars.has(k):
		return
	wars.erase(k)
	last_change[k] = c.day if c != null else 1
	for army in armies:
		if (army.faction == a or army.faction == b) and army.mode in ["march", "siege"] and army.target >= 0 \
				and not at_war(army.faction, owner[army.target]) and owner[army.target] != army.faction:
			send_home(army)
	post(c, "%s et %s signent une trêve." % [CampaignState.cap_first(short(a)), short(b)], true)


# ---------------------------------------------------------------- Armées

func army_by_id(id: int) -> WorldArmy:
	for a in armies:
		if a.id == id:
			return a
	return null


static func neighbours_of(town: int) -> Array[int]:
	var out: Array[int] = []
	for road in CampaignState.ROADS:
		if road[0] == town:
			out.append(int(road[1]))
		elif road[1] == town:
			out.append(int(road[0]))
	return out


static func town_pos(t: int) -> Vector2:
	return CampaignState.TOWNS[t]["pos"]


## Plus court chemin par les routes (Dijkstra) : villes à traverser après from, to comprise.
static func find_path(from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	if from == to:
		return out
	var n := CampaignState.TOWNS.size()
	var dist: Array[float] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[from] = 0.0
	for _k in n:
		var u := -1
		for i in n:
			if not done[i] and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or dist[u] == INF:
			break
		done[u] = true
		for v in neighbours_of(u):
			var d := dist[u] + town_pos(u).distance_to(town_pos(v))
			if d < dist[v]:
				dist[v] = d
				prev[v] = u
	if prev[to] < 0:
		return out
	var t := to
	while t != from:
		out.push_front(t)
		t = prev[t]
	return out


static func path_length(from: int, path: Array[int]) -> float:
	var len := 0.0
	var at := town_pos(from)
	for t in path:
		len += at.distance_to(town_pos(t))
		at = town_pos(t)
	return len


## Ville ennemie la plus proche (par les routes) d'une des villes « from » : [départ, but] ou [].
func nearest_enemy_town(f: int, from: Array[int]) -> Array[int]:
	var best := INF
	var out: Array[int] = []
	for e in enemies_of(f):
		for u in towns_of(e):
			for t in from:
				var l := path_length(t, find_path(t, u))
				if l < best:
					best = l
					out = [t, u]
	return out


func spawn_armies(c: CampaignState) -> void:
	for f in CampaignState.FACTIONS.size():
		if towns_of(f).is_empty():
			continue
		var war := at_war_any(f)
		var mine := 0
		for a in armies:
			if a.faction == f:
				mine += 1
		if mine >= (2 if war else 1) or rng.randf() >= (0.12 if war else 0.06):
			continue
		raise_army(c, f)


## Lève une armée : en guerre, elle marche sur la ville ennemie la plus proche ; en paix, elle
## patrouille vers une ville amie voisine. Renvoie null si la faction n'a nulle part où aller.
func raise_army(c: CampaignState, f: int) -> WorldArmy:
	var towns := towns_of(f)
	if towns.is_empty():
		return null
	var war := at_war_any(f)
	var src := -1
	var goal := -1
	if war:
		var pick := nearest_enemy_town(f, towns)
		if pick.is_empty():
			return null
		src = pick[0]
		goal = pick[1]
	else:
		src = towns[rng.randi() % towns.size()]
		var near: Array[int] = []
		for t in neighbours_of(src):
			if owner[t] == f:
				near.append(t)
		if near.is_empty():
			return null
		goal = near[rng.randi() % near.size()]
	var men := int(STRENGTH[f] * (WAR_SIZE if war else PEACE_SIZE) * rng.randf_range(0.8, 1.2) * rep_factor(c, f))
	@warning_ignore("integer_division")
	garrison[src] = maxi(GARRISON / 3, garrison[src] - men / 4) # La ville fournit des hommes
	var a := add_army(f, src, goal, men, "march" if war else "patrol")
	if war:
		post(c, "%s lève %s à %s et marche sur %s." % [CampaignState.cap_first(short(f)), CampaignState.plural(men, "homme", "hommes"), town_name(src), town_name(goal)])
	return a


func add_army(f: int, from: int, to: int, men: int, mode: String) -> WorldArmy:
	var a := WorldArmy.new()
	a.id = next_id
	next_id += 1
	a.faction = f
	a.force = men
	a.pos = town_pos(from)
	a.route = find_path(from, to)
	a.target = to
	a.mode = mode
	a.sync_troops()
	armies.append(a)
	return a


func move_armies(c: CampaignState) -> void:
	var s := season(c.day)
	var speed := ARMY_SPEED * float(MARCH_FACTOR[s])
	for a in armies.duplicate():
		if a.force <= 0:
			continue
		a.force -= maxi(1, int(round(a.force * float(ATTRITION[s]))))
		if a.mode == "siege":
			siege_day(c, a)
			continue
		# But devenu inutile (trêve) : l'armée rentre
		if a.mode == "march" and a.target >= 0 and owner[a.target] != a.faction and not at_war(a.faction, owner[a.target]):
			send_home(a)
		if not realtime and a.step(speed):
			arrive(c, a)
	for a in armies:
		a.sync_troops()


## Temps réel : les armées qui marchent avancent de hours heures (vitesse de la sorte « army »,
## route ou terrain, saison). Appelé par Overworld.tick ; la vie quotidienne reste dans advance.
func tick(c: CampaignState, hours: float) -> void:
	realtime = true
	var season_k := float(MARCH_FACTOR[season(c.day)])
	for a in armies.duplicate():
		if a.force <= 0 or a.mode == "siege" or a.route.is_empty():
			if a.force > 0 and a.mode != "siege" and a.route.is_empty():
				arrive(c, a)
			continue
		var speed: float = a.base_speed() * MapData.speed_at(a.pos) * season_k
		if a.step(speed * hours):
			arrive(c, a)
	armies = armies.filter(func(a: WorldArmy) -> bool: return a.force > 0)


func arrive(c: CampaignState, a: WorldArmy) -> void:
	var t := a.target
	if t < 0:
		a.force = 0
		return
	var o := owner[t]
	if o != a.faction and at_war(a.faction, o):
		a.mode = "siege"
		a.siege_days = 0
		post(c, "%s met le siège devant %s (%s)." % [CampaignState.cap_first(a.display_name()), town_name(t), short(o)])
	elif o == a.faction:
		if a.mode == "march" and at_war_any(a.faction):
			var from: Array[int] = [t]
			var pick := nearest_enemy_town(a.faction, from)
			if not pick.is_empty():
				a.route = find_path(t, pick[1])
				a.target = pick[1]
				return
		# Patrouille terminée ou repli : l'armée rejoint la garnison
		@warning_ignore("integer_division")
		garrison[t] = mini(garrison_max(t), garrison[t] + a.force / 2)
		a.force = 0
	else:
		send_home(a)


## Renvoie une armée vers la ville amie la plus proche (dispersée s'il n'y en a plus).
func send_home(a: WorldArmy) -> void:
	var home := -1
	for t in towns_of(a.faction):
		if home < 0 or a.pos.distance_to(town_pos(t)) < a.pos.distance_to(town_pos(home)):
			home = t
	if home < 0:
		a.force = 0
		return
	# Repart de la ville la plus proche de sa position (elle peut être sur une route)
	var near := 0
	for t in CampaignState.TOWNS.size():
		if a.pos.distance_to(town_pos(t)) < a.pos.distance_to(town_pos(near)):
			near = t
	a.route = find_path(near, home)
	if a.pos.distance_to(town_pos(near)) > 0.5:
		a.route.push_front(near)
	a.target = home
	a.mode = "retreat"
	a.siege_days = 0


func siege_day(c: CampaignState, a: WorldArmy) -> void:
	var t := a.target
	if owner[t] == a.faction or not at_war(a.faction, owner[t]):
		send_home(a)
		return
	a.siege_days += 1
	garrison[t] -= int(a.force * SIEGE_HIT * rng.randf_range(0.6, 1.4))
	a.force -= int(maxi(garrison[t], 0) * SIEGE_LOSS)
	if garrison[t] <= 0:
		capture(c, a, t)
	elif a.force < MIN_ARMY:
		post(c, "le siège de %s est levé : %s se disperse." % [town_name(t), a.display_name()])
		aftermath.append({"pos": a.pos, "faction": a.faction, "men": a.force})
		a.force = 0


## La ville tombe aux mains de l'armée : elle change de faction et ses contrats sont caducs.
func capture(c: CampaignState, a: WorldArmy, t: int) -> void:
	@warning_ignore("integer_division")
	var men := maxi(40, a.force / 2)
	a.force = 0
	aftermath.append({"pos": town_pos(t), "faction": owner[t], "men": garrison_max(t)})
	take_town(c, a.faction, t, men)


## La faction f prend la ville t (garnison men) : armée victorieuse (capture) ou assaut gagné par
## la compagnie pour son patron (after_battle). Les contrats de la ville sont caducs, sauf la
## bataille en cours ; le contrat final suit son patron (CampaignState.keep_final_in_patron_town).
func take_town(c: CampaignState, f: int, t: int, men: int) -> void:
	var old := owner[t]
	owner[t] = f
	garrison[t] = mini(garrison_max(t), men)
	captures += 1
	for other in armies:
		if other.mode == "siege" and other.target == t and not at_war(other.faction, f):
			send_home(other) # La ville a changé de maître : plus de raison de l'assiéger
	post(c, "%s prend %s à %s !" % [CampaignState.cap_first(short(f)), town_name(t), short(old)], true)
	if c != null:
		var keep := func(k: Dictionary) -> bool:
			return int(k["town"]) != t or k.get("final", false) or is_same(k, c.pending)
		c.contracts = c.contracts.filter(keep)
		c.refresh_contracts(t)
		c.keep_final_in_patron_town()


## Deux armées ennemies proches l'une de l'autre se livrent bataille (issue tirée au sort,
## pondérée par les effectifs). Le vaincu perd les trois quarts de ses hommes et se replie.
func clashes(c: CampaignState) -> void:
	for i in armies.size():
		for j in range(i + 1, armies.size()):
			var a := armies[i]
			var b := armies[j]
			if a.force < MIN_ARMY or b.force < MIN_ARMY or not at_war(a.faction, b.faction):
				continue
			if a.pos.distance_to(b.pos) > CLASH_RANGE:
				continue
			if c.overworld != null and c.overworld.offer_joint(c, a, b):
				continue # La compagnie suit l'une des deux armées : la bataille lui est proposée
			var pa := a.force * rng.randf_range(0.75, 1.25)
			var pb := b.force * rng.randf_range(0.75, 1.25)
			var win := a if pa >= pb else b
			var lose := b if pa >= pb else a
			var ratio := minf(minf(pa, pb) / maxf(pa, pb), 1.0)
			win.force -= int(lose.force * 0.5 * ratio + win.force * 0.05)
			aftermath.append({"pos": lose.pos, "faction": lose.faction, "men": lose.force - int(lose.force * 0.25)})
			lose.force = int(lose.force * 0.25)
			post(c, "bataille près de %s : %s met en déroute %s." % [town_name(nearest_town(win.pos)), win.display_name(), lose.display_name()])
			send_home(lose)


static func nearest_town(p: Vector2) -> int:
	var best := 0
	for t in CampaignState.TOWNS.size():
		if p.distance_to(town_pos(t)) < p.distance_to(town_pos(best)):
			best = t
	return best


# ---------------------------------------------------------------- Sièges (API pour les autres modules)

## Armée qui assiège la ville (null sinon).
func siege_at(town: int) -> WorldArmy:
	for a in armies:
		if a.mode == "siege" and a.target == town and a.force >= MIN_ARMY and at_war(a.faction, owner[town]):
			return a
	return null


func besieged(town: int) -> bool:
	return siege_at(town) != null


## {"faction" (assiégeant), "defender", "men", "days", "garrison", "army" (id)} ou {} sans siège.
func siege_info(town: int) -> Dictionary:
	var a := siege_at(town)
	if a == null:
		return {}
	return {"faction": a.faction, "defender": owner[town], "men": a.force, "days": a.siege_days,
		"garrison": maxi(garrison[town], 0), "army": a.id}


# ---------------------------------------------------------------- La compagnie et le monde

## Une armée est hostile à la compagnie si sa faction lui ferme ses portes, ou si elle s'en
## méfie (réputation négative) et que la compagnie est amie d'une faction qu'elle combat.
func hostile_to_player(c: CampaignState, a: WorldArmy) -> bool:
	if c.diplomacy.at_war_with(c, a.faction): # Vassale : en guerre avec les ennemis de son suzerain
		return true
	var r := c.reputation[a.faction]
	if r <= CampaignState.REP_CLOSED:
		return true
	if r >= 0:
		return false
	for f in enemies_of(a.faction):
		if c.reputation[f] >= REP_FRIEND:
			return true
	return false


## Un jour de marche de from vers to (k : part du chemin parcourue) : froid de l'hiver et
## rencontre d'une armée hostile (le joueur choisira à l'arrivée : bataille ou fuite).
func on_march_day(c: CampaignState, from: int, to: int, k: float) -> void:
	cold_day(c)
	if not encounter.is_empty() or c.in_battle() or c.is_destroyed():
		return
	var p := town_pos(from).lerp(town_pos(to), clampf(k, 0.0, 1.0))
	for a in armies:
		if a.force >= MIN_ARMY and hostile_to_player(c, a) and a.pos.distance_to(p) <= ENCOUNTER_RANGE:
			encounter = {"army": a.id, "town": to}
			travel_note(c, "%s (%s) barre la route de %s : livrer bataille ou fuir ?" % [a.display_name(), CampaignState.plural(a.force, "homme", "hommes"), town_name(to)])
			return


## Un jour de marche en hiver : le froid emporte parfois des hommes.
func cold_day(c: CampaignState) -> void:
	if season(c.day) == WINTER and not c.company.is_empty() and rng.randf() < COLD_CHANCE:
		var lost := 0
		for r in c.company:
			var n := int(round(int(r["men"]) * COLD_RATE))
			if lost == 0 and n == 0 and int(r["men"]) > 1:
				n = 1
			r["men"] = int(r["men"]) - n
			lost += n
		c.company = c.company.filter(func(r: Dictionary) -> bool: return int(r["men"]) > 0)
		c.men_lost += lost
		travel_note(c, "le froid emporte %s." % CampaignState.plural(lost, "homme", "hommes"))


func travel_note(c: CampaignState, msg: String) -> void:
	c.travel_events.append(CampaignState.cap_first(msg))
	c.add_log("Jour %d : %s" % [c.day, msg])


func has_encounter() -> bool:
	return not encounter.is_empty()


func encounter_army() -> WorldArmy:
	return army_by_id(int(encounter.get("army", -1)))


## Le joueur choisit de livrer bataille à l'armée rencontrée : la bataille est en attente
## (CampaignState.pending). Renvoie un message d'erreur ou "".
func fight(c: CampaignState) -> String:
	var a := encounter_army()
	var town := int(encounter.get("town", c.location))
	encounter = {}
	if a == null:
		return "L'armée s'est éloignée."
	if c.is_destroyed() or c.is_over():
		return "Vous n'avez plus de troupes."
	c.pending = make_battle(c, a, town)
	return ""


## Le joueur se dérobe : un jour de détour et une partie des bagages abandonnée.
func flee(c: CampaignState) -> String:
	var a := encounter_army()
	encounter = {}
	var who := a.display_name() if a != null else "l'armée"
	var lost := int(floor(c.gold * FLEE_GOLD))
	c.gold -= lost
	c.pass_day()
	var msg := "la compagnie se dérobe devant %s : un jour de détour, %d écus de bagages abandonnés." % [who, lost]
	c.add_log("Jour %d : %s" % [c.day, msg])
	c.check_ruin()
	return CampaignState.cap_first(msg)


## Bataille contre une armée de faction : ni prime ni contrat, seulement le butin (et la réputation).
func make_battle(c: CampaignState, a: WorldArmy, town: int, land_override := "") -> Dictionary:
	var types: Array = ARMY_TYPES[a.faction]
	var n := clampi(int(round(a.force / 40.0)), 3, types.size())
	var enemy: Array[Dictionary] = []
	for i in n:
		var t := str(types[i])
		var full := int(UnitTypes.STATS[t]["count"])
		var x := rng.randf()
		enemy.append({"type": t, "men": maxi(3, int(round(full * rng.randf_range(0.7, 1.0)))), "rank": 2 if x < 0.15 else (1 if x < 0.55 else 0)})
	# Une rencontre se joue en chemin, jamais sur la palissade de la ville : le terrain de la ville
	# s'il s'y prête (bois de Valombre, collines de Montfaucon...), sinon un terrain de route.
	var land := Terrain.for_contract(town, 1, CampaignState.TOWNS)
	if not land in ROAD_TERRAINS:
		land = str(ROAD_TERRAINS[rng.randi() % ROAD_TERRAINS.size()])
	if land_override != "": # Carte en temps réel : le terrain de l'endroit (MapData.battle_terrain_at)
		land = land_override
	return {
		"town": town, "faction": -1, "world_army": a.id, "terrain": land,
		"title": "%s barre la route de %s" % [CampaignState.cap_first(a.display_name()), town_name(town)],
		"text": "Les bannières de %s couvrent la route. Pas de prime : seulement le butin et la gloire." % short(a.faction),
		"foe": "troupes de %s" % short(a.faction),
		"difficulty": clampi(ceili(n / 2.0), 1, CampaignState.MAX_LEVEL),
		"enemy": enemy, "reward": 0, "expires": c.day, "seed": rng.randi_range(1, 1 << 30),
	}


## Fin d'une bataille (appelé par finish_battle, pending encore en place) : effets sur la carte
## d'une rencontre (after_encounter) ou d'un siège (after_siege). Renvoie la note ajoutée au
## compte rendu ("" sinon).
func after_battle(c: CampaignState, victory: bool) -> String:
	if c.pending.has("siege"):
		return after_siege(c, victory)
	return after_encounter(c, victory)


## Siège gagné. Défense d'une ville assiégée sur la carte : l'assiégeant, saigné, lève le siège et
## rentre chez lui. Assaut d'une ville de la carte (« target ») : elle passe au patron du contrat,
## s'il est toujours en guerre avec son maître. Une défaite ne change rien : le siège continue.
func after_siege(c: CampaignState, victory: bool) -> String:
	if not victory:
		return ""
	var town := int(c.pending["town"])
	if str(c.pending["siege"]) == "defense":
		var a := siege_at(town)
		if a == null:
			return ""
		a.force = int(a.force * SIEGE_BROKEN)
		post(c, "la compagnie brise le siège de %s : %s se retire." % [town_name(town), a.display_name()])
		send_home(a)
		return " Le siège de %s est levé : %s se retire." % [town_name(town), a.display_name()]
	var t := int(c.pending.get("target", -1))
	var f := int(c.pending.get("faction", -1))
	if t < 0 or t >= owner.size() or f < 0 or owner[t] == f or not at_war(f, owner[t]):
		return ""
	@warning_ignore("integer_division")
	take_town(c, f, t, garrison_max(t) / 2)
	return " %s tient désormais %s." % [CampaignState.cap_first(short(f)), town_name(t)]


## Fin d'une bataille contre une armée rencontrée : dispersée si la compagnie gagne, et
## réputation (renvoie la note, "" sinon).
func after_encounter(c: CampaignState, victory: bool) -> String:
	if not c.pending.has("world_army"):
		return ""
	var a := army_by_id(int(c.pending["world_army"]))
	if a == null:
		return ""
	var f := a.faction
	if not victory:
		a.force = int(a.force * 0.8)
		return ""
	a.force = 0
	armies.erase(a)
	c.change_reputation(f, -REP_ARMY)
	var parts: Array[String] = ["%s %+d" % [short(f), -REP_ARMY]]
	for e in enemies_of(f):
		c.change_reputation(e, REP_ARMY)
		parts.append("%s %+d" % [short(e), REP_ARMY])
	post(c, "la compagnie disperse %s près de %s." % [a.display_name(), town_name(int(c.pending["town"]))])
	return " %s est dispersée. Réputation : %s." % [CampaignState.cap_first(a.display_name()), ", ".join(parts)]


# ---------------------------------------------------------------- Contrats

## Ville tenue par une faction en guerre : un contrat de plus est proposé.
func extra_contracts(town: int) -> int:
	return 1 if at_war_any(owner[town]) else 0


## Adapte un contrat tout juste tiré (make_contract) au monde : prime de guerre. (La faction de
## la ville et l'ennemi sont déjà ceux d'aujourd'hui : make_contract lit town_owner.)
func adjust_contract(k: Dictionary) -> Dictionary:
	var o := owner[int(k["town"])]
	k["faction"] = o
	var foes := enemies_of(o)
	if not foes.is_empty():
		k["reward"] = int(round(int(k["reward"]) * WAR_REWARD / 10.0)) * 10
		var names: Array[String] = []
		for f in foes:
			names.append(short(f))
		k["text"] = str(k["text"]) + " En guerre contre %s, la ville paie mieux." % " et ".join(names)
	return k


# ---------------------------------------------------------------- Sauvegarde

func to_dict() -> Dictionary:
	var list: Array = []
	for a in armies:
		list.append(a.to_dict())
	return {
		"owner": Array(owner), "garrison": Array(garrison),
		"wars": wars.duplicate(), "last_change": last_change.duplicate(),
		"armies": list, "next_id": next_id, "raining": raining,
		"news": Array(news), "encounter": encounter.duplicate(), "captures": captures,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
	}


## pos_scale : agrandissement des positions des armées (sauvegarde d'avant la grande carte).
## Relit le monde sauvegardé ; d vide (sauvegarde de version 6 ou avant) : monde neuf, en paix.
## Renvoie null si les données sont invalides.
static func from_dict(d: Variant, seed_value: int, day := 1, pos_scale := 1.0) -> WorldSim:
	if not d is Dictionary or (d as Dictionary).is_empty():
		var fresh := create(seed_value)
		fresh.roll_weather(day)
		return fresh
	var w := WorldSim.new()
	var n := CampaignState.TOWNS.size()
	var nf := CampaignState.FACTIONS.size()
	var own: Array = d.get("owner", [])
	var gar: Array = d.get("garrison", [])
	if own.size() != n or gar.size() != n:
		return null
	for t in n:
		w.owner[t] = int(own[t])
		if w.owner[t] < 0 or w.owner[t] >= nf:
			return null
		w.garrison[t] = clampi(int(gar[t]), -GARRISON_CAPITAL, GARRISON_CAPITAL)
	for src in [["wars", w.wars], ["last_change", w.last_change]]:
		var dict: Variant = d.get(src[0], {})
		if not dict is Dictionary:
			return null
		for k in dict:
			var ab := str(k).split("-")
			if ab.size() != 2 or int(ab[0]) < 0 or int(ab[1]) >= nf or int(ab[0]) >= int(ab[1]):
				return null
			src[1][pair_key(int(ab[0]), int(ab[1]))] = int(dict[k])
	for a in d.get("armies", []):
		var army := WorldArmy.army_from_dict(a, pos_scale)
		if army == null:
			return null
		w.armies.append(army)
	w.next_id = maxi(1, int(d.get("next_id", 1)))
	for a in w.armies:
		w.next_id = maxi(w.next_id, a.id + 1)
	w.raining = bool(d.get("raining", false))
	for s in d.get("news", []):
		w.news.append(str(s))
	var e: Variant = d.get("encounter", {})
	if e is Dictionary and not (e as Dictionary).is_empty():
		var town := int(e.get("town", -1))
		if town < 0 or town >= n:
			return null
		w.encounter = {"army": int(e.get("army", -1)), "town": town}
	w.captures = maxi(0, int(d.get("captures", 0)))
	w.rng.seed = str(d.get("rng_seed", "1")).to_int()
	w.rng.state = str(d.get("rng_state", "1")).to_int()
	return w
