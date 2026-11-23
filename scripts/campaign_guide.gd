class_name CampaignGuide
extends RefCounted
## Tutoriel guidé de la première semaine de campagne : de courtes étapes affichées en haut à
## droite de la carte, qui avancent quand le joueur a vraiment fait l'action (on observe l'état
## de la campagne : régiments, équipement, vivres, batailles, marche).
## Proposé à la première nouvelle campagne (main_menu.gd), après la bataille d'entraînement
## (tutorial.gd) ; désactivable dans les Options (GameOptions.tutorial).
## L'étape en cours est sauvegardée (CampaignState.tutorial_step, -1 = pas de tutoriel).
##
## Brancher : campaign_map.gd crée le guide (attach) et appelle update() à chaque image.

const STEPS: Array[Dictionary] = [
	{"id": "recruit", "title": "Lever un régiment",
		"text": "Dans la fenêtre de la ville, section « Lever un régiment » : cliquez sur une troupe. Chaque ville lève des troupes différentes, à des prix différents."},
	{"id": "equip", "title": "S'équiper en ville",
		"text": "Section « Équipement » : achetez un casque, des armes ou une armure. Survolez un bouton : l'infobulle compare la pièce à celle portée."},
	{"id": "food", "title": "Acheter des vivres",
		"text": "Section « Vivres et repos » : achetez quelques jours de rations (chariots déjà pleins : rien à faire). Sans vivres, la compagnie a faim, puis déserte."},
	{"id": "contract", "title": "Accepter un contrat",
		"text": "Section « Contrats » : lisez les chances estimées (survolez-les), puis « Accepter et livrer bataille ». Pas de contrat ici ? Marchez vers une ville au drapeau rouge."},
	{"id": "march", "title": "Marcher",
		"text": "Fermez la ville (Repartir ou Échap), puis cliquez sur la carte : la compagnie y marche par les routes. Espace : pause ; 1, 2, 3 : vitesses."},
	{"id": "arrive", "title": "Entrer dans une autre ville",
		"text": "Cliquez sur une ville (un écusson) : la compagnie y marche et y entre. Les villes vendent, recrutent et proposent des contrats."},
]
const DONE_TOAST := "Tutoriel terminé : la compagnie est à vous ! (Options : Tutoriel guidé pour le revoir à la prochaine campagne)"

## Vrai quand la bataille d'entraînement doit déboucher sur la campagne (au lieu du menu).
static var after_training := false

var map: Node ## campaign_map.gd
var state: CampaignState
var base := {} ## État au début de l'étape (non sauvegardé, repris au chargement)
var panel: PanelContainer
var head: Label
var title: Label
var body: Label
var list: Label
var shown_step := -2


## Crée le guide si la campagne a un tutoriel en cours et que l'option est active (null sinon).
static func attach(m: Node) -> CampaignGuide:
	var st: CampaignState = m.state
	if st == null or st.tutorial_step < 0:
		return null
	if not GameOptions.tutorial:
		return null
	var g := CampaignGuide.new()
	g.map = m
	g.state = st
	g.begin_step()
	g.build_ui()
	return g


func step() -> int:
	return state.tutorial_step


func finished() -> bool:
	return state.tutorial_step < 0 or state.tutorial_step >= STEPS.size()


func current_id() -> String:
	return "done" if finished() else str(STEPS[state.tutorial_step]["id"])


static func gear_count(st: CampaignState) -> int:
	var n := 0
	for e in st.company:
		n += Equipment.of(e).size()
	return n


func begin_step() -> void:
	base = {
		"company": state.company.size(), "gear": gear_count(state), "food": state.supplies.food,
		"battles": state.victories + state.defeats, "pos": state.overworld.player.pos,
		"inside": state.overworld.inside,
	}


## Vrai quand l'action demandée par l'étape en cours a été faite.
func step_done() -> bool:
	var ow := state.overworld
	match current_id():
		"recruit":
			return state.company.size() > int(base["company"])
		"equip":
			return gear_count(state) > int(base["gear"])
		"food":
			# Chariots déjà pleins (assez de vivres) : rien à acheter, l'étape est faite
			return state.supplies.food > float(base["food"]) + 0.5 or Supplies.is_full(state)
		"contract":
			return state.in_battle() or state.victories + state.defeats > int(base["battles"])
		"march":
			return not ow.player.path.is_empty() or ow.player.pos.distance_to(base["pos"]) > 40.0
		"arrive":
			return ow.inside >= 0 and ow.player.pos.distance_to(base["pos"]) > 80.0
	return false


## Passe à l'étape suivante (faite, ou sautée par le bouton).
func advance(skipped := false) -> void:
	if finished():
		return
	var t := str(STEPS[state.tutorial_step]["title"])
	state.tutorial_step += 1
	begin_step()
	if state.tutorial_step >= STEPS.size():
		state.tutorial_step = -1
		map.notice = DONE_TOAST
	else:
		map.notice = ("Étape passée : %s." if skipped else "Étape réussie : %s.") % t
	state.save()
	map.refresh_ui()


func quit() -> void:
	state.tutorial_step = -1
	state.save()
	map.notice = "Tutoriel arrêté. Les commandes sont dans l'onglet Menu."
	map.refresh_ui()


## À chaque image : vérifie l'étape, met à jour et place le panneau.
func update() -> void:
	if not finished() and step_done():
		advance()
	if panel == null:
		return
	panel.visible = not finished() and GameOptions.tutorial
	if not panel.visible:
		return
	if shown_step != state.tutorial_step:
		shown_step = state.tutorial_step
		refresh_text()
	var vs: Vector2 = map.get_viewport_rect().size
	var top: float = map.bar.size.y if map.bar != null else 0.0
	panel.position = Vector2(roundf(vs.x - panel.size.x - 10.0), roundf(top + 8.0))


func refresh_text() -> void:
	var i := state.tutorial_step
	head.text = "TUTORIEL · première semaine · étape %d / %d" % [i + 1, STEPS.size()]
	title.text = str(STEPS[i]["title"])
	body.text = str(STEPS[i]["text"])
	var lines: Array[String] = []
	for k in STEPS.size():
		lines.append("%s  %s" % ["✓" if k < i else ("▶" if k == i else "·"), STEPS[k]["title"]])
	list.text = "\n".join(lines)
	panel.reset_size()


func build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "Tutoriel"
	panel.theme = map.make_theme()
	map.bar.get_parent().add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = 300
	panel.add_child(col)
	head = _label(col, 11, Color(0.75, 0.72, 0.65))
	title = _label(col, 16, Color(1, 0.84, 0.4))
	body = _label(col, 12, Color(1, 0.95, 0.85))
	list = _label(col, 12, Color(0.7, 0.68, 0.6))
	var row := HBoxContainer.new()
	col.add_child(row)
	for b in [["Passer l'étape", advance.bind(true)], ["Quitter le tutoriel", quit]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(b[1])
		row.add_child(btn)


func _label(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l
