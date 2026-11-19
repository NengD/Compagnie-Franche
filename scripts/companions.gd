class_name Companions
extends RefCounted
## Compagnons de la compagnie (CampaignState.companions, sauvegardé) : des héros qu'on engage
## dans certaines villes, un de chaque sorte au plus, chacun avec un petit arbre de compétences
## comme le capitaine (captain.gd) :
## - sergent : moral et discipline (moral maximal, désertions, anciens prisonniers) ;
## - chirurgien : moins de morts (plus de tombés relevés, plus de blessés graves sauvés, guérison) ;
## - éclaireur : voit plus loin sur la carte (repère les bandits cachés), marche plus vite, et
##   donne un meilleur aperçu de l'ennemi avant la bataille ;
## - quartier-maître : vivres, solde et rançons.
## Ils gagnent de l'expérience aux batailles, peuvent y être blessés (sans effet jusqu'à leur
## guérison) et touchent une solde (ajoutée à CampaignState.daily_wage).
## Les effets sont des fonctions statiques qui prennent la campagne : 1 (ou 0) sans compagnon.

const KINDS := {
	"sergeant": {"name": "Sergent", "role": "moral et discipline", "cost": 120, "wage": 2.0,
		"names": ["Gautier Poing-de-Fer", "Mahaut la Rude", "Odon Barbe-Grise", "Renaud le Tors"],
		"skills": {
			"drill": {"name": "Exercice", "text": "moral maximal des régiments +5 %"},
			"discipline": {"name": "Discipline", "text": "désertions (solde impayée, famine) -20 %"},
			"breaking": {"name": "Dressage", "text": "prisonniers : +10 % de volontaires, rancœur oubliée plus vite"},
		}},
	"surgeon": {"name": "Chirurgien", "role": "moins de morts, plus de blessés relevés", "cost": 150, "wage": 2.5,
		"names": ["Maître Anselme", "Ysabeau la Savante", "Frère Clément", "Maître Josse"],
		"skills": {
			"field": {"name": "Brancardiers", "text": "+5 % de tombés relevés après la bataille"},
			"wagons": {"name": "Chariots", "text": "+5 % de blessés graves sauvés"},
			"care": {"name": "Soins", "text": "les blessés guérissent 30 % plus vite"},
		}},
	"scout": {"name": "Éclaireur", "role": "voit plus loin et renseigne sur l'ennemi", "cost": 100, "wage": 1.5,
		"names": ["Colin Pied-Léger", "Aude la Rousse", "Tiphaine l'Écureuil", "Baudouin le Muet"],
		"skills": {
			"eyes": {"name": "Œil de lynx", "text": "repère les bandits cachés 25 % plus loin"},
			"tracks": {"name": "Pistes", "text": "la compagnie marche 5 % plus vite"},
			"spies": {"name": "Espions", "text": "aperçu de l'ennemi : effectifs exacts et rangs"},
		}},
	"quartermaster": {"name": "Quartier-maître", "role": "vivres et solde moins chers", "cost": 110, "wage": 2.0,
		"names": ["Guillemette Bourse-Plate", "Lambert le Compteur", "Jacquet Sac-à-Grain", "Pernelle l'Avisée"],
		"skills": {
			"rations": {"name": "Rations", "text": "vivres -10 %"},
			"pay": {"name": "Trésorier", "text": "solde de la compagnie -4 %"},
			"haggle": {"name": "Marchandage", "text": "rançons +15 %"},
		}},
}
const ORDER := ["sergeant", "surgeon", "scout", "quartermaster"]
## Compagnons qu'on trouve dans chaque ville (index de CampaignState.TOWNS).
const TOWN_OFFERS := {
	0: ["quartermaster", "scout"], 1: ["sergeant", "surgeon"], 2: ["scout", "sergeant"],
	3: ["quartermaster", "surgeon"], 4: ["sergeant"], 5: ["surgeon"], 6: ["quartermaster", "scout"],
}
const SKILL_MAX := 3
const LEVEL_XP := 100.0
const MAX_LEVEL := 1 + SKILL_MAX * 3
const XP_BATTLE := 30.0
const XP_VICTORY := 30.0
const WOUND_DAYS := 6
const WOUND_WIN := 0.06 ## Risque d'être blessé dans une victoire...
const WOUND_LOSS := 0.2 ## ... dans une défaite
const WAGE_LEVEL := 0.5 ## Solde en plus par niveau au-delà du premier

var list: Array[Dictionary] = [] ## {"kind", "name", "level", "xp", "points", "skills", "wounded_until"}


func to_dict() -> Array:
	return list.duplicate(true)


static func from_dict(v: Variant) -> Companions:
	var c := Companions.new()
	if not v is Array:
		return c
	for d in v:
		if not d is Dictionary or not KINDS.has(str(d.get("kind", ""))) or not c.get_kind(str(d["kind"])).is_empty():
			continue
		var kind := str(d["kind"])
		var m := make(kind, str(d.get("name", KINDS[kind]["names"][0])))
		m["level"] = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
		m["xp"] = clampf(float(d.get("xp", 0.0)), 0.0, LEVEL_XP * MAX_LEVEL)
		m["points"] = clampi(int(d.get("points", 0)), 0, MAX_LEVEL)
		m["wounded_until"] = maxi(0, int(d.get("wounded_until", 0)))
		var sk: Variant = d.get("skills", {})
		if sk is Dictionary:
			for k in m["skills"]:
				m["skills"][k] = clampi(int(sk.get(k, 0)), 0, SKILL_MAX)
		c.list.append(m)
	return c


static func make(kind: String, name: String) -> Dictionary:
	var skills := {}
	for k in KINDS[kind]["skills"]:
		skills[k] = 0
	return {"kind": kind, "name": name, "level": 1, "xp": 0.0, "points": 0, "skills": skills, "wounded_until": 0}


func get_kind(kind: String) -> Dictionary:
	for m in list:
		if str(m["kind"]) == kind:
			return m
	return {}


static func available(m: Dictionary, day: int) -> bool:
	return not m.is_empty() and day >= int(m["wounded_until"])


## Niveau d'une compétence d'un compagnon présent et valide ; -1 s'il est absent ou blessé.
static func skill(state: CampaignState, kind: String, sk: String) -> int:
	if state == null or state.companions == null:
		return -1
	var m := state.companions.get_kind(kind)
	if not available(m, state.day):
		return -1
	return int(m["skills"].get(sk, 0))


static func has(state: CampaignState, kind: String) -> bool:
	return state != null and state.companions != null and available(state.companions.get_kind(kind), state.day)


# ---------------------------------------------------------------- Engager, renvoyer, apprendre

## Nom du compagnon d'une sorte proposé dans cette campagne (stable, sans toucher au rng).
static func offer_name(state: CampaignState, kind: String) -> String:
	var names: Array = KINDS[kind]["names"]
	return str(names[posmod(hash([state.rng.seed, kind]), names.size())])


static func hire_cost(state: CampaignState, kind: String) -> int:
	return roundi(float(KINDS[kind]["cost"]) * Difficulty.value(state.difficulty, "wage"))


## Compagnons proposés dans une ville (ceux qu'on n'a pas déjà).
static func offers(state: CampaignState, town: int) -> Array[String]:
	var out: Array[String] = []
	for kind in TOWN_OFFERS.get(town, []):
		if state.companions.get_kind(kind).is_empty():
			out.append(str(kind))
	return out


## Engage un compagnon dans la ville où la compagnie est entrée. Renvoie un message d'erreur ou "".
static func hire(state: CampaignState, kind: String) -> String:
	var town := state.overworld.inside
	if town < 0 or town >= CampaignState.TOWNS.size():
		return "On engage les compagnons en ville."
	var closed := state.closed_message(town)
	if closed != "":
		return closed
	if not kind in offers(state, town):
		return "Personne de ce métier ne cherche d'emploi ici."
	var cost := hire_cost(state, kind)
	if state.gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	state.gold -= cost
	var m := make(kind, offer_name(state, kind))
	state.companions.list.append(m)
	state.add_log("Jour %d : %s, %s, rejoint la compagnie (-%d écus)." % [state.day, m["name"], str(KINDS[kind]["name"]).to_lower(), cost])
	return ""


static func dismiss(state: CampaignState, kind: String) -> String:
	var m := state.companions.get_kind(kind)
	if m.is_empty():
		return "Ce compagnon n'est plus là."
	state.companions.list.erase(m)
	state.add_log("Jour %d : %s quitte la compagnie." % [state.day, m["name"]])
	return ""


## Apprend une compétence (un point). Renvoie un message d'erreur ou "".
static func learn(state: CampaignState, kind: String, sk: String) -> String:
	var m := state.companions.get_kind(kind)
	if m.is_empty() or not m["skills"].has(sk):
		return "Compétence inconnue."
	if int(m["points"]) <= 0:
		return "Aucun point de compétence."
	if int(m["skills"][sk]) >= SKILL_MAX:
		return "%s est déjà au maximum." % KINDS[kind]["skills"][sk]["name"]
	m["points"] = int(m["points"]) - 1
	m["skills"][sk] = int(m["skills"][sk]) + 1
	return ""


static func wage_of(state: CampaignState, m: Dictionary) -> float:
	return (float(KINDS[str(m["kind"])]["wage"]) + WAGE_LEVEL * (int(m["level"]) - 1)) * Difficulty.value(state.difficulty, "wage")


## Solde quotidienne des compagnons (même blessés).
static func daily_wage(state: CampaignState) -> float:
	if state.companions == null:
		return 0.0
	var w := 0.0
	for m in state.companions.list:
		w += wage_of(state, m)
	return w


# ---------------------------------------------------------------- Bataille

## Après une bataille de campagne : expérience, niveaux, blessures. Renvoie une phrase.
func after_battle(state: CampaignState, victory: bool) -> String:
	var out := ""
	for m in list:
		if not available(m, state.day):
			continue
		m["xp"] = minf(float(m["xp"]) + XP_BATTLE + (XP_VICTORY if victory else 0.0), LEVEL_XP * MAX_LEVEL)
		while int(m["level"]) < MAX_LEVEL and float(m["xp"]) >= LEVEL_XP * int(m["level"]):
			m["level"] = int(m["level"]) + 1
			m["points"] = int(m["points"]) + 1
			out += " %s passe au niveau %d." % [m["name"], int(m["level"])]
		var risk := WOUND_WIN if victory else WOUND_LOSS
		if str(m["kind"]) != "surgeon" and has(state, "surgeon"):
			risk *= 0.5 # Le chirurgien soigne aussi les siens
		if state.rng.randf() < risk:
			m["wounded_until"] = state.day + 1 + WOUND_DAYS
			out += " %s est blessé : absent jusqu'au jour %d." % [m["name"], int(m["wounded_until"])]
	return out


## Multiplicateur du moral maximal des régiments (sergent).
static func morale_factor(state: CampaignState) -> float:
	var k := skill(state, "sergeant", "drill")
	return 1.0 if k < 0 else 1.05 + 0.05 * k


## Part des tombés relevés blessés après la bataille (CampaignState.finish_battle).
static func recover_rate(state: CampaignState, victory: bool) -> float:
	var base := CampaignState.WOUNDED_RECOVER if victory else 0.0
	var k := skill(state, "surgeon", "field")
	if k < 0:
		return base
	return base + (0.05 if victory else 0.15) + 0.05 * k


## Part des tombés non relevés sauvés dans les chariots, en plus (supplies.gd).
static func wagon_bonus(state: CampaignState) -> float:
	var k := skill(state, "surgeon", "wagons")
	return 0.0 if k < 0 else 0.03 + 0.05 * k


static func heal_factor(state: CampaignState) -> float:
	var k := skill(state, "surgeon", "care")
	return 1.0 if k < 0 else 1.2 + 0.3 * k


# ---------------------------------------------------------------- Campagne

## Multiplicateur des désertions (solde impayée, famine).
static func desert_factor(state: CampaignState) -> float:
	var k := skill(state, "sergeant", "discipline")
	return 1.0 if k < 0 else maxf(0.2, 0.8 - 0.2 * k)


## Part des prisonniers d'un groupe qui acceptent de servir.
static func enlist_share(state: CampaignState) -> float:
	var k := skill(state, "sergeant", "breaking")
	return Prisoners.ENLIST_SHARE + (0.0 if k < 0 else 0.05 + 0.1 * k)


## Vitesse à laquelle s'efface la rancœur des prisonniers enrôlés.
static func sullen_speed(state: CampaignState) -> float:
	var k := skill(state, "sergeant", "breaking")
	return 1.0 if k < 0 else 1.5 + 0.5 * k


static func food_factor(state: CampaignState) -> float:
	var k := skill(state, "quartermaster", "rations")
	return 1.0 if k < 0 else 0.9 - 0.1 * k


static func wage_factor(state: CampaignState) -> float:
	var k := skill(state, "quartermaster", "pay")
	return 1.0 if k < 0 else 0.97 - 0.04 * k


static func ransom_factor(state: CampaignState) -> float:
	var k := skill(state, "quartermaster", "haggle")
	return 1.0 if k < 0 else 1.05 + 0.15 * k


static func pace_factor(state: CampaignState) -> float:
	var k := skill(state, "scout", "tracks")
	return 1.0 if k < 0 else 1.0 + 0.05 * k


## Portée à laquelle l'éclaireur repère les groupes cachés (0 sans éclaireur).
static func sight(state: CampaignState) -> float:
	var k := skill(state, "scout", "eyes")
	return 0.0 if k < 0 else Overworld.SIGHT * (1.0 + 0.25 * k)


## L'éclaireur repère les groupes cachés à sa portée (Supplies.tick, après leur comportement :
## ils restent visibles jusqu'au prochain pas).
static func spot(state: CampaignState, ow: Overworld) -> void:
	var r := sight(state)
	if r <= 0.0:
		return
	for p in ow.parties:
		if p.hidden and p.pos.distance_to(ow.player.pos) <= r:
			p.hidden = false


## Rapport de l'éclaireur sur des troupes ({"type", "men", "xp" ou "rank"}) : "" sans éclaireur.
## Base : régiments par type et effectif à peu près ; Espions : effectifs exacts et rangs.
static func scout_report(state: CampaignState, troops: Array) -> String:
	var k := skill(state, "scout", "spies")
	if k < 0 or troops.is_empty():
		return ""
	var by_type := {}
	var ranks := [0, 0, 0]
	for r in troops:
		var t := str(r.get("type", ""))
		if not UnitTypes.STATS.has(t) or int(r.get("men", 0)) <= 0:
			continue
		by_type[t] = int(by_type.get(t, 0)) + int(r["men"])
		ranks[CampaignState.rank_of(r)] += int(r["men"])
	var parts: Array[String] = []
	for t in UnitTypes.ORDER:
		if by_type.has(t):
			var n := int(by_type[t])
			parts.append(CampaignState.type_count(t, n if k >= 1 else maxi(5, roundi(n / 5.0) * 5)))
	if parts.is_empty():
		return ""
	var s := "%s compte %s%s" % [state.companions.get_kind("scout")["name"], "" if k >= 1 else "environ ", ", ".join(parts)]
	if k >= 1 and ranks[1] + ranks[2] > 0:
		s += " (dont %d aguerris et %d vétérans)" % [ranks[1], ranks[2]]
	return s + "."
