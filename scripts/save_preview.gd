class_name SavePreview
extends RefCounted
## Aperçu d'un emplacement de sauvegarde pour le menu principal, lu sans charger la campagne :
## un petit en-tête JSON écrit à côté de la sauvegarde (<emplacement>.apercu.json) à chaque
## CampaignState.save() : jour, or, hommes, renommée, difficulté, date réelle, état, position de
## la compagnie et maîtres des villes (pour la miniature de la carte, dessinée par Thumb).
## Une sauvegarde d'avant l'aperçu (sans en-tête) est lue une fois en entier, puis l'en-tête
## est écrit pour la fois suivante.

const VERSION := 1
const THUMB_PIX := 4 ## Cases de la grille du terrain par pixel de la miniature

static var terrain_img: ImageTexture = null ## Fond de la miniature (calculé une fois)


static func path_for(save_path: String) -> String:
	return save_path.get_basename() + ".apercu.json"


## En-tête d'une campagne.
static func make(c: CampaignState) -> Dictionary:
	var owners: Array = []
	for t in CampaignState.TOWNS.size():
		owners.append(c.town_owner(t))
	var pos := c.overworld.player.pos
	return {
		"version": VERSION, "day": c.day, "gold": int(c.gold), "men": c.total_men(), "fame": c.fame,
		"difficulty": c.difficulty, "lenient": c.lenient, "saved_at": c.saved_at,
		"challenges": Array(c.challenges),
		"status": c.status_text(), "over": c.is_over(), "summary": c.summary(),
		"pos": [pos.x, pos.y], "owners": owners,
	}


## Écrit l'en-tête à côté de la sauvegarde (appelé par CampaignState.save).
static func write(c: CampaignState, save_path: String) -> bool:
	var f := FileAccess.open(path_for(save_path), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(make(c)))
	f.close()
	return true


## Aperçu de l'emplacement i ({} s'il est vide ou illisible). Sans en-tête (ancienne
## sauvegarde) ou si l'en-tête est plus vieux que la sauvegarde, la campagne est relue une fois.
static func read_slot(i: int) -> Dictionary:
	var p := CampaignState.slot_path(i)
	if not CampaignState.slot_used(i):
		return {}
	var d := read_header(path_for(p))
	if not d.is_empty() and FileAccess.file_exists(p) and FileAccess.get_modified_time(path_for(p)) + 1 < FileAccess.get_modified_time(p):
		d = {} # En-tête périmé (sauvegarde écrite par une version sans aperçu)
	if d.is_empty():
		var c := CampaignState.load_slot(i)
		if c == null:
			return {}
		d = make(c)
		if FileAccess.file_exists(p):
			write(c, p)
	return d


static func read_header(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var d: Dictionary = json.data
	if int(d.get("version", 0)) != VERSION or not d.has("day"):
		return {}
	return d


## Date réelle de la sauvegarde, en clair (« 18/11/2026 à 14 h 05 »).
static func date_text(unix: float) -> String:
	if unix <= 0.0:
		return "date inconnue"
	var t := Time.get_datetime_dict_from_unix_time(int(unix + Time.get_time_zone_from_system()["bias"] * 60))
	return "%02d/%02d/%d à %d h %02d" % [t["day"], t["month"], t["year"], t["hour"], t["minute"]]


## Lignes de l'aperçu (sous la miniature).
static func lines(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Jour %d · %d écus · %s" % [int(d["day"]), int(d["gold"]), CampaignState.plural(int(d["men"]), "homme", "hommes")])
	var diff := Difficulty.display_name(str(d.get("difficulty", Difficulty.NORMAL)))
	if bool(d.get("lenient", false)):
		diff += ", indulgent"
	out.append("Renommée %d · %s" % [int(d.get("fame", 0)), diff])
	var defis: Variant = d.get("challenges", [])
	if defis is Array and not (defis as Array).is_empty():
		out.append("Défis : " + Challenges.names(defis))
	out.append("Sauvegardé le " + date_text(float(d.get("saved_at", 0.0))))
	return out


## Fond de la miniature : eau, forêts et montagnes de la carte du monde (calculé une fois).
static func terrain_texture() -> ImageTexture:
	if terrain_img != null:
		return terrain_img
	var f := MapData.fields()
	var w: int = f["w"]
	var h: int = f["h"]
	var ground: PackedByteArray = f["ground"]
	@warning_ignore("integer_division")
	var img := Image.create(w / THUMB_PIX, h / THUMB_PIX, false, Image.FORMAT_RGB8)
	var cols := [Color(0.45, 0.55, 0.3), Color(0.24, 0.38, 0.2), Color(0.55, 0.55, 0.36),
		Color(0.38, 0.45, 0.35), Color(0.22, 0.36, 0.55), Color(0.55, 0.52, 0.5)]
	for y in img.get_height():
		for x in img.get_width():
			var g := int(ground[(y * THUMB_PIX) * w + x * THUMB_PIX])
			img.set_pixel(x, y, cols[clampi(g, 0, cols.size() - 1)])
	terrain_img = ImageTexture.create_from_image(img)
	return terrain_img


## Miniature de la carte de campagne : terrain, villes aux couleurs de leur maître, compagnie.
class Thumb extends Control:
	var data: Dictionary

	func _init(d: Dictionary, w := 150.0) -> void:
		data = d
		custom_minimum_size = Vector2(w, w * MapData.SIZE.y / MapData.SIZE.x)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_texture_rect(SavePreview.terrain_texture(), r, false)
		var k := size / MapData.SIZE
		var owners: Array = data.get("owners", [])
		for t in CampaignState.TOWNS.size():
			var p: Vector2 = CampaignState.TOWNS[t]["pos"] * k
			var o := int(owners[t]) if t < owners.size() else int(CampaignState.TOWNS[t]["faction"])
			var col: Color = CampaignState.FACTIONS[o]["color"] if o >= 0 and o < CampaignState.FACTIONS.size() else MapRender.WILD_COLOR
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), col)
		var pos: Array = data.get("pos", [])
		if pos.size() == 2:
			var c := Vector2(float(pos[0]), float(pos[1])) * k
			draw_circle(c, 4.0, Color(0, 0, 0, 0.85))
			draw_circle(c, 3.0, Color(1, 0.9, 0.45))
		draw_rect(r, Color(0.6, 0.47, 0.25), false, 1.0)
