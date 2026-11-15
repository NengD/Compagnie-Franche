class_name BattleAudio
extends Node
## Sons de bataille (assets libres, voir CREDITS.md).
## Volume selon la distance au centre de la caméra ; limite le nombre de sons simultanés.
## Musique sur le bus « Musique » (via GameAudio, fondu avec la carte et le menu), effets et
## ambiance sur le bus « Effets » (volumes réglés dans les Options).
##
## Le nœud suit lui-même l'état de la bataille (battle.state, battle.raining, battle.retreated) :
## cor de charge au lancement, fanfare de victoire, cor de retraite, musique de défaite, pluie.
## battle.gd n'a donc qu'à appeler play(), play_cries() et play_miss() ; les fonctions
## on_battle_start(), on_victory(), on_defeat() et set_rain() restent appelables à la main.

const SFX_DIR := "res://assets/audio/sfx/"
const AMB_DIR := "res://assets/audio/ambience/"
const MUSIC_PATH := "res://assets/audio/music/battle.mp3" ## Jouée par GameAudio (« battle »)
const VOICES := 20 ## Sons simultanés au maximum
const HORN_DB := -9.0
const FANFARE_DB := -8.0
## Ambiance en boucle : nom -> [fichier, volume (dB)]
const AMBIENCE := {
	"wind": ["wind.wav", -24.0],
	"birds": ["birds.ogg", -27.0],
	"rain": ["rain.ogg", -14.0],
}
## Cor : [début dans le fichier (s), durée (s), hauteur]. La retraite est le même cor, plus grave.
const HORNS := {
	"charge": [0.0, 6.0, 1.0],
	"retreat": [0.0, 4.5, 0.78],
}
## Copie de battle.State (DEPLOY, BATTLE, VICTORY, DEFEAT), lue sans dépendre de battle.gd
const ST_BATTLE := 1
const ST_VICTORY := 2
const ST_DEFEAT := 3

## Familles de sons : nom -> [fichiers, volume (dB), écart minimal entre deux sons (s)]
const BANKS := {
	"sword": [["sword_%d.ogg", 10], -10.0, 0.06],
	"clash": [["clash_%d.ogg", 10], -9.0, 0.06],
	"bow": [["bow.wav", 1], -12.0, 0.07],
	"swish": [["swish_%d.wav", [2, 3, 4]], -17.0, 0.09], # Flèche qui manque sa cible
	"death": [["death_%d.wav", 10], -9.0, 0.18],
}

var battle: Node2D ## Pour connaître la caméra
var enabled := true
var streams := {} ## nom -> Array[AudioStream]
var last_play := {} ## nom -> instant du dernier son
var voices: Array[AudioStreamPlayer] = []
var music: AudioStream ## Musique de bataille (jouée par GameAudio)
var ambience := {} ## nom -> AudioStreamPlayer (en boucle, volume ajusté dans _process)
var horn: AudioStreamPlayer
var horn_left := 0.0 ## Temps de cor restant avant le fondu
var fanfare: AudioStreamPlayer
var last_state := -1 ## Dernier état de bataille vu
var raining := false
var gallop: AudioStreamPlayer
var gallop_level := 0.0
var clock := 0.0
var cries: Array = [] ## Cris de déroute à venir : [instant, position]


func _ready() -> void:
	# Tests (sans fenêtre, ou lancés par « godot -s ») : on charge les sons sans les jouer.
	# Le pilote audio factice ne libère pas les lectures en cours à la fermeture.
	if GameOptions.is_test_run():
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

	for k in AMBIENCE:
		var a := _load(AMB_DIR + str(AMBIENCE[k][0]))
		if a == null:
			continue
		_set_loop(a)
		var p := AudioStreamPlayer.new()
		p.stream = a
		p.volume_db = -80.0
		p.bus = GameOptions.BUS_SFX
		add_child(p)
		ambience[k] = p

	var h := _load(SFX_DIR + "horn.mp3")
	if h != null:
		horn = AudioStreamPlayer.new()
		horn.stream = h
		horn.bus = GameOptions.BUS_SFX
		add_child(horn)
	var f := _load(SFX_DIR + "fanfare.ogg")
	if f != null:
		fanfare = AudioStreamPlayer.new()
		fanfare.stream = f
		fanfare.volume_db = FANFARE_DB
		fanfare.bus = GameOptions.BUS_SFX
		add_child(fanfare)

	music = _load(MUSIC_PATH)
	if enabled:
		GameAudio.music("battle")


func _set_loop(s: AudioStream) -> void:
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)


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
	for p in [gallop, horn, fanfare] + ambience.values():
		if p != null:
			p.stop()
			p.stream = null


## Nombre de sons chargés (pour les tests).
func loaded_count() -> int:
	var n := 0
	for k in streams:
		n += streams[k].size()
	for p in [gallop, horn, fanfare] + ambience.values():
		if p != null:
			n += 1
	if music != null:
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
	_watch_battle()
	_update_ambience(delta)
	if horn != null and horn.playing:
		horn_left -= delta
		if horn_left <= 0.0:
			horn.volume_db -= delta * 30.0 # Fondu de fin du cor
			if horn.volume_db < -50.0:
				horn.stop()


## Suit l'état de la bataille pour jouer cors et fanfares sans appel depuis battle.gd.
func _watch_battle() -> void:
	if battle == null:
		return
	var rain_now := bool(battle.get("raining"))
	if rain_now != raining:
		set_rain(rain_now)
	var st := int(battle.get("state"))
	if st == last_state:
		return
	var first := last_state < 0
	last_state = st
	if first:
		return # Premier état vu (déploiement, ou bataille déjà lancée par un test) : rien
	match st:
		ST_BATTLE:
			on_battle_start()
		ST_VICTORY:
			on_victory()
		ST_DEFEAT:
			on_defeat(bool(battle.get("retreated")))


## Vent toujours, oiseaux par beau temps, pluie quand il pleut (fondus doux).
func _update_ambience(delta: float) -> void:
	for k in ambience:
		var p: AudioStreamPlayer = ambience[k]
		var on: bool = enabled and (k == "wind" or (k == "rain") == raining)
		var target := float(AMBIENCE[k][1]) if on else -80.0
		p.volume_db = move_toward(p.volume_db, target, delta * 20.0)
		if p.volume_db > -70.0 and not p.playing:
			p.play()
		elif p.volume_db <= -79.0 and p.playing:
			p.stop()


## Lancement de la bataille : cor de charge.
func on_battle_start() -> void:
	play_horn("charge")


## Victoire : fanfare, puis la musique de victoire remplace celle de bataille.
func on_victory() -> void:
	if not enabled:
		return
	if fanfare != null:
		fanfare.play()
	GameAudio.music("victory")


## Défaite : cor de retraite si le joueur l'a sonnée, puis musique de défaite.
func on_defeat(retreat: bool) -> void:
	if not enabled:
		return
	if retreat:
		play_horn("retreat")
	GameAudio.music("defeat")


## Cor de charge ou de retraite (voir HORNS).
func play_horn(kind: String) -> void:
	if not enabled or horn == null or not HORNS.has(kind):
		return
	var spec: Array = HORNS[kind]
	horn.pitch_scale = float(spec[2])
	horn.volume_db = HORN_DB
	horn_left = float(spec[1])
	horn.play(float(spec[0]))


## Pluie : bruit de pluie à la place des oiseaux.
func set_rain(on: bool) -> void:
	raining = on


## Flèche (ou coup) qui manque sa cible : sifflement de la banque « swish ».
func play_miss(world_pos: Vector2) -> void:
	play("swish", world_pos)


func set_enabled(on: bool) -> void:
	enabled = on
	GameAudio.pause_music(not on)
	if not on:
		cries.clear()
		for v in voices:
			v.stop()
		for p in [horn, fanfare]:
			if p != null:
				p.stop()


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
