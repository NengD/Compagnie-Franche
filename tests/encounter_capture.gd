extends SceneTree
## Captures du panneau de rencontre (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/encounter_capture.gd [-- --out=<dossier>]
## Enregistre rencontre_villageois.png et rencontre_bandits.png dans user://captures (défaut).

const CaptureDir := preload("res://tests/capture_dir.gd")

var frame := 0
var state: CampaignState
var player: Party
var holder: Node
var shots := [] ## [nom du fichier, groupe]


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.event_chance = 0.0
	state = CampaignState.new_game(42)
	state.loot = 120
	player = Party.new()
	player.id = 1
	player.kind = "player"
	var v := Party.new()
	v.id = 5
	v.kind = "villagers"
	v.faction = 0
	v.name = "les gens de Brumefosse"
	v.gold = 60
	v.goods = 200
	v.troops = [{"type": "spear", "men": 24, "xp": 0.0}]
	var b := Party.new()
	b.id = 6
	b.kind = "bandits"
	b.name = "les Écorcheurs"
	b.troops = [{"type": "archer", "men": 38, "xp": 0.0}, {"type": "spear", "men": 22, "xp": 120.0}]
	b.target_id = player.id
	b.state = "chase"
	shots = [["rencontre_villageois.png", v], ["rencontre_bandits.png", b]]
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.32, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	holder = Node.new()
	root.add_child(holder)


func _process(_delta: float) -> bool:
	frame += 1
	var i := (frame - 1) / 10
	if i >= shots.size():
		return true
	var step := (frame - 1) % 10
	if step == 0:
		for c in holder.get_children():
			c.free()
		Encounter.open(holder, state, player, shots[i][1])
	elif step == 8:
		CaptureDir.save(self, shots[i][0])
	return false
