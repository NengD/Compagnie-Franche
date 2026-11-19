extends SceneTree
## Captures de la carte du monde en temps réel (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/overworld_capture.gd [-- --out=<dossier>]
## Écrit dans user://captures (voir capture_dir.gd) : carte_ville (au départ, panneau de la ville),
## carte_marche (en route, de jour), carte_nuit (de nuit, zoom arrière), carte_rencontre (une
## rencontre), puis la saison et la météo (MapSky) : carte_figurines (les groupes de près : caravane,
## villageois, bandits, déserteurs, patrouille, armée, la compagnie et ses armoiries, traces de
## marche), carte_printemps, carte_automne, carte_hiver, carte_hiver_nuit, carte_pluie,
## carte_brouillard (matin d'automne), carte_nuit_ville (lumières d'une ville). Campagne de test dans user://, jamais celle du joueur.

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
			map.contact = null
			c.world.encounter = {}
			c.overworld.inside = -1
			_figurines(c)
	# Saisons et météo : une prise toutes les 20 images
	if frame >= 100:
		@warning_ignore("integer_division")
		var i := (frame - 100) / 20
		if i >= SEASONS.size():
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			quit(0)
		elif (frame - 100) % 20 == 0:
			var s: Dictionary = SEASONS[i]
			c.day = int(s["day"])
			c.overworld.hour = float(s["hour"])
			c.world.raining = bool(s["rain"])
			map.view = ""
			map.town_open = false
			map.paused = true
			map.notice = ""
			map.cam.zoom = Vector2.ONE * float(s["zoom"])
			var at: Vector2 = s.get("at", c.overworld.player.pos)
			map.center_on(MapData.place_pos(0) if at.x < 0 else at)
			map.refresh_ui()
			map.update_light()
			map.toast_time = 0.0
			map.toast.visible = false
		elif (frame - 100) % 20 == 19:
			map.toast_time = 0.0
			map.toast.visible = false
			CaptureDir.save(self, str(SEASONS[i]["file"]))
	return false


## Prises des saisons : jour (le 1er est au printemps ; 30 jours par saison), heure, pluie, zoom.
const SEASONS := [
	{"file": "carte_figurines.png", "day": 12, "hour": 13.0, "rain": false, "zoom": 2.4},
	{"file": "carte_printemps.png", "day": 40, "hour": 12.0, "rain": false, "zoom": 1.0},
	{"file": "carte_automne.png", "day": 75, "hour": 14.0, "rain": false, "zoom": 1.0},
	{"file": "carte_hiver.png", "day": 100, "hour": 12.0, "rain": false, "zoom": 1.0},
	{"file": "carte_hiver_nuit.png", "day": 100, "hour": 23.0, "rain": true, "zoom": 1.0},
	{"file": "carte_pluie.png", "day": 50, "hour": 15.0, "rain": true, "zoom": 1.0},
	{"file": "carte_brouillard.png", "day": 70, "hour": 6.5, "rain": false, "zoom": 0.75},
	{"file": "carte_nuit_ville.png", "day": 20, "hour": 22.0, "rain": false, "zoom": 1.6, "at": Vector2(-1, -1)},
]


## Un groupe de chaque sorte autour de la compagnie, en marche vers l'est ou l'ouest (traces).
func _figurines(c: CampaignState) -> void:
	var ow := c.overworld
	for q in ow.parties.duplicate():
		ow.remove(c, q)
	var at := ow.player.pos
	var specs := [["caravan", Vector2(-120, -50), 20], ["villagers", Vector2(-40, -70), 25], ["bandits", Vector2(60, -60), 30],
		["deserters", Vector2(130, -10), 30], ["patrol", Vector2(-120, 40), 50], ["villagers", Vector2(40, 60), 12]]
	for sp in specs:
		var q := Party.new()
		q.kind = str(sp[0])
		q.faction = 1 if q.kind in ["patrol", "deserters"] else -1
		q.troops = [{"type": "spear", "men": int(sp[2]), "xp": 0.0}]
		q.pos = at + (sp[1] as Vector2) - Vector2(60, 0)
		ow.add(c, q)
		map.update_trails()
		q.pos += Vector2(60, 0) if int(sp[2]) % 2 == 0 else Vector2(-60, 0)
		for k in 6: # Trace : quelques pas
			q.pos += Vector2(10, 2) if int(sp[2]) % 2 == 0 else Vector2(-10, 2)
			map.update_trails()
	var a: WorldArmy = c.world.armies[0] if not c.world.armies.is_empty() else null
	if a != null:
		a.mode = "march"
		a.pos = at + Vector2(10, 110)
	ow.player.path.clear()
	for k in 6:
		ow.player.pos += Vector2(9, 3)
		map.update_trails()
