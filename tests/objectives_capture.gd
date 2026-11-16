extends SceneTree
## Captures des objectifs de bataille (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/objectives_capture.gd [-- --out=<dossier>]
## Une image par objectif (tenir, escorter, prendre, poursuivre) après quelques secondes de bataille :
## zone au sol, chariots, ligne de fuite et panneau du HUD. Écrit dans user://captures par défaut.

const CaptureDir := preload("res://tests/capture_dir.gd")
const KINDS := ["hold", "escort", "capture", "pursue"]
const SIM_SECONDS := 25.0

var b: Battle
var index := 0
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les captures
	CampaignState.current = null
	_open()


func _open() -> void:
	b = load("res://scenes/main.tscn").instantiate()
	b.seed_override = 61 + index
	b.objective_override = KINDS[index]
	root.add_child(b)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		b.start_battle()
		for i in int(SIM_SECONDS / 0.05):
			b.simulate(0.05)
		var o = b.sim.objective
		var at := Vector2(BattleSim.WORLD_SIZE.x * 0.5, 1000.0)
		match KINDS[index]:
			"hold", "capture":
				at = o.center
			"escort":
				at = o.wagons[0]["pos"]
			"pursue":
				at = Vector2(BattleSim.WORLD_SIZE.x * 0.5, 500.0)
		b.camera.position = at
		b.camera.clamp_to_world()
	elif frame == 12:
		CaptureDir.save(self, "objectif_%s.png" % KINDS[index])
		print("Capture : objectif_%s.png" % KINDS[index])
		root.remove_child(b)
		b.free()
		index += 1
		if index >= KINDS.size():
			quit(0)
			return true
		_open()
	return false
