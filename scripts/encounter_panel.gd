class_name EncounterPanel
extends Control
## Panneau d'une rencontre sur la carte (ouvert par Encounter.open) : accueil, forces en
## présence, choix numérotés (touches 1 à 9, focus clavier), Échap pour passer son chemin
## quand c'est permis. Les choix de commerce, de discussion et de recrutement laissent le
## panneau ouvert ; un choix qui termine la rencontre affiche son issue, puis « Continuer »
## émet closed(result). Une bataille émet closed tout de suite : l'appelant la lance.

signal closed(result: Dictionary)

var state: CampaignState
var player: Party
var other: Party
var result: Dictionary = {} ## Dernier résultat de Encounter.resolve
var ended := false ## La rencontre est finie (issue affichée, en attente de « Continuer »)
var frame: PanelContainer
var box: VBoxContainer
var buttons: Array[Button] = []
var option_ids: Array[String] = []
var notes: Array[String] = [] ## Issues des choix qui laissent le panneau ouvert


func setup(s: CampaignState, p: Party, o: Party) -> void:
	state = s
	player = p
	other = o
	build()


## Construit le panneau (avant même son entrée dans l'arbre).
func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # La carte derrière ne reçoit pas les clics
	theme = UiTheme.make(16)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	frame = PanelContainer.new()
	frame.name = "Cadre"
	add_child(frame)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(560, 0)
	frame.add_child(box)
	rebuild()


func _ready() -> void:
	get_viewport().size_changed.connect(place)
	place()


func place() -> void:
	if frame != null and is_inside_tree():
		UiTheme.fit_panel(frame, get_viewport_rect().size, 0.12)


func clear_box() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	buttons.clear()
	option_ids.clear()


static func wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	return l


## Reconstruit le panneau : en-tête, accueil, forces, issues des derniers choix, puis les choix.
func rebuild() -> void:
	clear_box()
	var title := UiTheme.label(CampaignState.cap_first(other.display_name()), 24, UiTheme.GOLD)
	title.name = "Titre"
	box.add_child(title)
	var greet := wrapped(UiTheme.label(Encounter.greeting(state, player, other)))
	greet.custom_minimum_size.x = 450
	box.add_child(greet)
	Portrait.beside(box, 0, Portrait.of_party(other), Vector2(72, 84)).name = "Portrait"
	box.add_child(wrapped(UiTheme.label(Encounter.strength_line(other), 15, UiTheme.WARN)))
	box.add_child(wrapped(UiTheme.label(Encounter.player_line(state, player), 15, UiTheme.DIM)))
	box.add_child(wrapped(UiTheme.label("Or : %d écus — butin : %d écus" % [int(state.gold), state.loot], 14, UiTheme.DIM)))
	for n in notes:
		box.add_child(wrapped(UiTheme.label(n, 15, UiTheme.GOLD)))
	box.add_child(HSeparator.new())
	if ended:
		box.add_child(wrapped(UiTheme.label(str(result.get("text", "")), 17, UiTheme.GOLD)))
		add_button("continue", "Continuer", "", true, "")
	else:
		var i := 0
		for o in Encounter.options(state, player, other):
			i += 1
			add_button(str(o["id"]), "%d. %s" % [i, o["label"]], str(o["hint"]), bool(o["enabled"]), str(o["reason"]))
	place.call_deferred()
	focus_first.call_deferred()


func add_button(id: String, label: String, hint: String, enabled: bool, reason: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var b := Button.new()
	b.name = "Choix_" + id
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	b.tooltip_text = hint if enabled else reason
	b.pressed.connect(choose.bind(id))
	row.add_child(b)
	var line := hint if enabled else reason
	if line != "":
		row.add_child(wrapped(UiTheme.label("    " + line, 13, UiTheme.DIM if enabled else UiTheme.WARN)))
	box.add_child(row)
	buttons.append(b)
	option_ids.append(id)
	# Focus vertical entre les boutons
	if buttons.size() > 1:
		var prev := buttons[buttons.size() - 2]
		prev.focus_neighbor_bottom = prev.get_path_to(b)
		b.focus_neighbor_top = b.get_path_to(prev)


func focus_first() -> void:
	for b in buttons:
		if is_instance_valid(b) and not b.disabled and b.is_inside_tree():
			b.grab_focus()
			return


## Applique un choix (ou « continue » après l'issue).
func choose(id: String) -> void:
	if id == "continue":
		closed.emit(result)
		return
	result = Encounter.resolve(state, player, other, id)
	if bool(result.get("battle", false)):
		closed.emit(result)
		return
	if bool(result.get("close", true)):
		ended = true
	elif str(result.get("text", "")) != "":
		notes.append(str(result["text"]))
		if notes.size() > 3:
			notes.remove_at(0)
	rebuild()


## Peut-on passer son chemin d'Échap ?
func can_leave() -> bool:
	for o in Encounter.options(state, player, other):
		if o["id"] == "leave" and bool(o["enabled"]):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		if ended:
			choose("continue")
		elif can_leave():
			choose("leave")
		get_viewport().set_input_as_handled()
		return
	# Chiffres de la rangée du haut (physical_keycode : sans Maj en AZERTY) ou du pavé numérique
	var idx := -1
	if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
		idx = int(k.physical_keycode) - int(KEY_1)
	elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
		idx = int(k.keycode) - int(KEY_KP_1)
	if idx >= 0 and idx < buttons.size():
		get_viewport().set_input_as_handled()
		if not buttons[idx].disabled:
			choose(option_ids[idx])
