class_name Equipment
extends RefCounted
## Équipement de régiment : trois pièces (casque, arme, armure), chacune en trois qualités.
## Acheté en ville (fenêtre de la ville sur la carte de campagne) et gardé dans l'entrée de
## compagnie (« gear » : liste d'identifiants, au plus un par pièce). Ses effets en bataille
## passent par Traits.apply_to() (multiplicateurs de statistiques).
##
## Améliorer une pièce remplace l'ancienne : on ne paie que la différence de prix. Les qualités
## supérieures se méritent : la 2 demande des aguerris, la 3 des vétérans (rang du régiment).

const SLOTS := ["helmet", "weapon", "armor"]
const SLOT_NAMES := {"helmet": "casque", "weapon": "armes", "armor": "armure"}
const MAX_TIER := 3

## « cost » : écus par homme du régiment au complet (modulé par les prix de la ville).
## « rank » : rang minimal du régiment (CampaignState.RANK_XP) pour l'acheter.
const ITEMS := {
	"helmet_1": {"slot": "helmet", "tier": 1, "rank": 0, "name": "Chapels de fer", "short": "chapels de fer",
		"text": "vie +8 %, moral +5 %", "cost": 2, "stats": {"hp": 1.08, "morale": 1.05}},
	"helmet_2": {"slot": "helmet", "tier": 2, "rank": 1, "name": "Bassinets", "short": "bassinets",
		"text": "vie +15 %, moral +10 %", "cost": 4, "stats": {"hp": 1.15, "morale": 1.1}},
	"helmet_3": {"slot": "helmet", "tier": 3, "rank": 2, "name": "Grands bassinets à visière", "short": "grands bassinets",
		"text": "vie +22 %, moral +15 %", "cost": 7, "stats": {"hp": 1.22, "morale": 1.15}},
	"weapon_1": {"slot": "weapon", "tier": 1, "rank": 0, "name": "Armes de bonne trempe", "short": "bonnes armes",
		"text": "dégâts +10 %", "cost": 3, "stats": {"damage": 1.1, "ranged_damage": 1.1}},
	"weapon_2": {"slot": "weapon", "tier": 2, "rank": 1, "name": "Armes de maître", "short": "armes de maître",
		"text": "dégâts +20 %", "cost": 6, "stats": {"damage": 1.2, "ranged_damage": 1.2}},
	"weapon_3": {"slot": "weapon", "tier": 3, "rank": 2, "name": "Armes de Milan", "short": "armes de Milan",
		"text": "dégâts +30 %", "cost": 10, "stats": {"damage": 1.3, "ranged_damage": 1.3}},
	"armor_1": {"slot": "armor", "tier": 1, "rank": 0, "name": "Gambisons", "short": "gambisons",
		"text": "dégâts des flèches -15 %, vie +5 %", "cost": 3, "stats": {"arrow_armor": 0.85, "hp": 1.05}},
	"armor_2": {"slot": "armor", "tier": 2, "rank": 1, "name": "Brigandines", "short": "brigandines",
		"text": "dégâts des flèches -30 %, vie +12 %, vitesse -3 %", "cost": 6, "stats": {"arrow_armor": 0.7, "hp": 1.12, "speed": 0.97}},
	"armor_3": {"slot": "armor", "tier": 3, "rank": 2, "name": "Harnois", "short": "harnois",
		"text": "dégâts des flèches -45 %, vie +22 %, vitesse -8 %", "cost": 11, "stats": {"arrow_armor": 0.55, "hp": 1.22, "speed": 0.92}},
}
## Anciens identifiants (sauvegardes d'avant les trois pièces) : l'équivalent le plus proche.
const LEGACY := {"armor": "armor_2", "weapons": "weapon_2"}


static func of(entry: Dictionary) -> Array:
	return entry.get("gear", [])


static func item_id(slot: String, tier: int) -> String:
	return "%s_%d" % [slot, tier]


## Qualité de la pièce slot portée par le régiment (0 : aucune).
static func tier(entry: Dictionary, slot: String) -> int:
	for id in of(entry):
		if ITEMS.has(id) and ITEMS[id]["slot"] == slot:
			return int(ITEMS[id]["tier"])
	return 0


## Pièce portée dans slot ("" : aucune).
static func worn(entry: Dictionary, slot: String) -> String:
	var t := tier(entry, slot)
	return item_id(slot, t) if t > 0 else ""


## Prochaine amélioration de slot ("" : déjà la meilleure).
static func next_item(entry: Dictionary, slot: String) -> String:
	var t := tier(entry, slot)
	return item_id(slot, t + 1) if t < MAX_TIER else ""


## Prix d'une pièce pour un régiment au complet du type donné, dans une ville.
static func full_price(type: String, id: String, town: int) -> int:
	var full := int(UnitTypes.STATS[type]["count"])
	return int(ceil(int(ITEMS[id]["cost"]) * full * float(CampaignState.TOWNS[town]["price"])))


## Prix pour le régiment index dans la ville où se trouve la compagnie : celui de la pièce, moins
## celui de la pièce qu'elle remplace (on revend l'ancienne au prix d'achat).
static func cost(state: CampaignState, index: int, id: String) -> int:
	var entry: Dictionary = state.company[index]
	var type := str(entry["type"])
	var price := full_price(type, id, state.location)
	var old := worn(entry, str(ITEMS[id]["slot"]))
	if old != "" and old != id:
		price -= full_price(type, old, state.location)
	return maxi(price, 0)


## Pourquoi le régiment index ne peut pas prendre la pièce id ("" : il le peut, or mis à part).
static func refusal(state: CampaignState, index: int, id: String) -> String:
	if not ITEMS.has(id) or index < 0 or index >= state.company.size():
		return "Équipement inconnu."
	var entry: Dictionary = state.company[index]
	var slot := str(ITEMS[id]["slot"])
	var t := int(ITEMS[id]["tier"])
	if tier(entry, slot) >= t:
		return "Ce régiment a déjà %s." % ("cette pièce" if tier(entry, slot) == t else "mieux")
	var need := int(ITEMS[id]["rank"])
	if CampaignState.rank_of(entry) < need:
		return "Réservé aux %s." % CampaignState.rank_name(need).to_lower()
	return ""


## Achète (ou améliore) une pièce pour le régiment index. Renvoie un message d'erreur ou "".
static func buy(state: CampaignState, index: int, id: String) -> String:
	if not ITEMS.has(id):
		id = str(LEGACY.get(id, id))
	var why := refusal(state, index, id)
	if why != "":
		return why
	if state.overworld != null and state.overworld.inside != state.location:
		return "Il faut être en ville pour s'équiper."
	var closed := state.closed_message(state.location)
	if closed != "":
		return closed
	var price := cost(state, index, id)
	if state.gold < price:
		return "Pas assez d'or (%d écus)." % price
	state.gold -= price
	var entry: Dictionary = state.company[index]
	var slot := str(ITEMS[id]["slot"])
	var list: Array = of(entry).filter(func(g: Variant) -> bool: return not (ITEMS.has(g) and ITEMS[g]["slot"] == slot))
	list.append(id)
	entry["gear"] = sorted(list)
	state.add_log("Jour %d : %s pour les %s (-%d écus)." % [state.day, str(ITEMS[id]["name"]).to_lower(), CampaignState.type_name(str(entry["type"])).to_lower(), price])
	return ""


## Pièces rangées dans l'ordre casque, armes, armure.
static func sorted(list: Array) -> Array:
	var out: Array = []
	for slot in SLOTS:
		for id in list:
			if ITEMS.has(id) and ITEMS[id]["slot"] == slot:
				out.append(id)
				break
	return out


## Relit une liste sauvegardée : anciens identifiants convertis, inconnus ignorés, la meilleure
## pièce gardée par emplacement.
static func read_list(saved: Variant) -> Array:
	var best := {}
	if saved is Array:
		for v in saved:
			var id := str(LEGACY.get(str(v), str(v)))
			if not ITEMS.has(id):
				continue
			var slot := str(ITEMS[id]["slot"])
			if not best.has(slot) or int(ITEMS[id]["tier"]) > int(ITEMS[best[slot]]["tier"]):
				best[slot] = id
	return sorted(best.values())
