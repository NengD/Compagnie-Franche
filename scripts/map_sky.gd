class_name MapSky
extends RefCounted
## Saisons, météo et lumière de la carte du monde (campaign_map.gd), d'après WorldSim (saison,
## pluie) et l'heure de l'Overworld.
##
## - season(day, hour) : mélange des saisons pour le shader du terrain (MapRender.set_season) :
##   neige au sol et sur les arbres en hiver (elle tombe en quelques jours et fond au printemps),
##   feuillage roux en automne, prés secs en été, fleurs au printemps ;
## - daylight / night : couleur de la lumière (un calque en mode multiplication, pas un
##   CanvasModulate : l'interface et les lumières n'en souffrent pas) ;
## - FogLayer : brouillard du matin et voile de la pluie ;
## - DarkLayer : la nuit (multiplication) ; GlowLayer : fenêtres des villes, feux, torche (addition) ;
## - RainLayer : pluie ou neige qui tombe, à taille d'écran constante.
## Quelques dizaines de tracés par image au plus : la carte reste fluide.

const NIGHT := Color(0.34, 0.39, 0.66)
const DUSK := Color(1.0, 0.76, 0.6)
const DAWN := Color(0.96, 0.8, 0.78)
const FOG_CELL := 260.0 ## Espacement des nappes de brouillard (pixels de carte)
const RAIN_DROPS := 230 ## Gouttes à l'écran
const SNOW_FLAKES := 120 ## Flocons à l'écran

static var _soft: GradientTexture2D = null


## Tache ronde et douce (blanc au centre, transparent au bord) : brouillard et halos.
static func soft() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


# ---------------------------------------------------------------- Saisons

## Mélange des saisons à cet instant : {"snow", "autumn", "summer", "spring"} (0 à 1).
## La neige tient dès le 2e jour d'hiver et fond pendant les 4 premiers jours du printemps ; le
## feuillage roussit à la fin de l'été et tombe au début de l'hiver.
## frozen : défi « Hiver éternel » (la neige couvre tout, toujours).
static func season(day: int, hour: float, frozen := false) -> Dictionary:
	if frozen:
		return {"snow": 1.0, "autumn": 0.0, "summer": 0.0, "spring": 0.0}
	var s := WorldSim.season_of(day)
	var t := float(WorldSim.season_day(day) - 1) + hour / 24.0 # Jours écoulés dans la saison
	var left := float(WorldSim.SEASON_DAYS) - t # Jours restants
	var out := {"snow": 0.0, "autumn": 0.0, "summer": 0.0, "spring": 0.0}
	match s:
		0: # Printemps
			if day > WorldSim.SEASON_DAYS: # Pas de neige au tout premier printemps (pas d'hiver avant)
				out["snow"] = 1.0 - clampf(t / 4.0, 0.0, 1.0)
			out["spring"] = clampf((t - 2.0) / 4.0, 0.0, 1.0) * clampf(left / 5.0, 0.0, 1.0)
		1: # Été
			out["summer"] = clampf(t / 5.0, 0.0, 1.0)
			out["autumn"] = clampf((5.0 - left) / 5.0, 0.0, 1.0) * 0.35
		2: # Automne
			out["autumn"] = clampf(0.35 + t / 4.0, 0.0, 1.0)
			out["summer"] = 1.0 - clampf(t / 4.0, 0.0, 1.0)
		WorldSim.WINTER:
			out["snow"] = clampf((t - 0.5) / 1.5, 0.0, 1.0)
			out["autumn"] = 1.0 - clampf(t / 3.0, 0.0, 1.0)
	return out


# ---------------------------------------------------------------- Lumière

## Nuit noire : 1 ; plein jour : 0.
static func night(hour: float) -> float:
	if hour < 4.5 or hour >= 21.5:
		return 1.0
	if hour < 7.0:
		return 1.0 - (hour - 4.5) / 2.5
	if hour < 18.5:
		return 0.0
	return (hour - 18.5) / 3.0


## Couleur de la lumière : nuit bleue, aube rose, crépuscule orangé, plein jour blanc.
static func daylight(hour: float) -> Color:
	if hour < 4.5 or hour >= 21.5:
		return NIGHT
	if hour < 6.0:
		return NIGHT.lerp(DAWN, (hour - 4.5) / 1.5)
	if hour < 8.0:
		return DAWN.lerp(Color.WHITE, (hour - 6.0) / 2.0)
	if hour < 17.5:
		return Color.WHITE
	if hour < 19.5:
		return Color.WHITE.lerp(DUSK, (hour - 17.5) / 2.0)
	return DUSK.lerp(NIGHT, (hour - 19.5) / 2.0)


## Épaisseur du brouillard (0 à 1) : il se lève à l'aube, s'épaissit vers 6-7 h et se dissipe
## vers 10 h ; plus dense en automne, au printemps et sous la pluie, rare en été.
static func fog(day: int, hour: float, raining: bool) -> float:
	var base: float = [0.7, 0.35, 0.95, 0.6][WorldSim.season_of(day)]
	var morning := 0.0
	if hour >= 3.5 and hour < 6.5:
		morning = (hour - 3.5) / 3.0
	elif hour >= 6.5 and hour < 10.5:
		morning = 1.0 - (hour - 6.5) / 4.0
	return clampf(morning * base + (0.25 if raining else 0.0) * morning, 0.0, 1.0)


# ---------------------------------------------------------------- Calques

## Brouillard en nappes qui dérivent, voile gris de la pluie (sous la nuit : ils s'assombrissent).
class FogLayer extends Node2D:
	var map: Node2D

	func _draw() -> void:
		var state: CampaignState = map.state
		var view: Rect2 = map.view_rect().grow(FOG_CELL)
		var hour := state.overworld.hour
		var rain := state.world.raining
		if rain:
			draw_rect(view, Color(0.3, 0.36, 0.45, 0.26))
		var f := MapSky.fog(state.day, hour, rain)
		if f <= 0.01:
			return
		draw_rect(view, Color(0.88, 0.9, 0.92, 0.26 * f))
		var t := Time.get_ticks_msec() / 1000.0
		var tex := MapSky.soft()
		var drift := Vector2(t * 6.0, t * 1.5)
		var c0 := ((view.position - drift) / FOG_CELL).floor()
		var c1 := ((view.end - drift) / FOG_CELL).ceil()
		for cy in range(int(c0.y), int(c1.y) + 1):
			for cx in range(int(c0.x), int(c1.x) + 1):
				var h := MapSky.hash2(cx, cy)
				if h < 0.25:
					continue
				var p := Vector2(cx + MapSky.hash2(cx, cy + 91), cy + MapSky.hash2(cx + 37, cy)) * FOG_CELL + drift
				# Plus épais près de l'eau (rivières, lacs)
				var wet := 1.0 - clampf(MapData.water_sdf(p) / 160.0, 0.0, 1.0)
				var r := FOG_CELL * (0.8 + 0.6 * h)
				var a := f * (0.4 + 0.35 * wet) * h
				draw_texture_rect(tex, Rect2(p - Vector2(r * 1.4, r * 0.7), Vector2(r * 2.8, r * 1.4)), false, Color(0.93, 0.94, 0.96, a))


## La nuit : un rectangle de la couleur de la lumière, en multiplication sur la vue.
class DarkLayer extends Node2D:
	var map: Node2D

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		material = m

	func _draw() -> void:
		var col := MapSky.daylight(map.state.overworld.hour)
		if col.is_equal_approx(Color.WHITE):
			return
		draw_rect(map.view_rect().grow(40), col)


## Lumières de la nuit, en addition : fenêtres et halo des villes, des villages, des châteaux,
## feux des repaires, torche de la compagnie.
class GlowLayer extends Node2D:
	var map: Node2D

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _draw() -> void:
		var state: CampaignState = map.state
		var n := MapSky.night(state.overworld.hour)
		if n <= 0.02:
			return
		var view: Rect2 = map.view_rect().grow(60)
		var tex := MapSky.soft()
		var t := Time.get_ticks_msec() / 1000.0
		var warm := Color(1.0, 0.62, 0.28)
		for i in MapData.place_count():
			var p := MapData.place_pos(i).round()
			if not view.has_point(p):
				continue
			var kind := str(MapData.place(i)["kind"])
			var flick := 0.9 + 0.1 * sin(t * 7.0 + i * 1.7)
			match kind:
				"town":
					_halo(tex, p + Vector2(0, -6), 54.0, Color(warm, 0.42 * n * flick))
					for w in [Vector2(-14, -6), Vector2(-6, -12), Vector2(4, -12), Vector2(14, -6), Vector2(1, 4), Vector2(-9, 2), Vector2(9, 2)]:
						draw_rect(Rect2(p + w, Vector2(2, 2)), Color(1.0, 0.85, 0.45, 0.9 * n))
				"village", "mill", "abbey":
					_halo(tex, p, 26.0, Color(warm, 0.3 * n * flick))
					for w in [Vector2(-6, 3), Vector2(8, -1), Vector2(2, 9)]:
						draw_rect(Rect2(p + w, Vector2(1, 1)), Color(1.0, 0.85, 0.45, 0.85 * n))
				"castle", "bridge":
					_halo(tex, p + Vector2(0, -6), 30.0, Color(warm, 0.3 * n * flick))
					draw_rect(Rect2(p + Vector2(-1, -15), Vector2(2, 2)), Color(1.0, 0.85, 0.45, 0.9 * n))
				"lair":
					_halo(tex, p + Vector2(0, 7), 20.0 + 3.0 * sin(t * 9.0 + i), Color(1.0, 0.45, 0.15, 0.55 * n))
		# Torche de la compagnie, feux de camp des armées qui assiègent
		var pl := state.overworld.player.pos
		_halo(tex, pl + Vector2(0, -6), 34.0, Color(1.0, 0.7, 0.35, 0.38 * n * (0.92 + 0.08 * sin(t * 11.0))))
		for a in state.world.armies:
			var ap := WorldView.army_spot(a)
			if view.has_point(ap):
				_halo(tex, ap + Vector2(0, 2), 22.0, Color(1.0, 0.55, 0.2, 0.3 * n))

	func _halo(tex: Texture2D, p: Vector2, r: float, col: Color) -> void:
		draw_texture_rect(tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## Pluie (ou neige, l'hiver) qui tombe : traits tirés en coordonnées d'écran, ramenés sur la carte
## (ils gardent la même taille quel que soit le zoom).
class RainLayer extends Node2D:
	var map: Node2D

	func _draw() -> void:
		var state: CampaignState = map.state
		if not state.world.raining:
			return
		var view: Rect2 = map.view_rect()
		var z: float = view.size.x / maxf(map.get_viewport_rect().size.x, 1.0) # Pixels de carte par pixel d'écran
		var size: Vector2 = map.get_viewport_rect().size
		var t := Time.get_ticks_msec() / 1000.0
		var light := MapSky.daylight(state.overworld.hour)
		draw_set_transform(view.position, 0.0, Vector2(z, z))
		if state.world.season(state.day) == WorldSim.WINTER:
			var flake := Color(1, 1, 1, 0.85) * Color(light, 1.0)
			for k in SNOW_FLAKES:
				var x := fposmod(k * 97.3 + sin(t * 1.3 + k) * 14.0 + t * 12.0, size.x)
				var y := fposmod(k * 53.1 + t * (40.0 + (k % 5) * 9.0), size.y)
				var s := 2.0 + float(k % 3)
				draw_rect(Rect2(Vector2(x, y).round(), Vector2(s, s)), flake)
		else:
			var drop := Color(0.82, 0.9, 1.0, 0.75) * Color(light, 1.0)
			for k in RAIN_DROPS:
				var speed := 620.0 + (k % 7) * 40.0
				var x := fposmod(k * 61.7 + t * 120.0, size.x)
				var y := fposmod(k * 37.9 + t * speed, size.y)
				draw_line(Vector2(x, y), Vector2(x - 5, y + 18), drop, 1.2)
			# Éclaboussures au sol
			var splash := Color(0.85, 0.9, 1.0, 0.45) * Color(light, 1.0)
			for k in 40:
				var phase := fposmod(t * 3.0 + k * 0.37, 1.0)
				var cell := floori(t * 3.0 + k * 0.37)
				var x := fposmod(k * 131.0 + cell * 71.3, size.x)
				var y := fposmod(k * 89.0 + cell * 43.7, size.y)
				draw_arc(Vector2(x, y), 1.0 + phase * 4.0, 0, TAU, 8, Color(splash, splash.a * (1.0 - phase)), 1.0)
		draw_set_transform(Vector2.ZERO)


## Nombre pseudo-aléatoire stable (0-1) d'après deux entiers.
static func hash2(x: int, y: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10007) / 10007.0
