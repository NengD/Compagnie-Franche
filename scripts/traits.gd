class_name Traits
extends RefCounted
## Traits de régiment : gagnés par l'expérience (une promotion) ou par des évènements de route.
## Ils sont rangés dans l'entrée de compagnie ({"type", "men", "xp", "traits": [...], "gear": [...]})
## et donnent des effets simples sur les statistiques en bataille ou sur l'économie.
## apply_to() applique aussi l'équipement (equipment.gd) au régiment de bataille.

## Effets : multiplicateurs de statistiques (« stats »), solde (« wage »), butin par ennemi tué (« loot »).
const TRAITS := {
	"tenaces": {"name": "tenaces", "text": "moral +20 %", "stats": {"morale": 1.2}},
	"rapides": {"name": "rapides", "text": "vitesse +10 %", "stats": {"speed": 1.1}},
	"adroits": {"name": "adroits", "text": "dégâts +10 %", "stats": {"damage": 1.1, "ranged_damage": 1.1}},
	"pillards": {"name": "pillards", "text": "+1 écu de butin par ennemi tué", "loot": 1},
	"frugaux": {"name": "frugaux", "text": "solde -20 %", "wage": 0.8},
}
## Ordre dans lequel un régiment gagne ses traits à chaque promotion (sans tirage au sort).
const PROMOTION_ORDER := {
	"spear": ["tenaces", "adroits", "frugaux"],
	"men_at_arms": ["adroits", "tenaces", "pillards"],
	"archer": ["adroits", "frugaux", "tenaces"],
	"cavalry": ["rapides", "pillards", "tenaces"],
}
const DEFAULT_ORDER := ["tenaces", "adroits", "rapides"]


static func of(entry: Dictionary) -> Array:
	return entry.get("traits", [])


static func has(entry: Dictionary, id: String) -> bool:
	return id in of(entry)


## Ajoute un trait (s'il est nouveau). Renvoie vrai s'il a été ajouté.
static func add(entry: Dictionary, id: String) -> bool:
	if not TRAITS.has(id) or has(entry, id):
		return false
	var list: Array = of(entry).duplicate()
	list.append(id)
	entry["traits"] = list
	return true


## Promotion : le régiment gagne le prochain trait de sa liste. Renvoie son nom ("" si aucun).
static func on_promotion(entry: Dictionary) -> String:
	var order: Array = PROMOTION_ORDER.get(str(entry.get("type", "")), DEFAULT_ORDER)
	for id in order:
		if add(entry, id):
			return id
	return ""


## Noms lisibles des traits et de l'équipement : « tenaces, armure » ("" si rien).
static func describe(entry: Dictionary) -> String:
	var parts: Array[String] = []
	for id in of(entry):
		parts.append(str(TRAITS[id]["name"]))
	for id in Equipment.of(entry):
		parts.append(str(Equipment.ITEMS[id]["short"]))
	return ", ".join(parts)


## Multiplicateur de solde d'un régiment (traits).
static func wage_factor(entry: Dictionary) -> float:
	var f := 1.0
	for id in of(entry):
		f *= float(TRAITS[id].get("wage", 1.0))
	return f


## Butin supplémentaire des régiments pillards : kills[i] ennemis tués par army[i].
static func extra_loot(army: Array, kills: Array) -> int:
	var extra := 0
	for i in mini(army.size(), kills.size()):
		for id in of(army[i]):
			extra += int(TRAITS[id].get("loot", 0)) * int(kills[i])
	return extra


## Relit les traits et l'équipement d'une entrée sauvegardée (inconnus ignorés) dans out.
static func read_entry(out: Dictionary, saved: Dictionary) -> void:
	var t: Array = []
	for id in saved.get("traits", []):
		if TRAITS.has(str(id)) and not str(id) in t:
			t.append(str(id))
	var g := Equipment.read_list(saved.get("gear", []))
	if not t.is_empty():
		out["traits"] = t
	if not g.is_empty():
		out["gear"] = g


## Applique traits et équipement d'une entrée de compagnie au régiment de bataille,
## avant set_rank (qui relit stats["morale"]). Les stats sont copiées : UnitTypes.STATS reste intact.
static func apply_to(r: Regiment, entry: Dictionary) -> void:
	r.gear = Equipment.of(entry).duplicate() # Visible sur les soldats (battle_renderer.gd)
	var mults: Array[Dictionary] = []
	for id in of(entry):
		mults.append(TRAITS[id].get("stats", {}))
	for id in Equipment.of(entry):
		mults.append(Equipment.ITEMS[id].get("stats", {}))
	if mults.is_empty():
		return
	r.stats = r.stats.duplicate()
	for m in mults:
		for key in m:
			if r.stats.has(key):
				r.stats[key] = float(r.stats[key]) * float(m[key])
