class_name MapRender
extends RefCounted
## Dessin du fond de la carte du monde (campaign_map.gd) d'après MapData.
##
## Le terrain est précalculé une fois par partie dans deux petites textures de champs (une valeur
## par case de la grille : eau, relief, forêt, montagne, marais, région, frontière) ; un shader les
## lit pour peindre la carte en pixels de PIX px : herbe, champs secs, ombrage du relief (lumière
## du nord-ouest), roche et neige des montagnes, arbres stylisés, marais, eau et rives, frontières
## des régions. Le shader suit aussi la saison (set_season, d'après MapSky.season) : neige au sol
## et sur les arbres, feuillage roux, prés secs, fleurs, glace au bord de l'eau. Les routes, les ponts et les noms sont des tracés vectoriels posés par-dessus,
## enregistrés une seule fois (LandLayer ne se redessine pas) ; seuls les noms des régions, qui
## suivent le zoom, sont redessinés avec la couche vivante.

const PIX := 2.0 ## Taille d'un « pixel » du fond (pixels de carte)
const WATER_RANGE := 128.0 ## Étendue de la distance à l'eau codée dans la texture (± la moitié)
const WARP_RANGE := MapData.REGION_WARP * 2.4 ## Étendue de l'ondulation des frontières codée dans la texture
const PEAK_STEP := 30.0 ## Espacement des pics dessinés sur les montagnes
const HILL_STEP := 42.0 ## Espacement des bosses dessinées sur les collines
const ROAD_DARK := Color(0.32, 0.23, 0.13)
const ROAD_MAIN := Color(0.82, 0.7, 0.47)
const ROAD_LANE := Color(0.72, 0.61, 0.42)
const ROAD_TRAIL := Color(0.5, 0.4, 0.27)
const WILD_COLOR := Color(0.45, 0.42, 0.4) ## Régions sans seigneur

static var fields_tex: ImageTexture = null ## R : eau, G : relief, B : forêt, A : montagne
static var fields2_tex: ImageTexture = null ## R : marais, G et B : ondulation des frontières
static var peaks: Array[Vector3] = [] ## Pics des montagnes (x, y, taille), du nord au sud
static var hills: Array[Vector3] = [] ## Bosses des collines (x, y, taille)
static var shader: Shader = null


## Construit les textures de champs (une fois : la carte ne change pas).
static func build() -> void:
	if fields_tex != null:
		return
	var f := MapData.fields()
	var w: int = f["w"]
	var h: int = f["h"]
	var water: PackedFloat32Array = f["water"]
	var height: PackedFloat32Array = f["height"]
	var forest: PackedFloat32Array = f["forest"]
	var mount: PackedFloat32Array = f["mount"]
	var marsh: PackedFloat32Array = f["marsh"]
	var warp: PackedVector2Array = f["warp"]
	var ground: PackedByteArray = f["ground"]
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(w * h * 4)
	b.resize(w * h * 4)
	for i in w * h:
		var k := i * 4
		a[k] = clampi(int((0.5 + water[i] / WATER_RANGE) * 255.0), 0, 255)
		a[k + 1] = clampi(int(height[i] * 255.0), 0, 255)
		a[k + 2] = clampi(int(forest[i] * 255.0), 0, 255)
		a[k + 3] = clampi(int(mount[i] * 255.0), 0, 255)
		b[k] = clampi(int(marsh[i] * 255.0), 0, 255)
		b[k + 1] = clampi(int((0.5 + warp[i].x / WARP_RANGE) * 255.0), 0, 255)
		b[k + 2] = clampi(int((0.5 + warp[i].y / WARP_RANGE) * 255.0), 0, 255)
		b[k + 3] = 255
	fields_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, a))
	fields2_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, b))
	shader = Shader.new()
	shader.code = SHADER
	# Pics et bosses sur une grille irrégulière : un par case de PEAK_STEP / HILL_STEP px
	for y in range(0, int(MapData.SIZE.y), int(PEAK_STEP)):
		for x in range(0, int(MapData.SIZE.x), int(PEAK_STEP)):
			var p := Vector2(x, y) + Vector2(_hash(x, y, 1), _hash(x, y, 2)) * PEAK_STEP
			var c := MapData.cell_of(p)
			var i := c.y * w + c.x
			if ground[i] == MapData.Ground.MOUNTAIN and not MapData.is_road(p):
				peaks.append(Vector3(p.x, p.y, 0.6 + 0.6 * mount[i] + 0.3 * _hash(x, y, 3)))
	for y in range(0, int(MapData.SIZE.y), int(HILL_STEP)):
		for x in range(0, int(MapData.SIZE.x), int(HILL_STEP)):
			var p := Vector2(x, y) + Vector2(_hash(x, y, 4), _hash(x, y, 5)) * HILL_STEP
			var c := MapData.cell_of(p)
			if ground[c.y * w + c.x] == MapData.Ground.HILLS and _hash(x, y, 6) < 0.55 and not MapData.is_road(p):
				hills.append(Vector3(p.x, p.y, 0.8 + 0.5 * _hash(x, y, 7)))
	peaks.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	hills.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)


## Nombre pseudo-aléatoire stable (0-1) d'après une position et un canal.
static func _hash(x: int, y: int, k: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10007) / 10007.0


## Matériau du fond : detail 1 pour la carte, 0 pour la mini-carte (sans arbres ni grain).
static func material(detail: float) -> ShaderMaterial:
	build()
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("fields", fields_tex)
	m.set_shader_parameter("fields2", fields2_tex)
	m.set_shader_parameter("map_size", MapData.SIZE)
	m.set_shader_parameter("pix", PIX if detail > 0.5 else MapData.CELL)
	m.set_shader_parameter("detail", detail)
	var cols := PackedVector3Array()
	var seeds := PackedVector2Array()
	for i in MapData.REGIONS.size():
		var c := region_color(i)
		cols.append(Vector3(c.r, c.g, c.b))
		seeds.append(MapData.REGIONS[i]["pos"])
	while cols.size() < 16:
		cols.append(Vector3(0.5, 0.5, 0.5))
		seeds.append(Vector2(-1e6, -1e6))
	m.set_shader_parameter("region_colors", cols)
	m.set_shader_parameter("seeds", seeds)
	m.set_shader_parameter("warp_range", WARP_RANGE)
	return m


## Saison du terrain (map : MapSky.season) : neige, automne, été, printemps (0 à 1).
static func set_season(m: ShaderMaterial, season: Dictionary) -> void:
	if m == null:
		return
	for k in ["snow", "autumn", "summer", "spring"]:
		m.set_shader_parameter(k, float(season.get(k, 0.0)))


## Couleur d'une région : celle de sa faction (gris pour les terres sans seigneur).
static func region_color(i: int) -> Color:
	var f := int(MapData.REGIONS[i]["faction"])
	return WILD_COLOR if f < 0 else CampaignState.FACTIONS[f]["color"]


# ---------------------------------------------------------------- Relief

## Bosses des collines puis pics des montagnes (face éclairée à l'ouest, ombre à l'est, neige sur
## les plus hauts), sous les routes. Dessiné une fois.
static func draw_relief(ci: CanvasItem) -> void:
	for h in hills:
		var p := Vector2(h.x, h.y)
		var r := 9.0 * h.z
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(p + Vector2(-r + 2.0 * r * k / 8.0, -sin(PI * k / 8.0) * r * 0.55))
		ci.draw_polyline(pts, Color(0.3, 0.28, 0.14, 0.55), 2.0)
		ci.draw_polyline(pts.slice(0, 5), Color(0.86, 0.82, 0.55, 0.35), 1.0)
	for pk in peaks:
		var p := Vector2(pk.x, pk.y)
		var w := 17.0 * pk.z
		var hgt := w * 1.05
		var top := p + Vector2(w * 0.08, -hgt)
		var left := p + Vector2(-w, 0)
		var right := p + Vector2(w, 0)
		var mid := p + Vector2(w * 0.2, 0)
		ci.draw_colored_polygon(PackedVector2Array([left + Vector2(4, 3), right + Vector2(6, 3), top + Vector2(6, 3)]), Color(0, 0, 0, 0.18))
		ci.draw_colored_polygon(PackedVector2Array([left, mid, top]), Color(0.66, 0.62, 0.56))
		ci.draw_colored_polygon(PackedVector2Array([mid, right, top]), Color(0.41, 0.37, 0.34))
		if pk.z > 1.2:
			var k := 0.34
			var sl := top.lerp(left, k)
			var sr := top.lerp(right, k)
			var sm := top.lerp(mid, k * 1.15)
			ci.draw_colored_polygon(PackedVector2Array([sl, sm, top]), Color(0.96, 0.96, 0.98))
			ci.draw_colored_polygon(PackedVector2Array([sm, sr, top]), Color(0.78, 0.8, 0.86))
		ci.draw_polyline(PackedVector2Array([left, top, right]), Color(0.22, 0.19, 0.17), 1.5)


# ---------------------------------------------------------------- Routes et ponts

## Routes (grandes routes, chemins, sentiers en pointillés) puis ponts. Dessiné une fois.
static func draw_roads(ci: CanvasItem) -> void:
	var order: Array[int] = []
	for k in MapData.roads().size():
		order.append(k)
	# Les sentiers d'abord, les grandes routes par-dessus
	order.sort_custom(func(x: int, y: int) -> bool: return MapData.road_class(x) > MapData.road_class(y))
	for k in order:
		var pts := MapData.road_points(k)
		match MapData.road_class(k):
			MapData.RoadClass.MAIN:
				ci.draw_polyline(pts, ROAD_DARK, 8.0)
				ci.draw_polyline(pts, ROAD_MAIN, 4.5)
				for p in pts: # Joints arrondis
					ci.draw_circle(p, 2.2, ROAD_MAIN)
			MapData.RoadClass.LANE:
				ci.draw_polyline(pts, Color(ROAD_DARK, 0.85), 5.0)
				ci.draw_polyline(pts, ROAD_LANE, 2.6)
			_:
				var acc := 0.0
				for j in pts.size() - 1:
					var a := pts[j]
					var b := pts[j + 1]
					var len := a.distance_to(b)
					var s := 0.0
					while s < len:
						var e := minf(s + 6.0, len)
						if fposmod(acc + s, 11.0) < 6.0:
							ci.draw_line(a.lerp(b, s / len), a.lerp(b, e / len), ROAD_TRAIL, 2.2)
						s = e + (5.0 if fposmod(acc + s, 11.0) < 6.0 else 0.0)
					acc += len
	for br in MapData.bridges():
		draw_bridge(ci, br["a"], br["b"], MapData.road_class(int(br["road"])))


## Pont de bois ou de pierre entre deux rives.
static func draw_bridge(ci: CanvasItem, a: Vector2, b: Vector2, cls: int) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var half := 7.0 if cls == MapData.RoadClass.MAIN else 5.0
	var stone := cls == MapData.RoadClass.MAIN
	var deck := Color(0.66, 0.62, 0.56) if stone else Color(0.55, 0.39, 0.22)
	var edge := Color(0.3, 0.27, 0.24) if stone else Color(0.28, 0.18, 0.1)
	var shadow := PackedVector2Array([a + n * half + Vector2(2, 3), b + n * half + Vector2(2, 3), b - n * half + Vector2(2, 3), a - n * half + Vector2(2, 3)])
	ci.draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	var poly := PackedVector2Array([a + n * half, b + n * half, b - n * half, a - n * half])
	ci.draw_colored_polygon(poly, deck)
	if not stone: # Planches
		var len := a.distance_to(b)
		var k := 3.0
		while k < len:
			var p := a + d * k
			ci.draw_line(p + n * half, p - n * half, edge.lerp(deck, 0.4), 1.0)
			k += 4.0
	ci.draw_line(a + n * half, b + n * half, edge, 1.5)
	ci.draw_line(a - n * half, b - n * half, edge, 1.5)


# ---------------------------------------------------------------- Noms sur la carte

## Noms des forêts, chaînes, lacs et rivières (en italique), posés une fois sur le fond. Ils
## restent lisibles à tous les zooms usuels (taille de carte fixe).
static func draw_feature_names(ci: CanvasItem, font: Font) -> void:
	var it := FontVariation.new()
	it.base_font = font
	it.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	var wood := Color(0.86, 0.95, 0.72, 0.9)
	var rock := Color(0.97, 0.93, 0.85, 0.92)
	var aqua := Color(0.82, 0.92, 1.0, 0.95)
	for f in MapData.FORESTS:
		label(ci, it, f["center"], str(f["name"]), 15, wood, 0.0)
	for m in MapData.MOUNTAINS:
		var pts: Array = m["points"]
		var mid: Vector2 = (pts[pts.size() / 2] + pts[(pts.size() - 1) / 2]) * 0.5
		label(ci, it, mid.clamp(Vector2(140, 30), MapData.SIZE - Vector2(140, 30)), str(m["name"]), 15, rock, 0.0)
	for l in MapData.LAKES:
		label(ci, it, l["center"], str(l["name"]), 13, aqua, 0.0)
	for i in MapData.RIVERS.size():
		var pts := MapData.river_points(i)
		var j := pts.size() / 2
		var a := pts[maxi(j - 3, 0)]
		var b := pts[mini(j + 3, pts.size() - 1)]
		var ang := (b - a).angle()
		if absf(ang) > PI * 0.5:
			ang = wrapf(ang + PI, -PI, PI)
		label(ci, it, pts[j] + (b - a).normalized().orthogonal() * -16.0, CampaignState.cap_first(str(MapData.RIVERS[i]["name"])), 12, aqua, ang)
	for y in [560.0, 2330.0]:
		var a := Vector2(MapData.river_x(y - 30.0), y - 30.0)
		var b := Vector2(MapData.river_x(y + 30.0), y + 30.0)
		var ang := (b - a).angle()
		if absf(ang) > PI * 0.5:
			ang = wrapf(ang + PI, -PI, PI)
		label(ci, it, Vector2(MapData.river_x(y) + 28.0, y), CampaignState.cap_first(MapData.RIVER_NAME), 13, aqua, ang)


## Un nom centré en p, avec un liseré sombre, éventuellement incliné.
static func label(ci: CanvasItem, font: Font, p: Vector2, text: String, size: int, col: Color, angle: float, scale := 1.0) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_set_transform(p, angle, Vector2(scale, scale))
	var at := Vector2(-w * 0.5, size * 0.35)
	ci.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.08, 0.06, 0.04, col.a * 0.75))
	ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	ci.draw_set_transform(Vector2.ZERO)


## Noms des régions, en capitales espacées, à taille d'écran constante ; visibles en vue
## éloignée seulement (ils s'effacent quand on zoome).
static func draw_region_names(ci: CanvasItem, font: Font, zoom: float, view: Rect2) -> void:
	var alpha := clampf((0.9 - zoom) / 0.35, 0.0, 1.0)
	if alpha <= 0.0:
		return
	for i in MapData.REGIONS.size():
		var r: Dictionary = MapData.REGIONS[i]
		var p := MapData.region_label_pos(i)
		if not view.grow(300.0 / zoom).has_point(p):
			continue
		var col := region_color(i).lightened(0.35)
		col.a = alpha
		label(ci, font, p, spaced(str(r["name"])), 20, col, 0.0, 1.0 / zoom)
		var f := int(r["faction"])
		var sub := "sans seigneur" if f < 0 else str(CampaignState.FACTIONS[f]["name"])
		label(ci, font, p + Vector2(0, 22.0 / zoom), sub, 12, Color(0.95, 0.9, 0.8, alpha * 0.85), 0.0, 1.0 / zoom)


## « VAL D'OMBRE » -> « V A L   D ' O M B R E ».
static func spaced(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		out += ("  " if ch == " " else ch + " ")
	return out.strip_edges()


# ---------------------------------------------------------------- Shader du fond

const SHADER := """
shader_type canvas_item;

uniform sampler2D fields : filter_linear, repeat_disable;
uniform sampler2D fields2 : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(3840.0, 3120.0);
uniform float pix = 2.0;
uniform float detail = 1.0;
uniform vec3 region_colors[16];
uniform vec2 seeds[16];
uniform float warp_range = 408.0;
uniform float snow = 0.0; // Neige au sol et sur les arbres (hiver)
uniform float autumn = 0.0; // Feuillage roux, herbe jaunie
uniform float summer = 0.0; // Prés secs, blés mûrs
uniform float spring = 0.0; // Herbe tendre et fleurs

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return v;
}

// Relief : hauteur des champs, crêtes plus marquées en montagne.
float relief(vec2 wp) {
	vec4 f = texture(fields, wp / map_size);
	float ridge = 1.0 - abs(fbm(wp * 0.012) * 2.0 - 1.0);
	return f.g + f.a * f.a * ridge * 0.35 * detail;
}

void fragment() {
	vec2 world = UV * map_size;
	vec2 wp = (floor(world / pix) + 0.5) * pix;
	vec2 uv = wp / map_size;
	vec4 f = texture(fields, uv);
	vec4 g = texture(fields2, uv);
	float n1 = fbm(wp * 0.0035);
	float n2 = fbm(wp * 0.03);
	float grain = mix(0.5, hash(floor(wp / pix)), detail);
	float sdf = (f.r - 0.5) * 128.0 + (n2 - 0.5) * 5.0 * detail;
	float mount = f.a;
	float marsh = g.r;
	float forest = f.b;

	// Herbe, prés plus clairs, champs secs
	vec3 col = mix(vec3(0.42, 0.56, 0.27), vec3(0.58, 0.66, 0.33), n1);
	col = mix(col, vec3(0.72, 0.67, 0.41), smoothstep(0.58, 0.72, n1 * 0.6 + n2 * 0.4) * 0.55);
	// Saisons : blés mûrs de l'été, herbe tendre du printemps, herbe jaunie de l'automne
	col = mix(col, vec3(0.8, 0.7, 0.36), summer * smoothstep(0.5, 0.68, n1 * 0.6 + n2 * 0.4) * 0.6);
	col = mix(col, col * vec3(0.95, 1.05, 0.9), spring);
	col = mix(col, vec3(0.62, 0.56, 0.3) * (0.85 + 0.3 * n1), autumn * 0.5);
	// Collines : teinte d'herbe rase
	col = mix(col, vec3(0.6, 0.58, 0.38), smoothstep(0.42, 0.7, f.g) * 0.6);
	// Montagne : roche, puis neige sur les crêtes
	vec3 rock = mix(vec3(0.47, 0.43, 0.4), vec3(0.64, 0.6, 0.55), n2);
	col = mix(col, rock, smoothstep(0.3, 0.58, mount));
	col = mix(col, vec3(0.86, 0.87, 0.9), smoothstep(0.96, 1.0, mount + (n2 - 0.5) * 0.1) * 0.5);
	// Marais : herbe sombre et flaques
	float m = smoothstep(0.3, 0.6, marsh);
	col = mix(col, vec3(0.38, 0.46, 0.33), m);
	if (marsh > 0.45 && n2 > 0.6) {
		col = mix(col, snow > 0.3 ? vec3(0.78, 0.86, 0.92) : vec3(0.3, 0.45, 0.5), 0.8);
	}
	// Neige : d'abord en plaques (selon le bruit), puis partout ; les marais restent plus sombres
	float cover = smoothstep(0.55, 0.75, n1 * 0.55 + n2 * 0.45 + snow * 0.75 - 0.2) * step(0.01, snow);
	vec3 snow_col = mix(vec3(0.86, 0.89, 0.95), vec3(0.97, 0.98, 1.0), n2);
	col = mix(col, snow_col, cover * (1.0 - 0.35 * m));
	// Ombrage du relief (lumière du nord-ouest)
	// (différences centrées sur une case de part et d'autre : pas de facettes de la grille)
	float e = 16.0;
	float gx = relief(wp - vec2(e, 0.0)) - relief(wp + vec2(e, 0.0));
	float gy = relief(wp - vec2(0.0, e)) - relief(wp + vec2(0.0, e));
	vec3 nrm = normalize(vec3(gx * 16.0, gy * 16.0, 1.0));
	float shade = dot(nrm, normalize(vec3(-0.6, -0.7, 0.75)));
	col *= 0.62 + 0.5 * shade;
	// Sous-bois et arbres stylisés (une couronne par case de 11 px, ombre portée au sud-est)
	forest += (n2 - 0.5) * 0.35 * detail;
	float fz = smoothstep(0.38, 0.62, forest);
	// Feuillage de saison : vert, roux en automne (sauf les sapins), poudré de neige en hiver
	vec3 wood = mix(vec3(0.16, 0.33, 0.15), vec3(0.5, 0.3, 0.12), autumn * 0.8);
	wood = mix(wood, vec3(0.62, 0.66, 0.68), snow * 0.55);
	if (detail < 0.5) {
		col = mix(col, wood, fz);
	} else if (forest > 0.2) {
		col = mix(col, mix(vec3(0.2, 0.33, 0.16), wood, 0.5 + 0.5 * max(autumn, snow)), fz * 0.85);
		float T = 11.0;
		vec2 cell = floor(wp / T);
		float best_y = -1e9;
		vec3 tree = vec3(0.0);
		bool shadow = false;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				float h = hash(c);
				vec2 ctr = (c + 0.2 + 0.6 * vec2(h, hash(c + 7.3))) * T;
				float dens = texture(fields, ctr / map_size).b + (fbm(ctr * 0.03) - 0.5) * 0.35;
				if (dens < 0.45 + 0.22 * hash(c + 3.1)) {
					continue;
				}
				float r = T * (0.55 + 0.3 * hash(c + 1.7));
				vec2 d = wp - ctr;
				if (length(d - vec2(2.5, 3.5)) < r) {
					shadow = true;
				}
				if (length(d) < r && ctr.y > best_y) {
					best_y = ctr.y;
					float lit = dot(d / r, vec2(-0.7, -0.7));
					float hs = hash(c + 5.5);
					vec3 leaf = mix(vec3(0.17, 0.36, 0.15), vec3(0.27, 0.45, 0.17), hs);
					float conifer = step(0.72, hash(c + 9.1));
					// Automne : orange, rouge, or ou brun selon l'arbre ; les sapins restent verts
					vec3 fall = hs < 0.3 ? vec3(0.68, 0.37, 0.12) : (hs < 0.5 ? vec3(0.55, 0.2, 0.1) : (hs < 0.75 ? vec3(0.72, 0.56, 0.2) : vec3(0.46, 0.3, 0.16)));
					leaf = mix(leaf, fall, autumn * 0.9 * (1.0 - conifer));
					// Hiver : branches nues (gris brun) pour les feuillus, vert sombre pour les sapins
					leaf = mix(leaf, mix(vec3(0.42, 0.36, 0.3), vec3(0.13, 0.27, 0.16), conifer), snow * 0.8);
					leaf *= 0.82 + 0.38 * lit;
					// Neige posée sur le haut de la couronne
					if (snow > 0.05 && dot(d / r, vec2(-0.35, -0.94)) > 0.35 - 0.3 * snow) {
						leaf = mix(leaf, vec3(0.93, 0.95, 0.99) * (0.9 + 0.12 * lit), 0.9 * min(snow * 1.5, 1.0));
					}
					if (length(d) > r - 1.6) {
						leaf *= 0.7;
					}
					tree = leaf;
				}
			}
		}
		if (shadow) {
			col *= 0.72;
		}
		if (best_y > -1e8) {
			col = tree;
		}
	}
	// Grain : brins, fleurs, cailloux
	if (detail > 0.5 && forest < 0.35 && mount < 0.3) {
		float s = hash(floor(wp / pix) + 0.37);
		if (s > 0.985 - spring * 0.006 && snow < 0.5) {
			// Fleurs : blanches et jaunes, plus nombreuses (et colorées) au printemps
			vec3 flower = mix(vec3(0.9, 0.86, 0.6), hash(floor(wp / pix) + 1.3) < 0.7 ? vec3(0.95, 0.88, 0.4) : vec3(0.82, 0.55, 0.72), spring);
			col = mix(col, flower, 0.5 + 0.15 * spring);
		} else if (s < 0.02) {
			col *= 0.85;
		}
	}
	col *= 0.97 + 0.06 * grain;
	// Régions : la graine la plus proche du point ondulé (comme MapData) ; liseré de la couleur
	// de la faction de chaque côté, frontière en tirets
	vec2 rp = wp + (g.gb - 0.5) * warp_range;
	float d1 = 1e9;
	float d2 = 1e9;
	int rid = 0;
	for (int k = 0; k < 16; k++) {
		float d = distance(rp, seeds[k]);
		if (d < d1) {
			d2 = d1;
			d1 = d;
			rid = k;
		} else if (d < d2) {
			d2 = d;
		}
	}
	float bd = (d2 - d1) * 0.5;
	vec3 fcol = region_colors[rid];
	if (sdf > 2.0) {
		col = mix(col, fcol, (0.42 * detail + 0.25) * (1.0 - smoothstep(1.5, 16.0, bd)));
		if (bd < mix(9.0, 2.2, detail) && (detail < 0.5 || mod(wp.x + wp.y, 20.0) < 12.0)) {
			col = mix(col, vec3(0.32, 0.1, 0.08), 0.85);
		}
	}
	// Eau : rive sablonneuse, peu profond clair, reflets
	if (sdf < 3.5) {
		vec3 sand = vec3(0.74, 0.69, 0.5);
		if (sdf >= 0.0) {
			col = mix(sand, col, smoothstep(1.5, 3.5, sdf) * 0.6);
		} else {
			float depth = clamp(-sdf / 36.0, 0.0, 1.0);
			col = mix(vec3(0.36, 0.58, 0.72), vec3(0.15, 0.31, 0.52), depth);
			if (sdf > -2.0) {
				col = mix(col, vec3(0.9, 0.95, 1.0), 0.25);
			}
			// Hiver : glace au bord de l'eau (et sur les mares)
			if (snow > 0.3 && sdf > -4.0 - 22.0 * snow * (0.6 + 0.4 * n2)) {
				col = mix(col, vec3(0.78, 0.86, 0.92) * (0.92 + 0.12 * grain), 0.85);
			}
			float wave = vnoise(wp * vec2(0.06, 0.22));
			if (detail > 0.5 && wave > 0.78 && hash(floor(wp / pix)) > 0.4) {
				col += vec3(0.12, 0.13, 0.14);
			}
		}
	}
	// Bord de la carte assombri
	vec2 edge = min(wp, map_size - wp);
	col *= 0.7 + 0.3 * smoothstep(0.0, 70.0, min(edge.x, edge.y));
	COLOR = vec4(col, 1.0);
}
"""
