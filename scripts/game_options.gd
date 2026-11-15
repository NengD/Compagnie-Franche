class_name GameOptions
extends RefCounted
## Options du joueur : volumes, plein écran, vitesse du jeu et touches de bataille.
## Sauvegardées dans user://options.cfg (ConfigFile) et appliquées au démarrage
## (ensure_loaded() est appelé par le menu, la carte et la bataille).
##
## Touches : on stocke le keycode logique (la lettre imprimée sur la touche), donc une touche
## choisie sur un clavier AZERTY reste la bonne. Les touches de caméra (ZQSD en AZERTY,
## WASD en QWERTY) sont repérées par leur position physique et ne peuvent pas être prises.

const DEFAULT_PATH := "user://options.cfg"
const SPEEDS: Array[float] = [1.0, 1.5, 2.0]
const BUS_MUSIC := "Musique"
const BUS_SFX := "Effets"

## Actions de bataille reconfigurables : identifiant, nom affiché, touche par défaut.
## Pour en ajouter une : une ligne ici, puis un cas « KEY_x: » (la touche par défaut) dans le
## « match GameOptions.remap_key(...) » de battle.gd._unhandled_input. Rien d'autre à faire.
const ACTIONS: Array[Dictionary] = [
	{"id": "halt", "name": "Halte", "key": KEY_H},
	{"id": "formation", "name": "Formation (ligne / colonne / carré)", "key": KEY_F},
	{"id": "sound", "name": "Couper / remettre le son", "key": KEY_M},
	{"id": "rain", "name": "Pluie", "key": KEY_T},
	{"id": "help", "name": "Aide", "key": KEY_F1},
	{"id": "speed", "name": "Vitesse du jeu", "key": KEY_V},
	{"id": "hold", "name": "Tenir la position", "key": KEY_G},
	{"id": "fire", "name": "Tir à volonté", "key": KEY_X},
	{"id": "retreat", "name": "Retraite", "key": KEY_R},
]

## Touches réservées (non reconfigurables) : keycode logique -> usage.
const RESERVED := {
	KEY_SPACE: "lancer / pause",
	KEY_ENTER: "fin de bataille",
	KEY_KP_ENTER: "fin de bataille",
	KEY_ESCAPE: "retour au menu",
	KEY_UP: "caméra", KEY_DOWN: "caméra", KEY_LEFT: "caméra", KEY_RIGHT: "caméra",
	KEY_SHIFT: "ajout à la sélection", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_META: "Méta",
}
## Positions physiques réservées : caméra (ZQSD / WASD) et chiffres de sélection.
const RESERVED_PHYSICAL := {
	KEY_W: "caméra", KEY_A: "caméra", KEY_S: "caméra", KEY_D: "caméra",
	KEY_1: "sélection", KEY_2: "sélection", KEY_3: "sélection", KEY_4: "sélection",
	KEY_5: "sélection", KEY_6: "sélection", KEY_7: "sélection", KEY_8: "sélection",
	KEY_9: "sélection",
}

static var path := DEFAULT_PATH ## Les tests utilisent un autre fichier
static var loaded := false
static var master_volume := 1.0 ## 0..1
static var music_volume := 0.8
static var sfx_volume := 1.0
static var fullscreen := false
static var speed := 1.0 ## Vitesse de la simulation en bataille
static var binds := {} ## id d'action -> keycode


## Charge et applique les options une seule fois par lancement.
static func ensure_loaded() -> void:
	if loaded:
		return
	load_options()
	apply()


static func reset_all() -> void:
	master_volume = 1.0
	music_volume = 0.8
	sfx_volume = 1.0
	fullscreen = false
	speed = 1.0
	reset_keys()


static func reset_keys() -> void:
	binds.clear()
	for a in ACTIONS:
		binds[a["id"]] = int(a["key"])


static func load_options() -> void:
	reset_all()
	loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "general", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "musique", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "effets", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("affichage", "plein_ecran", fullscreen))
	var sp := float(cfg.get_value("jeu", "vitesse", speed))
	speed = sp if sp in SPEEDS else 1.0
	for a in ACTIONS:
		var id: String = a["id"]
		binds[id] = int(cfg.get_value("touches", id, binds[id]))
	# Un fichier modifié à la main peut contenir deux fois la même touche : on revient au défaut.
	var seen := {}
	for id in binds:
		if seen.has(binds[id]):
			reset_keys()
			break
		seen[binds[id]] = true


static func save_options() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "general", master_volume)
	cfg.set_value("audio", "musique", music_volume)
	cfg.set_value("audio", "effets", sfx_volume)
	cfg.set_value("affichage", "plein_ecran", fullscreen)
	cfg.set_value("jeu", "vitesse", speed)
	for id in binds:
		cfg.set_value("touches", id, binds[id])
	return cfg.save(path) == OK


static func apply() -> void:
	apply_audio()
	apply_display()


# ---------------------------------------------------------------- Son

## Crée les bus Musique et Effets (reliés au bus Master) s'ils n'existent pas encore.
static func ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")


static func apply_audio() -> void:
	ensure_buses()
	_set_bus("Master", master_volume)
	_set_bus(BUS_MUSIC, music_volume)
	_set_bus(BUS_SFX, sfx_volume)


static func _set_bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


# ---------------------------------------------------------------- Affichage et vitesse

static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Vitesse suivante (x1 → x1,5 → x2 → x1).
static func next_speed() -> float:
	var i := SPEEDS.find(speed)
	speed = SPEEDS[(i + 1) % SPEEDS.size()]
	return speed


static func speed_label(s: float = -1.0) -> String:
	if s < 0.0:
		s = speed
	return "x" + String.num(s, 1).trim_suffix(".0").replace(".", ",")


# ---------------------------------------------------------------- Touches

static func action_name(id: String) -> String:
	for a in ACTIONS:
		if a["id"] == id:
			return a["name"]
	return id


static func default_key(id: String) -> int:
	for a in ACTIONS:
		if a["id"] == id:
			return int(a["key"])
	return KEY_NONE


static func key_for(id: String) -> int:
	ensure_loaded()
	return int(binds.get(id, default_key(id)))


## Nom lisible d'une touche (« H », « F1 »…).
static func key_name(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode)


## Nom de la touche d'une action, pour l'aide affichée.
static func key_label(id: String) -> String:
	return key_name(key_for(id))


## Action liée à une touche (ou "").
static func action_for_key(keycode: int) -> String:
	ensure_loaded()
	for id in binds:
		if int(binds[id]) == keycode:
			return id
	return ""


## Traduit la touche pressée vers la touche par défaut de l'action qu'elle déclenche, pour
## que battle.gd puisse garder un simple « match » sur les touches par défaut :
##  - touche liée à une action → touche par défaut de cette action ;
##  - touche par défaut d'une action déplacée ailleurs → KEY_NONE (elle ne fait plus rien) ;
##  - autre touche → inchangée.
static func remap_key(keycode: int) -> int:
	var id := action_for_key(keycode)
	if id != "":
		return default_key(id)
	for a in ACTIONS:
		if int(a["key"]) == keycode:
			return KEY_NONE
	return keycode


## Keycode logique d'un évènement clavier (repli sur la position physique si absent).
static func event_keycode(k: InputEventKey) -> int:
	var code := int(k.keycode)
	if code == KEY_NONE and k.physical_keycode != KEY_NONE:
		if DisplayServer.get_name() == "headless":
			code = int(k.physical_keycode) # Pas de disposition clavier sans affichage (tests)
		else:
			code = int(DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode))
	return code


## Raison pour laquelle une touche ne peut pas être choisie ("" si elle est libre de réserve).
static func reserved_reason(keycode: int, physical: int) -> String:
	if RESERVED.has(keycode):
		return RESERVED[keycode]
	if RESERVED_PHYSICAL.has(physical):
		return RESERVED_PHYSICAL[physical]
	return ""


## Associe la touche d'un évènement à une action. Renvoie un message pour le joueur.
## Si la touche était déjà prise par une autre action, les deux actions échangent leurs touches.
static func bind_event(id: String, k: InputEventKey) -> String:
	return bind_key(id, event_keycode(k), int(k.physical_keycode))


static func bind_key(id: String, keycode: int, physical: int = KEY_NONE) -> String:
	ensure_loaded()
	if keycode == KEY_NONE:
		return "Touche non reconnue."
	var why := reserved_reason(keycode, physical)
	if why != "":
		return "%s est réservée (%s)." % [key_name(keycode), why]
	var old := key_for(id)
	var other := action_for_key(keycode)
	binds[id] = keycode
	if other != "" and other != id:
		binds[other] = old
		return "%s était déjà utilisée par « %s » : cette action passe sur %s." % [key_name(keycode), action_name(other), key_name(old)]
	return "%s : %s." % [action_name(id), key_name(keycode)]


## Actions qui partagent une même touche (ne devrait jamais arriver ; pour les tests).
static func conflicts() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for id in binds:
		var code: int = binds[id]
		if seen.has(code):
			out.append("%s / %s" % [seen[code], id])
		seen[code] = id
	return out
