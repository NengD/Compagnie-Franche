class_name CompanyPanel
extends RefCounted
## Sections du panneau de la carte de campagne pour le capitaine (niveau, compétences, blessure)
## et pour les traits et l'équipement des régiments (achat en ville, prix affichés).
## map : le nœud de campaign_map.gd (add_label, add_button, add_section, state, notice, refresh_ui).

const DIM := Color(0.75, 0.72, 0.65)


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
	map.add_label("Aura de moral %d px · %s" % [int(cap.aura_radius()), " · ".join(parts)], 12, DIM)
	if cap.points > 0:
		map.add_label("%s à dépenser :" % CampaignState.plural(cap.points, "point de compétence", "points de compétence"), 12, Color(1, 0.84, 0.4))
		for k in Captain.SKILLS:
			var ok := int(cap.skills[k]) < Captain.SKILL_MAX
			map.add_button("%s : %s" % [Captain.SKILLS[k]["name"], Captain.SKILLS[k]["text"]], CompanyPanel.learn.bind(map, k), ok)


static func build_equipment(map: Node, state: CampaignState) -> void:
	if state.company.is_empty():
		return
	map.add_section("Traits et équipement")
	var closed := state.closed_message(state.location)
	for i in state.company.size():
		var entry: Dictionary = state.company[i]
		var desc := Traits.describe(entry)
		map.add_label("%d. %s : %s" % [i + 1, CampaignState.type_name(str(entry["type"])), desc if desc != "" else "aucun"], 12)
		var row := HBoxContainer.new()
		var any := false
		for id in Equipment.ORDER:
			if id in Equipment.of(entry):
				continue
			var price := Equipment.cost(state, i, id)
			var b: Button = map.add_button("%s : %d écus" % [str(Equipment.ITEMS[id]["short"]).capitalize(), price], CompanyPanel.buy.bind(map, i, id), state.gold >= price and closed == "", row)
			b.tooltip_text = "%s (%s)" % [Equipment.ITEMS[id]["name"], Equipment.ITEMS[id]["text"]]
			any = true
		if any:
			map.box.add_child(row)
		else:
			row.free()
	var help: Array[String] = []
	for id in Equipment.ORDER:
		help.append("%s : %s" % [Equipment.ITEMS[id]["short"], Equipment.ITEMS[id]["text"]])
	for id in Traits.TRAITS:
		help.append("%s : %s" % [Traits.TRAITS[id]["name"], Traits.TRAITS[id]["text"]])
	map.add_label("Traits gagnés aux promotions et en route. " + " · ".join(help) + ".", 11, Color(0.6, 0.58, 0.52))


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
