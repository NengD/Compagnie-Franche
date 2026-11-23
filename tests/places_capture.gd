extends SceneTree
## Captures des lieux de la carte et des portraits (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/places_capture.gd [-- --out=<dossier>]
## Écrit (voir capture_dir.gd) : lieux_villes (cité, villes, châteaux, villages ; Valombre prise
## par la Ligue), lieux_siege (Saint-Aubin assiégée : camp et fumées), lieux_fief (le fief de la
## compagnie à ses armoiries, assiégé), portraits_planche (36 portraits de rôles variés),
## portraits_compagnie (onglet Compagnie : capitaine et compagnons), portraits_rencontre
## (panneau de rencontre). Campagne de test dans user://, jamais celle du joueur.

const CaptureDir := preload("res://tests/capture_dir.gd")

var map: Node
var frame := 0
var sheet: Control
var panel: EncounterPanel


## Planche de portraits : neuf rôles par ligne.
class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.07, 0.05))
		var roles := ["captain", "sergeant", "surgeon", "scout", "quartermaster", "soldier", "bandit", "villager", "merchant"]
		var cell := Vector2(132, 152)
		var cols := 9
		for k in 36:
			var at := Vector2(24 + (k % cols) * cell.x, 24 + floori(k / float(cols)) * (cell.y + 18))
			var role: String = roles[k % roles.size()]
			var opts := {"role": role, "woman": k % 5 == 3}
			if role == "captain":
				opts["arms"] = Heraldry.random(k)
			var r := Rect2(at, cell - Vector2(16, 16))
			draw_rect(r.grow(3), Portrait.FRAME)
			Portrait.draw(self, r, Portrait.make(k * 17 + 3, opts))
			draw_string(ThemeDB.fallback_font, at + Vector2(0, cell.y + 2), role, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.85, 0.7))


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.slot_prefix = "user://capture_lieux"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	var c := CampaignState.new_game(4321)
	CampaignState.current = c
	c.world.armies.clear()
	c.world.owner[0] = 2 # Valombre prise par la Ligue
	c.world.declare_war(c, 1, 0)
	var army := c.world.add_army(1, 2, 1, 600, "siege")
	army.mode = "siege"
	army.target = 1
	var castle := MapData.place_named("Tour du Guet")
	c.fiefs.owners[str(castle)] = Fiefs.PLAYER
	c.fiefs.held.append({"place": castle, "garrison": [], "since": 1, "from": 0, "siege": {"faction": 1, "men": 120, "days": 3}})
	for kind in ["sergeant", "surgeon", "scout"]:
		c.companions.list.append(Companions.make(kind, Companions.offer_name(c, kind)))
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func look(at: Vector2, z: float) -> void:
	map.paused = true
	map.view = ""
	map.town_open = false
	map.state.overworld.hour = 12.0
	map.update_light()
	map.cam.zoom = Vector2(z, z)
	map.center_on(at)
	map.refresh_ui()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		5:
			look(Vector2(700, 1450), 0.75)
		20:
			CaptureDir.save(self, "lieux_villes.png")
			look(MapData.place_pos(1), 1.6)
		35:
			CaptureDir.save(self, "lieux_siege.png")
			look(MapData.place_pos(MapData.place_named("Tour du Guet")), 1.8)
		50:
			CaptureDir.save(self, "lieux_fief.png")
			sheet = Sheet.new()
			sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
			var layer := CanvasLayer.new()
			layer.layer = 50
			layer.add_child(sheet)
			root.add_child(layer)
		60:
			CaptureDir.save(self, "portraits_planche.png")
			sheet.get_parent().queue_free()
			map.view = "company"
			map.refresh_ui()
		75:
			CaptureDir.save(self, "portraits_compagnie.png")
			map.view = ""
			map.refresh_ui()
			var q := Party.new()
			q.kind = "bandits"
			q.name = "les Écorcheurs"
			q.troops = [{"type": "spear", "men": 40, "xp": 0.0}]
			q.pos = map.state.overworld.player.pos + Vector2(30, 0)
			map.state.overworld.add(map.state, q)
			panel = Encounter.open(root, map.state, map.state.overworld.player, q) as EncounterPanel
		90:
			CaptureDir.save(self, "portraits_rencontre.png")
		92:
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			quit(0)
	return false
