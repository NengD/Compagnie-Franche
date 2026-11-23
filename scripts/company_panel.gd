class_name CompanyPanel
extends RefCounted
## Sections du panneau de la carte de campagne pour le capitaine (niveau, compétences, blessure)
## et pour l'équipement des régiments (casque, armes, armure : achat et amélioration en ville).
## map : le nœud de campaign_map.gd (add_label, add_button, add_section, state, notice, refresh_ui).

const DIM := Color(0.75, 0.72, 0.65)
const ROMAN := ["", "I", "II", "III"]


static func build(map: Node) -> void:
	var state: CampaignState = map.state
	build_captain(map, state)
	build_equipment(map, state)


static func build_captain(map: Node, state: CampaignState) -> void:
	var cap := state.captain
	map.add_section("Capitaine")
	map.add_label("%s — niveau %d (expérience %d / %d)" % [cap.name, cap.level, int(cap.xp), int(Captain.LEVEL_XP * cap.level)], 13)
	if not cap.available(state.day):
		map.add_label("Blessé : il garde le lit jusqu'au jour %d (absent des batailles)." % cap.wounded_until, 12, Color(1, 0.5, 0.4))
	var parts: Array[String] = []
	for p in Captain.PATH_ORDER:
		parts.append("%s %d" % [Captain.PATHS[p]["name"], cap.spent(p)])
	map.add_label("Aura de moral %d px · points dépensés : %s" % [int(cap.aura_radius()), " · ".join(parts)], 12, DIM)
	var label := "Compétences du capitaine (%s)" % CampaignState.plural(cap.points, "point à dépenser", "points à dépenser") if cap.points > 0 else "Compétences du capitaine"
	map.add_button(label, map.toggle_view.bind("captain"))
	build_officers(map, state)


## Officiers : un compagnon à la tête de chaque régiment qu'on veut (officers.gd).
static func build_officers(map: Node, state: CampaignState) -> void:
	if state.companions.list.is_empty() or state.company.is_empty():
		return
	map.add_section("Officiers")
	map.add_label("Un compagnon nommé à la tête d'un régiment lui donne un bonus (sergent : mêlée, chirurgien : moral, éclaireur : vitesse, quartier-maître : tir), mais il peut tomber si le régiment perd beaucoup d'hommes : tué ou blessé.", 11, Color(0.6, 0.58, 0.52))
	for kind in Companions.ORDER:
		var m := state.companions.get_kind(kind)
		if m.is_empty():
			continue
		var reg := Officers.regiment_of(state, kind)
		var where := "à la tête des %s (%d)" % [CampaignState.type_name(str(state.company[reg]["type"])).to_lower(), reg + 1] if reg >= 0 else "sans régiment"
		var hurt := "" if Companions.available(m, state.day) else " — blessé, ne combat pas"
		map.add_label("%s, %s : %s, %s%s" % [m["name"], str(Companions.KINDS[kind]["name"]).to_lower(), Officers.bonus_text(m), where, hurt], 12)
		var row := HBoxContainer.new()
		for i in state.company.size():
			if i == reg:
				continue
			var b: Button = map.add_button("→ %d" % (i + 1), CompanyPanel.name_officer.bind(map, kind, i), true, row)
			b.tooltip_text = "Nommer %s à la tête des %s (%d)%s" % [m["name"], CampaignState.type_name(str(state.company[i]["type"])).to_lower(), i + 1,
				" (remplace %s)" % state.companions.get_kind(Officers.of(state.company[i]))["name"] if Officers.of(state.company[i]) != "" else ""]
		if reg >= 0:
			map.add_button("Relever", CompanyPanel.remove_officer.bind(map, reg), true, row)
		map.box.add_child(row)


## Fenêtre de l'arbre de compétences du capitaine : trois voies côte à côte.
static func build_tree(map: Node) -> void:
	var state: CampaignState = map.state
	var cap := state.captain
	map.window_title.text = "Compétences de %s" % cap.name
	map.add_label("Niveau %d · %s · un point par niveau (%d au plus) : il faut choisir sa voie." % [cap.level, CampaignState.plural(cap.points, "point à dépenser", "points à dépenser"), Captain.MAX_LEVEL - 1], 13, Color(1, 0.84, 0.4) if cap.points > 0 else Color(0.92, 0.88, 0.78))
	map.add_label("Meneur et Tacticien jouent en bataille quand le capitaine y est ; l'Intendant joue toujours.", 11, Color(0.6, 0.58, 0.52))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	map.box.add_child(cols)
	for p in Captain.PATH_ORDER:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.custom_minimum_size.x = 170
		cols.add_child(col)
		col.add_child(tree_label("%s (%d)" % [Captain.PATHS[p]["name"], cap.spent(p)], 15, Color(1, 0.84, 0.4)))
		col.add_child(tree_label(CampaignState.cap_first(str(Captain.PATHS[p]["text"])), 11, DIM))
		for k in Captain.SKILLS:
			var info: Dictionary = Captain.SKILLS[k]
			if str(info["path"]) != p:
				continue
			col.add_child(HSeparator.new())
			var r := cap.rank(k)
			var owned := r >= int(info["max"])
			col.add_child(tree_label("%s %d/%d" % [info["name"], r, int(info["max"])], 13, Color(0.6, 1, 0.6) if r > 0 else Color(0.92, 0.88, 0.78)))
			col.add_child(tree_label(CampaignState.cap_first(str(info["text"])) + ".", 11, DIM))
			var reqs: Array[String] = []
			if int(info["level"]) > 1:
				reqs.append("niveau %d" % int(info["level"]))
			for q in info["req"]:
				reqs.append(str(Captain.SKILLS[q]["name"]))
			col.add_child(tree_label("Coût %s%s" % [CampaignState.plural(int(info["cost"]), "point", "points"), " · requiert " + ", ".join(reqs) if not reqs.is_empty() else ""], 11, Color(0.6, 0.58, 0.52)))
			var why := cap.refusal(k)
			var b: Button = map.add_button("Apprendre" if not owned else "Acquis", CompanyPanel.learn.bind(map, k), why == "", col)
			b.tooltip_text = why if why != "" else "%s : %s" % [info["name"], info["text"]]
			b.set_meta("skill", k)
	map.add_button("Retour à la compagnie", map.toggle_view.bind("company"))


static func tree_label(s: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func build_equipment(map: Node, state: CampaignState) -> void:
	if state.company.is_empty():
		return
	var in_town: bool = map.town_here() >= 0
	map.add_section("Équipement")
	if not in_town:
		map.add_label("Casques, armes et armures s'achètent et s'améliorent en ville.", 11, DIM)
	var closed := state.closed_message(state.location) if in_town else ""
	for i in state.company.size():
		var entry: Dictionary = state.company[i]
		var parts: Array[String] = []
		for slot in Equipment.SLOTS:
			var w := Equipment.worn(entry, slot)
			parts.append("%s : %s" % [Equipment.SLOT_NAMES[slot], Equipment.ITEMS[w]["short"] if w != "" else "—"])
		map.add_label("%d. %s   ·   %s" % [i + 1, CampaignState.type_name(str(entry["type"])), "   ·   ".join(parts)], 12)
		if not Traits.of(entry).is_empty():
			var names: Array[String] = []
			for id in Traits.of(entry):
				names.append(str(Traits.TRAITS[id]["name"]))
			map.add_label("    Traits : %s" % ", ".join(names), 11, DIM)
		if not in_town:
			continue
		var row := HBoxContainer.new()
		var any := false
		for slot in Equipment.SLOTS:
			var next := Equipment.next_item(entry, slot)
			if next == "":
				continue
			var item: Dictionary = Equipment.ITEMS[next]
			var price := Equipment.cost(state, i, next)
			var why := Equipment.refusal(state, i, next)
			var label := "%s %s : %d écus" % [str(Equipment.SLOT_NAMES[slot]).capitalize(), ROMAN[int(item["tier"])], price]
			var b: Button = map.add_button(label, CompanyPanel.buy.bind(map, i, next), why == "" and state.gold >= price and closed == "", row)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = "%s : %s.%s" % [item["name"], item["text"], ("
" + why) if why != "" else ""]
			any = true
		if any:
			map.box.add_child(row)
		else:
			row.free()
	if in_town:
		map.add_label("Améliorer une pièce remplace l'ancienne : on ne paie que la différence. Qualité II : aguerris ; qualité III : vétérans. Survolez un bouton pour ses effets.", 11, Color(0.6, 0.58, 0.52))


static func learn(map: Node, skill: String) -> void:
	var state: CampaignState = map.state
	map.notice = state.captain.learn(skill)
	GameAudio.feedback(map.notice == "")
	state.save()
	map.refresh_ui()


static func name_officer(map: Node, kind: String, index: int) -> void:
	var state: CampaignState = map.state
	map.notice = Officers.assign(state, kind, index)
	GameAudio.feedback(map.notice == "")
	state.save()
	map.refresh_ui()


static func remove_officer(map: Node, index: int) -> void:
	var state: CampaignState = map.state
	map.notice = Officers.remove(state, index)
	GameAudio.feedback(map.notice == "")
	state.save()
	map.refresh_ui()


static func buy(map: Node, index: int, id: String) -> void:
	var state: CampaignState = map.state
	map.notice = Equipment.buy(state, index, id)
	GameAudio.feedback(map.notice == "")
	state.save()
	map.refresh_ui()
