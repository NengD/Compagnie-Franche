class_name GameAudio
extends Node
## Audio qui survit aux changements de scène : musiques (menu, carte, bataille, victoire,
## défaite) avec fondu enchaîné, et sons d'interface (clic, survol, or dépensé, refus).
## Assets libres, voir CREDITS.md. Musique sur le bus « Musique », sons sur le bus « Effets ».
##
## Pas d'autoload : le nœud est créé à la demande sous la racine de l'arbre (instance()) et
## reste en place d'une scène à l'autre. Il branche tout seul le clic et le survol sur chaque
## bouton qui entre dans l'arbre : les scènes n'ont qu'à appeler GameAudio.music("menu"),
## GameAudio.feedback(ok)…
## Pendant les tests (GameOptions.is_test_run()), rien n'est créé ni joué ; load_all() permet
## quand même de vérifier que tous les fichiers se chargent.

const NODE_NAME := "GameAudio"
const FADE := 1.6 ## Durée du fondu enchaîné entre deux musiques (s)
const SILENT_DB := -60.0
const UI_VOICES := 4

## Musiques : nom -> [fichier, volume (dB), en boucle]
const MUSIC := {
	"menu": ["res://assets/audio/music/menu.mp3", -14.0, true],
	"campaign": ["res://assets/audio/music/campaign.mp3", -15.0, true],
	"battle": ["res://assets/audio/music/battle.mp3", -15.0, true],
	"victory": ["res://assets/audio/music/victory.mp3", -13.0, false],
	"defeat": ["res://assets/audio/music/defeat.mp3", -13.0, false],
}
## Sons d'interface : nom -> [fichier, volume (dB)]
const UI := {
	"click": ["res://assets/audio/ui/click.wav", -12.0],
	"hover": ["res://assets/audio/ui/hover.wav", -22.0],
	"coins": ["res://assets/audio/ui/coins.ogg", -8.0],
	"refuse": ["res://assets/audio/ui/refuse.ogg", -10.0],
}

static var _cache := {} ## chemin -> AudioStream
static var _node: GameAudio = null ## Le nœud persistant (peut ne pas être encore dans l'arbre)

var current := "" ## Musique en cours (ou demandée)
var music_paused := false
var players: Array[AudioStreamPlayer] = [] ## Deux lecteurs de musique pour le fondu
var active := 0
var tweens: Array = [null, null]
var ui_voices: Array[AudioStreamPlayer] = []
var last_hover_ms := -1000
## Tests : on choisit les musiques sans rien lancer (le pilote audio factice ne libère pas
## les lectures en cours à la fermeture).
var silent := GameOptions.is_test_run()


# ---------------------------------------------------------------- Accès statique

## Le nœud persistant (créé au premier appel), ou null pendant les tests.
static func instance() -> GameAudio:
	if GameOptions.is_test_run():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if _node != null and is_instance_valid(_node):
		return _node
	_node = GameAudio.new()
	_node.name = NODE_NAME
	# La racine peut être occupée (appel depuis le _ready d'une scène) : ajout différé.
	tree.root.add_child.call_deferred(_node)
	return _node


## Lance une musique (fondu enchaîné avec la précédente). "" = silence.
static func music(music_name: String) -> void:
	var n := instance()
	if n != null:
		n.play_music(music_name)


## Coupe ou reprend la musique (touche M en bataille).
static func pause_music(on: bool) -> void:
	var n := instance()
	if n != null:
		n.set_music_paused(on)


## Son d'interface (« click », « hover », « coins », « refuse »).
static func ui(sound: String) -> void:
	var n := instance()
	if n != null:
		n.play_ui(sound)


## Retour d'une action qui coûte de l'or : pièces si elle a réussi, refus sinon.
static func feedback(ok: bool) -> void:
	ui("coins" if ok else "refuse")


## Charge un son (avec cache) ; avertissement et null s'il manque.
static func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("Son manquant : " + path)
		return null
	var s := load(path) as AudioStream
	_cache[path] = s
	return s


## Charge toutes les musiques et tous les sons d'interface (pour les tests).
## Renvoie les chemins qui n'ont pas pu être chargés.
static func load_all() -> Array[String]:
	var missing: Array[String] = []
	for k in MUSIC:
		if stream(MUSIC[k][0]) == null:
			missing.append(MUSIC[k][0])
	for k in UI:
		if stream(UI[k][0]) == null:
			missing.append(UI[k][0])
	return missing


# ---------------------------------------------------------------- Nœud

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Le fondu continue même jeu en pause
	GameOptions.ensure_loaded()
	GameOptions.ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = GameOptions.BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		players.append(p)
	for i in UI_VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = GameOptions.BUS_SFX
		add_child(v)
		ui_voices.append(v)
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)
	# Musique demandée avant l'entrée dans l'arbre (ajout différé)
	if current != "":
		var wanted := current
		current = ""
		play_music(wanted)


func _exit_tree() -> void:
	for p in players + ui_voices:
		p.stop()
		p.stream = null


func play_music(music_name: String) -> void:
	if music_name == current:
		if music_paused:
			set_music_paused(false)
		return
	current = music_name
	music_paused = false
	if players.is_empty():
		return # Pas encore dans l'arbre : _ready() s'en charge
	_fade(active, SILENT_DB, true)
	if not MUSIC.has(music_name):
		return
	var s := stream(MUSIC[music_name][0])
	if s == null:
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = MUSIC[music_name][2]
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = MUSIC[music_name][2]
	active = 1 - active
	var p := players[active]
	p.stream = s
	p.volume_db = SILENT_DB
	p.stream_paused = false
	if not silent:
		p.play()
	_fade(active, float(MUSIC[music_name][1]), false)


func _fade(i: int, to_db: float, stop_after: bool) -> void:
	var p := players[i]
	if tweens[i] != null and (tweens[i] as Tween).is_valid():
		(tweens[i] as Tween).kill()
	if not p.playing:
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, FADE)
	if stop_after:
		t.tween_callback(p.stop)
	tweens[i] = t


func set_music_paused(on: bool) -> void:
	music_paused = on
	for p in players:
		p.stream_paused = on


func play_ui(sound: String) -> void:
	if silent or not UI.has(sound) or ui_voices.is_empty():
		return
	var s := stream(UI[sound][0])
	if s == null:
		return
	for v in ui_voices:
		if not v.playing:
			v.stream = s
			v.volume_db = float(UI[sound][1])
			v.pitch_scale = randf_range(0.96, 1.04)
			v.play()
			return


# ---------------------------------------------------------------- Boutons

## Branche le clic et le survol sur tous les boutons déjà présents.
func _hook_tree(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_hook_tree(c)


func _on_node_added(n: Node) -> void:
	if not n is BaseButton or n.has_meta("ui_audio"):
		return
	var b := n as BaseButton
	b.set_meta("ui_audio", true)
	b.pressed.connect(_on_pressed)
	b.mouse_entered.connect(_on_hover.bind(b))
	b.gui_input.connect(_on_button_input.bind(b))


func _on_pressed() -> void:
	play_ui("click")


func _on_hover(b: BaseButton) -> void:
	if b.disabled or Time.get_ticks_msec() - last_hover_ms < 60:
		return
	last_hover_ms = Time.get_ticks_msec()
	play_ui("hover")


## Clic sur un bouton grisé (or insuffisant, action impossible) : son de refus.
func _on_button_input(event: InputEvent, b: BaseButton) -> void:
	var mb := event as InputEventMouseButton
	if b.disabled and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		play_ui("refuse")
