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
	for k in Captain.SKILLS:
		parts.append("%s %d/%d" % [Captain.SKILLS[k]["name"], int(cap.skills[k]), Captain.SKILL_MAX])
	var al: Label = map.add_label("Aura de moral %d px · %s" % [int(cap.aura_radius()), " · ".join(parts)], 12, DIM)
	var tips: Array[String] = []
	for k in Captain.SKILLS:
		tips.append(Tooltips.skill_text(cap, k))
	al.tooltip_text = "

".join(tips)
	al.mouse_filter = Control.MOUSE_FILTER_PASS
	if cap.points > 0:
		map.add_label("%s à dépenser :" % CampaignState.plural(cap.points, "point de compétence", "points de compétence"), 12, Color(1, 0.84, 0.4))
		for k in Captain.SKILLS:
			var ok := int(cap.skills[k]) < Captain.SKILL_MAX
			var sb: Button = map.add_button("%s : %s" % [Captain.SKILLS[k]["name"], Captain.SKILLS[k]["text"]], CompanyPanel.learn.bind(map, k), ok)
			sb.tooltip_text = Tooltips.skill_text(cap, k)


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
			var tl: Label = map.add_label("    Traits : %s" % ", ".join(names), 11, DIM)
			tl.tooltip_text = Tooltips.traits_text(entry)
			tl.mouse_filter = Control.MOUSE_FILTER_PASS
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
			b.tooltip_text = Tooltips.gear_text(entry, next) + (("
" + why) if why != "" else "")
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


static func buy(map: Node, index: int, id: String) -> void:
	var state: CampaignState = map.state
	map.notice = Equipment.buy(state, index, id)
	GameAudio.feedback(map.notice == "")
	state.save()
	map.refresh_ui()
