extends "res://scripts/battle.gd"
## Tutoriel : petite bataille guidée. Les étapes s'affichent en haut à droite et ne se valident
## que lorsque le joueur fait vraiment l'action demandée (on observe l'état de la bataille).
## L'ennemi attend sans bouger que la bataille soit lancée (étape « Espace »).

const TUTO_SEED := 4242

## Étapes : identifiant, titre, consigne. Les touches viennent des Options (reconfigurables).
var steps: Array[Dictionary] = []
var step := 0 ## Étape en cours (steps.size() = terminé)
var step_clock := 0.0 ## Temps passé sur l'étape en cours
var snapshot := {} ## Destinations des régiments au début de l'étape « déplacer »
var overlay: Control


func _ready() -> void:
	seed_override = TUTO_SEED
	if CampaignState.current != null:
		CampaignState.current.pending = {} # Le tutoriel n'est jamais une bataille de contrat
	super._ready()
	show_help = false
	messages.clear()
	build_steps()
	add_message("Tutoriel : suivez les consignes en haut à droite. Échap : menu principal.")
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	layer.add_child(overlay)
	begin_step()


func build_steps() -> void:
	var f := GameOptions.key_label("formation")
	steps = [
		{"id": "select", "title": "Sélectionner",
			"text": "Cliquez sur un de vos régiments (en bleu), ou glissez un cadre avec le clic gauche."},
		{"id": "move", "title": "Déplacer",
			"text": "Clic droit sur le sol : le régiment sélectionné y marche et fait face à la direction du mouvement."},
		{"id": "line", "title": "Tracer une ligne de front",
			"text": "Sélectionnez tout (Ctrl+A), puis maintenez le clic droit et glissez : la longueur du trait règle la largeur du front."},
		{"id": "formation", "title": "Changer de formation",
			"text": "Appuyez sur %s : ligne → colonne (plus rapide) → carré (lent, sans flanc ni dos)." % f},
		{"id": "run", "title": "Courir",
			"text": "Double clic droit sur le sol : le régiment court (x1,6) mais se fatigue vite (barre jaune)."},
		{"id": "start", "title": "Lancer la bataille",
			"text": "Placez vos troupes face à l'ennemi, en haut, puis appuyez sur Espace."},
		{"id": "cavalry", "title": "La cavalerie sur les archers",
			"text": "Sélectionnez la cavalerie (touche 4), puis clic droit sur les archers ennemis : la cavalerie bat les archers."},
		{"id": "win", "title": "Gagner",
			"text": "Piquiers contre la cavalerie, hommes d'armes contre les piquiers, frappez de flanc. Mettez l'ennemi en déroute !"},
	]


# ---------------------------------------------------------------- Armées et terrain réduits

## Champ dégagé au centre (pas d'embuscade surprise), quelques bois sur les côtés.
func generate_world() -> void:
	for c in [Vector2(420, 1000), Vector2(2780, 900), Vector2(2650, 1550)]:
		var r := 150.0
		forests.append([c, r])
		for j in int(r * r / 150.0):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r
			trees.append(c + Vector2(cos(a), sin(a)) * d)
	trees.sort_custom(func(a, b): return a.y < b.y)
	road_noise.seed = rng.randi()
	road_noise.frequency = 0.0075
	if not build_tiled_ground():
		build_procedural_ground()


func spawn_armies() -> void:
	var cx := WORLD_SIZE.x * 0.5
	# Joueur : un régiment de chaque type (touches 1 à 4)
	add_regiment(PLAYER, "spear", Vector2(cx - 170, 1620), Vector2.UP)
	add_regiment(PLAYER, "men_at_arms", Vector2(cx + 170, 1620), Vector2.UP)
	add_regiment(PLAYER, "archer", Vector2(cx, 1740), Vector2.UP)
	add_regiment(PLAYER, "cavalry", Vector2(cx + 520, 1680), Vector2.UP)
	# Ennemi : petite troupe, archers bien visibles derrière l'infanterie
	add_regiment(ENEMY, "spear", Vector2(cx - 140, 1060), Vector2.DOWN, 10)
	add_regiment(ENEMY, "men_at_arms", Vector2(cx + 150, 1060), Vector2.DOWN, 8)
	add_regiment(ENEMY, "archer", Vector2(cx + 420, 960), Vector2.DOWN, 12)


# ---------------------------------------------------------------- Étapes

func current_id() -> String:
	return str(steps[step]["id"]) if step < steps.size() else "done"


func finished() -> bool:
	return step >= steps.size()


func begin_step() -> void:
	step_clock = 0.0
	snapshot.clear()
	for r in player_regiments():
		snapshot[r.id] = r.dest


## Vrai quand l'action demandée par l'étape en cours a été faite.
func step_done() -> bool:
	match current_id():
		"select":
			return not selected_regiments().is_empty()
		"move":
			for r in player_regiments():
				if snapshot.has(r.id) and r.dest.distance_to(snapshot[r.id]) > 30.0:
					return true
		"line":
			var n := 0
			for r in player_regiments():
				if r.cols_override > 0:
					n += 1
			return n >= 2
		"formation":
			for r in player_regiments():
				if r.formation != Regiment.Formation.LINE:
					return true
		"run":
			for r in player_regiments():
				if r.running:
					return true
		"start":
			return state != State.DEPLOY
		"cavalry":
			for r in player_regiments():
				if r.type == "cavalry" and r.target != null and r.target.type == "archer":
					return true
			# Archers ennemis déjà détruits ou en fuite : l'étape n'a plus d'objet
			for r in regiments:
				if r.team == ENEMY and r.type == "archer" and not r.is_dead() and not r.routing:
					return false
			return true
		"win":
			return state == State.VICTORY
	return false


## Vérifie l'étape en cours et passe aux suivantes tant qu'elles sont faites.
func check_steps() -> void:
	while not finished() and step_done():
		add_message("Étape réussie : %s" % steps[step]["title"])
		step += 1
		begin_step()
		if finished():
			add_message("Tutoriel terminé ! Échap : menu principal.")


func _process(delta: float) -> void:
	super._process(delta)
	step_clock += delta
	check_steps()
	if overlay != null:
		overlay.queue_redraw()


## Espace ne lance la bataille qu'à l'étape prévue (l'ennemi attend jusque-là).
func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_SPACE and state == State.DEPLOY:
		var at := steps.map(func(s): return s["id"]).find("start")
		if step < at:
			add_message("Pas encore ! Terminez d'abord l'étape « %s »." % steps[step]["title"])
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


# ---------------------------------------------------------------- Affichage

func draw_overlay() -> void:
	var vs := overlay.get_viewport_rect().size
	var f := ThemeDB.fallback_font
	var gold := Color(1, 0.84, 0.4)
	var w := 380.0 # Assez étroit pour laisser lisible le grand texte central du HUD
	var title := "TUTORIEL TERMINÉ"
	var head := "Bravo !"
	var hint := "Vous savez mener une compagnie. Échap : menu principal, Entrée : recommencer."
	var col := Color(1, 0.95, 0.85)
	if not finished():
		title = "TUTORIEL · étape %d / %d" % [step + 1, steps.size()]
		head = str(steps[step]["title"])
		hint = str(steps[step]["text"])
	if state == State.DEFEAT:
		hint = "Défaite… Entrée pour recommencer le tutoriel, Échap pour le menu."
		col = Color(1, 0.55, 0.4)
	var text_h := f.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, w - 28, 14).y
	var rect := Rect2(vs.x - w - 12, 40, w, 62 + text_h + 10 + steps.size() * 17)
	overlay.draw_rect(rect, Color(0.08, 0.06, 0.04, 0.88))
	overlay.draw_rect(rect, Color(0.6, 0.47, 0.25), false, 2.0)
	var p := rect.position + Vector2(14, 22)
	overlay.draw_string(f, p, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.72, 0.65))
	# Titre de l'étape qui pulse doucement pour attirer l'œil
	var pulse := 0.75 + 0.25 * sin(step_clock * 4.0)
	overlay.draw_string(f, p + Vector2(0, 22), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold * Color(1, 1, 1, pulse))
	overlay.draw_multiline_string(f, p + Vector2(0, 44), hint, HORIZONTAL_ALIGNMENT_LEFT, w - 28, 14, -1, col)
	var y := p.y + 40 + text_h + 14
	for i in steps.size():
		var c := Color(0.55, 0.85, 0.45) if i < step else (gold if i == step else Color(0.6, 0.57, 0.5))
		var mark := "✓" if i < step else ("▶" if i == step else "·")
		overlay.draw_string(f, Vector2(rect.position.x + 16, y), "%s  %s" % [mark, steps[i]["title"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		y += 17
