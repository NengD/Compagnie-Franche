extends SceneTree
## Test headless du domaine (fiefs.gd, trade.gd, diplomacy.gd, quests.gd, realm_panel.gd et le bloc
## « Domaine » de campaign_state.gd) :
##   godot --headless --path . -s tests/realm_test.gd
## - commerce : prix selon la ville, achats et ventes qui font bouger les prix, charge et chariots,
##   caravanes et sièges, cargaison perdue dans une défaite ;
## - fiefs : achat, assaut (contrat de siège), levée, garnison, revenu, sièges du fief (seul ou défendu) ;
## - diplomacie : serment, guerre avec les ennemis du suzerain, solde, contrat réservé, combattre son
##   suzerain, rupture ; l'indépendant ne touche pas au hasard de la campagne ;
## - quêtes : repaire, escorte, tenir un pont (pillards menés par PartyAI), livraison, échecs ;
## - sauvegarde du domaine (et ancienne sauvegarde sans domaine) ; fenêtres de la carte.
## Fichiers de test dans user:// seulement. Code de sortie : 0 si tout va bien, 1 sinon.


class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s:%d (%s) %s" % [file, line, function, rationale if rationale != "" else code])
		mutex.unlock()


var counter := ErrorCounter.new()
var fails: Array[String] = []
var frame := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func new_state(seed_value := 42) -> CampaignState:
	var s := CampaignState.new_game(seed_value)
	s.overworld.spawning = false
	s.gold = 3000.0
	return s


## Survivants « au complet » pour finish_battle.
func full(s: CampaignState) -> Array:
	var out: Array = []
	for r in s.battle_army():
		out.append(int(r["men"]))
	return out


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.slot_prefix = "user://test_domaine"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	test_trade()
	test_fiefs()
	test_fief_sieges()
	test_diplomacy()
	test_independent()
	test_quests()
	test_hold()
	test_save()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		test_panels()
		return false
	CampaignState.delete_slot(1)
	if not counter.errors.is_empty():
		fails.append("erreurs du moteur : %s" % "; ".join(counter.errors.slice(0, 5)))
	if fails.is_empty():
		print("Domaine : OK")
		quit(0)
	else:
		print("Domaine : %d échec(s)" % fails.size())
		for f in fails:
			print("  - " + f)
		quit(1)
	return true


# ---------------------------------------------------------------- Commerce

func test_trade() -> void:
	var s := new_state()
	var tr := s.trade
	# Valombre (0) produit le grain et manque de fer ; Brévannes (3) manque de grain
	check(tr.buy_price(s, 0, "grain") < int(Trade.BASE_PRICE["grain"]), "commerce : grain pas moins cher là où on le produit")
	check(tr.buy_price(s, 0, "iron") > int(Trade.BASE_PRICE["iron"]), "commerce : fer pas plus cher là où il manque")
	check(tr.sell_price(s, 3, "grain") > tr.buy_price(s, 0, "grain"), "commerce : aucun bénéfice possible sur le grain")
	var cap := tr.capacity(s)
	check(cap == int(s.total_men() * Trade.CARGO_PER_MAN), "commerce : charge %d" % cap)
	var p0 := tr.buy_price(s, 0, "grain")
	var g0 := s.gold
	check(tr.buy(s, 0, "grain", 10) == "", "commerce : achat refusé")
	check(tr.carried("grain") == 10 and s.gold < g0, "commerce : achat sans effet")
	check(tr.buy_price(s, 0, "grain") >= p0 and float(tr.supply[0][0]) < 0.0, "commerce : l'achat ne fait pas monter le prix")
	tr.buy(s, 0, "grain", 999)
	check(tr.load_total() == cap and tr.room(s) == 0, "commerce : charge dépassée (%d / %d)" % [tr.load_total(), cap])
	check(tr.buy(s, 0, "wine", 1) != "", "commerce : achat sans place accepté")
	check(tr.buy_wagon(s, 0) == "" and tr.capacity(s) == cap + Trade.WAGON_LOAD, "commerce : chariot")
	check(tr.buy(s, 0, "salt", 5) == "" and tr.carried("salt") == 5, "commerce : achat avec le chariot")
	var g1 := s.gold
	var ps := tr.sell_price(s, 3, "grain")
	check(tr.sell(s, 3, "grain", 10) == "" and s.gold > g1 + 9 * (ps - 3), "commerce : vente")
	check(tr.sell_price(s, 3, "grain") <= ps, "commerce : la vente ne fait pas baisser le prix")
	check(tr.sell(s, 3, "iron", 1) != "", "commerce : vente de ce qu'on n'a pas")
	# L'offre revient vers la normale
	var before := absf(float(tr.supply[0][0]))
	tr.day(s)
	check(absf(float(tr.supply[0][0])) < before, "commerce : l'offre ne revient pas vers la normale")
	# Une caravane de Valombre (grain) arrive à Brévannes : le grain y baisse
	var car := Party.new()
	car.kind = "caravan"
	car.home = 0
	car.goods = 600
	car.pos = MapData.place_pos(3)
	s.overworld.add(s, car)
	var pg := tr.buy_price(s, 3, "grain")
	var sup := float(tr.supply[3][0])
	tr.day(s)
	check(float(tr.supply[3][0]) > sup * Trade.RECOVERY, "commerce : la caravane ne change pas l'offre")
	check(tr.buy_price(s, 3, "grain") <= pg, "commerce : la caravane ne fait pas baisser le grain")
	# Siège de Brévannes : tout est plus cher, le grain s'épuise
	s.overworld.remove(s, car)
	s.world.declare_war(s, 1, 2)
	var px := tr.buy_price(s, 3, "cloth")
	var a := s.world.add_army(1, 2, 3, 300, "siege")
	a.mode = "siege"
	check(s.world.besieged(3), "commerce : le siège de test n'a pas pris")
	check(tr.buy_price(s, 3, "cloth") > px, "commerce : un siège ne fait pas monter les prix")
	var sg := float(tr.supply[3][0])
	tr.day(s)
	check(float(tr.supply[3][0]) < sg, "commerce : le grain ne manque pas dans la ville assiégée")
	# Défaite : la moitié de la cargaison est perdue
	var load := tr.load_total()
	var note := tr.after_battle(s, false)
	check(tr.load_total() <= load / 2 + 1 and note != "", "commerce : cargaison gardée après une défaite")
	check(tr.after_battle(s, true) == "", "commerce : perte après une victoire")
	# Moins d'hommes : le surplus est abandonné
	s.company.resize(1)
	tr.fit_load(s)
	check(tr.load_total() <= tr.capacity(s), "commerce : surcharge après des pertes")
	print("Commerce : OK")


# ---------------------------------------------------------------- Fiefs

func test_fiefs() -> void:
	var s := new_state()
	var fs := s.fiefs
	var tour := MapData.place_named("Tour du Guet")
	check(Fiefs.is_castle(tour) and fs.owner_of(tour) == 0, "fief : Tour du Guet n'est pas un château du Comté")
	check(fs.buy_refusal(s, tour) != "", "fief : achat sans réputation accepté")
	s.reputation[0] = 30
	s.gold = 10000.0
	s.overworld.inside = tour
	var fame := s.fame
	check(fs.buy(s, tour) == "", "fief : achat refusé (%s)" % fs.buy_refusal(s, tour))
	check(fs.owns(tour) and fs.held.size() == 1 and is_equal_approx(s.gold, 10000.0 - Fiefs.BUY_PRICE), "fief : achat sans effet")
	check(s.fame == fame + Fiefs.FIEF_FAME, "fief : pas de renommée pour un château")
	check(fs.buy(s, tour) != "", "fief : château acheté deux fois")
	# Levée : toutes les troupes, moins cher qu'en ville
	check("foot_knight" in fs.levy_types(s, tour) and fs.levy_types(s, tour).size() == UnitTypes.ORDER.size(), "fief : levée incomplète")
	var n := s.company.size()
	var g := s.gold
	check(fs.levy(s, tour, "foot_knight") == "" and s.company.size() == n + 1, "fief : levée refusée")
	check(is_equal_approx(g - s.gold, fs.levy_cost(s, tour, "foot_knight", 12)) and fs.levy_cost(s, tour, "spear", 20) < s.recruit_cost("spear", 20, 0), "fief : prix de la levée")
	# Garnison
	check(fs.station(s, tour, 0) == "" and s.company.size() == n and (fs.fief(tour)["garrison"] as Array).size() == 1, "fief : garnison refusée")
	check(fs.withdraw(s, tour, 0) == "" and s.company.size() == n + 1, "fief : reprise de la garnison")
	fs.station(s, tour, 0)
	fs.station(s, tour, 0)
	var e := fs.fief(tour)
	check(Fiefs.garrison_men(e) > 0 and fs.garrison_wage(s, e) > 0.0, "fief : garnison sans hommes ni solde")
	s.overworld.inside = 0
	check(fs.station(s, tour, 0) != "", "fief : garnison laissée de loin")
	# Revenu de la semaine
	s.day = 13
	var before := s.gold
	s.pass_day() # Jour 14
	var wage := s.daily_wage()
	check(s.gold > before - wage - 1.0 + Fiefs.INCOME * 0.5, "fief : pas de revenu le jour 14 (%d -> %d)" % [int(before), int(s.gold)])
	# Château d'une autre faction : assaut
	var gris := MapData.place_named("Grisemont")
	check(fs.owner_of(gris) == 1 and fs.assault_refusal(s, gris) == "", "fief : assaut de Grisemont refusé")
	var rep := s.reputation[1]
	check(fs.assault(s, gris) == "" and s.in_battle() and str(s.pending["siege"]) == "assault" and int(s.pending["fief"]) == gris, "fief : contrat d'assaut")
	check(not s.world.besieged(int(s.pending["town"])), "fief : assaut rattaché à une ville assiégée")
	check(s.pending["enemy"].size() >= 5, "fief : garnison trop maigre")
	var out := s.finish_battle(true, full(s))
	check(fs.owns(gris) and fs.held.size() == 2, "fief : château pris non acquis")
	check(s.reputation[1] <= rep + Fiefs.REP_ASSAULT, "fief : l'assaut ne fâche pas son seigneur")
	check("fief" in str(out["text"]), "fief : compte rendu muet")
	# Défaite d'un assaut : rien ne change, sauf la réputation
	var fl := MapData.place_named("Fort-Lisière")
	fs.assault(s, fl)
	s.finish_battle(false, full(s))
	check(not fs.owns(fl) and fs.owner_of(fl) == 2, "fief : assaut perdu qui donne le château")
	# Le suzerain : on ne prend pas ses châteaux, on lève chez lui
	s.diplomacy.liege = 2
	check(fs.assault_refusal(s, fl) != "", "fief : assaut d'un château du suzerain")
	s.overworld.inside = fl
	check(fs.levy_types(s, fl) == Fiefs.LORD_LEVY and fs.levy(s, fl, "cavalry") == "", "fief : levée chez le suzerain")
	print("Fiefs : OK")


func test_fief_sieges() -> void:
	var s := new_state(7)
	var fs := s.fiefs
	var tour := MapData.place_named("Tour du Guet")
	fs.grant(s, tour, 0)
	var e := fs.fief(tour)
	# Sans garnison, un siège non défendu prend le château
	fs.start_siege(s, e, 1)
	check(not (e["siege"] as Dictionary).is_empty(), "siège du fief : pas commencé")
	for i in Fiefs.ATTACK_DAYS:
		fs.day(s)
	check(not fs.owns(tour) and fs.owner_of(tour) == 1, "siège du fief : château vide non perdu")
	# Une forte garnison tient seule
	fs.grant(s, tour, -1)
	e = fs.fief(tour)
	for i in 4:
		(e["garrison"] as Array).append({"type": "men_at_arms", "men": 16, "xp": 250.0})
	fs.start_siege(s, e, 1)
	e["siege"]["men"] = 60
	for i in Fiefs.ATTACK_DAYS:
		fs.day(s)
	check(fs.owns(tour) and (e["siege"] as Dictionary).is_empty(), "siège du fief : la garnison ne tient pas")
	# La compagnie vient défendre : bataille de défense
	fs.start_siege(s, e, 1)
	check(fs.defend_refusal(s, tour) != "", "siège du fief : défense de loin")
	s.overworld.inside = tour
	check(fs.defend(s, tour) == "" and str(s.pending.get("siege", "")) == "defense", "siège du fief : défense refusée")
	s.finish_battle(true, full(s))
	check(fs.owns(tour) and (e["siege"] as Dictionary).is_empty(), "siège du fief : victoire qui ne lève pas le siège")
	fs.start_siege(s, e, 2)
	fs.defend(s, tour)
	s.finish_battle(false, full(s))
	check(not fs.owns(tour) and fs.owner_of(tour) == 2, "siège du fief : défaite qui garde le château")
	# Les factions hostiles finissent par attaquer
	var s2 := new_state(9)
	s2.fiefs.grant(s2, tour, -1)
	var e2 := s2.fiefs.fief(tour)
	e2["since"] = -100
	check(s2.fiefs.hostile_factions(s2, e2).is_empty(), "siège du fief : hostile sans raison")
	s2.reputation[1] = -60
	var hf := s2.fiefs.hostile_factions(s2, e2)
	check(hf.size() == 1 and hf[0] == 1, "siège du fief : la faction hostile ne compte pas")
	var started := false
	for i in 400:
		s2.fiefs.day(s2)
		if not (e2["siege"] as Dictionary).is_empty():
			started = true
			break
	check(started, "siège du fief : aucune attaque en 400 jours")
	print("Sièges du fief : OK")


# ---------------------------------------------------------------- Diplomatie

func test_diplomacy() -> void:
	var s := new_state()
	var d := s.diplomacy
	check(d.swear_refusal(s, 0, 0) != "", "diplomatie : serment sans réputation")
	s.reputation[0] = 30
	check(d.swear_refusal(s, 0, 2) != "", "diplomatie : serment hors de ses villes")
	s.world.declare_war(s, 0, 1)
	var rep1 := s.reputation[1]
	check(d.swear(s, 0, 0) == "" and d.liege == 0 and s.overworld.player.faction == 0, "diplomatie : serment refusé")
	check(s.reputation[1] == rep1 + Diplomacy.SWEAR_ENEMY_REP, "diplomatie : les ennemis du suzerain ne s'en fâchent pas")
	# Guerre avec ses ennemis
	check(d.at_war_with(s, 1) and not d.at_war_with(s, 2) and not d.at_war_with(s, 0), "diplomatie : guerres")
	check(s.closed_message(2) != "" and s.closed_message(0) == "", "diplomatie : villes ennemies ouvertes")
	var army := WorldArmy.new()
	army.faction = 1
	army.force = 100
	check(s.world.hostile_to_player(s, army), "diplomatie : armée ennemie pas hostile")
	var patrol := Party.new()
	patrol.kind = "patrol"
	patrol.faction = 1
	check(PartyAI.patrol_hostile(s, s.overworld, patrol), "diplomatie : patrouille ennemie pas hostile")
	# Solde mensuelle et contrat réservé
	d.last_pay = s.day - Diplomacy.PAY_DAYS
	var g := s.gold
	d.day(s)
	check(is_equal_approx(s.gold, g + d.monthly_pay(s)) and d.last_pay == s.day, "diplomatie : solde mensuelle")
	var reserved: Array = s.contracts.filter(func(k: Dictionary) -> bool: return k.get("liege", false))
	check(reserved.size() == 1 and int(reserved[0]["town"]) == s.final_town(0), "diplomatie : contrat réservé")
	d.day(s)
	check(s.contracts.filter(func(k: Dictionary) -> bool: return k.get("liege", false)).size() == 1, "diplomatie : contrats réservés en double")
	# Combattre les troupes de son suzerain
	var r0 := s.reputation[0]
	s.pending = s.make_ambush(0)
	s.pending["enemy_faction"] = 0
	s.finish_battle(true, full(s))
	check(s.reputation[0] <= r0 + Diplomacy.ALLY_FIGHT_REP + 1, "diplomatie : combattre son suzerain sans peine")
	# Rupture
	s.reputation[0] = 40
	s.fame = 50
	check(d.break_oath(s) == "" and d.liege == -1 and s.overworld.player.faction == -1, "diplomatie : rupture refusée")
	check(s.reputation[0] == 40 + Diplomacy.BREAK_REP and s.fame == 50 - Diplomacy.BREAK_FAME, "diplomatie : rupture sans malus")
	check(s.contracts.filter(func(k: Dictionary) -> bool: return k.get("liege", false)).is_empty(), "diplomatie : contrat réservé gardé après la rupture")
	s.reputation[0] = 60
	check(d.swear_refusal(s, 0, 0) != "", "diplomatie : la faction trahie reprend aussitôt la compagnie")
	check(not d.at_war_with(s, 1) and s.closed_message(2) == "", "diplomatie : guerre gardée après la rupture")
	# Suzerain sans ville : serment dissous
	var s2 := new_state(3)
	s2.reputation[2] = 30
	s2.diplomacy.swear(s2, 2, 3)
	for t in s2.world.towns_of(2):
		s2.world.owner[t] = 1
	s2.diplomacy.day(s2)
	check(s2.diplomacy.liege == -1, "diplomatie : suzerain sans terre gardé")
	print("Diplomatie : OK")


## L'indépendant : rien ne change, et le hasard de la campagne n'est pas touché par le domaine.
func test_independent() -> void:
	var s := new_state(11)
	var st := s.rng.state
	for i in 30:
		s.realm_day()
	check(s.rng.state == st, "indépendant : le domaine tire le hasard de la campagne")
	for t in CampaignState.TOWNS.size():
		check(s.realm_closed(t) == "", "indépendant : ville %d fermée par la diplomatie" % t)
	check(s.diplomacy.after_battle(s, true) == "", "indépendant : note de diplomatie")
	print("Indépendant : OK")


# ---------------------------------------------------------------- Quêtes

## Une offre de la sorte kind, tirée par make_offer (donneur au besoin forcé).
func offer_of(s: CampaignState, kind: String) -> Dictionary:
	for i in 300:
		for gv in Quests.givers(s):
			var q := s.quests.make_offer(s, gv)
			if str(q.get("kind", "")) == kind:
				s.quests.offers.append(q)
				return q
	return {}


func take(s: CampaignState, q: Dictionary) -> bool:
	s.overworld.inside = int(q["giver"])
	return s.quests.accept(s, int(q["id"])) == ""


func test_quests() -> void:
	var s := new_state()
	var qs := s.quests
	check(not qs.offers.is_empty(), "quêtes : aucune offre au départ")
	qs.offers.clear()
	# Repaire
	var q := offer_of(s, "lair")
	check(not q.is_empty() and MapData.place(int(q["target"]))["kind"] in ["lair", "ruins"], "quêtes : pas de repaire")
	check(take(s, q) and qs.active.size() == 1 and int(q["deadline"]) == s.day + int(q["days"]), "quêtes : repaire refusé")
	check(qs.attack_lair(s, int(q["id"])) != "", "quêtes : attaque du repaire de loin")
	s.overworld.inside = int(q["target"])
	check(qs.attack_lair(s, int(q["id"])) == "" and int(s.pending.get("quest", -1)) == int(q["id"]), "quêtes : attaque du repaire")
	check(s.pending["enemy"].size() >= 2 and not s.pending.has("party") and not s.pending.has("party_id"), "quêtes : armée du repaire")
	var band := Quests.band_men(q)
	s.finish_battle(false, full(s), [5])
	check(qs.active.has(q) and Quests.band_men(q) < band, "quêtes : défaite au repaire sans pertes pour la bande")
	var gold := s.gold
	qs.attack_lair(s, int(q["id"]))
	s.finish_battle(true, full(s))
	check(not qs.active.has(q) and qs.done == 1 and s.gold >= gold + int(q["reward"]) - s.daily_wage() - 1.0, "quêtes : repaire nettoyé sans récompense")
	# Escorte réussie, puis escorte perdue dans une défaite
	q = offer_of(s, "escort")
	check(take(s, q), "quêtes : escorte refusée")
	check(qs.turn_in(s, int(q["id"])) != "", "quêtes : escorte rendue hors de la ville")
	s.overworld.inside = int(q["target"])
	check(qs.due_at(int(q["target"])).has(q) and qs.turn_in(s, int(q["id"])) == "" and qs.done == 2, "quêtes : escorte non rendue")
	q = offer_of(s, "escort")
	take(s, q)
	var rep := s.reputation.duplicate()
	s.pending = s.make_ambush(0)
	s.finish_battle(false, full(s))
	check(not qs.active.has(q), "quêtes : le noble survit à la défaite")
	var f := int(q["faction"])
	check(s.reputation[f] < int(rep[f]), "quêtes : échec sans perte de réputation")
	# Livraison
	q = offer_of(s, "deliver")
	check(take(s, q), "quêtes : livraison refusée")
	s.overworld.inside = int(q["target"])
	check(qs.turn_in(s, int(q["id"])) != "", "quêtes : livraison sans marchandises")
	s.trade.cargo[str(q["good"])] = int(q["qty"]) + 2
	check(qs.turn_in(s, int(q["id"])) == "" and s.trade.carried(str(q["good"])) == 2, "quêtes : livraison")
	# Date limite dépassée
	q = offer_of(s, "deliver")
	take(s, q)
	s.day = int(q["deadline"])
	qs.day(s)
	check(qs.active.has(q), "quêtes : échec avant la date limite")
	s.day += 1
	qs.day(s)
	check(not qs.active.has(q), "quêtes : date limite ignorée")
	# Trois quêtes au plus
	for k in Quests.MAX_ACTIVE:
		take(s, offer_of(s, "deliver"))
	var extra := offer_of(s, "deliver")
	check(not take(s, extra), "quêtes : plus de %d quêtes à la fois" % Quests.MAX_ACTIVE)
	# Offres périmées
	s.day += Quests.OFFER_DAYS + 1
	qs.refresh_offers(s, 0.0)
	check(qs.offers.is_empty(), "quêtes : offres périmées gardées")
	print("Quêtes : OK")


## Tenir un pont : camper, pillards lancés sur la compagnie par PartyAI, jours comptés.
func test_hold() -> void:
	var s := new_state(5)
	var qs := s.quests
	qs.offers.clear()
	var q := offer_of(s, "hold")
	check(not q.is_empty() and MapData.place(int(q["target"]))["kind"] in ["bridge", "ford"], "tenir : pas de pont")
	take(s, q)
	var at := MapData.place_pos(int(q["target"]))
	s.overworld.parties.clear() # Seuls les pillards de la quête sur la carte
	s.overworld.hour = 1.0 # Pas de fin de journée pendant l'approche
	check(qs.start_camp(s, int(q["id"])) != "", "tenir : camp dressé de loin")
	s.overworld.enter(s, int(q["target"]))
	check(qs.start_camp(s, int(q["id"])) == "" and bool(q["camp"]) and s.overworld.inside == -1, "tenir : camp refusé")
	var raiders := s.overworld.by_id(s, int(q["raiders"]))
	check(raiders != null and raiders.kind == "bandits" and raiders.target_id == s.overworld.player.id, "tenir : pas de pillards lancés")
	# PartyAI mène les pillards jusqu'à la compagnie (rapprochés pour un test court)
	raiders.pos = MapData.walkable_point(at + Vector2(90, 0))
	raiders.path.clear()
	var met := false
	for i in 48:
		var ev := s.overworld.tick(s, 0.5)
		if str(ev.get("event", "")) == "contact" and int(ev["id"]) == raiders.id:
			met = true
			break
	check(met, "tenir : les pillards n'attaquent pas")
	# Les jours comptent tant que la compagnie reste ; une nouvelle bande vient chaque jour
	s.overworld.player.pos = at
	raiders.troops.clear() # Dispersés
	qs.day(s)
	check(int(q["held"]) == 1 and int(q["raiders"]) != raiders.id, "tenir : jour non compté ou pas de nouvelle bande")
	s.overworld.player.pos = at + Vector2(400, 0)
	qs.day(s)
	check(int(q["held"]) == 0 and not bool(q["camp"]), "tenir : partir ne remet pas à zéro")
	s.overworld.player.pos = at
	qs.start_camp(s, int(q["id"]))
	var g := s.gold
	for i in int(q["need"]):
		qs.day(s)
	check(not qs.active.has(q) and s.gold >= g + int(q["reward"]), "tenir : pont tenu sans récompense")
	print("Tenir un pont : OK")


# ---------------------------------------------------------------- Sauvegarde

func test_save() -> void:
	var s := new_state(21)
	var tour := MapData.place_named("Tour du Guet")
	s.fiefs.grant(s, tour, 0)
	(s.fiefs.fief(tour)["garrison"] as Array).append({"type": "archer", "men": 12, "xp": 120.0, "traits": ["tenaces"]})
	s.fiefs.start_siege(s, s.fiefs.fief(tour), 1)
	s.trade.cargo = {"wine": 7, "iron": 3}
	s.trade.wagons = 2
	s.trade.shift(4, "cloth", 0.5)
	s.reputation[0] = 30
	s.diplomacy.swear(s, 0, 0)
	s.diplomacy.day(s)
	s.quests.offers.clear()
	take(s, offer_of(s, "lair"))
	take(s, offer_of(s, "hold"))
	offer_of(s, "deliver")
	# Bataille de fief en cours, hors de la liste des contrats
	s.overworld.inside = tour
	s.fiefs.defend(s, tour)
	var d: Variant = JSON.parse_string(JSON.stringify(s.to_dict()))
	var l := CampaignState.from_dict(d)
	check(l != null, "sauvegarde : domaine illisible")
	if l == null:
		return
	check(JSON.stringify(l.realm_to_dict()) == JSON.stringify(s.realm_to_dict()), "sauvegarde : domaine changé à la relecture")
	check(l.fiefs.owns(tour) and Fiefs.garrison_men(l.fiefs.fief(tour)) == 12, "sauvegarde : fief perdu")
	check(l.trade.carried("wine") == 7 and l.trade.wagons == 2, "sauvegarde : cargaison perdue")
	check(l.diplomacy.liege == 0 and l.overworld.player.faction == 0, "sauvegarde : serment perdu")
	check(l.quests.active.size() == 2 and l.quests.offers.size() >= 1, "sauvegarde : quêtes perdues")
	check(l.in_battle() and int(l.pending.get("fief", -1)) == tour and str(l.pending.get("siege", "")) == "defense", "sauvegarde : bataille de fief perdue")
	check(l.contracts.filter(func(k: Dictionary) -> bool: return k.get("liege", false)).size() == 1, "sauvegarde : contrat réservé perdu")
	# Les deux campagnes continuent de la même façon (hasards propres sauvegardés)
	l.pending = {}
	s.pending = {}
	for i in 5:
		s.realm_day()
		l.realm_day()
	check(JSON.stringify(l.quests.to_dict()) == JSON.stringify(s.quests.to_dict()), "sauvegarde : quêtes qui divergent après relecture")
	# Une sauvegarde d'avant le domaine : rien, et de premières quêtes
	var old: Dictionary = JSON.parse_string(JSON.stringify(new_state(22).to_dict()))
	old.erase("realm")
	old["version"] = 9
	var o := CampaignState.from_dict(old)
	check(o != null and o.fiefs.held.is_empty() and o.diplomacy.liege == -1 and o.trade.load_total() == 0 and not o.quests.offers.is_empty(), "sauvegarde : version 9 mal relue")
	# Sauvegarde sur disque
	check(s.save() and CampaignState.load_game() != null, "sauvegarde : écriture du domaine")
	print("Sauvegarde du domaine : OK")


# ---------------------------------------------------------------- Fenêtres

func labels_of(m: Node) -> String:
	var parts: Array[String] = []
	for c in (m.box as Control).find_children("*", "Label", true, false):
		parts.append((c as Label).text)
	for c in (m.box as Control).find_children("*", "Button", true, false):
		parts.append((c as Button).text)
	return "\n".join(parts)


func test_panels() -> void:
	var s := new_state(31)
	s.reputation[0] = 30
	s.trade.cargo = {"grain": 4}
	CampaignState.current = s
	var m: Node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	m.auto_launch = false
	root.add_child(m)
	m.town_open = true
	m.refresh_ui()
	var t := labels_of(m)
	check("Marché" in t and "Allégeance" in t and "Acheter 5" in t, "fenêtre de ville : marché ou allégeance absents")
	m.toggle_view("quests")
	check(m.window_title.text == "Quêtes" and "En cours" in labels_of(m), "onglet Quêtes absent")
	m.toggle_view("company")
	check("Cargaison" in labels_of(m) and "Fiefs" in labels_of(m), "onglet Compagnie : domaine absent")
	m.toggle_view("company")
	# Château d'un seigneur, puis son propre fief
	var tour := MapData.place_named("Tour du Guet")
	s.overworld.enter(s, tour)
	m.town_open = true
	m.refresh_ui()
	t = labels_of(m)
	check("Tour du Guet" in m.window_title.text and "Acheter le château" in t and "Donner l'assaut" in t, "fenêtre de château")
	s.fiefs.grant(s, tour, -1)
	m.refresh_ui()
	t = labels_of(m)
	check("votre fief" in m.window_title.text and "Garnison" in t and "Lever des troupes" in t, "fenêtre du fief")
	RealmPanel.do_station(m, tour, 0)
	check((s.fiefs.fief(tour)["garrison"] as Array).size() == 1, "fenêtre du fief : bouton de garnison")
	m.queue_redraw()
	check(RealmPanel.place_lines(s, tour).has("Votre fief"), "infobulle du fief")
	root.remove_child(m)
	m.free()
	CampaignState.current = null
	print("Fenêtres : OK")
