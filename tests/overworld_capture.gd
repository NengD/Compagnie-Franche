extends SceneTree
## Captures de la carte du monde en temps réel (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/overworld_capture.gd [-- --out=<dossier>]
## Écrit dans user://captures (voir capture_dir.gd) : carte_ville (au départ, panneau de la ville),
## carte_marche (en route, de jour), carte_nuit (de nuit, zoom arrière), carte_rencontre (une
## rencontre). Campagne de test dans user://, jamais celle du joueur.

const CaptureDir := preload("res://tests/capture_dir.gd")

var map: Node
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.slot_prefix = "user://capture_carte"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	var c := CampaignState.new_game(1234)
	c.gold = 2000.0
	c.world.declare_war(c, 0, 1)
	CampaignState.current = c
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func _process(_delta: float) -> bool:
	frame += 1
	var c: CampaignState = map.state
	match frame:
		20:
			CaptureDir.save(self, "carte_ville.png")
			map.click_place(1)
			map.advance_time(12.0)
			map.center_on(c.overworld.player.pos)
		40:
			CaptureDir.save(self, "carte_marche.png")
			map.advance_time(24.0 - c.overworld.hour + 23.0) # 23 h, le lendemain
			map.zoom_at(0.6, Vector2(400, 360))
			map.center_on(c.overworld.player.pos)
		60:
			CaptureDir.save(self, "carte_nuit.png")
			var b := Party.new()
			b.kind = "bandits"
			b.name = "les Écorcheurs"
			b.troops = [{"type": "spear", "men": 20, "xp": 0.0}, {"type": "archer", "men": 10, "xp": 0.0}]
			b.pos = c.overworld.player.pos + Vector2(10, 0)
			c.overworld.add(c, b)
			c.overworld.inside = -1
			map.advance_time(0.5)
			map.zoom_at(1.0 / 0.6, Vector2(400, 360))
			map.center_on(c.overworld.player.pos)
		80:
			CaptureDir.save(self, "carte_rencontre.png")
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			quit(0)
	return false
