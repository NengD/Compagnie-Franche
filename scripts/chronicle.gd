class_name Chronicle
extends RefCounted
## Chronique de la campagne (CampaignState.chronicle, sauvegardée) : les faits marquants notés au
## fil de la partie (batailles, officiers tombés, fiefs pris ou perdus), dont on tire un récit de
## quelques paragraphes (narrate) pour l'écran de fin et l'onglet Journal.
## Le récit s'appuie aussi sur les statistiques de la campagne : une sauvegarde d'avant la
## chronique (version 13 et avant) donne un récit plus court, mais jamais vide.

const MAX_EVENTS := 300 ## Au-delà, les faits les plus anciens sont oubliés

var events: Array[Dictionary] = [] ## {"day", "kind", ...} du plus ancien au plus récent


func to_dict() -> Array:
	return events.duplicate(true)


static func from_dict(v: Variant) -> Chronicle:
	var c := Chronicle.new()
	if v is Array:
		for e in v:
			if e is Dictionary and str(e.get("kind", "")) != "":
				var d: Dictionary = (e as Dictionary).duplicate(true)
				d["day"] = maxi(1, int(d.get("day", 1)))
				c.events.append(d)
	while c.events.size() > MAX_EVENTS:
		c.events.pop_front()
	return c


## Note un fait de la campagne (data : ses détails).
static func note(state: CampaignState, kind: String, data: Dictionary = {}) -> void:
	if state == null or state.chronicle == null:
		return
	var e := data.duplicate(true)
	e["kind"] = kind
	e["day"] = state.day
	state.chronicle.events.append(e)
	while state.chronicle.events.size() > MAX_EVENTS:
		state.chronicle.events.pop_front()


## Bataille de campagne (CampaignState.finish_battle, avant Captain.after_battle).
static func note_battle(state: CampaignState, victory: bool, retreat: bool, lost: int, killed: int) -> void:
	var p := state.pending
	var town := int(p.get("town", -1))
	note(state, "battle", {"victory": victory, "retreat": retreat and not victory, "ambush": bool(p.get("ambush", false)),
		"foe": str(p.get("foe", "")), "title": str(p.get("title", "")), "final": bool(p.get("final", false)),
		"town": town if town >= 0 and town < CampaignState.TOWNS.size() else -1,
		"killed": killed, "lost": lost, "captain_fell": state.captain.fell})


func of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if str(e["kind"]) == kind:
			out.append(e)
	return out


# ---------------------------------------------------------------- Récit

static func battle_place(e: Dictionary) -> String:
	var t := int(e.get("town", -1))
	return " près de %s" % CampaignState.TOWNS[t]["name"] if t >= 0 else ""


static func join_names(parts: Array) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " et " + str(parts[-1])


## Le récit de la campagne : quelques paragraphes (jamais vide).
static func narrate(state: CampaignState) -> Array[String]:
	var out: Array[String] = []
	var ch: Chronicle = state.chronicle if state.chronicle != null else Chronicle.new()
	var days := state.end_day if state.end_day > 0 else state.day
	# Les débuts
	var start := "Au premier jour, %s leva la bannière de la compagnie à %s, en des temps %s." % [state.captain.name, CampaignState.TOWNS[0]["name"],
		{"easy": "cléments", "hard": "impitoyables"}.get(state.difficulty, "troublés")]
	if state.ended == "":
		start += " Voici ce qu'on racontait déjà d'elle au jour %d." % state.day
	out.append(start)
	# Les batailles
	var fought := state.victories + state.defeats
	if fought == 0:
		out.append("La compagnie n'avait encore livré aucune bataille : on ne parlait d'elle que dans les tavernes.")
	else:
		var s := "En %s, elle livra %s : %s et %s. %s tombèrent sous ses coups ; elle perdit %s." % [
			CampaignState.plural(days, "jour", "jours"), CampaignState.plural(fought, "bataille", "batailles"),
			CampaignState.plural(state.victories, "victoire", "victoires"), CampaignState.plural(state.defeats, "défaite", "défaites"),
			CampaignState.cap_first(CampaignState.plural(state.enemies_killed, "ennemi", "ennemis")), CampaignState.plural(state.men_lost, "homme", "hommes")]
		var best: Dictionary = {}
		var worst: Dictionary = {}
		var falls := 0
		for e in ch.of_kind("battle"):
			if bool(e.get("captain_fell", false)):
				falls += 1
			if bool(e.get("final", false)):
				continue
			if bool(e["victory"]) and (best.is_empty() or int(e["killed"]) > int(best["killed"])):
				best = e
			if not bool(e["victory"]) and (worst.is_empty() or int(e["lost"]) > int(worst["lost"])):
				worst = e
		if not best.is_empty():
			s += " Sa plus belle victoire fut remportée au jour %d sur les %s%s : %s tués pour %s perdus." % [int(best["day"]), best["foe"], battle_place(best),
				CampaignState.plural(int(best["killed"]), "ennemi", "ennemis"), CampaignState.plural(int(best["lost"]), "homme", "hommes")]
		if not worst.is_empty():
			s += " Le jour le plus sombre fut le jour %d : face aux %s%s, %s, et %s y restèrent." % [int(worst["day"]), worst["foe"], battle_place(worst),
				"elle dut sonner la retraite" if bool(worst.get("retreat", false)) else "elle fut battue", CampaignState.plural(int(worst["lost"]), "homme", "hommes")]
		if falls > 0:
			s += " %s lui-même tomba %s, blessé, mais se releva toujours." % [state.captain.name, "une fois" if falls == 1 else "%d fois" % falls]
		out.append(s)
	# Les officiers
	var dead := ch.of_kind("officer_dead")
	var hurt := ch.of_kind("officer_wounded")
	if not dead.is_empty() or not hurt.is_empty():
		var s := ""
		if not dead.is_empty():
			var names: Array[String] = []
			for e in dead:
				names.append("%s, %s, au jour %d à la tête %s" % [e["name"], e["role"], int(e["day"]), e["regiment"]])
			s = "Elle pleura %s : %s." % ["un officier" if dead.size() == 1 else "%d officiers" % dead.size(), join_names(names)]
		if not hurt.is_empty():
			var names2: Array[String] = []
			for e in hurt:
				if not str(e["name"]) in names2:
					names2.append(str(e["name"]))
			s += (" " if s != "" else "") + "%s %s blessé%s à la tête de ses hommes, mais en revin%s." % [join_names(names2), "fut" if names2.size() == 1 else "furent",
				"" if names2.size() == 1 else "s", "t" if names2.size() == 1 else "rent"]
		out.append(s)
	elif not state.companions.list.is_empty():
		var names3: Array[String] = []
		for m in state.companions.list:
			names3.append(str(m["name"]))
		out.append("Aucun officier ne tomba : %s %s toutes ses campagnes." % [join_names(names3), "survécut à" if names3.size() == 1 else "survécurent à"])
	# Les fiefs
	var won := ch.of_kind("fief")
	var lost := ch.of_kind("fief_lost")
	if not won.is_empty() or not lost.is_empty():
		var parts: Array[String] = []
		for e in won:
			parts.append("%s %s au jour %d" % ["acheta" if bool(e.get("bought", false)) else "prit", e["place"], int(e["day"])])
		var s := "Elle se tailla un domaine : elle %s." % join_names(parts) if not parts.is_empty() else ""
		if not lost.is_empty():
			var names4: Array[String] = []
			for e in lost:
				names4.append(str(e["place"]))
			s += (" " if s != "" else "") + "Mais elle perdit %s." % join_names(names4)
		out.append(s)
	# L'issue
	match state.ended:
		"victory":
			out.append("%s Ainsi finit la campagne, et le nom de la compagnie entra dans la légende." % state.end_note)
		"ruin":
			out.append("%s Ainsi finit la campagne : de la compagnie, il ne resta qu'une bannière déchirée." % state.end_note)
		_:
			out.append("L'histoire n'est pas finie : au jour %d, la compagnie compte %s et %d écus, et sa renommée atteint %d (%d pour la bataille qui décidera de la guerre)." % [
				state.day, CampaignState.plural(state.total_men(), "homme", "hommes"), int(state.gold), state.fame, CampaignState.FINAL_FAME])
	return out


## Onglet Journal de la carte : la chronique sous les derniers évènements.
static func build_journal(map: Node) -> void:
	map.add_section("Chronique de la compagnie")
	for p in narrate(map.state):
		map.add_label(p, 12, Color(0.9, 0.85, 0.72))
