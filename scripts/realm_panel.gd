class_name RealmPanel
extends RefCounted
## Sections des fenêtres de la carte de campagne pour le domaine : marché, quêtes et allégeance dans
## la fenêtre de la ville ; château (fief, achat, assaut, levée chez le suzerain), repaire et pont des
## quêtes ; allégeance, fiefs et cargaison dans l'onglet Compagnie ; onglet « Quêtes » ; marques sur
## la carte (bannière des fiefs, cibles des quêtes) et lignes des infobulles.
## map : le nœud de campaign_map.gd (add_label, add_button, add_section, box, state, notice,
## refresh_ui, close_town, start_battle, town_open).

const DIM := Color(0.75, 0.72, 0.65)
const HINT := Color(0.6, 0.58, 0.52)
const GOLD := Color(1, 0.84, 0.4)
const WARN := Color(1, 0.5, 0.4)
const GOOD := Color(0.6, 0.9, 0.55)
const TITLE := Color(1, 0.9, 0.7)
const COMPANY := Color(0.22, 0.38, 0.85) ## Couleurs de la compagnie : bleu et or
const SELL_STEP := 5

static var confirm_break := false ## Premier clic sur « Rompre le serment » : demande confirmation


# ---------------------------------------------------------------- Actions

## Applique le résultat d'une action (err : "" si elle a réussi) : message, son, sauvegarde.
static func done(map: Node, err: String, ok_text := "") -> void:
	map.notice = err if err != "" else ok_text
	GameAudio.feedback(err == "")
	(map.state as CampaignState).save()
	map.refresh_ui()


## Une action qui lance une bataille (assaut, défense, repaire).
static func battle(map: Node, err: String) -> void:
	if err != "":
		done(map, err)
		return
	map.town_open = false
	map.start_battle()
	map.refresh_ui()


static func do_buy(map: Node, town: int, g: String, n: int) -> void:
	done(map, map.state.trade.buy(map.state, town, g, n))


static func do_sell(map: Node, town: int, g: String, n: int) -> void:
	done(map, map.state.trade.sell(map.state, town, g, n))


static func do_wagon(map: Node, town: int, buy: bool) -> void:
	var s: CampaignState = map.state
	done(map, s.trade.buy_wagon(s, town) if buy else s.trade.sell_wagon(s))


static func do_accept(map: Node, id: int) -> void:
	done(map, map.state.quests.accept(map.state, id), "Quête acceptée.")


static func do_turn_in(map: Node, id: int) -> void:
	done(map, map.state.quests.turn_in(map.state, id))


static func do_abandon(map: Node, id: int) -> void:
	done(map, map.state.quests.abandon(map.state, id), "Quête abandonnée.")


static func do_swear(map: Node, f: int, town: int) -> void:
	done(map, map.state.diplomacy.swear(map.state, f, town), "La compagnie prête allégeance à %s." % CampaignState.faction_name(f))


static func do_break(map: Node, sure: bool) -> void:
	if not sure:
		confirm_break = not confirm_break
		map.refresh_ui()
		return
	confirm_break = false
	done(map, map.state.diplomacy.break_oath(map.state), "Serment rompu : la compagnie est de nouveau libre.")


static func do_buy_castle(map: Node, i: int) -> void:
	done(map, map.state.fiefs.buy(map.state, i), "Le château de %s est à vous !" % Fiefs.place_name(i))


static func do_assault(map: Node, i: int) -> void:
	battle(map, map.state.fiefs.assault(map.state, i))


static func do_defend(map: Node, i: int) -> void:
	battle(map, map.state.fiefs.defend(map.state, i))


static func do_levy(map: Node, i: int, type: String) -> void:
	done(map, map.state.fiefs.levy(map.state, i, type))


static func do_station(map: Node, i: int, index: int) -> void:
	done(map, map.state.fiefs.station(map.state, i, index))


static func do_withdraw(map: Node, i: int, index: int) -> void:
	done(map, map.state.fiefs.withdraw(map.state, i, index))


static func do_attack_lair(map: Node, id: int) -> void:
	battle(map, map.state.quests.attack_lair(map.state, id))


static func do_camp(map: Node, id: int) -> void:
	var err: String = map.state.quests.start_camp(map.state, id)
	if err == "":
		map.town_open = false
	done(map, err, "La compagnie dresse le camp. Des pillards approchent !")


# ---------------------------------------------------------------- Fenêtre de la ville

static func build_town(map: Node, here: int) -> void:
	var s: CampaignState = map.state
	build_market(map, s, here)
	build_place_quests(map, s, here)
	build_allegiance(map, s, here)


static func build_market(map: Node, s: CampaignState, here: int) -> void:
	var tr := s.trade
	map.add_section("Marché")
	var closed := s.closed_message(here)
	if closed != "":
		map.add_label(closed + " Les marchands ne traitent pas avec vous.", 12, WARN)
	map.add_label("Charge : %d / %d (%s, %s)   ·   cargaison : %s" % [tr.load_total(), tr.capacity(s), CampaignState.plural(s.total_men(), "homme", "hommes"),
		CampaignState.plural(tr.wagons, "chariot", "chariots"), tr.cargo_text()], 12, DIM)
	if s.world.besieged(here):
		map.add_label("Ville assiégée : tout est plus cher, le grain et le vin manquent.", 12, WARN)
	for g in Trade.GOODS:
		var row := HBoxContainer.new()
		map.box.add_child(row)
		var l := Label.new()
		var tag := ""
		var col := Color(0.92, 0.88, 0.78)
		if g in Trade.PRODUCES[here]:
			tag = " (produit ici)"
			col = GOOD
		elif g in Trade.LACKS[here]:
			tag = " (manque ici)"
			col = Color(1, 0.72, 0.45)
		var have := tr.carried(g)
		l.text = "%s%s : achat %d · vente %d%s" % [Trade.good_name(g).capitalize(), tag, tr.buy_price(s, here, g), tr.sell_price(s, here, g), ("   · porté %d" % have) if have > 0 else ""]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = "Prix de base %d écus la charge. Chaque achat fait monter le prix, chaque vente le fait baisser ; les caravanes et les sièges le font bouger." % int(Trade.BASE_PRICE[g])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		var room := tr.room(s)
		map.add_button("Acheter %d" % SELL_STEP, RealmPanel.do_buy.bind(map, here, g, SELL_STEP), closed == "" and room > 0 and s.gold >= tr.buy_price(s, here, g), row)
		map.add_button("Vendre %d" % SELL_STEP, RealmPanel.do_sell.bind(map, here, g, SELL_STEP), closed == "" and have > 0, row)
		var all: Button = map.add_button("Tout", RealmPanel.do_sell.bind(map, here, g, have), closed == "" and have > 0, row)
		all.tooltip_text = "Tout vendre"
	var wrow := HBoxContainer.new()
	map.box.add_child(wrow)
	map.add_button("Acheter un chariot (%d écus, +%d de charge)" % [Trade.WAGON_PRICE, Trade.WAGON_LOAD], RealmPanel.do_wagon.bind(map, here, true),
		closed == "" and tr.wagons < Trade.MAX_WAGONS and s.gold >= Trade.WAGON_PRICE, wrow)
	@warning_ignore("integer_division")
	map.add_button("Revendre un chariot (%d écus)" % (Trade.WAGON_PRICE / 2), RealmPanel.do_wagon.bind(map, here, false), tr.wagons > 0, wrow)
	map.add_label("Achetez là où l'on produit, revendez là où l'on manque. Une défaite fait perdre la moitié de la cargaison.", 11, HINT)


## Quêtes proposées par le lieu (ville ou château) et quêtes à y rendre.
static func build_place_quests(map: Node, s: CampaignState, place: int) -> void:
	var offers := s.quests.offers_at(place)
	var due := s.quests.due_at(place)
	if offers.is_empty() and due.is_empty():
		return
	map.add_section("Quêtes")
	for q in due:
		var why := s.quests.turn_in_refusal(s, q)
		map.add_label("À rendre : %s (%d écus)" % [q["title"], int(q["reward"])], 13, TITLE)
		var label := "Remettre %s" % q["noble"] if str(q["kind"]) == "escort" else "Livrer %d %s" % [int(q["qty"]), Trade.UNITS[q["good"]]]
		map.add_button(label, RealmPanel.do_turn_in.bind(map, int(q["id"])), why == "")
		if why != "":
			map.add_label(why, 11, WARN)
	for q in offers:
		map.add_label("%s : %s" % [Quests.KIND_NAMES[q["kind"]], q["title"]], 13, TITLE)
		map.add_label(str(q["text"]), 12, Color(0.8, 0.77, 0.7))
		map.add_label("Récompense : %d écus   ·   %s pour la mener   ·   offre valable jusqu'au jour %d" % [int(q["reward"]), CampaignState.plural(int(q["days"]), "jour", "jours"), int(q["expires"])], 12, GOLD)
		var why := s.quests.accept_refusal(s, int(q["id"]))
		map.add_button("Accepter la quête", RealmPanel.do_accept.bind(map, int(q["id"])), why == "")
		if why != "" and s.quests.active.size() >= Quests.MAX_ACTIVE:
			map.add_label(why, 11, WARN)


static func build_allegiance(map: Node, s: CampaignState, here: int) -> void:
	var d := s.diplomacy
	var f := s.town_owner(here)
	map.add_section("Allégeance")
	map.add_label(d.status_text(s), 12, DIM)
	if d.liege < 0:
		var why := d.swear_refusal(s, f, here)
		map.add_button("Prêter allégeance à %s (solde %d écus par mois)" % [CampaignState.faction_name(f), d.monthly_pay(s)], RealmPanel.do_swear.bind(map, f, here), why == "")
		if why != "":
			map.add_label(why, 11, HINT)
		map.add_label("Vassale : solde mensuelle, levées dans les châteaux du suzerain, contrat réservé dans sa capitale ; mais ses ennemis deviennent les vôtres, et combattre ses troupes coûte cher.", 11, HINT)
	elif d.liege == f:
		if confirm_break:
			map.add_label("Rompre le serment : réputation %+d auprès de %s, renommée -%d. Sûr ?" % [Diplomacy.BREAK_REP, CampaignState.FACTIONS[f]["short"], Diplomacy.BREAK_FAME], 12, WARN)
			var row := HBoxContainer.new()
			map.box.add_child(row)
			map.add_button("Oui, rompre", RealmPanel.do_break.bind(map, true), true, row)
			map.add_button("Non", RealmPanel.do_break.bind(map, false), true, row)
		else:
			map.add_button("Rompre le serment", RealmPanel.do_break.bind(map, false))


# ---------------------------------------------------------------- Autres lieux

## Fenêtre d'un lieu qui n'est pas une ville : château, ou cible d'une quête. Renvoie faux s'il n'y
## a rien à montrer (la carte affiche alors son « lieu calme »).
static func build_place(map: Node, i: int) -> bool:
	if i < 0:
		return false
	var s: CampaignState = map.state
	if Fiefs.is_castle(i):
		build_castle(map, s, i)
		return true
	var q := s.quests.quest_at(i)
	if q.is_empty():
		return false
	map.window_title.text = Quests.place_name(i)
	map.add_label(Quests.KIND_NAMES[q["kind"]] + " : " + str(q["title"]), 14, TITLE)
	map.add_label(s.quests.status_line(s, q), 12, DIM)
	match str(q["kind"]):
		"lair":
			map.add_label("%s : %s." % [CampaignState.cap_first(str(q["band_name"])), Encounter.estimate(q["band"])], 12, WARN)
			map.add_button("Attaquer le repaire", RealmPanel.do_attack_lair.bind(map, int(q["id"])), not s.is_destroyed() and not s.in_battle())
		"hold":
			if bool(q.get("camp", false)):
				map.add_label("Le camp est dressé : restez ici, les pillards viendront.", 12, DIM)
			map.add_button("Dresser le camp et tenir (le temps reprend)", RealmPanel.do_camp.bind(map, int(q["id"])), not s.is_destroyed())
			map.add_label("Chaque jour passé ici compte ; s'éloigner remet le compte à zéro. Une bande de pillards attaque chaque jour.", 11, HINT)
	map.add_button("Repartir (le temps reprend)", Callable(map, "close_town"))
	return true


static func build_castle(map: Node, s: CampaignState, i: int) -> void:
	var fs := s.fiefs
	var owner := fs.owner_of(i)
	map.window_title.text = "%s%s" % [Fiefs.place_name(i), " — votre fief" if owner == Fiefs.PLAYER else ""]
	if owner == Fiefs.PLAYER:
		build_fief(map, s, i)
	else:
		if owner >= 0:
			map.add_label("Château de %s — réputation %+d (%s)" % [CampaignState.faction_name(owner), s.reputation[owner], s.reputation_label(owner)], 12, CampaignState.FACTIONS[owner]["color"])
		build_levy(map, s, i)
		build_place_quests(map, s, i)
		map.add_section("Le château")
		var price := fs.buy_price(s, i)
		var why := fs.buy_refusal(s, i)
		map.add_button("Acheter le château : %d écus" % price, RealmPanel.do_buy_castle.bind(map, i), why == "")
		if why != "":
			map.add_label(why, 11, HINT)
		var ass := fs.assault_refusal(s, i)
		map.add_label("Garnison : %s" % CampaignState.army_summary(fs.castle_garrison(s, i)), 12, DIM)
		map.add_button("Donner l'assaut (réputation %+d auprès de son seigneur)" % Fiefs.REP_ASSAULT, RealmPanel.do_assault.bind(map, i), ass == "" and not map.ambushed)
		if ass != "":
			map.add_label(ass, 11, HINT)
		map.add_label("Un fief rapporte %d écus par semaine ; on y lève toutes les troupes et on y laisse une garnison." % Fiefs.INCOME, 11, HINT)
	map.add_button("Repartir (le temps reprend)", Callable(map, "close_town"))


static func build_fief(map: Node, s: CampaignState, i: int) -> void:
	var fs := s.fiefs
	var e := fs.fief(i)
	var siege: Dictionary = e["siege"]
	map.add_label("Le fief de la compagnie depuis le jour %d. Revenu de la semaine : %+d écus (%d moins la solde de la garnison)." % [int(e["since"]), fs.weekly_net(s, e), Fiefs.INCOME], 12, GOLD)
	if not siege.is_empty():
		map.add_label("Assiégé par %s : %d hommes ! La garnison tiendra seule dans %s." % [CampaignState.FACTIONS[int(siege["faction"])]["short"], int(siege["men"]), CampaignState.plural(int(siege["days"]), "jour", "jours")], 13, WARN)
		map.add_button("Défendre le château", RealmPanel.do_defend.bind(map, i), fs.defend_refusal(s, i) == "" and not map.ambushed)
	map.add_section("Garnison (%d / %d régiments, %d hommes)" % [(e["garrison"] as Array).size(), Fiefs.MAX_GARRISON, Fiefs.garrison_men(e)])
	if (e["garrison"] as Array).is_empty():
		map.add_label("Personne ne garde les murs : laissez des régiments en garnison.", 12, WARN)
	for k in (e["garrison"] as Array).size():
		var r: Dictionary = e["garrison"][k]
		var row := HBoxContainer.new()
		map.box.add_child(row)
		var l := Label.new()
		l.text = "%s   %d hommes   %s" % [CampaignState.type_name(str(r["type"])), int(r["men"]), CampaignState.rank_name(CampaignState.rank_of(r))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		map.add_button("Reprendre", RealmPanel.do_withdraw.bind(map, i, k), s.company.size() < CampaignState.MAX_REGIMENTS, row)
	if s.company.size() > 1 and (e["garrison"] as Array).size() < Fiefs.MAX_GARRISON:
		map.add_label("Laisser en garnison :", 12, DIM)
		var row := HFlowContainer.new()
		map.box.add_child(row)
		for k in s.company.size():
			var r: Dictionary = s.company[k]
			map.add_button("%d. %s (%d)" % [k + 1, CampaignState.type_name(str(r["type"])), int(r["men"])], RealmPanel.do_station.bind(map, i, k), true, row)
	build_levy(map, s, i)


## Levée de troupes dans un château (son fief, ou un château du suzerain).
static func build_levy(map: Node, s: CampaignState, i: int) -> void:
	var types := s.fiefs.levy_types(s, i)
	if types.is_empty():
		return
	map.add_section("Lever des troupes" + ("" if s.fiefs.owns(i) else " (château de votre suzerain)"))
	for t in UnitTypes.ORDER:
		if not t in types:
			continue
		var men: int = UnitTypes.STATS[t]["count"]
		var cost := s.fiefs.levy_cost(s, i, t, men)
		map.add_button("%s : %d hommes, %d écus" % [CampaignState.type_name(t), men, cost], RealmPanel.do_levy.bind(map, i, t),
			s.gold >= cost and s.company.size() < CampaignState.MAX_REGIMENTS)


# ---------------------------------------------------------------- Onglets

## Onglet Compagnie : allégeance, fiefs, cargaison.
static func build_company(map: Node) -> void:
	var s: CampaignState = map.state
	map.add_section("Allégeance")
	map.add_label(s.diplomacy.status_text(s), 12, DIM)
	map.add_section("Fiefs")
	if s.fiefs.held.is_empty():
		map.add_label("La compagnie n'a pas de terre. Un château s'achète (%d écus) ou se prend d'assaut." % Fiefs.BUY_PRICE, 12, DIM)
	for e in s.fiefs.held:
		var line := "%s : garnison %d hommes, %+d écus par semaine" % [Fiefs.place_name(int(e["place"])), Fiefs.garrison_men(e), s.fiefs.weekly_net(s, e)]
		var siege: Dictionary = e["siege"]
		if not siege.is_empty():
			line += " — ASSIÉGÉ par %s (%s)" % [CampaignState.FACTIONS[int(siege["faction"])]["short"], CampaignState.plural(int(siege["days"]), "jour", "jours")]
		map.add_label(line, 12, WARN if not siege.is_empty() else Color(0.92, 0.88, 0.78))
	map.add_section("Cargaison")
	map.add_label("Charge %d / %d : %s." % [s.trade.load_total(), s.trade.capacity(s), s.trade.cargo_text()], 12, DIM)


## Onglet Quêtes : quêtes en cours et offres connues.
static func build_quests(map: Node) -> void:
	var s: CampaignState = map.state
	var qs := s.quests
	map.window_title.text = "Quêtes"
	map.add_section("En cours (%d / %d)" % [qs.active.size(), Quests.MAX_ACTIVE])
	if qs.active.is_empty():
		map.add_label("Aucune quête en cours. Les villes et les seigneurs des châteaux en proposent : entrez-y pour les accepter.", 12, DIM)
	for q in qs.active:
		var late := int(q["deadline"]) - s.day <= 2
		map.add_label("%s : %s" % [Quests.KIND_NAMES[q["kind"]], q["title"]], 14, TITLE)
		map.add_label(qs.status_line(s, q), 12, WARN if late else DIM)
		map.add_label("Récompense : %d écus (donnée par %s)" % [int(q["reward"]), Quests.place_name(int(q["giver"]))], 12, GOLD)
		map.add_button("Abandonner (réputation %+d)" % Quests.REP_FAIL, RealmPanel.do_abandon.bind(map, int(q["id"])))
	map.add_section("Proposées")
	if qs.offers.is_empty():
		map.add_label("Aucune offre pour l'instant.", 12, DIM)
	for q in qs.offers:
		map.add_label("%s : %s — à %s, %d écus (jusqu'au jour %d)" % [Quests.KIND_NAMES[q["kind"]], q["title"], Quests.place_name(int(q["giver"])), int(q["reward"]), int(q["expires"])], 12)
	map.add_label("Quêtes réussies : %d. Une quête réussie rapporte %+d de réputation auprès de qui la donne et %d de renommée ; manquée, elle en coûte %d." % [qs.done, Quests.REP_DONE, Quests.FAME_DONE, -Quests.REP_FAIL], 11, HINT)


# ---------------------------------------------------------------- Carte

## Marques d'un lieu sur la carte : bannière de la compagnie sur ses fiefs (anneau rouge s'il est
## assiégé), nouvelle bannière d'un château pris, « ! » doré sur les cibles des quêtes.
static func draw_place(map: Node2D, i: int, p: Vector2) -> void:
	var s: CampaignState = map.state
	if Fiefs.is_castle(i):
		var o := s.fiefs.owner_of(i)
		if o == Fiefs.PLAYER: # La bannière aux armoiries est dessinée par MapPlaces
			map.draw_arc(p, 26.0, 0, TAU, 28, COMPANY, 2.0)
			var e := s.fiefs.fief(i)
			if not e.is_empty() and not (e["siege"] as Dictionary).is_empty():
				map.draw_arc(p, 31.0, 0, TAU, 28, Color(0.9, 0.15, 0.1), 3.0)
	for q in s.quests.active:
		if int(q["target"]) == i:
			var at := p + Vector2(-16, -30)
			map.draw_circle(at, 8.0, Color(0.1, 0.07, 0.03, 0.85))
			map.draw_string(map.font, at + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
			break


## Lignes de plus de l'infobulle d'un lieu.
static func place_lines(s: CampaignState, i: int) -> Array[String]:
	var out: Array[String] = []
	if Fiefs.is_castle(i):
		var o := s.fiefs.owner_of(i)
		if o == Fiefs.PLAYER:
			out.append("Votre fief")
		elif o != int(MapData.place(i).get("faction", -1)) and o >= 0:
			out.append("Tenu désormais par %s" % CampaignState.FACTIONS[o]["short"])
	if i < Trade.PRODUCES.size():
		var made: Array[String] = []
		var lacks: Array[String] = []
		for g in Trade.PRODUCES[i]:
			made.append(Trade.good_name(g))
		for g in Trade.LACKS[i]:
			lacks.append(Trade.good_name(g))
		out.append("Produit : %s ; manque : %s" % [", ".join(made), ", ".join(lacks)])
	for q in s.quests.active:
		if int(q["target"]) == i:
			out.append("Quête : %s" % q["title"])
	var n := s.quests.offers_at(i).size()
	if n > 0:
		out.append(CampaignState.plural(n, "quête proposée", "quêtes proposées"))
	return out
