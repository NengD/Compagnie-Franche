class_name Portrait
extends RefCounted
## Portraits en pixels assemblés à partir de pièces tirées d'une graine : forme du visage, peau,
## yeux, cheveux (coupe et couleur), barbe, cicatrice ou bandeau, couvre-chef ou casque, habit.
## make(graine, options) renvoie un dictionnaire de pièces (stable : même graine, même portrait) ;
## draw() le peint dans un rectangle ; View est le Control des panneaux.
## Rien n'est sauvegardé : la graine se déduit de celle de la campagne (capitaine, compagnons)
## ou de l'identifiant du groupe rencontré, qui sont déjà dans la sauvegarde.
##
## Options de make : « role » (ROLE_GEAR), « woman », « clothes » (Color), « arms » (armoiries
## Heraldry : tabard du capitaine), « name » (quelques surnoms se voient : le Roux, Barbe-Grise,
## le Borgne, Frère...).

const W := 24 ## Grille du portrait (cases), peinte à l'échelle du rectangle
const H := 28
const SHAPES := ["oval", "round", "square", "long"]
## Demi-largeur du visage, ligne par ligne (de y = 6 au menton, y = 19).
const SHAPE_ROWS := {
	"oval": [4, 5, 6, 6, 6, 6, 6, 6, 6, 5, 5, 4, 3, 2],
	"round": [4, 5, 6, 7, 7, 7, 7, 7, 7, 6, 6, 5, 4, 2],
	"square": [5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 4],
	"long": [4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 4, 4, 3],
}
const SKINS := ["#f1d2b6", "#e3b48f", "#c98f68", "#a86f4c", "#7a4e33"]
const HAIR_COLORS := {"noir": "#231a14", "brun": "#4a3020", "châtain": "#7a4f2a", "roux": "#a5482a",
	"blond": "#d6b25e", "gris": "#9a948c", "blanc": "#dcd8d0"}
const EYES := ["#3a2a1c", "#4a6a8a", "#5a7040", "#6a5030"]
const HAIRS := ["short", "long", "bowl", "curly", "bald", "tonsure"]
const WOMAN_HAIRS := ["long", "braid", "bun"]
const BEARDS := ["none", "stubble", "short", "full", "moustache", "goatee"]
const SCARS := ["none", "cheek", "brow", "lip", "eyepatch"]
const HEADGEAR := ["none", "kettle", "nasal", "coif", "hood", "felt", "straw", "kerchief"]
## Couvre-chefs possibles selon le rôle (tirés à égalité ; un doublon pèse double).
const ROLE_GEAR := {
	"captain": ["none", "none", "nasal", "kettle", "coif"],
	"sergeant": ["kettle", "nasal", "coif", "none"],
	"surgeon": ["none", "hood", "felt"],
	"scout": ["hood", "hood", "none", "felt"],
	"quartermaster": ["felt", "none", "none"],
	"soldier": ["kettle", "nasal", "coif", "kettle"],
	"bandit": ["hood", "none", "coif", "kettle"],
	"deserter": ["kettle", "none", "hood"],
	"villager": ["straw", "none", "hood"],
	"merchant": ["felt", "felt", "none"],
	"": ["none", "hood", "felt", "kettle"],
}
## Habits selon le rôle (si « clothes » n'est pas donné).
const ROLE_CLOTHES := {
	"surgeon": ["#3c3a44", "#5a2a2a"], "scout": ["#3d5530", "#5a4a2a"], "quartermaster": ["#6a4a24", "#2f4a6a"],
	"bandit": ["#4a3a2a", "#3a3530"], "villager": ["#8a7a5a", "#6a7a5a", "#7a5a3a"], "merchant": ["#6a2a4a", "#2a4a6a", "#7a5a1a"],
	"": ["#5a4030", "#40506a", "#5a6a3a", "#6a3030"],
}
## Les compagnons et capitaines qui sont des femmes (noms de companions.gd).
const WOMEN := ["Mahaut la Rude", "Ysabeau la Savante", "Aude la Rousse", "Tiphaine l'Écureuil",
	"Guillemette Bourse-Plate", "Pernelle l'Avisée"]
## Rôle du portrait d'après la sorte de groupe rencontré (Party.KINDS).
const PARTY_ROLES := {"villagers": "villager", "bandits": "bandit", "caravan": "merchant", "patrol": "soldier",
	"army": "soldier", "deserters": "deserter", "player": "captain"}

const FRAME := Color(0.1, 0.07, 0.05)
const METAL := Color(0.62, 0.64, 0.66)
const MAIL := Color(0.5, 0.52, 0.54)


## Pièces d'un portrait d'après une graine (et des options, voir l'en-tête).
static func make(seed_value: int, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "portrait"])
	var role := str(opts.get("role", ""))
	var name := str(opts.get("name", ""))
	var woman := bool(opts.get("woman", name in WOMEN))
	var p := {}
	p["seed"] = seed_value
	p["role"] = role
	p["woman"] = woman
	p["shape"] = SHAPES[rng.randi() % SHAPES.size()]
	p["skin"] = SKINS[rng.randi() % SKINS.size()]
	p["eyes"] = EYES[rng.randi() % EYES.size()]
	var old := rng.randf() < 0.2
	var hair_keys: Array = HAIR_COLORS.keys()
	var hair_key: String = hair_keys[rng.randi() % 5] # Noir à blond : les cheveux gris viennent avec l'âge
	if old:
		hair_key = "gris" if rng.randf() < 0.6 else "blanc"
	p["hair"] = (WOMAN_HAIRS[rng.randi() % WOMAN_HAIRS.size()] if woman else HAIRS[rng.randi() % HAIRS.size()])
	p["beard"] = "none" if woman else BEARDS[rng.randi() % BEARDS.size()]
	var scar_roll := rng.randf()
	var scars_for := 0.55 if role in ["captain", "sergeant", "soldier", "bandit", "deserter"] else 0.15
	p["scar"] = SCARS[1 + rng.randi() % (SCARS.size() - 2)] if scar_roll < scars_for else "none"
	var gear: Array = ROLE_GEAR.get(role, ROLE_GEAR[""])
	p["headgear"] = gear[rng.randi() % gear.size()]
	if woman and p["headgear"] in ["straw", "felt"] and rng.randf() < 0.5:
		p["headgear"] = "kerchief"
	var cl: Array = ROLE_CLOTHES.get(role, ROLE_CLOTHES[""])
	p["clothes"] = cl[rng.randi() % cl.size()]
	p["armor"] = role in ["captain", "sergeant", "soldier"] or (role in ["bandit", "deserter"] and rng.randf() < 0.4)
	p["background"] = Color.from_hsv(rng.randf(), 0.25, 0.32).to_html(false)
	# Surnoms qui se voient
	if "Roux" in name or "Rousse" in name:
		hair_key = "roux"
	if "Barbe-Grise" in name:
		hair_key = "gris"
		p["beard"] = "full"
		old = true
	if "Borgne" in name:
		p["scar"] = "eyepatch"
	if name.begins_with("Frère"):
		p["hair"] = "tonsure"
		p["headgear"] = "none"
	if "Muet" in name or "Sans-Peur" in name or "Écorcheur" in name:
		if p["scar"] == "none":
			p["scar"] = "lip" if "Muet" in name else "cheek"
	p["old"] = old
	p["hair_color"] = HAIR_COLORS[hair_key]
	if opts.has("clothes"):
		p["clothes"] = (opts["clothes"] as Color).to_html(false)
	if opts.has("arms") and (opts["arms"] as Dictionary).size() > 0:
		p["tabard"] = [Heraldry.color(opts["arms"], 0).to_html(false), Heraldry.color(opts["arms"], 2).to_html(false)]
	return p


# ---------------------------------------------------------------- Portraits de la campagne

## Le capitaine : graine de la campagne, tabard aux armoiries de la compagnie.
static func of_captain(state: CampaignState) -> Dictionary:
	return make(hash([state.rng.seed, "capitaine"]), {"role": "captain", "name": state.captain.name, "arms": state.arms})


## Un compagnon (entrée de Companions.list, ou une offre {"kind", "name"}) : graine de la
## campagne et de son métier, comme son nom (Companions.offer_name).
static func of_companion(state: CampaignState, m: Dictionary) -> Dictionary:
	var kind := str(m.get("kind", ""))
	return make(hash([state.rng.seed, kind, str(m.get("name", ""))]), {"role": kind, "name": str(m.get("name", ""))})


## Le chef d'un groupe rencontré : graine de son identifiant ; soldats aux couleurs de leur faction.
static func of_party(q: Party) -> Dictionary:
	var opts := {"role": str(PARTY_ROLES.get(q.kind, ""))}
	if q.kind in ["patrol", "army"] and q.faction >= 0:
		opts["clothes"] = (CampaignState.FACTIONS[q.faction]["color"] as Color).darkened(0.25)
	return make(hash([q.id, q.kind, q.name]), opts)


# ---------------------------------------------------------------- Dessin

## Peint le portrait p dans r (fond compris, sans cadre).
static func draw(ci: CanvasItem, r: Rect2, p: Dictionary) -> void:
	var u := minf(r.size.x / W, r.size.y / H)
	var o := r.position + (r.size - Vector2(W, H) * u) * 0.5
	var pen := Pen.new(ci, o, u)
	var skin := Color.html(str(p["skin"]))
	var shade := skin.darkened(0.18)
	var hair := Color.html(str(p["hair_color"]))
	var cloth := Color.html(str(p["clothes"]))
	var rows: Array = SHAPE_ROWS.get(str(p["shape"]), SHAPE_ROWS["oval"])
	var gear := str(p["headgear"])
	# Fond : dégradé sombre
	var bg := Color.html(str(p["background"]))
	ci.draw_rect(r, bg.darkened(0.35))
	for k in 6:
		pen.rect(0, k * 2, W, 2, bg.lerp(bg.darkened(0.35), k / 6.0))
	# Cheveux longs derrière la tête
	if p["hair"] in ["long", "braid"] and gear not in ["coif", "hood"]:
		var hw: int = rows[3] + 1
		pen.rect(12 - hw, 7, hw * 2, 13 if p["hair"] == "long" else 10, hair.darkened(0.15))
		if p["hair"] == "braid":
			pen.rect(12 + hw - 1, 16, 2, 7, hair.darkened(0.1))
	# Épaules et habit
	draw_body(pen, p, cloth)
	# Cou
	pen.rect(10, 18, 4, 4, shade)
	# Visage
	for k in rows.size():
		var hw2: int = rows[k]
		pen.rect(12 - hw2, 6 + k, hw2 * 2, 1, skin)
	var ear: int = rows[5]
	pen.rect(11 - ear, 11, 1, 3, shade)
	pen.rect(12 + ear, 11, 1, 3, shade)
	# Joues (ombre) et rides
	pen.rect(12 - ear, 15, 1, 2, shade)
	pen.rect(11 + ear, 15, 1, 2, shade)
	if bool(p["old"]):
		pen.rect(9, 9, 6, 1, shade)
		pen.rect(8, 14, 1, 2, shade.darkened(0.1))
		pen.rect(15, 14, 1, 2, shade.darkened(0.1))
	# Yeux, sourcils, nez, bouche
	var eye := Color.html(str(p["eyes"]))
	pen.rect(8, 12, 2, 1, Color(0.95, 0.93, 0.88))
	pen.rect(14, 12, 2, 1, Color(0.95, 0.93, 0.88))
	pen.rect(9, 12, 1, 1, eye)
	pen.rect(14, 12, 1, 1, eye)
	var brow := hair.darkened(0.3) if str(p["hair"]) != "bald" else shade.darkened(0.3)
	pen.rect(8, 11, 3, 1, brow)
	pen.rect(13, 11, 3, 1, brow)
	pen.rect(12, 12, 1, 3, shade)
	pen.rect(11, 15, 2, 1, shade)
	var lips := skin.lerp(Color(0.6, 0.2, 0.18), 0.45)
	pen.rect(10, 17, 4, 1, lips)
	if bool(p["woman"]):
		pen.rect(8, 15, 1, 1, skin.lerp(Color(0.85, 0.35, 0.3), 0.25))
		pen.rect(15, 15, 1, 1, skin.lerp(Color(0.85, 0.35, 0.3), 0.25))
	draw_beard(pen, p, rows, hair, lips)
	draw_scar(pen, p, skin)
	draw_hair(pen, p, rows, hair, skin)
	draw_headgear(pen, p, rows, cloth)


static func draw_body(pen: Pen, p: Dictionary, cloth: Color) -> void:
	for y in range(20, H):
		var hw := mini(11, 6 + (y - 20) * 2)
		pen.rect(12 - hw, y, hw * 2, 1, cloth)
	pen.rect(9, 20, 6, 1, cloth.darkened(0.3)) # Encolure
	if bool(p["armor"]):
		# Cotte de mailles aux épaules
		for y in range(21, H):
			var hw := mini(11, 6 + (y - 20) * 2)
			pen.rect(12 - hw, y, 3, 1, MAIL)
			pen.rect(9 + hw, y, 3, 1, MAIL)
		pen.rect(10, 20, 4, 1, MAIL)
	if p.has("tabard"):
		var t: Array = p["tabard"]
		pen.rect(7, 22, 10, H - 22, Color.html(str(t[0])))
		pen.rect(11, 23, 2, H - 24, Color.html(str(t[1])))
		pen.rect(8, 25, 8, 2, Color.html(str(t[1])))


static func draw_beard(pen: Pen, p: Dictionary, rows: Array, hair: Color, lips: Color) -> void:
	match str(p["beard"]):
		"stubble":
			var st := Color(hair.r, hair.g, hair.b, 0.35)
			for y in range(15, 20):
				var hw: int = rows[y - 6]
				pen.rect(12 - hw, y, hw * 2, 1, st)
			pen.rect(10, 17, 4, 1, lips)
		"short":
			for y in range(15, 20):
				var hw: int = rows[y - 6]
				pen.rect(12 - hw, y, hw * 2, 1, hair)
			pen.rect(10, 17, 4, 1, lips)
		"full":
			for y in range(14, 20):
				var hw: int = rows[y - 6]
				pen.rect(12 - hw, y, hw * 2, 1, hair)
			pen.rect(9, 20, 6, 1, hair)
			pen.rect(10, 21, 4, 1, hair)
			pen.rect(10, 17, 4, 1, lips)
		"moustache":
			pen.rect(9, 16, 6, 1, hair)
			pen.rect(9, 17, 1, 1, hair)
			pen.rect(14, 17, 1, 1, hair)
		"goatee":
			pen.rect(10, 16, 4, 1, hair)
			pen.rect(11, 18, 2, 3, hair)


static func draw_scar(pen: Pen, p: Dictionary, skin: Color) -> void:
	var scar := skin.lerp(Color(0.7, 0.25, 0.25), 0.55)
	match str(p["scar"]):
		"cheek":
			pen.line(Vector2(15.5, 13), Vector2(13.5, 17), scar)
		"brow":
			pen.line(Vector2(9.5, 9.5), Vector2(10.5, 13.5), scar)
		"lip":
			pen.line(Vector2(11.5, 15.5), Vector2(12.5, 18.5), scar)
		"eyepatch":
			pen.line(Vector2(6, 9), Vector2(18, 13), Color(0.12, 0.1, 0.08))
			pen.rect(13, 11, 4, 3, Color(0.12, 0.1, 0.08))


static func draw_hair(pen: Pen, p: Dictionary, rows: Array, hair: Color, skin: Color) -> void:
	var hw: int = rows[3]
	match str(p["hair"]):
		"short":
			pen.rect(12 - hw, 5, hw * 2, 3, hair)
			pen.rect(12 - hw - 1, 7, 2, 4, hair)
			pen.rect(11 + hw, 7, 2, 4, hair)
		"long", "braid":
			pen.rect(12 - hw, 5, hw * 2, 3, hair)
			pen.rect(12 - hw - 1, 7, 2, 10, hair)
			pen.rect(11 + hw, 7, 2, 10, hair)
		"bun":
			pen.rect(12 - hw, 5, hw * 2, 3, hair)
			pen.rect(12 - hw - 1, 7, 2, 4, hair)
			pen.rect(11 + hw, 7, 2, 4, hair)
			pen.rect(10, 2, 4, 3, hair)
		"bowl":
			pen.rect(12 - hw - 1, 5, hw * 2 + 2, 5, hair)
			pen.rect(12 - hw - 1, 10, 2, 2, hair)
			pen.rect(11 + hw, 10, 2, 2, hair)
		"curly":
			for k in range(-hw - 1, hw + 1, 2):
				pen.rect(12 + k, 4, 2, 2, hair)
			pen.rect(12 - hw - 1, 6, hw * 2 + 2, 2, hair)
			pen.rect(12 - hw - 1, 8, 2, 4, hair)
			pen.rect(11 + hw, 8, 2, 4, hair)
		"tonsure":
			pen.rect(12 - hw, 6, hw * 2, 2, hair)
			pen.rect(10, 6, 4, 1, skin)
			pen.rect(12 - hw - 1, 8, 2, 4, hair)
			pen.rect(11 + hw, 8, 2, 4, hair)
		"bald":
			pen.rect(12 - hw - 1, 9, 1, 3, hair)
			pen.rect(12 + hw, 9, 1, 3, hair)
			pen.rect(10, 7, 2, 1, skin.lightened(0.2)) # Reflet du crâne


static func draw_headgear(pen: Pen, p: Dictionary, rows: Array, cloth: Color) -> void:
	var hw: int = rows[3]
	match str(p["headgear"]):
		"kettle": # Chapel de fer
			pen.rect(12 - hw, 3, hw * 2, 5, METAL)
			pen.rect(12 - hw + 1, 2, hw * 2 - 2, 1, METAL)
			pen.rect(12 - hw - 3, 8, hw * 2 + 6, 1, METAL.darkened(0.2))
			pen.rect(12 - hw + 1, 4, 2, 2, METAL.lightened(0.25))
		"nasal": # Casque à nasal
			pen.rect(12 - hw - 1, 3, hw * 2 + 2, 6, METAL)
			pen.rect(12 - hw + 1, 2, hw * 2 - 2, 1, METAL)
			pen.rect(12 - hw - 1, 9, hw * 2 + 2, 1, METAL.darkened(0.25))
			pen.rect(11, 9, 2, 5, METAL.darkened(0.1))
			pen.rect(12 - hw + 1, 4, 2, 2, METAL.lightened(0.25))
		"coif": # Camail de mailles autour du visage
			pen.rect(12 - hw - 2, 4, hw * 2 + 4, 5, MAIL)
			pen.rect(12 - hw - 2, 9, 3, 12, MAIL)
			pen.rect(11 + hw, 9, 3, 12, MAIL)
			pen.rect(8, 19, 8, 2, MAIL)
			for y in range(5, 20, 2):
				pen.rect(12 - hw - 1, y, 1, 1, MAIL.darkened(0.3))
				pen.rect(12 + hw, y, 1, 1, MAIL.darkened(0.3))
		"hood": # Capuchon (pointe dans le dos)
			var h := cloth.darkened(0.15)
			pen.rect(12 - hw - 2, 4, hw * 2 + 4, 5, h)
			pen.rect(12 - hw - 2, 9, 3, 11, h)
			pen.rect(11 + hw, 9, 3, 11, h)
			pen.rect(12 + hw, 2, 3, 3, h)
			pen.rect(7, 19, 10, 2, h)
		"felt": # Chapeau de feutre
			var f := cloth.darkened(0.35)
			pen.rect(12 - hw, 2, hw * 2, 5, f)
			pen.rect(12 - hw - 3, 7, hw * 2 + 6, 1, f.darkened(0.2))
			pen.rect(12 - hw, 5, hw * 2, 1, Color(0.75, 0.6, 0.3))
		"straw": # Chapeau de paille
			var s := Color(0.85, 0.72, 0.4)
			pen.rect(12 - hw + 1, 3, hw * 2 - 2, 4, s)
			pen.rect(12 - hw - 4, 7, hw * 2 + 8, 1, s.darkened(0.15))
			pen.rect(12 - hw + 1, 6, hw * 2 - 2, 1, Color(0.55, 0.3, 0.2))
		"kerchief": # Couvre-chef de toile
			var k := Color(0.9, 0.88, 0.8)
			pen.rect(12 - hw - 1, 4, hw * 2 + 2, 4, k)
			pen.rect(12 - hw - 1, 8, 2, 8, k)
			pen.rect(11 + hw, 8, 2, 8, k)


## Petit pinceau à cases (coordonnées de la grille W x H).
class Pen:
	var ci: CanvasItem
	var origin: Vector2
	var unit: float

	func _init(c: CanvasItem, o: Vector2, u: float) -> void:
		ci = c
		origin = o
		unit = u

	func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
		ci.draw_rect(Rect2(origin + Vector2(x, y) * unit, Vector2(w, h) * unit), col)

	func line(a: Vector2, b: Vector2, col: Color) -> void:
		ci.draw_line(origin + a * unit, origin + b * unit, col, maxf(1.0, unit * 0.8))


# ---------------------------------------------------------------- Panneaux

## Portrait encadré pour les panneaux (fenêtre Compagnie, compagnons, rencontres).
class View extends Control:
	var data: Dictionary = {}
	var dim := false ## Grisé (compagnon blessé)

	func _init(d: Dictionary = {}, size_px := Vector2(64, 74)) -> void:
		data = d
		custom_minimum_size = size_px
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), custom_minimum_size - Vector2(6, 6))
		draw_rect(r.grow(3), Portrait.FRAME)
		draw_rect(r.grow(2), Color(0.6, 0.47, 0.25), false, 1.0)
		if not data.is_empty():
			Portrait.draw(self, r, data)
		if dim:
			draw_rect(r, Color(0.1, 0.1, 0.12, 0.5))


## Place un portrait à gauche des nœuds de box ajoutés depuis l'indice from (des étiquettes) :
## ils passent dans une colonne à droite du portrait. Renvoie la vue.
static func beside(box: Container, from: int, d: Dictionary, size_px := Vector2(64, 74)) -> View:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var view := View.new(d, size_px)
	row.add_child(view)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var moved: Array[Node] = []
	for k in range(from, box.get_child_count()):
		moved.append(box.get_child(k))
	for n in moved:
		box.remove_child(n)
		col.add_child(n)
	box.add_child(row)
	return view
