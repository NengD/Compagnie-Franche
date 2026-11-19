class_name BattleOrders
extends RefCounted
## Ordres du joueur et saisie : sélection (clic, cadre, Ctrl+A), déplacement et attaque (clic droit),
## ligne de front (clic droit glissé), course (double clic droit), groupes de contrôle (Ctrl+chiffre),
## halte, formation, tenir la position, tir à volonté, retraite et touches de la bataille.
##
## Les touches reconfigurables passent par GameOptions.remap_key : on garde ici un simple
## « match » sur les touches par défaut. Les chiffres se lisent par position physique (AZERTY),
## les lettres par keycode logique.
## Nouvel ordre : une touche dans handle_key(), une fonction qui agit sur selected_regiments().

const PLAYER := BattleSim.PLAYER
const ENEMY := BattleSim.ENEMY
const WORLD_SIZE := BattleSim.WORLD_SIZE
const LINE_DRAG_MIN_PX := 12.0 ## En dessous, un clic droit glissé reste un simple clic
const LINE_GAP := 20.0 ## Espace entre deux régiments sur une ligne
const GROUP_DOUBLE_MS := 400 ## Deux appuis sur le même chiffre en moins de ce délai : centrer la caméra
const RETREAT_CONFIRM_MS := 3000 ## Délai pour confirmer la retraite (second appui sur R)

var battle: Battle
var sim: BattleSim

var dragging := false ## Cadre de sélection (clic gauche maintenu)
var drag_start := Vector2.ZERO
var drag_now := Vector2.ZERO
var panning := false ## Clic du milieu maintenu
var minimap_dragging := false ## Clic gauche maintenu sur la mini-carte : la vue suit la souris
var line_double := false ## Le clic droit en cours est un double clic (ordre de course)
var line_dragging := false ## Clic droit maintenu : tracé d'une ligne de formation
var line_start := Vector2.ZERO
var line_now := Vector2.ZERO
var groups := {} ## Groupes de contrôle : chiffre (0-8) -> Array[Regiment]
var last_digit := -1 ## Dernier chiffre appuyé (pour le double appui)
var last_digit_ms := -100000
var retreat_ask_ms := -100000 ## Instant du premier appui sur R (il faut confirmer)
var roster_list: Array[Regiment] = [] ## Numérotation fixe des régiments du joueur (voir roster())


func _init(b: Battle) -> void:
	battle = b
	sim = b.sim


## Abandonne les gestes en cours (ouverture du menu pause).
func cancel_gestures() -> void:
	dragging = false
	line_dragging = false
	panning = false
	minimap_dragging = false


# ---------------------------------------------------------------- Saisie

func handle_input(event: InputEvent) -> void:
	if battle.menu_open():
		# Menu pause ouvert : seul Échap compte (retour ou fermeture), le reste est ignoré
		var ek := event as InputEventKey
		if ek != null and ek.pressed and not ek.echo and ek.keycode == KEY_ESCAPE:
			battle.pause_menu.on_escape()
		battle.get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		handle_mouse_button(mb)
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if panning:
			battle.camera.pan(mm.relative)
		if minimap_dragging:
			minimap_click(mm.position)
		if dragging:
			drag_now = battle.event_world_pos(mm)
		if line_dragging:
			line_now = battle.event_world_pos(mm)
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		handle_key(k)


func handle_mouse_button(mb: InputEventMouseButton) -> void:
	var wp := battle.event_world_pos(mb)
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed and battle.hud != null and battle.hud.cards_tab_rect(battle.hud.get_viewport_rect().size).has_point(mb.position):
				toggle_cards() # Onglet des cartes : les cacher ou les montrer
				return
			if mb.pressed and minimap_click(mb.position):
				minimap_dragging = true # Glisser sur la mini-carte : la vue suit
				return
			if not mb.pressed and minimap_dragging:
				minimap_dragging = false
				return
			if mb.pressed:
				dragging = true
				drag_start = wp
				drag_now = wp
			elif dragging:
				dragging = false
				finish_selection(drag_start, wp, mb.shift_pressed)
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				line_dragging = true
				line_double = mb.double_click
				line_start = wp
				line_now = wp
			elif line_dragging:
				line_dragging = false
				if is_line_drag(line_start, wp):
					issue_line_order(line_start, wp, line_double)
				else:
					# Simple clic : déplacement ou attaque ; double clic : la même chose en courant
					issue_order(line_start, line_double)
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				battle.camera.zoom_at(1.15)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				battle.camera.zoom_at(1.0 / 1.15)
		MOUSE_BUTTON_MIDDLE:
			panning = mb.pressed


## Clic sur la mini-carte (position dans la vue) : centre la caméra sur ce point du champ.
## Renvoie faux si le point n'est pas sur la mini-carte (ou si elle est cachée).
func minimap_click(screen_pos: Vector2) -> bool:
	if battle.hud == null or battle.camera == null:
		return false
	var r := Minimap.rect(battle.hud, battle.hud.get_viewport_rect().size)
	if not r.has_area() or not (minimap_dragging or r.grow(2.0).has_point(screen_pos)):
		return false
	battle.camera.position = Minimap.to_world(screen_pos, r)
	battle.camera.clamp_to_world()
	return true


## Affiche ou cache la mini-carte (mémorisé pour les batailles suivantes).
func toggle_minimap() -> void:
	battle.show_minimap = not battle.show_minimap
	GameOptions.show_minimap = battle.show_minimap
	minimap_dragging = false
	GameOptions.save_options()


## Affiche ou cache les cartes des régiments (mémorisé pour les batailles suivantes).
func toggle_cards() -> void:
	battle.show_cards = not battle.show_cards
	GameOptions.show_cards = battle.show_cards
	GameOptions.save_options()


func handle_key(k: InputEventKey) -> void:
	if k.keycode == KEY_A and k.ctrl_pressed:
		for r in sim.player_regiments():
			r.selected = true
		return
	# Touches reconfigurables (Options) : ramenées à leur touche par défaut
	match GameOptions.remap_key(GameOptions.event_keycode(k)):
		KEY_SPACE:
			if sim.state == BattleSim.State.DEPLOY:
				battle.start_battle()
			else:
				battle.paused = not battle.paused
		KEY_T:
			if battle.campaign != null:
				# En campagne, la météo du jour s'impose (world_sim.gd) : T est réservée à l'escarmouche
				battle.add_message("La météo est celle du jour : on ne commande pas à la pluie.")
				return
			sim.raining = not sim.raining
			battle.add_message("Il pleut : les archers tirent moins loin et moins juste." if sim.raining else "La pluie cesse.")
		KEY_H:
			halt()
		KEY_TAB:
			toggle_cards()
		KEY_N:
			toggle_minimap()
		KEY_F1:
			battle.show_help = not battle.show_help
			GameOptions.show_help = battle.show_help # Mémorisé pour les batailles suivantes
			GameOptions.save_options()
		KEY_F:
			cycle_formation()
		KEY_G:
			toggle_hold_position()
		KEY_X:
			toggle_fire_at_will()
		KEY_R:
			request_retreat()
		KEY_C:
			Captain.order_join(battle)
		KEY_M:
			battle.audio.set_enabled(not battle.audio.enabled)
			battle.add_message("Son activé." if battle.audio.enabled else "Son coupé.")
		KEY_V:
			battle.game_speed = GameOptions.next_speed()
			GameOptions.save_options()
			battle.add_message("Vitesse du jeu : %s" % GameOptions.speed_label(battle.game_speed))
		KEY_ENTER, KEY_KP_ENTER:
			if battle.report_panel != null and not battle.report_panel.visible:
				battle.show_report() # Premier appui pendant le ralenti : afficher le bilan tout de suite
			else:
				battle.continue_after_battle()
		KEY_ESCAPE:
			if sim.state == BattleSim.State.DEPLOY or sim.state == BattleSim.State.BATTLE:
				battle.open_pause_menu()
			elif battle.campaign == null:
				# Écran de fin d'escarmouche : retour au menu principal (en contrat : Entrée)
				battle.back_to_menu()
	# Touches 1 à 9 (position physique, fonctionne en AZERTY)
	var idx: int = int(k.physical_keycode) - int(KEY_1)
	if idx >= 0 and idx < 9:
		if k.ctrl_pressed:
			store_group(idx)
		else:
			recall_digit(idx, k.shift_pressed)


## Vrai si le clic droit a assez glissé (en pixels écran) pour tracer une ligne.
func is_line_drag(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) * battle.camera.zoom.x >= LINE_DRAG_MIN_PX


# ---------------------------------------------------------------- Sélection et groupes

func finish_selection(a: Vector2, b: Vector2, add: bool) -> void:
	if not add:
		for r in sim.regiments:
			r.selected = false
		if sim.captain != null:
			sim.captain.selected = false
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	if rect.size.length() < 8.0:
		if sim.captain != null and sim.captain.pick(b):
			return # Clic sur le capitaine : lui et son escorte
		var r := sim.regiment_at(b, PLAYER)
		if r != null:
			r.selected = true
		return
	for r in sim.player_regiments():
		for s in r.soldiers:
			if s.alive and rect.has_point(s.pos):
				r.selected = true
				break


## Ctrl + chiffre : mémorise la sélection dans le groupe (une sélection vide efface le groupe).
func store_group(idx: int) -> void:
	var sel := sim.selected_regiments()
	if sel.is_empty():
		if groups.erase(idx):
			battle.add_message("Groupe %d effacé." % (idx + 1))
		return
	groups[idx] = sel
	battle.add_message("Groupe %d : %d régiment%s." % [idx + 1, sel.size(), "s" if sel.size() > 1 else ""])


## Membres encore valides (vivants, pas en fuite) d'un groupe de contrôle.
func group_members(idx: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	if groups.has(idx):
		for r in groups[idx]:
			if r.team == PLAYER and not r.is_dead() and not r.routing:
				out.append(r)
	return out


## Régiments du joueur dans un ordre fixe pour toute la bataille : numéros des cartes du HUD et
## des touches 1 à 8. Ordre de la compagnie (company_index, comme sur la carte de campagne), puis
## ordre de création. Un régiment mort ou en fuite garde sa place ; un régiment ajouté en cours
## de bataille (tutoriel) prend la suivante.
func roster() -> Array[Regiment]:
	var fresh: Array[Regiment] = []
	for r in sim.regiments:
		if r.team == PLAYER and not roster_list.has(r):
			fresh.append(r)
	if not fresh.is_empty():
		fresh.sort_custom(func(x: Regiment, y: Regiment) -> bool:
			var kx := x.company_index if x.company_index >= 0 else 1000 + x.id
			var ky := y.company_index if y.company_index >= 0 else 1000 + y.id
			return kx < ky)
		roster_list.append_array(fresh)
	# Régiments retirés de la simulation (tests qui la vident) : on les oublie
	roster_list = roster_list.filter(func(r: Regiment) -> bool: return sim.regiments.has(r))
	return roster_list


## Numéro affiché d'un régiment du joueur (1, 2…), 0 s'il n'en a pas.
func roster_number(r: Regiment) -> int:
	return roster().find(r) + 1


## Chiffre seul : rappelle le groupe s'il existe, sinon sélectionne le régiment n° idx + 1
## (numéro fixe, voir roster() ; rien si ce régiment est mort ou en fuite).
## Un double appui centre la caméra sur la sélection rappelée.
func recall_digit(idx: int, add: bool) -> void:
	var list := group_members(idx)
	if list.is_empty():
		var all := roster()
		if idx < all.size() and not all[idx].is_dead() and not all[idx].routing:
			list.append(all[idx])
	if list.is_empty():
		return
	if not add:
		for r in sim.regiments:
			r.selected = false
	for r in list:
		r.selected = true
	var now := Time.get_ticks_msec()
	if idx == last_digit and now - last_digit_ms <= GROUP_DOUBLE_MS:
		battle.camera.center_on(list)
		last_digit = -1
	else:
		last_digit = idx
		last_digit_ms = now


## Groupes de contrôle d'un régiment, pour sa carte (« G1 », « G2,4 »…, vide si aucun).
func group_label(r: Regiment) -> String:
	var ids: Array[String] = []
	for g in range(9):
		if groups.has(g) and (groups[g] as Array).has(r):
			ids.append(str(g + 1))
	return "" if ids.is_empty() else "G" + ",".join(ids)


# ---------------------------------------------------------------- Ordres permanents

## Touche H : halte, les régiments sélectionnés s'arrêtent là où ils sont.
func halt() -> void:
	for r in sim.selected_regiments():
		r.target = null
		r.holding = false
		r.running = false
		r.dest = r.center


## Touche G : tenir la position (bascule). Si tous tiennent déjà, l'ordre est levé.
func toggle_hold_position() -> void:
	var sel := sim.selected_regiments()
	if sel.is_empty():
		return
	var on := false
	for r in sel:
		if not r.hold_position:
			on = true
	for r in sel:
		r.hold_position = on
		if on:
			# On reste là où l'on est : l'éventuelle cible n'est plus poursuivie
			if r.target != null and not r.stats["ranged"]:
				r.target = null
				r.dest = r.center
			r.running = false
	battle.add_message("Tenir la position." if on else "Fin de l'ordre de tenir la position.")


## Touche X : tir à volonté / cesser le tir (tireurs sélectionnés).
func toggle_fire_at_will() -> void:
	var archers: Array[Regiment] = []
	for r in sim.selected_regiments():
		if r.stats["ranged"]:
			archers.append(r)
	if archers.is_empty():
		return
	var on := false
	for r in archers:
		if not r.fire_at_will:
			on = true
	for r in archers:
		r.fire_at_will = on
	battle.add_message("Tir à volonté !" if on else "Cessez le tir ! (tir seulement sur ordre)")


## Touche F : ligne → colonne → carré pour les régiments sélectionnés.
func cycle_formation() -> void:
	var sel := sim.selected_regiments()
	if sel.is_empty():
		return
	var f := sel[0].next_formation()
	for r in sel:
		r.formation = f
	var hint := ""
	match f:
		Regiment.Formation.COLUMN:
			hint = " (plus rapide)"
		Regiment.Formation.SQUARE:
			hint = " (lent, ni flanc ni dos)"
	battle.add_message("Formation : %s%s" % [Regiment.FORMATION_NAMES[f], hint])


## Touche R : un premier appui demande confirmation, un second (dans les 3 s) sonne la retraite.
func request_retreat() -> void:
	if sim.state != BattleSim.State.BATTLE:
		return
	if Time.get_ticks_msec() - retreat_ask_ms > RETREAT_CONFIRM_MS:
		retreat_ask_ms = Time.get_ticks_msec()
		battle.add_message("Appuyez encore sur R pour sonner la retraite (défaite, mais pertes limitées).")
		return
	battle.order_retreat()


# ---------------------------------------------------------------- Déplacements et attaques

## Ordre de course : seuls les régiments assez reposés obéissent.
func set_running(sel: Array[Regiment], run: bool) -> void:
	var refused := false
	for r in sel:
		r.running = run and r.stamina >= UnitTypes.RUN_MIN_STAMINA
		if run and not r.running:
			refused = true
	if refused:
		battle.add_message("Trop fatigués pour courir !")


## Clic droit en wp : attaque l'ennemi visé, sinon s'y rend en ligne, face au mouvement.
func issue_order(wp: Vector2, run := false) -> void:
	var sel := sim.selected_regiments()
	if sel.is_empty():
		return
	var enemy: Regiment = null
	if sim.state == BattleSim.State.BATTLE:
		enemy = sim.regiment_at(wp, ENEMY)
	elif sim.state == BattleSim.State.DEPLOY and sim.regiment_at(wp, ENEMY) != null:
		battle.add_message("Pas d'attaque pendant le déploiement : appuyez d'abord sur Espace pour lancer la bataille.")
		battle.add_marker(wp, Color(1, 0.3, 0.2))
		return
	set_running(sel, run)
	if enemy != null:
		for r in sel:
			r.target = enemy
			r.holding = false
			r.think = 0.0
		battle.add_marker(enemy.center, Color(1, 0.3, 0.2))
		return

	# Déplacement : les régiments se placent côte à côte, face à la direction du mouvement
	var gc := Vector2.ZERO
	for r in sel:
		gc += r.center
	gc /= sel.size()
	var dir := wp - gc
	var facing: Vector2 = sel[0].facing
	if dir.length() > 40.0:
		facing = dir.normalized()
	var right := Vector2(-facing.y, facing.x)
	sel.sort_custom(func(x, y): return x.center.dot(right) < y.center.dot(right))
	var widths := []
	var total := 0.0
	for r in sel:
		var w := r.width() + LINE_GAP
		widths.append(w)
		total += w
	var x := -total * 0.5
	for i in sel.size():
		var r: Regiment = sel[i]
		var w: float = widths[i]
		r.dest = order_dest(r, (wp + right * (x + w * 0.5)).clamp(Vector2(20, 20), WORLD_SIZE - Vector2(20, 20)), facing)
		r.facing = facing
		r.target = null
		r.holding = false
		x += w
	battle.add_marker(wp, Color(1, 1, 1))


## Calcule la disposition des régiments le long d'une ligne tracée de a vers b (comme dans
## Total War). Renvoie pour chacun : {"reg", "dest", "facing", "cols"}. Ne modifie rien.
func line_layout(sel: Array[Regiment], a: Vector2, b: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sel.is_empty() or a.distance_to(b) < 0.5:
		return out
	var dir := (b - a).normalized()
	var length := a.distance_to(b)

	# Orientation : perpendiculaire à la ligne, du côté opposé à la position actuelle des troupes.
	var gc := Vector2.ZERO
	for r in sel:
		gc += r.center
	gc /= sel.size()
	var facing := Vector2(dir.y, -dir.x) # Par défaut : tracé gauche → droite = face vers le haut
	var side := ((a + b) * 0.5 - gc).dot(facing)
	if side < -16.0:
		facing = -facing

	# Les régiments gardent leur ordre le long de la ligne (donc leur ordre gauche-droite).
	var order: Array[Regiment] = sel.duplicate()
	order.sort_custom(func(x, y): return x.center.dot(dir) < y.center.dot(dir))

	# La longueur est partagée en proportion de la taille de chaque régiment,
	# pour que tous aient à peu près la même profondeur.
	var natural := 0.0
	for r in order:
		natural += r.alive_n * float(r.stats["spacing"])
	var usable := maxf(length - LINE_GAP * (order.size() - 1), 1.0)
	var x := 0.0
	for r in order:
		var sp: float = r.stats["spacing"]
		var share := usable * r.alive_n * sp / natural
		var cols := clampi(roundi(share / sp), r.min_columns(), r.max_columns())
		var w := cols * sp
		var dest := (a + dir * (x + w * 0.5)).clamp(Vector2(20, 20), WORLD_SIZE - Vector2(20, 20))
		out.append({"reg": r, "dest": dest, "facing": facing, "cols": cols})
		x += w + LINE_GAP
	return out


## Ordre de formation : place les régiments sélectionnés sur la ligne tracée.
func issue_line_order(a: Vector2, b: Vector2, run := false) -> void:
	var sel := sim.selected_regiments()
	var layout := line_layout(sel, a, b)
	if layout.is_empty():
		return
	set_running(sel, run)
	for e in layout:
		var r: Regiment = e["reg"]
		r.cols_override = e["cols"]
		r.formation = Regiment.Formation.LINE
		r.dest = order_dest(r, e["dest"], e["facing"], e["cols"])
		r.facing = e["facing"]
		r.target = null
		r.holding = false
	battle.add_marker((a + b) * 0.5, Color(1, 1, 1))


## Demi-étendue (en x et en y) de la formation de r posée face à facing.
## cols > 0 : largeur de front imposée (ligne tracée) ; sinon celle de la formation actuelle.
func formation_extent(r: Regiment, facing: Vector2, cols := 0) -> Vector2:
	var n := maxi(r.alive_n, 1)
	var sp: float = r.stats["spacing"]
	var c := r.columns(n)
	var rows := r.depth_rows(n)
	if cols > 0:
		c = clampi(cols, 1, n)
		rows = ceili(float(n) / float(c))
	var hw := (c - 1) * 0.5 * sp + float(r.stats["radius"])
	var hd := (rows - 1) * 0.5 * sp + float(r.stats["radius"])
	var right := Vector2(-facing.y, facing.x)
	return Vector2(absf(right.x) * hw + absf(facing.x) * hd, absf(right.y) * hw + absf(facing.y) * hd)


## Destination d'un ordre du joueur : pendant le déploiement, toute la formation doit tenir
## dans la zone bleue (sous deploy_top()), en tenant compte de sa largeur et de sa profondeur.
func order_dest(r: Regiment, dest: Vector2, facing: Vector2, cols := 0) -> Vector2:
	if sim.state != BattleSim.State.DEPLOY or r.team != PLAYER:
		return dest
	var ext := formation_extent(r, facing, cols)
	var lo := Vector2(ext.x + 4.0, sim.deploy_top() + ext.y + 2.0)
	var hi := WORLD_SIZE - ext - Vector2(4, 4)
	return Vector2(clampf(dest.x, lo.x, maxf(lo.x, hi.x)), clampf(dest.y, lo.y, maxf(lo.y, hi.y)))
