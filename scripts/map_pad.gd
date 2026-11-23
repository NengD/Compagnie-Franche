class_name MapPad
extends RefCounted
## Manette sur la carte de campagne (Input joypad de Godot) :
## - stick gauche : curseur (la vue suit quand il touche le bord) ; stick droit : déplacer la vue ;
## - A : aller au point visé (ville : y entrer, groupe : le poursuivre) ; dans une fenêtre, le
##   bouton qui a le focus (navigation à la croix ou au stick, comme au clavier) ;
## - B : fermer la fenêtre ou l'onglet ; Start : menu ; Select : recentrer sur la compagnie ;
## - gâchettes : vitesse (droite : plus vite, gauche : plus lent puis pause) ; X : pause ; Y : halte ;
## - LB / RB : onglet précédent / suivant (Compagnie, Monde, Journal, Quêtes).
## Dès qu'on touche la souris ou le clavier, la manette rend la main (focus et curseur cachés).
##
## Brancher : campaign_map.gd appelle input(event) dans _input, step(delta) dans _process et
## draw_cursor() dans _draw ; refresh_ui() appelle focus_window().

const TABS := ["company", "world", "journal", "quests"]
const DEADZONE := 0.2
const CURSOR_SPEED := 700.0 ## Pixels d'écran par seconde, stick à fond
const PAN_SPEED := 900.0
const TRIGGER_ON := 0.6 ## Gâchette enfoncée au-delà de cette valeur

var map: Node ## campaign_map.gd
var active := false ## Dernière entrée venue de la manette
var cursor := Vector2(-1, -1) ## Position du curseur (écran) ; négative : centre de l'écran
var stick := Vector2.ZERO ## Stick gauche (après zone morte)
var look := Vector2.ZERO ## Stick droit
var triggers := [false, false] ## Gauche, droite : enfoncées (pour ne réagir qu'à l'appui)


func _init(m: Node) -> void:
	map = m


## Toute entrée passe ici avant l'interface (campaign_map._input). Renvoie vrai si elle est traitée.
func input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		set_active(true)
		var v := jm.axis_value if absf(jm.axis_value) > DEADZONE else 0.0
		match jm.axis:
			JOY_AXIS_LEFT_X:
				stick.x = v
			JOY_AXIS_LEFT_Y:
				stick.y = v
			JOY_AXIS_RIGHT_X:
				look.x = v
			JOY_AXIS_RIGHT_Y:
				look.y = v
			JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT:
				var i := 0 if jm.axis == JOY_AXIS_TRIGGER_LEFT else 1
				var on := jm.axis_value > TRIGGER_ON
				if on and not triggers[i]:
					change_speed(-1 if i == 0 else 1)
				triggers[i] = on
		return false # Les menus déroulants et curseurs de l'interface peuvent aussi s'en servir
	if event is InputEventJoypadButton:
		set_active(true)
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return false
		return button(jb.button_index)
	if event is InputEventMouseButton or event is InputEventKey:
		set_active(false)
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0:
		set_active(false)
	return false


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		if cursor.x < 0.0:
			cursor = map.get_viewport_rect().size * 0.5
		focus_window()
	else:
		var f: Control = map.get_viewport().gui_get_focus_owner()
		if f != null:
			f.release_focus()
		if map.panel != null:
			for b in buttons_in(map.panel):
				b.focus_mode = Control.FOCUS_NONE # Espace (pause) ne doit pas presser un bouton cliqué
	map.queue_redraw()


## Un bouton de la manette. Vrai s'il est traité ici (l'interface ne le voit pas).
func button(b: int) -> bool:
	var open: bool = map.panel != null and map.panel.visible
	match b:
		JOY_BUTTON_A:
			if open:
				var f: Control = map.get_viewport().gui_get_focus_owner()
				if f == null or not map.panel.is_ancestor_of(f):
					focus_window()
					return true
				return false # Le bouton qui a le focus est pressé (ui_accept)
			map.click_map(map.screen_to_world(cursor))
			return true
		JOY_BUTTON_B:
			if open and map.close_button.visible:
				map.close_window()
			return true
		JOY_BUTTON_START:
			map.escape()
			return true
		JOY_BUTTON_BACK:
			map.center_on(map.state.overworld.player.pos)
			return true
		JOY_BUTTON_X:
			map.toggle_pause()
			return true
		JOY_BUTTON_Y:
			if not map.time_locked():
				map.state.overworld.halt()
				map.notice = "Halte."
				map.refresh_ui()
			return true
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			cycle_tab(-1 if b == JOY_BUTTON_LEFT_SHOULDER else 1)
			return true
	return false


## Gâchettes : vitesse suivante ou précédente ; sous x1, la pause.
func change_speed(dir: int) -> void:
	if dir > 0:
		if map.paused:
			map.set_speed(map.speed_index)
		else:
			map.set_speed(map.speed_index + 1)
	elif map.speed_index > 0 and not map.paused:
		map.set_speed(map.speed_index - 1)
	elif not map.paused:
		map.toggle_pause()


## LB / RB : onglet précédent ou suivant (aucun onglet ouvert : le premier ou le dernier).
func cycle_tab(dir: int) -> void:
	var i := TABS.find(map.view)
	if i < 0:
		i = 0 if dir > 0 else TABS.size() - 1
	else:
		i = posmod(i + dir, TABS.size())
	map.view = ""
	map.toggle_view(TABS[i])


## Donne le focus au premier bouton actif de la fenêtre (navigation à la croix ensuite).
func focus_window() -> void:
	if not active or map.panel == null or not map.panel.visible:
		return
	var first: Button = null
	for b in buttons_in(map.panel):
		b.focus_mode = Control.FOCUS_ALL
		if first == null and not b.disabled and b != map.close_button:
			first = b
	if first != null:
		_grab.call_deferred(first)


static func _grab(b: Button) -> void:
	if is_instance_valid(b) and b.is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()


static func buttons_in(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in n.get_children():
		if c is Button:
			out.append(c as Button)
		out.append_array(buttons_in(c))
	return out


## À chaque image : le curseur suit le stick gauche, la vue le stick droit (et le bord de l'écran).
func step(delta: float) -> void:
	if not active:
		return
	var vs: Vector2 = map.get_viewport_rect().size
	if stick != Vector2.ZERO and not map.panel.visible:
		cursor = (cursor + stick * CURSOR_SPEED * delta).clamp(Vector2.ZERO, vs)
		var edge := Vector2.ZERO
		for a in 2:
			if cursor[a] <= 2.0:
				edge[a] = -1.0
			elif cursor[a] >= vs[a] - 2.0:
				edge[a] = 1.0
		if edge != Vector2.ZERO:
			pan(edge, delta)
		map.queue_redraw()
	if look != Vector2.ZERO:
		pan(look, delta)


func pan(v: Vector2, delta: float) -> void:
	map.cam.position += v * PAN_SPEED * delta / map.cam.zoom.x
	map.clamp_camera()


## Point de la carte visé par le curseur (pour l'infobulle de survol).
func world_point() -> Vector2:
	return map.screen_to_world(cursor)


## Curseur de la manette (croix dorée), dessiné dans le repère de la carte.
func draw_cursor() -> void:
	if not active or map.panel.visible:
		return
	var p := world_point()
	var s: float = 1.0 / map.cam.zoom.x
	var c := Color(1, 0.84, 0.4)
	map.draw_arc(p, 9.0 * s, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0 * s)
	map.draw_arc(p, 9.0 * s, 0.0, TAU, 24, c, 2.0 * s)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		map.draw_line(p + d * 5.0 * s, p + d * 14.0 * s, c, 2.0 * s)
