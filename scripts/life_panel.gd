class_name LifePanel
extends RefCounted
## Sections de la carte de campagne pour les vivres, la fatigue, les blessés, les prisonniers et
## les compagnons (supplies.gd, prisoners.gd, companions.gd), et boutons « Marche forcée » et
## « Camper » de la barre du haut.
## map : le nœud de campaign_map.gd (add_label, add_button, add_section, state, notice,
## refresh_ui, town_here, show_toast).

const DIM := Color(0.75, 0.72, 0.65)
const HINT := Color(0.6, 0.58, 0.52)
const GOLD := Color(1, 0.84, 0.4)
const RED := Color(1, 0.5, 0.4)
const BUY_DAYS := [5, 10]


# ---------------------------------------------------------------- Barre du haut

## Boutons de la barre (après les vitesses) : marche forcée et camp.
static func build_bar(map: Node, row: HBoxContainer) -> void:
	var buttons := {}
	for v in [["forced", "Marche forcée", "Vitesse x2 sur la carte, mais la compagnie se fatigue (touche F)"],
			["camp", "Camper", "La compagnie s'arrête, se repose et soigne ses blessés (touche K)"]]:
		var b := Button.new()
		b.text = v[1]
		b.tooltip_text = v[2]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(LifePanel.press.bind(map, str(v[0])))
		row.add_child(b)
		buttons[v[0]] = b
	map.set_meta("life_buttons", buttons)


static func press(map: Node, what: String) -> void:
	var state: CampaignState = map.state
	if what == "forced":
		map.notice = Supplies.toggle_forced(state)
	elif map.time_locked():
		map.notice = "Une décision vous attend."
	else:
		map.notice = Supplies.toggle_camp(state, state.overworld)
	GameAudio.ui("click")
	map.refresh_ui()


## Raccourcis clavier de la carte (F : marche forcée, K : camper). Renvoie vrai si la touche est prise.
static func key(map: Node, event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	match event.physical_keycode:
		KEY_F:
			press(map, "forced")
			return true
		KEY_K:
			press(map, "camp")
			return true
	return false


## Suite de la barre du haut : vivres et fatigue ; met aussi à jour les boutons.
static func top_text(map: Node) -> String:
	var state: CampaignState = map.state
	var s := state.supplies
	if map.has_meta("life_buttons"):
		var buttons: Dictionary = map.get_meta("life_buttons")
		(buttons["forced"] as Button).set_pressed_no_signal(s.forced)
		(buttons["camp"] as Button).set_pressed_no_signal(s.camping)
	var t := "   ·   vivres %d j" % floori(Supplies.days_left(state))
	if Supplies.hungry(state):
		t = "   ·   FAMINE"
	t += "   ·   fatigue %d %%" % roundi(s.fatigue)
	if s.camping:
		t += " (camp)"
	return t


# ---------------------------------------------------------------- Fenêtres

## Sections de la ville et de l'onglet Compagnie.
static func build(map: Node) -> void:
	var state: CampaignState = map.state
	build_supplies(map, state)
	build_prisoners(map, state)
	build_companions(map, state)


static func build_supplies(map: Node, state: CampaignState) -> void:
	var s := state.supplies
	var in_town: bool = map.town_here() >= 0
	map.add_section("Vivres et repos")
	var per_day := Supplies.consumption(state)
	map.add_label("Vivres : %s (%d rations, %d par jour)   ·   fatigue %d / 100 (%s)" % [CampaignState.plural(floori(Supplies.days_left(state)), "jour", "jours"), floori(s.food), ceili(per_day), roundi(s.fatigue), Supplies.fatigue_label(state)], 12)
	if Supplies.hungry(state):
		map.add_label("La compagnie a faim depuis %s : moral bas en bataille, et des désertions dès le jour %d sans vivres." % [CampaignState.plural(s.hungry_days, "jour", "jours"), Supplies.HUNGER_DESERT_DAYS], 12, RED)
	var w := s.wounded_total()
	if w > 0:
		var parts: Array[String] = []
		for t in UnitTypes.ORDER:
			if s.wounded.has(t):
				parts.append(CampaignState.type_count(t, int(s.wounded[t])))
		map.add_label("Blessés graves dans les chariots : %s. Ils guérissent au repos (ville, camp) et rejoignent un régiment de leur type qui a de la place." % ", ".join(parts), 12, DIM)
	if in_town:
		var row := HBoxContainer.new()
		for d in BUY_DAYS:
			var cost := Supplies.buy_cost(state, d)
			var b: Button = map.add_button("+%d jours : %d écus" % [d, cost], LifePanel.buy.bind(map, float(d)), Supplies.rations_for(state, d) >= 1.0 and state.gold >= cost, row)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var full := Supplies.buy_cost(state, Supplies.FOOD_MAX_DAYS)
		var bf: Button = map.add_button("Remplir les chariots : %d écus" % full, LifePanel.buy.bind(map, 0.0), not Supplies.is_full(state) and state.gold >= full, row)
		bf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map.box.add_child(row)
		map.add_label("Une ration nourrit un homme un jour (%.2f écus ici). Les chariots portent %d jours. Dans les murs, la compagnie se repose." % [Supplies.ration_price(state), int(Supplies.FOOD_MAX_DAYS)], 11, HINT)
	else:
		map.add_label("Vivres en ville, ou auprès des villageois et des caravanes. Marche forcée (F) : deux fois plus vite, mais épuisante ; une compagnie fatiguée commence la bataille avec moins d'endurance. Camper (K) : repos et soins.", 11, HINT)


static func build_prisoners(map: Node, state: CampaignState) -> void:
	var p := state.prisoners
	if p.list.is_empty():
		return
	var town := Prisoners.ransom_town(state) if map.town_here() >= 0 else -1
	var closed := state.closed_message(town) if town >= 0 else ""
	map.add_section("Prisonniers (%d)" % p.total())
	map.add_label("Ils mangent une demi-ration chacun, et certains s'évadent chaque nuit (davantage s'ils sont nombreux ou si l'on a faim).", 11, HINT)
	for i in p.list.size():
		var g: Dictionary = p.list[i]
		map.add_label(CampaignState.cap_first(Prisoners.group_name(g)), 12)
		var row := HBoxContainer.new()
		if town >= 0:
			var pay := Prisoners.ransom_value(state, g, town)
			var b: Button = map.add_button("Rançon : %d écus" % pay, LifePanel.act.bind(map, "ransom", i), closed == "", row)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := mini(Prisoners.willing(state, g), Prisoners.room_for(state, str(g["type"])))
		var be: Button = map.add_button("Enrôler %d" % n, LifePanel.act.bind(map, "enlist", i), n > 0, row)
		be.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		be.tooltip_text = "Les volontaires complètent les régiments de leur type ou en forment un nouveau, le moral bas au début."
		var f := int(g["faction"])
		var br: Button = map.add_button("Relâcher" + (" (%s %+d)" % [CampaignState.FACTIONS[f]["short"], Prisoners.release_reputation(g)] if f >= 0 else ""), LifePanel.act.bind(map, "release", i), true, row)
		br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map.box.add_child(row)
	if town >= 0 and p.list.size() > 1:
		map.add_button("Tout rançonner", LifePanel.act.bind(map, "ransom_all", -1), closed == "")
	elif town < 0:
		map.add_label("Les rançons se négocient en ville.", 11, HINT)


static func build_companions(map: Node, state: CampaignState) -> void:
	var here: int = map.town_here()
	var offers: Array[String] = []
	if here >= 0:
		offers = Companions.offers(state, here)
	if state.companions.list.is_empty() and offers.is_empty():
		if here < 0:
			map.add_section("Compagnons")
			map.add_label("Aucun compagnon. Sergents, chirurgiens, éclaireurs et quartiers-maîtres s'engagent dans certaines villes.", 11, HINT)
		return
	map.add_section("Compagnons")
	for kind in Companions.ORDER:
		var m := state.companions.get_kind(kind)
		if m.is_empty():
			continue
		var info: Dictionary = Companions.KINDS[kind]
		map.add_label("%s, %s — niveau %d (expérience %d / %d)   ·   solde %.1f / jour" % [m["name"], str(info["name"]).to_lower(), int(m["level"]), int(m["xp"]), int(Companions.LEVEL_XP * int(m["level"])), Companions.wage_of(state, m)], 13)
		if not Companions.available(m, state.day):
			map.add_label("Blessé : sans effet jusqu'au jour %d." % int(m["wounded_until"]), 12, RED)
		var parts: Array[String] = []
		for sk in info["skills"]:
			parts.append("%s %d/%d" % [info["skills"][sk]["name"], int(m["skills"][sk]), Companions.SKILL_MAX])
		map.add_label("%s · %s" % [CampaignState.cap_first(str(info["role"])), " · ".join(parts)], 12, DIM)
		if int(m["points"]) > 0:
			map.add_label("%s à dépenser :" % CampaignState.plural(int(m["points"]), "point de compétence", "points de compétence"), 12, GOLD)
			for sk in info["skills"]:
				map.add_button("%s : %s" % [info["skills"][sk]["name"], info["skills"][sk]["text"]], LifePanel.learn.bind(map, kind, str(sk)), int(m["skills"][sk]) < Companions.SKILL_MAX)
	if here >= 0:
		var closed := state.closed_message(here)
		for kind in offers:
			var info: Dictionary = Companions.KINDS[kind]
			var cost := Companions.hire_cost(state, kind)
			var b: Button = map.add_button("Engager %s, %s (%s) : %d écus, solde %.1f / jour" % [Companions.offer_name(state, kind), str(info["name"]).to_lower(), info["role"], cost, float(info["wage"]) * Difficulty.value(state.difficulty, "wage")], LifePanel.hire.bind(map, kind), state.gold >= cost and closed == "")
			var names: Array[String] = []
			for sk in info["skills"]:
				names.append("%s (%s)" % [info["skills"][sk]["name"], info["skills"][sk]["text"]])
			b.tooltip_text = "Compétences : %s." % ", ".join(names)


## Ligne du bilan de fin de bataille (battle_report.gd) : prisonniers faits, blessés graves.
static func report_line(c: Dictionary) -> String:
	var parts: Array[String] = []
	if int(c.get("prisoners", 0)) > 0:
		parts.append("%s : à rançonner en ville, enrôler ou relâcher (onglet Compagnie)" % CampaignState.plural(int(c["prisoners"]), "prisonnier", "prisonniers"))
	if int(c.get("wounded", 0)) > 0:
		parts.append("%s dans les chariots" % CampaignState.plural(int(c["wounded"]), "blessé grave", "blessés graves"))
	return CampaignState.cap_first("   ·   ".join(parts))


## Rencontre : le rapport de l'éclaireur sur le groupe rencontré.
static func build_contact(map: Node, other: Party) -> void:
	var s := Companions.scout_report(map.state, other.troops)
	if s != "":
		map.add_label(s, 12, Color(0.7, 0.85, 1.0))


# ---------------------------------------------------------------- Actions

static func done(map: Node, err: String) -> void:
	map.notice = err
	GameAudio.feedback(err == "")
	map.state.save()
	map.refresh_ui()


static func buy(map: Node, days: float) -> void:
	done(map, Supplies.buy(map.state, days))


static func act(map: Node, what: String, i: int) -> void:
	var state: CampaignState = map.state
	match what:
		"ransom":
			done(map, Prisoners.ransom(state, i))
		"ransom_all":
			done(map, Prisoners.ransom_all(state))
		"enlist":
			done(map, Prisoners.enlist(state, i))
		"release":
			done(map, Prisoners.release(state, i))


static func hire(map: Node, kind: String) -> void:
	done(map, Companions.hire(map.state, kind))


static func learn(map: Node, kind: String, sk: String) -> void:
	done(map, Companions.learn(map.state, kind, sk))
