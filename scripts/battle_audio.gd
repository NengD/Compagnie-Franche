class_name BattleAudio
extends Node
## Sons de bataille et musique (assets libres, voir CREDITS.md).
## Volume selon la distance au centre de la caméra ; limite le nombre de sons simultanés.
## Musique sur le bus « Musique », effets sur le bus « Effets » (volumes réglés dans les Options).

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_PATH := "res://assets/audio/music/battle.mp3"
const VOICES := 20 ## Sons simultanés au maximum
const MUSIC_DB := -15.0

## Familles de sons : nom -> [fichiers, volume (dB), écart minimal entre deux sons (s)]
const BANKS := {
	"sword": [["sword_%d.ogg", 10], -10.0, 0.06],
	"clash": [["clash_%d.ogg", 10], -9.0, 0.06],
	"bow": [["bow.wav", 1], -12.0, 0.07],
	"swish": [["swish_%d.wav", [2, 3, 4]], -16.0, 0.08],
	"death": [["death_%d.wav", 10], -9.0, 0.18],
}

var battle: Node2D ## Pour connaître la caméra
var enabled := true
var streams := {} ## nom -> Array[AudioStream]
var last_play := {} ## nom -> instant du dernier son
var voices: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var gallop: AudioStreamPlayer
var gallop_level := 0.0
var clock := 0.0
var cries: Array = [] ## Cris de déroute à venir : [instant, position]


func _ready() -> void:
	# Sans fenêtre (tests), personne n'entend rien : on charge les sons sans les jouer.
	# Le pilote audio factice ne libère pas les lectures en cours à la fermeture.
	if DisplayServer.get_name() == "headless":
		enabled = false
	GameOptions.ensure_loaded()
	GameOptions.ensure_buses()
	for bank in BANKS:
		var spec: Array = BANKS[bank][0]
		var pattern: String = spec[0]
		var list: Array[AudioStream] = []
		var ids: Array = []
		if spec[1] is Array:
			ids = spec[1]
		elif int(spec[1]) == 1 and not pattern.contains("%"):
			ids = [0]
		else:
			ids = range(1, int(spec[1]) + 1)
		for i in ids:
			var file := pattern if not pattern.contains("%") else pattern % i
			var s := _load(SFX_DIR + file)
			if s != null:
				list.append(s)
		streams[bank] = list

	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = GameOptions.BUS_SFX
		add_child(p)
		voices.append(p)

	var g := _load(SFX_DIR + "gallop.mp3")
	if g != null:
		if g is AudioStreamMP3:
			(g as AudioStreamMP3).loop = true
		gallop = AudioStreamPlayer.new()
		gallop.stream = g
		gallop.volume_db = -80.0
		gallop.bus = GameOptions.BUS_SFX
		add_child(gallop)

	var m := _load(MUSIC_PATH)
	if m != null:
		if m is AudioStreamMP3:
			(m as AudioStreamMP3).loop = true
		music = AudioStreamPlayer.new()
		music.stream = m
		music.volume_db = MUSIC_DB
		music.bus = GameOptions.BUS_MUSIC
		add_child(music)
		if enabled:
			music.play()


func _load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Son manquant : " + path)
		return null
	return load(path) as AudioStream


func _exit_tree() -> void:
	# Arrête tout pour que le serveur audio libère les lectures en cours
	for v in voices:
		v.stop()
		v.stream = null
	for p in [music, gallop]:
		if p != null:
			p.stop()
			p.stream = null


## Nombre de sons chargés (pour les tests).
func loaded_count() -> int:
	var n := 0
	for k in streams:
		n += streams[k].size()
	if music != null:
		n += 1
	if gallop != null:
		n += 1
	return n


func _process(delta: float) -> void:
	clock += delta
	while not cries.is_empty() and float(cries[0][0]) <= clock:
		var c: Array = cries.pop_front()
		_cry(c[1])
	if gallop != null:
		var target := -80.0 if (gallop_level <= 0.01 or not enabled) else lerpf(-26.0, -8.0, gallop_level)
		gallop.volume_db = move_toward(gallop.volume_db, target, delta * 60.0)
		if gallop.volume_db > -70.0 and not gallop.playing:
			gallop.play()
		elif gallop.volume_db <= -79.0 and gallop.playing:
			gallop.stop()


func set_enabled(on: bool) -> void:
	enabled = on
	if music != null:
		if on and not music.playing:
			music.play()
		elif not on:
			music.stop()
	if not on:
		cries.clear()
		for v in voices:
			v.stop()


## Joue un son de la famille « bank » à une position du monde.
func play(bank: String, world_pos: Vector2, extra_db := 0.0) -> void:
	if not enabled or not streams.has(bank):
		return
	var list: Array = streams[bank]
	if list.is_empty():
		return
	var gap: float = BANKS[bank][2]
	if clock - float(last_play.get(bank, -10.0)) < gap:
		return
	var att := attenuation(world_pos)
	if att <= -40.0:
		return
	for v in voices:
		if not v.playing:
			last_play[bank] = clock
			v.stream = list[randi() % list.size()]
			v.volume_db = float(BANKS[bank][1]) + att + extra_db
			v.pitch_scale = randf_range(0.9, 1.1)
			v.play()
			return


## Cris de panique d'un régiment qui fuit : quelques cris étalés sur une seconde et demie.
## Réutilise les cris de la banque « death », joués plus aigus pour sonner comme des hurlements.
func play_cries(world_pos: Vector2, n: int) -> void:
	if not enabled:
		return
	var t := clock
	for i in n:
		t += randf_range(0.12, 0.4)
		cries.append([t, world_pos + Vector2(randf_range(-30, 30), randf_range(-20, 20))])
	cries.sort_custom(func(a, b): return a[0] < b[0])


func _cry(world_pos: Vector2) -> void:
	var list: Array = streams.get("death", [])
	if not enabled or list.is_empty():
		return
	var att := attenuation(world_pos)
	if att <= -40.0:
		return
	for v in voices:
		if not v.playing:
			v.stream = list[randi() % list.size()]
			v.volume_db = -11.0 + att
			v.pitch_scale = randf_range(1.2, 1.45)
			v.play()
			return


## Atténuation (dB) selon la distance au centre de l'écran : plein volume à l'écran,
## de plus en plus faible au-delà, et silence quand on est très loin ou très dézoomé.
func attenuation(world_pos: Vector2) -> float:
	if battle == null or battle.camera == null:
		return 0.0
	var cam: Camera2D = battle.camera
	var half := battle.get_viewport_rect().size / cam.zoom * 0.5
	var d := (world_pos - cam.position).abs() / half.max(Vector2(1, 1))
	var k := maxf(d.x, d.y) # 1 = bord de l'écran
	var db := 0.0
	if k > 1.0:
		db -= (k - 1.0) * 18.0
	db -= maxf(0.0, 1.0 - cam.zoom.x) * 8.0 # Vue lointaine : bataille plus feutrée
	return db
