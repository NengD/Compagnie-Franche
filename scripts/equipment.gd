class_name Equipment
extends RefCounted
## Équipement de régiment, acheté en ville (panneau de la carte de campagne) et gardé dans
## l'entrée de compagnie (« gear »). Ses effets en bataille passent par Traits.apply_to().

## « cost » : écus par homme du régiment au complet (modulé par les prix de la ville).
const ITEMS := {
	"armor": {"name": "Brigandines", "short": "armure", "text": "dégâts des flèches -30 %", "cost": 3, "stats": {"arrow_armor": 0.7}},
	"weapons": {"name": "Meilleures armes", "short": "armes", "text": "dégâts +15 %", "cost": 4, "stats": {"damage": 1.15, "ranged_damage": 1.15}},
}
const ORDER := ["armor", "weapons"]


static func of(entry: Dictionary) -> Array:
	return entry.get("gear", [])


## Prix d'un équipement pour le régiment index, dans la ville où se trouve la compagnie.
static func cost(state: CampaignState, index: int, id: String) -> int:
	var entry: Dictionary = state.company[index]
	var full := int(UnitTypes.STATS[str(entry["type"])]["count"])
	return int(ceil(int(ITEMS[id]["cost"]) * full * float(CampaignState.TOWNS[state.location]["price"])))


## Achète un équipement pour le régiment index. Renvoie un message d'erreur ou "".
static func buy(state: CampaignState, index: int, id: String) -> String:
	if not ITEMS.has(id) or index < 0 or index >= state.company.size():
		return "Équipement inconnu."
	var closed := state.closed_message(state.location)
	if closed != "":
		return closed
	var entry: Dictionary = state.company[index]
	if id in of(entry):
		return "Ce régiment a déjà cet équipement."
	var price := cost(state, index, id)
	if state.gold < price:
		return "Pas assez d'or (%d écus)." % price
	state.gold -= price
	var list: Array = of(entry).duplicate()
	list.append(id)
	entry["gear"] = list
	state.add_log("Jour %d : %s pour les %s (-%d écus)." % [state.day, str(ITEMS[id]["name"]).to_lower(), CampaignState.type_name(str(entry["type"])).to_lower(), price])
	return ""
