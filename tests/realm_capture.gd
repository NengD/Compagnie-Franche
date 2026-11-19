extends SceneTree
## Captures du domaine (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . --resolution 1280x720 -s tests/realm_capture.gd [-- --out=<dossier>]
## Écrit dans user://captures (voir capture_dir.gd) : domaine_marche (fenêtre de la ville, section
## Marché), domaine_quetes (onglet Quêtes) et domaine_fief (le fief de la compagnie sur la carte).
## Campagne de test dans user://, jamais celle du joueur.

const CaptureDir := preload("res://tests/capture_dir.gd")

var map: Node
var frame := 0
var fief := -1


## Une offre de la sorte kind, ajoutée aux offres, puis acceptée.
func quest(c: CampaignState, kind: String) -> void:
	for i in 300:
		for gv in Quests.givers(c):
			var q := c.quests.make_offer(c, gv)
			if str(q.get("kind", "")) == kind:
				c.quests.offers.append(q)
				var keep := c.overworld.inside
				c.overworld.inside = gv
				c.quests.accept(c, int(q["id"]))
				c.overworld.inside = keep
				return


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.slot_prefix = "user://capture_domaine"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	var c := CampaignState.new_game(1234)
	c.gold = 2400.0
	c.reputation[0] = 30
	c.trade.cargo = {"grain": 12, "salt": 6}
	c.trade.wagons = 1
	c.trade.shift(0, "grain", -0.3)
	quest(c, "lair")
	quest(c, "deliver")
	quest(c, "hold")
	fief = MapData.place_named("Tour du Guet")
	c.fiefs.grant(c, fief, 0)
	(c.fiefs.fief(fief)["garrison"] as Array).append({"type": "spear", "men": 20, "xp": 120.0})
	CampaignState.current = c
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func _process(_delta: float) -> bool:
	frame += 1
	var c: CampaignState = map.state
	match frame:
		10:
			map.town_open = true
			map.refresh_ui()
		14:
			for l in (map.box as Control).find_children("*", "Label", true, false):
				if (l as Label).text == "Marché":
					map.scroll.scroll_vertical = int((l as Control).position.y) - 8
		24:
			CaptureDir.save(self, "domaine_marche.png")
			map.toggle_view("quests")
		34:
			CaptureDir.save(self, "domaine_quetes.png")
			map.toggle_view("quests")
			map.town_open = false
			map.refresh_ui()
			map.zoom_at(1.6, Vector2(640, 360))
			map.center_on(MapData.place_pos(fief))
		44:
			CaptureDir.save(self, "domaine_fief.png")
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			quit(0)
	return false
