class_name GameOptions
extends RefCounted
## Options du joueur : volumes, plein écran, taille de l'interface, vitesse du jeu,
## difficulté de l'escarmouche, aide de bataille, accessibilité (formes des camps, sous-titres)
## et touches de bataille (caméra comprise).
## Sauvegardées dans user://options.cfg (ConfigFile) et appliquées au démarrage
## (ensure_loaded() est appelé par le menu, la carte et la bataille).
##
## Touches : on stocke le keycode logique (la lettre imprimée sur la touche), donc une touche
## choisie sur un clavier AZERTY reste la bonne. Les touches de caméra (ZQSD en AZERTY,
## WASD en QWERTY par défaut) sont repérées par leur position physique (CAMERA_ACTIONS) :
## elles se reconfigurent aussi, mais une action ne peut pas prendre une touche de caméra.

const DEFAULT_PATH := "user://options.cfg"
const SPEEDS: Array[float] = [1.0, 1.5, 2.0]
## Tailles de l'interface proposées (facteur appliqué à toute la fenêtre, voir apply_display()).
const UI_SCALES: Array[float] = [0.9, 1.0, 1.25, 1.5]
const BUS_MUSIC := "Musique"
const BUS_SFX := "Effets"
## Niveaux des effets visuels de bataille (battle_effects.gd) et leurs noms affichés.
const EFFECTS: Array[String] = ["full", "reduced", "none"]
const EFFECTS_NAMES: Array[String] = ["Complets", "Réduits", "Aucun"]

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
	{"id": "captain", "name": "Capitaine : rejoindre la sélection", "key": KEY_C},
	{"id": "cards", "name": "Cartes des régiments (afficher / cacher)", "key": KEY_TAB},
	{"id": "minimap", "name": "Mini-carte (afficher / cacher)", "key": KEY_N},
]
## Défilement de la caméra : touches repérées par leur position physique (« key » est un
## physical_keycode : W = Z en AZERTY). Les flèches marchent toujours en plus.
const CAMERA_ACTIONS: Array[Dictionary] = [
	{"id": "cam_up", "name": "Caméra : haut", "key": KEY_W},
	{"id": "cam_left", "name": "Caméra : gauche", "key": KEY_A},
	{"id": "cam_down", "name": "Caméra : bas", "key": KEY_S},
	{"id": "cam_right", "name": "Caméra : droite", "key": KEY_D},
]

## Touches réservées (non reconfigurables) : keycode logique -> usage.
const RESERVED := {
	KEY_SPACE: "lancer / pause",
	KEY_ENTER: "fin de bataille",
	KEY_KP_ENTER: "fin de bataille",
	KEY_ESCAPE: "retour au menu",
	KEY_F11: "plein écran",
	KEY_UP: "caméra", KEY_DOWN: "caméra", KEY_LEFT: "caméra", KEY_RIGHT: "caméra",
	KEY_SHIFT: "ajout à la sélection", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_META: "Méta",
}
## Positions physiques réservées : chiffres de sélection (la caméra est vérifiée à part,
## puisqu'elle se reconfigure : voir camera_action_for_physical).
const RESERVED_PHYSICAL := {
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
static var ui_scale := 1.0 ## Taille de l'interface (une valeur de UI_SCALES)
static var speed := 1.0 ## Vitesse de la simulation en bataille
static var difficulty := Difficulty.NORMAL ## Difficulté de l'escarmouche (la campagne a la sienne)
static var effects := "full" ## Effets visuels de bataille : une valeur de EFFECTS
static var binds := {} ## id d'action -> keycode
static var camera_binds := {} ## id d'action de caméra -> physical_keycode
static var show_help := false ## Aide de bataille (F1) dépliée ; mémorisée d'une bataille à l'autre
static var show_cards := true ## Cartes des régiments affichées en bataille (Tab) ; mémorisé aussi
static var show_minimap := true ## Mini-carte de bataille affichée (N) ; mémorisée aussi
static var team_shapes := false ## Accessibilité : formes et motifs en plus du bleu et du rouge
static var subtitles := false ## Accessibilité : sous-titres des évènements sonores importants


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
	ui_scale = 1.0
	speed = 1.0
	difficulty = Difficulty.NORMAL
	show_help = false
	show_cards = true
	show_minimap = true
	team_shapes = false
	subtitles = false
	effects = "full"
	reset_keys()


static func reset_keys() -> void:
	binds.clear()
	for a in ACTIONS:
		binds[a["id"]] = int(a["key"])
	camera_binds.clear()
	for a in CAMERA_ACTIONS:
		camera_binds[a["id"]] = int(a["key"])


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
	var ui := float(cfg.get_value("affichage", "taille_interface", ui_scale))
	ui_scale = ui if ui in UI_SCALES else 1.0
	var sp := float(cfg.get_value("jeu", "vitesse", speed))
	speed = sp if sp in SPEEDS else 1.0
	difficulty = Difficulty.sanitize(str(cfg.get_value("jeu", "difficulte", difficulty)))
	show_help = bool(cfg.get_value("interface", "aide", show_help))
	show_cards = bool(cfg.get_value("interface", "cartes", show_cards))
	show_minimap = bool(cfg.get_value("interface", "minicarte", show_minimap))
	team_shapes = bool(cfg.get_value("accessibilite", "formes_camps", team_shapes))
	subtitles = bool(cfg.get_value("accessibilite", "sous_titres", subtitles))
	var fx := str(cfg.get_value("affichage", "effets", effects))
	effects = fx if fx in EFFECTS else "full"
	for a in ACTIONS:
		var id: String = a["id"]
		binds[id] = int(cfg.get_value("touches", id, binds[id]))
	for a in CAMERA_ACTIONS:
		var id: String = a["id"]
		camera_binds[id] = int(cfg.get_value("touches_camera", id, camera_binds[id]))
	# Un fichier modifié à la main peut contenir deux fois la même touche : on revient au défaut.
	if not conflicts().is_empty():
		reset_keys()


static func save_options() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "general", master_volume)
	cfg.set_value("audio", "musique", music_volume)
	cfg.set_value("audio", "effets", sfx_volume)
	cfg.set_value("affichage", "plein_ecran", fullscreen)
	cfg.set_value("affichage", "taille_interface", ui_scale)
	cfg.set_value("affichage", "effets", effects)
	cfg.set_value("jeu", "vitesse", speed)
	cfg.set_value("jeu", "difficulte", difficulty)
	cfg.set_value("interface", "aide", show_help)
	cfg.set_value("interface", "cartes", show_cards)
	cfg.set_value("interface", "minicarte", show_minimap)
	cfg.set_value("accessibilite", "formes_camps", team_shapes)
	cfg.set_value("accessibilite", "sous_titres", subtitles)
	for id in binds:
		cfg.set_value("touches", id, binds[id])
	for id in camera_binds:
		cfg.set_value("touches_camera", id, camera_binds[id])
	return cfg.save(path) == OK


static func apply() -> void:
	apply_audio()
	apply_display()


# ---------------------------------------------------------------- Son

## Crée les bus Musique et Effets (reliés au bus Master) s'ils n'existent pas encore.
static func ensure_buses() -> void:
	if is_test_run():
		AudioServer.set_bus_mute(0, true) # Tests : sortie principale coupée
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
	if is_test_run():
		AudioServer.set_bus_mute(0, true) # Tests : jamais de son, même avec fenêtre


## Vrai quand le jeu est lancé par un script de test (godot -s ...) ou sans affichage.
static func is_test_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")


static func _set_bus(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


# ---------------------------------------------------------------- Affichage et vitesse

## Affichage : la fenêtre s'étire en mode « canvas_items » avec l'aspect « expand »
## (project.godot) : la base 1280×720 est agrandie ou réduite selon la hauteur, et les écrans
## 16:10 ou 21:9 montrent simplement plus de surface. Les polices sont rendues à la taille
## finale (nettes à toute échelle). La taille de l'interface multiplie ce facteur.
static func apply_display() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Vrai si la fenêtre est en plein écran (quel que soit le moyen qui l'y a mise).
static func is_window_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return fullscreen
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Alt+Entrée / F11 : bascule le plein écran et le sauvegarde.
static func toggle_fullscreen() -> void:
	ensure_loaded()
	fullscreen = not is_window_fullscreen()
	apply_display()
	save_options()


static func set_ui_scale(v: float) -> void:
	ui_scale = v if v in UI_SCALES else 1.0
	apply_display()
	save_options()


## « 125 % » : nom d'une taille de l'interface.
static func ui_scale_label(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


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

## Vrai pour une action de défilement de la caméra (touche physique).
static func is_camera(id: String) -> bool:
	return id.begins_with("cam_")


static func action_name(id: String) -> String:
	for a in ACTIONS + CAMERA_ACTIONS:
		if a["id"] == id:
			return a["name"]
	return id


static func default_key(id: String) -> int:
	for a in ACTIONS + CAMERA_ACTIONS:
		if a["id"] == id:
			return int(a["key"])
	return KEY_NONE


## Touche d'une action : keycode logique, ou physical_keycode pour la caméra.
static func key_for(id: String) -> int:
	ensure_loaded()
	if is_camera(id):
		return int(camera_binds.get(id, default_key(id)))
	return int(binds.get(id, default_key(id)))


## Touche logique (lettre imprimée) à une position physique, selon la disposition du clavier.
static func logical_of_physical(physical: int) -> int:
	if DisplayServer.get_name() == "headless":
		return physical # Pas de disposition clavier sans affichage (tests)
	var code := int(DisplayServer.keyboard_get_keycode_from_physical(physical))
	return code if code != KEY_NONE else physical


## Action de caméra liée à une position physique (ou "").
static func camera_action_for_physical(physical: int) -> String:
	ensure_loaded()
	for id in camera_binds:
		if int(camera_binds[id]) == physical:
			return id
	return ""


## Vrai si la touche de caméra id est enfoncée (lu à chaque image par battle_camera.gd).
static func camera_pressed(id: String) -> bool:
	return Input.is_physical_key_pressed(key_for(id) as Key)


## « ZQSD » en AZERTY, « WASD » en QWERTY : les quatre touches de caméra, pour l'aide.
static func camera_keys_label() -> String:
	var s := ""
	for id in ["cam_up", "cam_left", "cam_down", "cam_right"]:
		s += key_label(id)
	return s


## Nom lisible d'une touche (« H », « F1 »…).
static func key_name(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "—"
	return OS.get_keycode_string(keycode)


## Nom de la touche d'une action, pour l'aide affichée.
static func key_label(id: String) -> String:
	if is_camera(id):
		return key_name(logical_of_physical(key_for(id)))
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
	var cam := camera_action_for_physical(physical)
	if cam != "":
		return action_name(cam).to_lower()
	return ""


## Associe la touche d'un évènement à une action. Renvoie un message pour le joueur.
## Si la touche était déjà prise par une autre action, les deux actions échangent leurs touches.
static func bind_event(id: String, k: InputEventKey) -> String:
	return bind_key(id, event_keycode(k), int(k.physical_keycode))


static func bind_key(id: String, keycode: int, physical: int = KEY_NONE) -> String:
	ensure_loaded()
	if is_camera(id):
		return bind_camera(id, keycode, physical)
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


## Touche de caméra : on garde la position physique (ZQSD reste ZQSD en AZERTY). Refusée si elle
## est réservée ou prise par une action de bataille ; échange avec une autre touche de caméra.
static func bind_camera(id: String, keycode: int, physical: int) -> String:
	if physical == KEY_NONE:
		physical = keycode # Évènement sans position physique (tests) : même code
	if physical == KEY_NONE:
		return "Touche non reconnue."
	var logical := keycode if keycode != KEY_NONE else logical_of_physical(physical)
	var shown := key_name(logical)
	if RESERVED.has(logical) or RESERVED.has(physical):
		return "%s est réservée (%s)." % [shown, RESERVED.get(logical, RESERVED.get(physical))]
	if RESERVED_PHYSICAL.has(physical):
		return "%s est réservée (%s)." % [shown, RESERVED_PHYSICAL[physical]]
	var act := action_for_key(logical)
	if act != "":
		return "%s est déjà utilisée par « %s » : changez d'abord cette action." % [shown, action_name(act)]
	var old := key_for(id)
	var other := camera_action_for_physical(physical)
	camera_binds[id] = physical
	if other != "" and other != id:
		camera_binds[other] = old
		return "%s était déjà utilisée par « %s » : cette action passe sur %s." % [shown, action_name(other), key_name(logical_of_physical(old))]
	return "%s : %s." % [action_name(id), shown]


## Actions qui partagent une même touche (ne devrait jamais arriver ; pour les tests).
## La caméra compte aussi : une touche de caméra ne doit être ni doublée ni prise par une action.
static func conflicts() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for id in binds:
		var code: int = binds[id]
		if seen.has(code):
			out.append("%s / %s" % [seen[code], id])
		seen[code] = id
	var seen_cam := {}
	for id in camera_binds:
		var phys: int = camera_binds[id]
		if seen_cam.has(phys):
			out.append("%s / %s" % [seen_cam[phys], id])
		seen_cam[phys] = id
		var logical := logical_of_physical(phys)
		if seen.has(logical):
			out.append("%s / %s" % [seen[logical], id])
		if RESERVED_PHYSICAL.has(phys) or RESERVED.has(logical):
			out.append("%s réservée" % id)
	return out
