class_name SpriteBank
extends RefCounted
## Sprites pixel art « MiniWorld Sprites » de Shade (CC0, voir CREDITS.md).
## Si un fichier manque, has_unit() / has_trees() renvoient false et le jeu
## revient au dessin en code.
## Les unités sans planche à elles (arbalétriers, chevaliers à pied, archers montés) reprennent
## celle d'un type proche, teintée (« tint ») ; battle_renderer.gd y ajoute leurs détails en code.

const DOWN := 0
const UP := 1
const RIGHT := 2
const LEFT := 3

const UNIT_DIR := "res://assets/sprites/units/"
const TEAM_SUFFIX := ["Cyan", "Red"] ## Joueur, ennemi

## Description des planches. Lignes indexées par direction [bas, haut, droite, gauche].
## « idle » absent = première image de la marche.
const UNITS := {
	"men_at_arms": {
		"file": "Swordsman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 6, 7], "attack_n": 4,
	},
	"spear": {
		"file": "Spearman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [], "attack_n": 0, # Planche d'attaque irrégulière : on fait une fente en code
	},
	"archer": {
		"file": "Bowman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 7, 6], "attack_n": 3,
	},
	"cavalry": {
		"file": "%sKnight.png", "cell": 32, "foot": Vector2(16, 25),
		"walk": [1, 10, 4, 7], "walk_n": 4,
		"idle": [0, 9, 3, 6],
		"attack": [2, 11, 5, 8], "attack_n": 4,
		"barding": true, # Caparaçon aux couleurs du camp (barding_image)
	},
	"crossbow": {
		"file": "Bowman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 7, 6], "attack_n": 3,
		"tint": Color(0.92, 0.82, 0.68), # Gambison de toile écrue
	},
	"foot_knight": {
		"file": "Swordsman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 6, 7], "attack_n": 4,
		"tint": Color(0.93, 0.96, 1.0), # Harnois blanc (repeint en plates polies, voir BattleRenderer.look_of)
	},
	"horse_archer": {
		"file": "%sKnight.png", "cell": 32, "foot": Vector2(16, 25),
		"walk": [1, 10, 4, 7], "walk_n": 4,
		"idle": [0, 9, 3, 6],
		"attack": [2, 11, 5, 8], "attack_n": 4,
		"tint": Color(1.0, 0.9, 0.7), # Harnachement de cuir
	},
}

## Équipement visible (pièces d'Equipment, qualités 1 à 3) : les planches sont repeintes une fois
## par combinaison casque/armure utilisée (dressed_tex) ; l'éclat des armes est dessiné par le rendu
## au bout de la lame (blade_tip). Couleurs de base, nuancées par la luminosité d'origine.
const HELMET_COLORS: Array[Color] = [Color.WHITE, Color(0.46, 0.43, 0.4), Color(0.8, 0.83, 0.88), Color(0.92, 0.95, 1.0)]
const ARMOR_COLORS: Array[Color] = [Color.WHITE, Color(0.88, 0.82, 0.66), Color(0.52, 0.24, 0.18), Color(0.86, 0.9, 1.0)]
const GOLD := Color(0.95, 0.78, 0.3)
const RIVET := Color(0.86, 0.72, 0.38)
## Bas de la bande de la tête (rangées de la case au-dessus : casque ; en dessous : corps).
const HEAD_BAND := {16: 9, 32: 12}
const BODY_BAND := {16: 15, 32: 19}

var unit_tex := {} ## "type/équipe" -> Texture2D
var dressed := {} ## "type/équipe/casque/armure" -> Texture2D (planche repeinte)
var tips := {} ## "type" -> {Vector2i(colonne, rangée) -> pointe de la lame dans la case}
var trees: Array[Dictionary] = [] ## {"tex", "src"} pour chaque variante d'arbre
var grass_tiles: Array[Texture2D] = []
var ok := false ## Vrai si toutes les unités sont disponibles


func _init() -> void:
	var all := true
	for type in UNITS:
		var file: String = UNITS[type]["file"]
		for team in 2:
			var path := UNIT_DIR + (file % TEAM_SUFFIX[team])
			var t := _load(path)
			if t != null:
				unit_tex["%s/%d" % [type, team]] = t
			else:
				all = false
	ok = all

	# Arbres : Trees.png (cases 1 à 3) et PineTrees.png (case 1) ;
	# la case 0 est une souche et le pin de la case 2 est enneigé.
	var leafy := _load("res://assets/sprites/nature/Trees.png")
	if leafy != null:
		for i in [1, 2, 3, 3]:
			trees.append({"tex": leafy, "src": Rect2(i * 16, 0, 16, 16)})
	var pine := _load("res://assets/sprites/nature/PineTrees.png")
	if pine != null:
		trees.append({"tex": pine, "src": Rect2(16, 0, 16, 16)})


func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Sprite manquant, dessin en code utilisé : " + path)
		return null
	return load(path) as Texture2D


## Planche repeinte avec l'équipement (casque et armure de qualité 0 à 3). Sans accès aux pixels
## (mode sans affichage), la planche d'origine.
func dressed_tex(type: String, team: int, helmet: int, armor: int) -> Texture2D:
	var base: Texture2D = unit_tex["%s/%d" % [type, team]]
	var barded: bool = UNITS[type].get("barding", false)
	if helmet <= 0 and armor <= 0 and not barded:
		return base
	var key := "%s/%d/%d/%d" % [type, team, helmet, armor]
	if dressed.has(key):
		return dressed[key]
	var img := pixels(base)
	var tex := base
	if img != null:
		dress_image(img, int(UNITS[type]["cell"]), helmet, armor)
		if barded:
			barding_image(img, int(UNITS[type]["cell"]), CAPARISON[team])
		tex = ImageTexture.create_from_image(img)
	dressed[key] = tex
	return tex


## Copie RGBA8 des pixels d'une texture (null si inaccessibles).
static func pixels(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Pixel « métal » (gris peu saturé, ni contour ni reflet blanc) d'une pièce d'armure ou d'un casque.
static func is_metal(c: Color) -> bool:
	return c.a > 0.5 and c.s < 0.2 and c.v > 0.3 and c.v < 0.86


## Vrai si (x, y) appartient à une hampe ou une lame d'un pixel de large (à ne pas repeindre).
static func is_shaft(img: Image, x: int, y: int, x0: int, cell: int) -> bool:
	var l := img.get_pixel(x - 1, y) if x > x0 else Color(0, 0, 0, 0)
	var r := img.get_pixel(x + 1, y) if x < x0 + cell - 1 else Color(0, 0, 0, 0)
	return (l.a < 0.5 or l.v < 0.25) and (r.a < 0.5 or r.v < 0.25)


## Repeint chaque case d'une planche : casque (haut de la case) et armure (corps), en gardant les
## ombres d'origine. Formes : bord du chapel de fer (1), pointe du bassinet (2), pointe et cercle
## doré du grand bassinet (3) ; rivets de la brigandine, reflets du harnois.
static func dress_image(img: Image, cell: int, helmet: int, armor: int) -> void:
	@warning_ignore("integer_division")
	var head_end: int = HEAD_BAND.get(cell, cell / 2)
	var body_end: int = BODY_BAND.get(cell, cell)
	var outline := Color(0.08, 0.07, 0.07)
	@warning_ignore("integer_division")
	for cy in img.get_height() / cell:
		@warning_ignore("integer_division")
		for cx in img.get_width() / cell:
			var x0 := cx * cell
			var y0 := cy * cell
			# Pixels de métal de la case (hors hampes), relevés avant de rien repeindre
			var metal: Array[Vector2i] = []
			var top := cell
			for y in body_end:
				for x in cell:
					if is_metal(img.get_pixel(x0 + x, y0 + y)) and not is_shaft(img, x0 + x, y0 + y, x0, cell):
						metal.append(Vector2i(x, y))
						if y < head_end:
							top = mini(top, y)
			# Largeur du casque trois rangées sous son sommet (le front)
			var fy := mini(top + 3, head_end - 1)
			var left := cell
			var right := -1
			for m in metal:
				if m.y == fy:
					left = mini(left, m.x)
					right = maxi(right, m.x)
			for m in metal:
				var c := img.get_pixel(x0 + m.x, y0 + m.y)
				var k := 0.55 + c.v * 0.6
				if m.y < head_end:
					if helmet > 0:
						var hc := HELMET_COLORS[helmet] * k
						img.set_pixel(x0 + m.x, y0 + m.y, Color(hc, 1.0))
				elif armor > 0:
					var ac := ARMOR_COLORS[armor] * (k if armor != 3 else 0.4 + c.v * 0.9)
					if armor == 2 and (m.x + m.y) % 3 == 0:
						ac = RIVET
					img.set_pixel(x0 + m.x, y0 + m.y, Color(ac, 1.0))
			if helmet <= 0 or top >= head_end or right <= left:
				continue
			match helmet:
				1: # Chapel de fer : un large bord qui dépasse de chaque côté
					for x in [left - 3, left - 2, left - 1, right + 1, right + 2, right + 3]:
						if x >= 0 and x < cell:
							img.set_pixel(x0 + x, y0 + fy, outline if x in [left - 3, right + 3] else HELMET_COLORS[1])
				2, 3: # Bassinet : une pointe au sommet
					@warning_ignore("integer_division")
					var mid := (left + right) / 2
					if top >= 2:
						img.set_pixel(x0 + mid, y0 + top - 1, HELMET_COLORS[helmet])
						img.set_pixel(x0 + mid, y0 + top - 2, outline)
					if helmet == 3: # Cercle doré du grand bassinet
						for m in metal:
							if m.y == fy:
								img.set_pixel(x0 + m.x, y0 + m.y, GOLD)


## Couleurs des caparaçons (joueur, ennemi) et de leur galon.
const CAPARISON: Array[Color] = [Color(0.2, 0.34, 0.8), Color(0.74, 0.14, 0.12)]
const HEM := Color(0.92, 0.78, 0.36)
## Rangées du cheval couvertes par le caparaçon dans une case de 32 (au-dessous : les jambes).
const BARD_TOP := 14
const BARD_BOTTOM := 22


## Pixel de robe de cheval (brun ou fauve, assez saturé).
static func is_horse(c: Color) -> bool:
	return c.a > 0.5 and c.s > 0.3 and c.v > 0.2 and (c.h < 0.13 or c.h > 0.96)


## Caparaçon des cavaliers lourds : la robe du cheval, de BARD_TOP à BARD_BOTTOM, repeinte à la
## couleur du camp (ombres gardées), un galon doré sur la rangée du bas et une bande sur deux plus
## sombre ; les jambes restent nues. Les archers montés n'en ont pas.
static func barding_image(img: Image, cell: int, col: Color) -> void:
	@warning_ignore("integer_division")
	for cy in img.get_height() / cell:
		@warning_ignore("integer_division")
		for cx in img.get_width() / cell:
			var x0 := cx * cell
			var y0 := cy * cell
			for y in range(BARD_TOP, mini(BARD_BOTTOM + 1, cell)):
				for x in cell:
					var c := img.get_pixel(x0 + x, y0 + y)
					if not is_horse(c):
						continue
					var k := 0.5 + c.v * 0.6
					var cc := col * k
					if y == BARD_BOTTOM or (y == BARD_BOTTOM - 1 and not is_horse(img.get_pixel(x0 + x, y0 + y + 1))):
						cc = HEM * k
					elif int(x / 3.0) % 2 == 1:
						cc = cc.darkened(0.15)
					img.set_pixel(x0 + x, y0 + y, Color(cc, 1.0))


## Pointe de la lame (ou de l'arme) dans la case src d'une planche, pour l'éclat des bonnes armes :
## le plus haut pixel blanc d'une hampe. Vector2(-1, -1) si inconnue (pas d'accès aux pixels).
func blade_tip(type: String, src: Rect2) -> Vector2:
	if not tips.has(type):
		tips[type] = find_tips(unit_tex.get("%s/0" % type), int(UNITS[type]["cell"]))
	return tips[type].get(Vector2i(int(src.position.x), int(src.position.y)), Vector2(-1, -1))


static func find_tips(tex: Texture2D, cell: int) -> Dictionary:
	var out := {}
	if tex == null:
		return out
	var img := pixels(tex)
	if img == null:
		return out
	@warning_ignore("integer_division")
	for cy in img.get_height() / cell:
		@warning_ignore("integer_division")
		for cx in img.get_width() / cell:
			var x0 := cx * cell
			var y0 := cy * cell
			var found := false
			for y in cell:
				for x in cell:
					var c := img.get_pixel(x0 + x, y0 + y)
					if c.a > 0.5 and c.v > 0.86 and c.s < 0.2:
						out[Vector2i(x0, y0)] = Vector2(x, y)
						found = true
						break
				if found:
					break
	return out


func has_unit(type: String, team: int) -> bool:
	return unit_tex.has("%s/%d" % [type, team])


func has_trees() -> bool:
	return not trees.is_empty()


## Direction de la planche la plus proche d'un vecteur.
static func dir_of(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return RIGHT if v.x > 0.0 else LEFT
	return DOWN if v.y > 0.0 else UP


## Teinte à appliquer à la planche d'un type (blanc = telle quelle).
static func tint(type: String) -> Color:
	return UNITS[type].get("tint", Color.WHITE)


## Image à afficher : {"tex", "src" (zone de la planche), "foot" (point des pieds), "tint"}.
## anim : "idle", "walk" ou "attack" ; t : temps d'animation (images) ou progression (0..1) pour l'attaque.
func frame(type: String, team: int, dir: int, anim: String, t: float) -> Dictionary:
	var d: Dictionary = UNITS[type]
	var cell: int = d["cell"]
	var row: int
	var col := 0
	match anim:
		"attack":
			var n: int = d["attack_n"]
			if n > 0:
				row = d["attack"][dir]
				col = clampi(int(t * n), 0, n - 1)
			else:
				row = d["walk"][dir]
		"walk":
			row = d["walk"][dir]
			col = int(t) % int(d["walk_n"])
		_:
			if d.has("idle"):
				row = d["idle"][dir]
			else:
				row = d["walk"][dir]
	return {
		"tex": unit_tex["%s/%d" % [type, team]],
		"src": Rect2(col * cell, row * cell, cell, cell),
		"foot": d["foot"],
		"tint": d.get("tint", Color.WHITE),
	}


## Variante d'arbre stable pour une position donnée.
func tree_at(p: Vector2) -> Dictionary:
	var h := absi(int(p.x) * 73856093 ^ int(p.y) * 19349663)
	return trees[h % trees.size()]
