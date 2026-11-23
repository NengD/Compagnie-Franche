class_name Tooltips
extends RefCounted
## Infobulles de la carte de campagne : textes calculés (sans nœud), posés sur les boutons et
## les lignes des fenêtres par campaign_map.gd, company_panel.gd et life_panel.gd.
## - pièce d'équipement comparée à celle portée (gains en %) ;
## - chances estimées d'un contrat (rapport de force entre la compagnie et l'ennemi) ;
## - effets des compétences du capitaine (niveau actuel → suivant) et des traits ;
## - terrain d'une rencontre (ce qu'il change à la bataille).

## Statistiques comparées pour l'équipement : clé, nom affiché, vrai si une baisse est un gain.
const GEAR_STATS := [
	["hp", "vie", false],
	["morale", "moral", false],
	["damage", "dégâts", false],
	["arrow_armor", "dégâts des flèches reçus", true],
	["speed", "vitesse", false],
]
## Seuils du rapport de force (compagnie / ennemi) et leur appréciation.
const ODDS_WORDS := [[0.6, "très risqué"], [0.85, "risqué"], [1.15, "équilibré"], [1.6, "favorable"], [INF, "très favorable"]]
const ODDS_SHARPNESS := 2.2 ## Plus c'est grand, plus un petit avantage pèse sur les chances


# ---------------------------------------------------------------- Équipement

## Multiplicateur d'une statistique donné par une pièce ("" : aucune pièce, 1).
static func item_mult(id: String, stat: String) -> float:
	if id == "" or not Equipment.ITEMS.has(id):
		return 1.0
	return float((Equipment.ITEMS[id]["stats"] as Dictionary).get(stat, 1.0))


## Écart en % de chaque statistique entre la pièce id et celle portée au même emplacement par
## le régiment entry : {stat: écart en %} (ex. {"hp": 6.48, "morale": 4.76}). Les statistiques
## inchangées ne figurent pas. Pour « arrow_armor », un écart négatif est un gain.
static func gear_delta(entry: Dictionary, id: String) -> Dictionary:
	var out := {}
	if not Equipment.ITEMS.has(id):
		return out
	var worn := Equipment.worn(entry, str(Equipment.ITEMS[id]["slot"]))
	for s in GEAR_STATS:
		var k: String = s[0]
		var d := (item_mult(id, k) / item_mult(worn, k) - 1.0) * 100.0
		if absf(d) >= 0.05:
			out[k] = d
	return out


## « +6,5 % » (une décimale si besoin, virgule française).
static func pct(v: float) -> String:
	var r := roundf(v * 10.0) / 10.0
	var s := ("%+.0f" % r) if is_equal_approx(r, roundf(r)) else ("%+.1f" % r)
	return s.replace(".", ",") + " %"


## Infobulle d'un bouton d'achat : la pièce, ce qu'elle remplace et les gains par rapport à elle.
static func gear_text(entry: Dictionary, id: String) -> String:
	var item: Dictionary = Equipment.ITEMS[id]
	var worn := Equipment.worn(entry, str(item["slot"]))
	var lines: Array[String] = ["%s : %s." % [item["name"], item["text"]]]
	lines.append("Remplace : %s." % (str(Equipment.ITEMS[worn]["short"]) if worn != "" else "rien (aucune pièce portée)"))
	var parts: Array[String] = []
	var delta := gear_delta(entry, id)
	for s in GEAR_STATS:
		if delta.has(s[0]):
			var d: float = delta[s[0]]
			var good := (d < 0.0) == bool(s[2])
			parts.append("%s %s%s" % [s[1], pct(d), "" if good else " (perte)"])
	if not parts.is_empty():
		lines.append("Par rapport à la pièce portée : " + ", ".join(parts) + ".")
	return "\n".join(lines)


# ---------------------------------------------------------------- Contrats

## Force de combat d'un régiment (entrée de compagnie ou d'armée ennemie) : hommes × vie × coups,
## tir compris, modulés par le rang, l'équipement et les traits. Une estimation, pas la simulation.
static func regiment_power(entry: Dictionary, enemy := false, level := Difficulty.NORMAL) -> float:
	var type := str(entry.get("type", ""))
	if not UnitTypes.STATS.has(type):
		return 0.0
	var st: Dictionary = UnitTypes.STATS[type]
	var hp := float(st["hp"])
	var hit := float(st["damage"]) / maxf(float(st["cooldown"]), 0.1)
	if bool(st["ranged"]):
		hit += float(st.get("ranged_damage", 0.0)) / maxf(float(st.get("reload", 1.0)), 0.1) * 1.5
	if bool(st["mounted"]):
		hit *= 1.3 # L'élan de la charge
	var rank := CampaignState.rank_of(entry)
	hit *= 1.0 + Regiment.RANK_DAMAGE * rank
	hp *= 1.0 + Regiment.RANK_MORALE * rank # Le moral tient la ligne aussi longtemps que la vie
	for id in Equipment.of(entry):
		if Equipment.ITEMS.has(id):
			var m: Dictionary = Equipment.ITEMS[id]["stats"]
			hp *= float(m.get("hp", 1.0)) * float(m.get("morale", 1.0))
			hit *= float(m.get("damage", 1.0))
	for id in Traits.of(entry):
		if Traits.TRAITS.has(id):
			var m: Dictionary = Traits.TRAITS[id].get("stats", {})
			hp *= float(m.get("morale", 1.0))
			hit *= float(m.get("damage", 1.0))
	if enemy:
		hit *= Difficulty.value(level, "enemy_damage")
		hp *= Difficulty.value(level, "enemy_morale")
	return float(entry.get("men", 0)) * sqrt(hp * hit)


static func army_power(list: Array, enemy := false, level := Difficulty.NORMAL) -> float:
	var p := 0.0
	for e in list:
		p += regiment_power(e, enemy, level)
	return p


## Chances estimées d'un contrat : {"ratio" (compagnie / ennemi), "chance" (0..1), "word"}.
static func contract_odds(state: CampaignState, contract: Dictionary) -> Dictionary:
	var mine := army_power(state.battle_army())
	var foe := army_power(contract.get("enemy", []), true, state.difficulty)
	var ratio := mine / maxf(foe, 0.001) if foe > 0.0 else 10.0
	var k := pow(ratio, ODDS_SHARPNESS)
	var chance := clampf(k / (1.0 + k), 0.03, 0.97)
	var word := ""
	for w in ODDS_WORDS:
		if ratio < float(w[0]):
			word = str(w[1])
			break
	return {"ratio": ratio, "chance": chance, "word": word}


## Ligne et infobulle des chances d'un contrat.
static func contract_line(state: CampaignState, contract: Dictionary) -> String:
	if state.company.is_empty():
		return "Chances estimées : aucune, la compagnie n'a pas un homme."
	var o := contract_odds(state, contract)
	return "Chances estimées : %d %% (%s, rapport de force %.1f contre 1)" % [roundi(float(o["chance"]) * 100.0), o["word"], float(o["ratio"])]


static func contract_text(state: CampaignState, contract: Dictionary) -> String:
	if state.company.is_empty():
		return contract_line(state, contract)
	return "%s.
Vos %s contre %s.
L'estimation compte les hommes, leur rang, leur équipement et leurs traits ; le terrain, les alliés, la fatigue et vos ordres font le reste." % [
		contract_line(state, contract), CampaignState.plural(state.total_men(), "homme", "hommes"),
		CampaignState.army_summary(contract.get("enemy", []))]


# ---------------------------------------------------------------- Compétences et traits

## Effet d'une compétence du capitaine au niveau actuel et au suivant.
static func skill_text(cap: Captain, skill: String) -> String:
	var lvl := cap.rank(skill)
	var info: Dictionary = Captain.SKILLS[skill]
	var top := int(info["max"])
	var lines: Array[String] = ["%s (%d / %d) : %s." % [info["name"], lvl, top, info["text"]]]
	var now := skill_effect(skill, lvl)
	if now != "": # Effet chiffré (aura, ralliement, solde)
		lines.append("Aujourd'hui : %s." % now)
		if lvl < top:
			lines.append("Au rang %d : %s." % [lvl + 1, skill_effect(skill, lvl + 1)])
	if lvl >= top:
		lines.append("Niveau maximal atteint.")
	return "\n".join(lines)


static func skill_effect(skill: String, lvl: int) -> String:
	match skill:
		"aura":
			return "aura de moral de %d px" % int(Captain.AURA_RADIUS * (1.0 + Captain.AURA_STEP * lvl))
		"rally":
			return "aucun ralliement" if lvl == 0 else "les fuyards proches regagnent %.0f de moral par seconde" % (Captain.RALLY_REGEN * lvl)
		"wages":
			return "solde de la compagnie %s" % ("normale" if lvl == 0 else pct(-Captain.WAGE_STEP * 100.0 * lvl))
	return ""


## Infobulle des traits d'un régiment : un trait par ligne avec son effet.
static func traits_text(entry: Dictionary) -> String:
	var lines: Array[String] = []
	for id in Traits.of(entry):
		if Traits.TRAITS.has(id):
			lines.append("%s : %s" % [CampaignState.cap_first(str(Traits.TRAITS[id]["name"])), Traits.TRAITS[id]["text"]])
	return "\n".join(lines)


# ---------------------------------------------------------------- Terrain

## Infobulle du terrain d'une rencontre : son nom et ce qu'il change à la bataille.
static func terrain_text(kind: String) -> String:
	var hint := str(Terrain.HINTS.get(kind, ""))
	var name := CampaignState.cap_first(str(Terrain.NAMES.get(kind, kind)))
	var tips := {
		"plain": "Les cavaliers y chargent sans gêne ; tenez vos flancs.",
		"forest": "Un régiment en forêt est caché tant que l'ennemi ne s'approche pas ; on y marche lentement.",
		"hills": "Prenez les hauteurs avec vos archers avant l'ennemi.",
		"river": "Tenez les gués : l'ennemi qui traverse à la nage est lent et vulnérable.",
		"village": "Les ruelles cassent les charges ; l'infanterie s'y défend bien.",
		"siege": "Gardez vos tireurs derrière les pieux et vos piquiers aux brèches.",
	}
	var out := "%s : %s" % [name, hint]
	if tips.has(kind):
		out += "\nConseil : " + str(tips[kind])
	return out
