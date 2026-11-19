class_name Quests
extends RefCounted
## Quêtes variées, données par les villes et les seigneurs des châteaux, en plus des contrats :
##   lair     nettoyer un repaire de bandits (ruines ou repaire de la carte) : la bande attend sur
##            place, on l'attaque depuis le lieu (bataille contre un groupe, sans prime) ;
##   escort   escorter un noble jusqu'à une ville (le rendre dans la fenêtre de la ville ; une
##            bataille perdue en route, et il est pris) ;
##   hold     tenir un pont ou un gué X jours : la compagnie campe sur place, chaque jour une bande
##            de pillards (Party « bandits » lancée sur elle, menée par PartyAI) vient l'en déloger ;
##            s'éloigner remet le compte à zéro ;
##   deliver  livrer des marchandises (trade.gd) à une ville qui en manque.
## Chaque quête a une récompense (or, réputation auprès de qui la donne, un peu de renommée) et une
## date limite ; suivi dans l'onglet « Quêtes » de la carte. Une offre reste OFFER_DAYS jours.
## Le hasard vient de rng (propre aux quêtes) : le reste de la campagne ne change pas.
## Branché par CampaignState (bloc « Domaine ») ; panneau : realm_panel.gd.

const KINDS := ["lair", "escort", "hold", "deliver"]
const KIND_NAMES := {"lair": "Repaire", "escort": "Escorte", "hold": "Tenir", "deliver": "Livraison"}
const MAX_ACTIVE := 3
const MAX_OFFERS := 8
const OFFER_DAYS := 10
const OFFER_CHANCE := 0.25 ## Chance quotidienne qu'un donneur sans offre en propose une
const REP_DONE := 5
const REP_FAIL := -5
const FAME_DONE := 3
const HOLD_RADIUS := 90.0 ## Distance au pont à laquelle la compagnie le tient
const RAID_SPAWN := 220.0 ## Les pillards apparaissent à peu près à tant du pont
const QUEST_RANGE := 1500.0 ## Distance maximale entre le donneur et le lieu de la quête
const NOBLES := ["le jeune sire de Montrevel", "dame Aude de Saint-Clair", "le chanoine Thibaut", "messire Enguerrand", "la veuve de Lormes", "le sénéchal Gauvain"]
const BAND_NAMES := ["les brigands de %s", "la bande terrée à %s", "les écorcheurs de %s"]

var offers: Array[Dictionary] = []
var active: Array[Dictionary] = []
var next_id := 1
var done := 0 ## Quêtes réussies
var rng := RandomNumberGenerator.new()


static func place_name(i: int) -> String:
	return str(MapData.place(i)["name"])


## Faction d'un donneur (ville ou château).
static func giver_faction(c: CampaignState, i: int) -> int:
	if i >= 0 and i < CampaignState.TOWNS.size():
		return c.town_owner(i)
	return c.fiefs.owner_of(i)


## Lieux qui donnent des quêtes : les villes et les châteaux des seigneurs (pas ceux de la compagnie).
static func givers(c: CampaignState) -> Array[int]:
	var out: Array[int] = []
	for t in CampaignState.TOWNS.size():
		out.append(t)
	for i in PartyAI.places_of(["castle"]):
		if c.fiefs.owner_of(i) >= 0:
			out.append(i)
	return out


func by_id(list: Array[Dictionary], id: int) -> Dictionary:
	for q in list:
		if int(q["id"]) == id:
			return q
	return {}


func offers_at(giver: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in offers:
		if int(q["giver"]) == giver:
			out.append(q)
	return out


## Lieu déjà visé par une offre ou une quête en cours ?
func target_taken(i: int) -> bool:
	for q in offers + active:
		if int(q.get("target", -1)) == i and str(q["kind"]) in ["lair", "hold"]:
			return true
	return false


func near_places(giver: int, kinds: Array) -> Array[int]:
	var out: Array[int] = []
	var at := MapData.place_pos(giver)
	for i in PartyAI.places_of(kinds):
		if i != giver and MapData.place_pos(i).distance_to(at) <= QUEST_RANGE and not target_taken(i):
			out.append(i)
	return out


# ---------------------------------------------------------------- Offres

## Tire une offre pour un donneur ({} si aucune ne convient).
func make_offer(c: CampaignState, giver: int) -> Dictionary:
	var kinds: Array[String] = []
	var lairs := near_places(giver, ["lair", "ruins"])
	var bridges := near_places(giver, ["bridge", "ford"])
	var towns: Array[int] = []
	for t in CampaignState.TOWNS.size():
		var d := MapData.place_pos(t).distance_to(MapData.place_pos(giver))
		if t != giver and d >= 600.0 and d <= 2400.0:
			towns.append(t)
	if not lairs.is_empty():
		kinds.append("lair")
	if not towns.is_empty():
		kinds.append("escort")
	if not bridges.is_empty():
		kinds.append("hold")
	if giver < CampaignState.TOWNS.size():
		kinds.append("deliver")
	if kinds.is_empty():
		return {}
	var kind := kinds[rng.randi() % kinds.size()]
	var q := {"id": next_id, "kind": kind, "giver": giver, "faction": giver_faction(c, giver), "expires": c.day + OFFER_DAYS}
	var k := Difficulty.value(c.difficulty, "reward")
	match kind:
		"lair":
			var t := lairs[rng.randi() % lairs.size()]
			@warning_ignore("integer_division")
			var men := clampi(rng.randi_range(25, 45) + c.day / 3, 25, 90)
			@warning_ignore("integer_division")
			var archers := men / 3
			@warning_ignore("integer_division")
			var heavy := men / 6 if c.day >= 30 else 0
			var band: Array = [{"type": "spear", "men": men - archers - heavy, "xp": rng.randf_range(30.0, 110.0)},
				{"type": "archer", "men": archers, "xp": rng.randf_range(30.0, 110.0)}]
			if heavy > 0:
				band.append({"type": "men_at_arms", "men": heavy, "xp": 100.0})
			q.merge({"target": t, "band": band, "band_name": str(BAND_NAMES[rng.randi() % BAND_NAMES.size()]) % place_name(t),
				"days": 12, "reward": int(round((100 + men * 5) * k / 10.0)) * 10})
			q["title"] = "Nettoyer %s" % place_name(t)
			q["text"] = "Une bande de %d brigands s'est terrée à %s et rançonne le pays. Allez-y et détruisez-la." % [men, place_name(t)]
		"escort":
			var t := towns[rng.randi() % towns.size()]
			var dist := MapData.place_pos(t).distance_to(MapData.place_pos(giver))
			var noble := str(NOBLES[rng.randi() % NOBLES.size()])
			q.merge({"target": t, "noble": noble, "days": ceili(dist / 380.0) + 4,
				"reward": int(round((80 + dist / 8.0) * k / 10.0)) * 10})
			q["title"] = "Escorter %s jusqu'à %s" % [noble, place_name(t)]
			q["text"] = "%s doit se rendre à %s sans tomber aux mains des brigands. La compagnie l'emmène et le remet à bon port." % [CampaignState.cap_first(noble), place_name(t)]
		"hold":
			var t := bridges[rng.randi() % bridges.size()]
			var need := rng.randi_range(2, 3)
			q.merge({"target": t, "need": need, "held": 0, "camp": false, "raiders": -1, "days": 8 + need,
				"reward": int(round((180 + need * 140) * k / 10.0)) * 10})
			q["title"] = "Tenir %s %s" % [place_name(t), CampaignState.plural(need, "jour", "jours")]
			q["text"] = "Des pillards veulent forcer le passage de %s. Campez-y %s d'affilée et repoussez leurs bandes." % [place_name(t), CampaignState.plural(need, "jour", "jours")]
		"deliver":
			var lacks: Array = Trade.LACKS[giver]
			var g := str(lacks[rng.randi() % lacks.size()])
			var qty := rng.randi_range(2, 5) * 5
			q.merge({"target": giver, "good": g, "qty": qty, "days": 12,
				"reward": int(round(qty * float(Trade.BASE_PRICE[g]) * 2.0 * k / 10.0)) * 10})
			q["title"] = "Livrer %d %s à %s" % [qty, Trade.UNITS[g], place_name(giver)]
			q["text"] = "%s manque de %s. Achetez-en là où on le produit et rapportez %d charges." % [place_name(giver), Trade.good_name(g), qty]
	next_id += 1
	return q


## Tire de nouvelles offres (une au plus par donneur) et retire les offres périmées.
func refresh_offers(c: CampaignState, chance := OFFER_CHANCE) -> void:
	offers = offers.filter(func(q: Dictionary) -> bool: return int(q["expires"]) >= c.day)
	for g in givers(c):
		if offers.size() >= MAX_OFFERS:
			break
		if not offers_at(g).is_empty() or c.faction_closed(giver_faction(c, g)):
			continue
		if rng.randf() >= chance:
			continue
		var q := make_offer(c, g)
		if not q.is_empty():
			offers.append(q)


# ---------------------------------------------------------------- Quêtes en cours

func accept_refusal(c: CampaignState, id: int) -> String:
	var q := by_id(offers, id)
	if q.is_empty():
		return "Cette quête n'est plus proposée."
	if c.overworld.inside != int(q["giver"]):
		return "Elle se prend à %s." % place_name(int(q["giver"]))
	if active.size() >= MAX_ACTIVE:
		return "La compagnie mène déjà %d quêtes." % MAX_ACTIVE
	if c.faction_closed(int(q["faction"])):
		return c.closed_message(clampi(int(q["giver"]), 0, CampaignState.TOWNS.size() - 1)) if int(q["giver"]) < CampaignState.TOWNS.size() else "Ce seigneur ne veut plus de vous."
	if str(q["kind"]) == "escort" and c.is_destroyed():
		return "Sans troupes, personne ne vous confie sa vie."
	return ""


func accept(c: CampaignState, id: int) -> String:
	var why := accept_refusal(c, id)
	if why != "":
		return why
	var q := by_id(offers, id)
	offers.erase(q)
	q["deadline"] = c.day + int(q["days"])
	active.append(q)
	c.add_log("Jour %d : quête acceptée : %s (avant le jour %d)." % [c.day, q["title"], int(q["deadline"])])
	return ""


func complete(c: CampaignState, q: Dictionary) -> String:
	active.erase(q)
	done += 1
	var pay := int(q["reward"])
	c.gold += pay
	c.gold_earned += pay
	c.fame += FAME_DONE
	var f := int(q.get("faction", -1))
	var msg := "Quête réussie : %s. %d écus, renommée +%d" % [q["title"], pay, FAME_DONE]
	if f >= 0:
		c.change_reputation(f, REP_DONE)
		msg += ", %s %+d" % [CampaignState.FACTIONS[f]["short"], REP_DONE]
	msg += "."
	c.add_log("Jour %d : %s" % [c.day, msg])
	return msg


func fail(c: CampaignState, q: Dictionary, why: String) -> String:
	active.erase(q)
	var f := int(q.get("faction", -1))
	var msg := "Quête manquée : %s (%s)." % [q["title"], why]
	if f >= 0:
		c.change_reputation(f, REP_FAIL)
		msg += " Réputation : %s %+d." % [CampaignState.FACTIONS[f]["short"], REP_FAIL]
	c.add_log("Jour %d : %s" % [c.day, msg])
	return msg


func abandon(c: CampaignState, id: int) -> String:
	var q := by_id(active, id)
	if q.is_empty():
		return "Quête inconnue."
	fail(c, q, "abandonnée")
	return ""


## Peut-on rendre la quête ici et maintenant ? ("" : oui ; escorte et livraison, dans la ville visée)
func turn_in_refusal(c: CampaignState, q: Dictionary) -> String:
	if not str(q["kind"]) in ["escort", "deliver"]:
		return "Cette quête ne se rend pas ainsi."
	if c.overworld.inside != int(q["target"]):
		return "Il faut être à %s." % place_name(int(q["target"]))
	if str(q["kind"]) == "deliver" and c.trade.carried(str(q["good"])) < int(q["qty"]):
		return "Il vous faut %d %s (vous en portez %d)." % [int(q["qty"]), Trade.UNITS[q["good"]], c.trade.carried(str(q["good"]))]
	return ""


func turn_in(c: CampaignState, id: int) -> String:
	var q := by_id(active, id)
	if q.is_empty():
		return "Quête inconnue."
	var why := turn_in_refusal(c, q)
	if why != "":
		return why
	if str(q["kind"]) == "deliver":
		c.trade.take(str(q["good"]), int(q["qty"]))
	complete(c, q)
	return ""


## Quêtes à rendre dans un lieu (escorte et livraison dont c'est la destination).
func due_at(place: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in active:
		if str(q["kind"]) in ["escort", "deliver"] and int(q["target"]) == place:
			out.append(q)
	return out


## Quête « repaire » ou « tenir » dont ce lieu est la cible ({} sinon).
func quest_at(place: int) -> Dictionary:
	for q in active:
		if str(q["kind"]) in ["lair", "hold"] and int(q["target"]) == place:
			return q
	return {}


static func band_men(q: Dictionary) -> int:
	var n := 0
	for r in q.get("band", []):
		n += int(r["men"])
	return n


## Bataille contre la bande du repaire (la compagnie est au repaire). Renvoie une erreur ou "".
func attack_lair(c: CampaignState, id: int) -> String:
	var q := by_id(active, id)
	if q.is_empty() or str(q["kind"]) != "lair":
		return "Quête inconnue."
	if c.overworld.inside != int(q["target"]):
		return "Il faut être à %s." % place_name(int(q["target"]))
	if c.is_destroyed():
		return "Vous n'avez plus de troupes."
	if c.in_battle():
		return "Une bataille vous attend déjà."
	var band := Party.new()
	band.id = -100 - int(q["id"]) # Groupe hors du registre de la carte
	band.kind = "bandits"
	band.name = str(q["band_name"])
	for r in q["band"]:
		band.troops.append({"type": str(r["type"]), "men": int(r["men"]), "xp": float(r.get("xp", 0.0))})
	var k := c.party_contract(band, MapData.battle_terrain_at(MapData.place_pos(int(q["target"]))))
	k.erase("party_id")
	k["quest"] = int(q["id"])
	k["title"] = "Repaire : %s" % band.name
	k["text"] = "La compagnie surprend %s dans leur repaire." % band.name
	c.pending = k
	return ""


## Camper sur le pont (ou le gué) d'une quête « tenir » : la compagnie sort des murs et attend.
## Une première bande de pillards se met en route.
func start_camp(c: CampaignState, id: int) -> String:
	var q := by_id(active, id)
	if q.is_empty() or str(q["kind"]) != "hold":
		return "Quête inconnue."
	var at := MapData.place_pos(int(q["target"]))
	if c.overworld.player.pos.distance_to(at) > HOLD_RADIUS:
		return "Il faut être à %s." % place_name(int(q["target"]))
	if c.is_destroyed():
		return "Vous n'avez plus de troupes."
	q["camp"] = true
	c.overworld.inside = -1 # Hors des murs : les pillards peuvent l'attaquer
	c.overworld.halt()
	c.overworld.player.pos = at
	send_raiders(c, q)
	c.add_log("Jour %d : la compagnie campe à %s." % [c.day, place_name(int(q["target"]))])
	return ""


## Lance une bande de pillards sur la compagnie qui tient le pont (si la précédente n'est plus là).
func send_raiders(c: CampaignState, q: Dictionary) -> Party:
	var ow := c.overworld
	var old := ow.by_id(c, int(q.get("raiders", -1)))
	if old != null and not old.is_dead():
		return null
	var at := MapData.place_pos(int(q["target"]))
	var p := Party.new()
	p.kind = "bandits"
	p.name = "les pillards de %s" % place_name(int(q["target"]))
	var men := clampi(int(c.total_men() * 0.45), 20, 90)
	@warning_ignore("integer_division")
	var archers := men * 2 / 5
	p.troops = [{"type": "spear", "men": men - archers, "xp": rng.randf_range(20.0, 90.0)},
		{"type": "archer", "men": archers, "xp": rng.randf_range(20.0, 90.0)}]
	var spot := at
	for i in 8:
		var cand := MapData.walkable_point(at + Vector2.RIGHT.rotated(rng.randf() * TAU) * RAID_SPAWN)
		if MapData.walkable(cand) and cand.distance_to(at) > RAID_SPAWN * 0.6:
			spot = cand
			break
	p.pos = spot
	p.base = spot
	p.gold = rng.randi_range(2, 6) * 10
	ow.add(c, p)
	p.go(MapData.find_path(p.pos, ow.player.pos)) # (go efface la cible : elle vient après)
	p.target_id = ow.player.id
	p.state = "chase"
	q["raiders"] = p.id
	return p


## Un jour passe : offres, dates limites, pont tenu.
func day(c: CampaignState) -> void:
	for q in active.duplicate():
		if str(q["kind"]) == "hold" and bool(q.get("camp", false)):
			var at := MapData.place_pos(int(q["target"]))
			if c.overworld.player.pos.distance_to(at) <= HOLD_RADIUS and not c.is_destroyed():
				q["held"] = int(q["held"]) + 1
				if int(q["held"]) >= int(q["need"]):
					complete(c, q)
					continue
				send_raiders(c, q)
			else:
				q["camp"] = false
				q["held"] = 0
				c.add_log("Jour %d : la compagnie a quitté %s : il faudra recommencer à le tenir." % [c.day, place_name(int(q["target"]))])
		if c.day > int(q["deadline"]):
			fail(c, q, "trop tard")
	refresh_offers(c)


## Après une bataille : repaire nettoyé (ou bande entamée), noble pris dans une défaite.
func after_battle(c: CampaignState, victory: bool, killed: int) -> String:
	var notes: Array[String] = []
	var qid := int(c.pending.get("quest", -1))
	var q := by_id(active, qid) if qid >= 0 else {}
	if not q.is_empty() and str(q["kind"]) == "lair":
		if victory:
			notes.append(complete(c, q))
		else:
			var before := band_men(q)
			var keep := clampf(1.0 - float(killed) / maxf(1.0, before), 0.0, 1.0)
			for r in q["band"]:
				r["men"] = maxi(1, int(round(int(r["men"]) * keep)))
	if not victory:
		for e in active.duplicate():
			if str(e["kind"]) == "escort":
				notes.append(fail(c, e, "%s est pris par l'ennemi" % e["noble"]))
	return (" " + " ".join(notes)) if not notes.is_empty() else ""


## Ligne de suivi d'une quête en cours.
func status_line(c: CampaignState, q: Dictionary) -> String:
	var left := int(q["deadline"]) - c.day
	var when := "avant le jour %d (%s)" % [int(q["deadline"]), CampaignState.plural(maxi(0, left), "jour", "jours")]
	match str(q["kind"]):
		"lair":
			return "Aller à %s et vaincre %s (%s), %s." % [place_name(int(q["target"])), q["band_name"], CampaignState.plural(band_men(q), "homme", "hommes"), when]
		"escort":
			return "Mener %s à %s, %s." % [q["noble"], place_name(int(q["target"])), when]
		"hold":
			var s := "Camper à %s : %d / %d jours tenus" % [place_name(int(q["target"])), int(q["held"]), int(q["need"])]
			s += " (campement dressé)" if bool(q.get("camp", false)) else " (allez-y et dressez le camp)"
			return "%s, %s." % [s, when]
		"deliver":
			return "Porter %d %s à %s (vous en portez %d), %s." % [int(q["qty"]), Trade.UNITS[q["good"]], place_name(int(q["target"])), c.trade.carried(str(q["good"])), when]
	return when


func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(true), "active": active.duplicate(true), "next_id": next_id, "done": done,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


## Relit une quête sauvegardée ({} si elle est invalide).
static func quest_from_dict(v: Variant) -> Dictionary:
	if not v is Dictionary or not str(v.get("kind", "")) in KINDS:
		return {}
	var q: Dictionary = (v as Dictionary).duplicate(true)
	for key in ["id", "giver", "faction", "target", "days", "reward", "expires", "deadline", "need", "held", "qty", "raiders"]:
		if q.has(key):
			q[key] = int(q[key])
	var n := MapData.place_count()
	if int(q.get("giver", -1)) < 0 or int(q["giver"]) >= n or int(q.get("target", -1)) < 0 or int(q["target"]) >= n:
		return {}
	if q["kind"] == "deliver" and not str(q.get("good", "")) in Trade.GOODS:
		return {}
	if q["kind"] == "lair":
		var band: Array = []
		for r in q.get("band", []):
			if r is Dictionary and UnitTypes.STATS.has(str(r.get("type", ""))):
				band.append({"type": str(r["type"]), "men": maxi(1, int(r.get("men", 1))), "xp": float(r.get("xp", 0.0))})
		if band.is_empty():
			return {}
		q["band"] = band
	return q


static func from_dict(v: Variant, seed_value: int) -> Quests:
	var out := Quests.new()
	out.rng.seed = hash([seed_value, "quêtes"])
	if not v is Dictionary:
		return out
	for x in v.get("offers", []):
		var q := quest_from_dict(x)
		if not q.is_empty():
			out.offers.append(q)
	for x in v.get("active", []):
		var q := quest_from_dict(x)
		if not q.is_empty() and q.has("deadline"):
			out.active.append(q)
	out.next_id = maxi(1, int(v.get("next_id", 1)))
	out.done = maxi(0, int(v.get("done", 0)))
	if v.has("rng_state"):
		out.rng.seed = str(v.get("rng_seed", "1")).to_int()
		out.rng.state = str(v.get("rng_state", "1")).to_int()
	return out
