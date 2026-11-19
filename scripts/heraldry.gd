class_name Heraldry
extends RefCounted
## Armoiries simples de la compagnie (CampaignState.arms) : {"field", "charge", "colors"}.
## - field : partition de l'écu (FIELDS) ;
## - charge : meuble posé au centre (CHARGES) ;
## - colors : trois couleurs « #rrggbb » : le champ, la seconde couleur de la partition, le meuble.
## Tirées au hasard au départ (generator propre : les tirages de la campagne ne changent pas),
## sauvegardées et modifiables dans l'onglet Compagnie. draw() les peint dans un rectangle
## (bannière de la carte, aperçu du panneau).

const FIELDS := ["plain", "per_pale", "per_fess", "per_bend", "quarterly", "chief", "chevron"]
const FIELD_NAMES := {"plain": "plein", "per_pale": "parti", "per_fess": "coupé", "per_bend": "tranché",
	"quarterly": "écartelé", "chief": "au chef", "chevron": "au chevron"}
const CHARGES := ["none", "cross", "saltire", "star", "ring", "lozenge", "sword", "tower"]
const CHARGE_NAMES := {"none": "sans meuble", "cross": "croix", "saltire": "sautoir", "star": "étoile",
	"ring": "anneau", "lozenge": "losange", "sword": "épée", "tower": "tour"}
## Émaux : couleurs (sombres) et métaux (clairs). Le meuble est toujours d'un métal sur un champ
## de couleur, ou l'inverse, pour rester lisible (règle des émaux).
const COLOURS := {"gueules": "#b3201b", "azur": "#2448a8", "sinople": "#2a7a32", "sable": "#1e1a18", "pourpre": "#6a2a78"}
const METALS := {"or": "#e8c040", "argent": "#ecebe4"}


## Armoiries tirées au hasard d'après une graine.
static func random(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + "armoiries")
	var cols: Array = COLOURS.values()
	var mets: Array = METALS.values()
	var c1: String = cols[rng.randi() % cols.size()]
	var m1: String = mets[rng.randi() % mets.size()]
	var dark_field := rng.randf() < 0.65
	var field: String = FIELDS[rng.randi() % FIELDS.size()]
	var charge: String = CHARGES[1 + rng.randi() % (CHARGES.size() - 1)]
	if field in ["per_pale", "per_fess", "per_bend", "quarterly"]:
		charge = "none" # Une partition se suffit (le meuble se perdrait sur la moitié de sa couleur)
	var a := c1 if dark_field else m1
	var b := m1 if dark_field else c1
	# Seconde couleur de la partition et meuble : l'autre famille (contraste avec le champ)
	return {"field": field, "charge": charge, "colors": [a, b, b]}


## Armoiries valides (les champs inconnus sont remplacés) ; vide -> tirées d'après seed_value.
static func sanitize(d: Variant, seed_value: int) -> Dictionary:
	if not d is Dictionary or (d as Dictionary).is_empty():
		return random(seed_value)
	var src: Dictionary = d
	var out := random(seed_value)
	if str(src.get("field", "")) in FIELDS:
		out["field"] = str(src["field"])
	if str(src.get("charge", "")) in CHARGES:
		out["charge"] = str(src["charge"])
	var cols: Variant = src.get("colors", [])
	if cols is Array and (cols as Array).size() == 3:
		var ok: Array = []
		for c in cols:
			ok.append(str(c) if Color.html_is_valid(str(c)) else "")
		if not "" in ok:
			out["colors"] = ok
	return out


static func color(arms: Dictionary, i: int) -> Color:
	var cols: Array = arms.get("colors", ["#2448a8", "#ecebe4", "#ecebe4"])
	return Color.html(str(cols[clampi(i, 0, cols.size() - 1)]))


## Tous les émaux, dans l'ordre (couleurs puis métaux) : pour les boutons de l'onglet Compagnie.
static func tinctures() -> Array[String]:
	var out: Array[String] = []
	for c in COLOURS.values():
		out.append(str(c))
	for c in METALS.values():
		out.append(str(c))
	return out


## Valeur suivante d'une liste (boutons « changer » de l'onglet Compagnie).
static func next_in(list: Array, v: Variant) -> Variant:
	var i := list.find(v)
	return list[(i + 1) % list.size()]


## Peint les armoiries dans r (le bord n'est pas tracé : à l'appelant).
static func draw(ci: CanvasItem, r: Rect2, arms: Dictionary) -> void:
	var a := color(arms, 0)
	var b := color(arms, 1)
	var m := color(arms, 2)
	var p := r.position
	var s := r.size
	ci.draw_rect(r, a)
	match str(arms.get("field", "plain")):
		"per_pale":
			ci.draw_rect(Rect2(p + Vector2(s.x * 0.5, 0), Vector2(s.x * 0.5, s.y)), b)
		"per_fess":
			ci.draw_rect(Rect2(p + Vector2(0, s.y * 0.5), Vector2(s.x, s.y * 0.5)), b)
		"per_bend":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y)]), b)
		"quarterly":
			ci.draw_rect(Rect2(p + Vector2(s.x * 0.5, 0), s * 0.5), b)
			ci.draw_rect(Rect2(p + Vector2(0, s.y * 0.5), s * 0.5), b)
		"chief":
			ci.draw_rect(Rect2(p, Vector2(s.x, s.y * 0.3)), b)
		"chevron":
			var t := s.y * 0.18
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, s.y * 0.85), p + Vector2(s.x * 0.5, s.y * 0.3),
				p + Vector2(s.x, s.y * 0.85), p + Vector2(s.x, s.y * 0.85 + t), p + Vector2(s.x * 0.5, s.y * 0.3 + t),
				p + Vector2(0, s.y * 0.85 + t)]), b)
	var field := str(arms.get("field", "plain"))
	var c := r.get_center()
	var u := minf(s.x, s.y)
	if field == "chief":
		c.y += s.y * 0.15
	elif field == "chevron": # Sous la pointe du chevron, en plus petit
		c.y = p.y + s.y * 0.68
		u *= 0.6
	match str(arms.get("charge", "none")):
		"cross":
			ci.draw_rect(Rect2(c.x - u * 0.09, p.y + s.y * 0.12, u * 0.18, s.y * 0.76), m)
			ci.draw_rect(Rect2(p.x + s.x * 0.12, c.y - u * 0.09, s.x * 0.76, u * 0.18), m)
		"saltire":
			var w := maxf(1.0, u * 0.16)
			ci.draw_line(p + s * 0.12, p + s * 0.88, m, w)
			ci.draw_line(p + Vector2(s.x * 0.88, s.y * 0.12), p + Vector2(s.x * 0.12, s.y * 0.88), m, w)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var rad := u * (0.36 if k % 2 == 0 else 0.15)
				pts.append(c + Vector2.from_angle(-PI * 0.5 + k * PI / 5.0) * rad)
			ci.draw_colored_polygon(pts, m)
		"ring":
			ci.draw_arc(c, u * 0.26, 0, TAU, 16, m, maxf(1.0, u * 0.11))
		"lozenge":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u * 0.38), c + Vector2(u * 0.26, 0), c + Vector2(0, u * 0.38), c + Vector2(-u * 0.26, 0)]), m)
		"sword":
			ci.draw_rect(Rect2(c.x - u * 0.05, c.y - u * 0.4, u * 0.1, u * 0.62), m)
			ci.draw_rect(Rect2(c.x - u * 0.22, c.y + u * 0.14, u * 0.44, u * 0.09), m)
			ci.draw_rect(Rect2(c.x - u * 0.05, c.y + u * 0.23, u * 0.1, u * 0.17), m)
		"tower":
			ci.draw_rect(Rect2(c.x - u * 0.2, c.y - u * 0.22, u * 0.4, u * 0.55), m)
			for k in 3:
				ci.draw_rect(Rect2(c.x - u * 0.2 + k * u * 0.15, c.y - u * 0.34, u * 0.1, u * 0.13), m)
			ci.draw_rect(Rect2(c.x - u * 0.06, c.y + u * 0.12, u * 0.12, u * 0.21), a.lerp(Color.BLACK, 0.4))


## Blason court pour le panneau : « De gueules au chevron d'argent, à la tour d'or ».
const FIELD_BLAZON := {"plain": "De %s", "per_pale": "Parti %s et %s", "per_fess": "Coupé %s et %s",
	"per_bend": "Tranché %s et %s", "quarterly": "Écartelé %s et %s", "chief": "%s au chef %s", "chevron": "%s au chevron %s"}
const CHARGE_BLAZON := {"cross": "à la croix", "saltire": "au sautoir", "star": "à l'étoile", "ring": "à l'anneau",
	"lozenge": "au losange", "sword": "à l'épée", "tower": "à la tour"}


static func blazon(arms: Dictionary) -> String:
	var field := str(arms.get("field", "plain"))
	var charge := str(arms.get("charge", "none"))
	var a := tincture_name(color(arms, 0))
	var b := tincture_name(color(arms, 1))
	var s: String
	match field:
		"plain":
			s = "D" + of(a).substr(1)
		"chief", "chevron":
			s = CampaignState.cap_first(of(a)) + str(FIELD_BLAZON[field]).trim_prefix("%s") % of(b)
		_:
			s = str(FIELD_BLAZON.get(field, "%s %s")) % [of(a), of(b)]
	if charge != "none":
		s += ", %s %s" % [str(CHARGE_BLAZON.get(charge, charge)), of(tincture_name(color(arms, 2)))]
	return s


## « de gueules », « d'or », « d'argent », « d'azur ».
static func of(t: String) -> String:
	return ("d'" if t.substr(0, 1) in ["a", "e", "i", "o", "u", "#"] else "de ") + t


static func tincture_name(c: Color) -> String:
	var all := COLOURS.duplicate()
	all.merge(METALS)
	for k in all:
		if Color.html(str(all[k])).is_equal_approx(c):
			return str(k)
	return "#" + c.to_html(false)


# ---------------------------------------------------------------- Onglet Compagnie

## Aperçu des armoiries (bannière) dans le panneau.
class ArmsPreview extends Control:
	var arms: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(48, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), Vector2(40, 34))
		draw_rect(r.grow(2), Color(0.1, 0.07, 0.05))
		Heraldry.draw(self, r, arms)
		# Pointe de l'écu
		draw_colored_polygon(PackedVector2Array([Vector2(2, 38), Vector2(46, 38), Vector2(24, 54)]), Color(0.1, 0.07, 0.05))
		var lo := Rect2(Vector2(4, 38), Vector2(40, 0))
		var pts := PackedVector2Array([lo.position, lo.position + Vector2(40, 0), Vector2(24, 51)])
		var field := str(arms.get("field", "plain"))
		var tip := Heraldry.color(arms, 1) if field in ["per_fess", "per_bend", "quarterly"] else Heraldry.color(arms, 0)
		draw_colored_polygon(pts, tip)


## Section « Armoiries » de l'onglet Compagnie : aperçu, blason, boutons pour changer chaque
## partie. map : le nœud de la carte (state, box, add_section, add_label, add_button).
static func build_panel(map: Node) -> void:
	var state: CampaignState = map.state
	map.add_section("Armoiries")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	map.box.add_child(row)
	var preview := ArmsPreview.new()
	preview.arms = state.arms
	row.add_child(preview)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	col.add_child(text)
	var buttons := HFlowContainer.new()
	col.add_child(buttons)
	var refresh := func() -> void:
		text.text = blazon(state.arms) + ". La compagnie les porte sur sa bannière."
		preview.queue_redraw()
	refresh.call()
	var change := func(key: String, i: int) -> void:
		match key:
			"field":
				state.arms["field"] = next_in(FIELDS, str(state.arms["field"]))
			"charge":
				state.arms["charge"] = next_in(CHARGES, str(state.arms["charge"]))
			"colors":
				var cols: Array = state.arms["colors"]
				cols[i] = next_in(tinctures(), str(cols[i]))
			"random":
				var fresh := random(randi())
				for k in fresh:
					state.arms[k] = fresh[k]
		state.save()
		GameAudio.ui("click")
		refresh.call()
	for spec in [["Partition", "field", 0], ["Meuble", "charge", 0], ["Champ", "colors", 0], ["Seconde couleur", "colors", 1], ["Couleur du meuble", "colors", 2], ["Au hasard", "random", 0]]:
		map.add_button(str(spec[0]), change.bind(str(spec[1]), int(spec[2])), true, buttons)
