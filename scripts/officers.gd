class_name Officers
extends RefCounted
## Officiers : un compagnon (companions.gd) peut être nommé à la tête d'un régiment de la compagnie.
##
## Le régiment porte le métier de son officier (clé « officer » de l'entrée de CampaignState.company,
## sauvegardée) ; un compagnon ne mène qu'un régiment, un régiment n'a qu'un officier.
## Bonus selon le métier, un peu plus fort à chaque niveau du compagnon :
## - sergent : mêlée (il drille ses hommes) ;
## - chirurgien : moral (les hommes savent qu'on les relèvera) ;
## - éclaireur : vitesse ;
## - quartier-maître : tir (carquois toujours pleins).
## En bataille, l'officier marche avec son régiment (petit fanion de sa couleur) ; à chaque homme
## perdu, il risque de tomber (FALL_RATE sur un régiment entier) et tombe forcément si le régiment
## est anéanti. Tombé, il est tué (DEATH_CHANCE, moins avec un chirurgien) ou blessé ; son régiment
## perd du moral et son bonus. La campagne l'apprend après la bataille (after_battle) : un officier
## tué quitte la compagnie (journal et chronique), un blessé garde le lit (Companions.WOUND_DAYS).
## Un officier blessé reste nommé mais ne combat pas tant qu'il n'est pas guéri.

const BONUS := {
	"sergeant": {"stat": "damage", "label": "mêlée", "color": Color(0.85, 0.25, 0.2)},
	"surgeon": {"stat": "morale", "label": "moral", "color": Color(0.95, 0.95, 0.95)},
	"scout": {"stat": "speed", "label": "vitesse", "color": Color(0.35, 0.75, 0.35)},
	"quartermaster": {"stat": "ranged_damage", "label": "tir", "color": Color(0.9, 0.7, 0.25)},
}
const BASE_BONUS := 0.10 ## Bonus d'un officier de niveau 1
const LEVEL_BONUS := 0.02 ## ... en plus par niveau au-delà du premier
const FALL_RATE := 0.6 ## Risque cumulé de tomber si tout le régiment tombe homme après homme
const DEATH_CHANCE := 0.4 ## Un officier tombé est tué (sinon blessé)...
const DEATH_SURGEON := 0.25 ## ... avec un chirurgien dans la compagnie (qui n'est pas lui)
const FALL_MORALE := 20.0 ## Moral perdu par son régiment quand l'officier tombe


# ---------------------------------------------------------------- Nominations

## Métier de l'officier d'une entrée de la compagnie ("" sans officier).
static func of(entry: Dictionary) -> String:
	return str(entry.get("officer", ""))


## Relit l'officier d'une entrée sauvegardée (version 14).
static func read_entry(entry: Dictionary, r: Dictionary) -> void:
	var k := str(r.get("officer", ""))
	if Companions.KINDS.has(k):
		entry["officer"] = k


## Retire les nominations invalides après lecture (compagnon absent, doublon).
static func sanitize(state: CampaignState) -> void:
	var seen := {}
	for entry in state.company:
		var k := of(entry)
		if k == "":
			continue
		if state.companions.get_kind(k).is_empty() or seen.has(k):
			entry.erase("officer")
		else:
			seen[k] = true


## Indice du régiment mené par ce compagnon (-1 s'il n'en mène aucun).
static func regiment_of(state: CampaignState, kind: String) -> int:
	for i in state.company.size():
		if of(state.company[i]) == kind:
			return i
	return -1


## Bonus (fraction) d'un officier selon son niveau.
static func bonus_value(m: Dictionary) -> float:
	return BASE_BONUS + LEVEL_BONUS * (int(m.get("level", 1)) - 1)


static func bonus_text(m: Dictionary) -> String:
	return "%s +%d %%" % [BONUS[str(m["kind"])]["label"], roundi(bonus_value(m) * 100.0)]


## Nomme un compagnon à la tête du régiment index (il quitte son ancien régiment, et l'ancien
## officier de ce régiment est relevé). Renvoie un message d'erreur ou "".
static func assign(state: CampaignState, kind: String, index: int) -> String:
	var m := state.companions.get_kind(kind)
	if m.is_empty():
		return "Ce compagnon n'est pas dans la compagnie."
	if index < 0 or index >= state.company.size():
		return "Régiment inconnu."
	if state.in_battle():
		return "On ne change pas d'officier en pleine bataille."
	var entry: Dictionary = state.company[index]
	if of(entry) == kind:
		return "%s mène déjà ce régiment." % m["name"]
	var old := regiment_of(state, kind)
	if old >= 0:
		state.company[old].erase("officer")
	entry["officer"] = kind
	state.add_log("Jour %d : %s prend la tête des %s (%s)." % [state.day, m["name"], CampaignState.type_name(str(entry["type"])).to_lower(), bonus_text(m)])
	return ""


## Relève l'officier du régiment index. Renvoie un message d'erreur ou "".
static func remove(state: CampaignState, index: int) -> String:
	if index < 0 or index >= state.company.size() or of(state.company[index]) == "":
		return "Ce régiment n'a pas d'officier."
	if state.in_battle():
		return "On ne change pas d'officier en pleine bataille."
	state.company[index].erase("officer")
	return ""


## Le compagnon quitte la compagnie : il n'est plus officier nulle part.
static func clear(state: CampaignState, kind: String) -> void:
	for entry in state.company:
		if of(entry) == kind:
			entry.erase("officer")


# ---------------------------------------------------------------- Bataille

## Place les officiers valides à la tête de leurs régiments et applique leurs bonus
## (après Captain.enter_battle et Supplies.enter_battle : le moral est déjà fixé).
static func enter_battle(battle: Battle) -> void:
	var state := battle.campaign
	if state == null or battle.is_tutorial:
		return
	var army := state.battle_army()
	var names: Array[String] = []
	for r in battle.sim.regiments:
		if r.team != BattleSim.PLAYER or r.allied or r.company_index < 0 or r.company_index >= army.size():
			continue
		var kind := of(army[r.company_index])
		var m := state.companions.get_kind(kind) if kind != "" else {}
		if not Companions.available(m, state.day):
			continue
		m.erase("fell")
		apply_bonus(r, m)
		names.append("%s (%s)" % [m["name"], r.display_name().to_lower()])
	if not names.is_empty():
		battle.add_message("Officiers : %s." % ", ".join(names))


## L'officier m prend la tête du régiment r : bonus de son métier.
static func apply_bonus(r: Regiment, m: Dictionary) -> void:
	r.officer = m
	r.officer_fate = ""
	r.officer_seen = r.alive_n
	var k := 1.0 + bonus_value(m)
	var stat := str(BONUS[str(m["kind"])]["stat"])
	if stat == "morale":
		r.max_morale *= k
		r.morale *= k
	else:
		r.stats = r.stats.duplicate()
		if r.stats.has(stat):
			r.stats[stat] = float(r.stats[stat]) * k


## L'officier perd son bonus (il est tombé).
static func drop_bonus(r: Regiment) -> void:
	var k := 1.0 + bonus_value(r.officer)
	var stat := str(BONUS[str(r.officer["kind"])]["stat"])
	if stat == "morale":
		r.max_morale /= k
		r.morale = minf(r.morale, r.max_morale)
	elif r.stats.has(stat):
		r.stats[stat] = float(r.stats[stat]) / k


## À chaque pas de la simulation : les officiers des régiments qui perdent des hommes risquent de tomber.
static func step(sim: BattleSim) -> void:
	if sim.state != BattleSim.State.BATTLE:
		return
	for r in sim.regiments:
		if r.officer.is_empty() or r.officer_fate != "":
			continue
		var lost := r.officer_seen - r.alive_n
		if lost <= 0:
			continue
		r.officer_seen = r.alive_n
		var fled := false
		for s in r.soldiers:
			if s.fled:
				fled = true
				break
		var p := 1.0 - pow(1.0 - FALL_RATE / float(maxi(int(r.stats["count"]), 1)), lost)
		if (r.alive_n <= 0 and not fled) or sim.rng.randf() < p:
			fall(sim, r)


## L'officier du régiment r tombe : tué ou blessé, son régiment est ébranlé.
static func fall(sim: BattleSim, r: Regiment) -> void:
	var state := CampaignState.current
	var death := DEATH_CHANCE
	if str(r.officer["kind"]) != "surgeon" and state != null and Companions.has(state, "surgeon"):
		death = DEATH_SURGEON
	r.officer_fate = "dead" if sim.rng.randf() < death else "wounded"
	r.officer["fell"] = r.officer_fate # Lu par after_battle (le même dictionnaire que la campagne)
	drop_bonus(r)
	var fall_k := sim.captain.fall_factor() if sim.captain != null else 1.0
	if not r.is_dead() and not r.routing:
		r.morale -= FALL_MORALE * fall_k
	var what := "tué" if r.officer_fate == "dead" else "grièvement blessé"
	sim.message("%s tombe à la tête des %s : %s !" % [r.officer["name"], r.display_name().to_lower(), what])
	sim.cries_played.emit(r.center, 3)


## Dessin de l'officier (battle_renderer.gd) : derrière le centre de son régiment, un fanion à sa couleur.
static func draw(ci: CanvasItem, sim: BattleSim) -> void:
	for r in sim.regiments:
		if r.officer.is_empty() or r.officer_fate != "" or r.is_dead():
			continue
		var n := maxi(r.alive_n, 1)
		var depth := r.depth_rows(n) * float(r.stats["spacing"]) * 0.5
		var p := (r.center - r.facing * (depth + 8.0) + r.facing.orthogonal() * 10.0).round()
		var col: Color = BONUS[str(r.officer["kind"])]["color"]
		ci.draw_rect(Rect2(p.x - 4, p.y + 2, 8, 2), Color(0, 0, 0, 0.3))
		ci.draw_rect(Rect2(p.x - 2, p.y - 5, 4, 7), Color(0.3, 0.3, 0.55))
		ci.draw_rect(Rect2(p.x - 2, p.y - 8, 4, 3), Color(0.85, 0.7, 0.55))
		ci.draw_line(p + Vector2(3, 1), p + Vector2(3, -16), Color(0.48, 0.32, 0.17), 1.0)
		ci.draw_rect(Rect2(p.x + 3, p.y - 16, 6, 4), col)
		ci.draw_rect(Rect2(p.x + 3, p.y - 16, 6, 4), Color(0, 0, 0, 0.6), false, 1.0)


# ---------------------------------------------------------------- Après la bataille

## Après une bataille de campagne (CampaignState.finish_battle, avant Companions.after_battle) :
## officiers tués (ils quittent la compagnie) ou blessés. Les officiers d'un régiment anéanti
## qui ne sont pas tombés pendant la bataille (bataille résolue sans la scène) risquent aussi.
## lost_regiments : métiers des officiers dont le régiment a disparu. Renvoie une phrase.
static func after_battle(state: CampaignState, lost_regiments: Array) -> String:
	var out := ""
	for m in state.companions.list.duplicate():
		var fate := str(m.get("fell", ""))
		m.erase("fell")
		if fate == "" and str(m["kind"]) in lost_regiments and Companions.available(m, state.day):
			fate = "dead" if state.rng.randf() < DEATH_CHANCE else "wounded"
		if fate == "":
			continue
		var role := str(Companions.KINDS[str(m["kind"])]["name"]).to_lower()
		var reg := regiment_of(state, str(m["kind"]))
		var where := "des " + CampaignState.type_name(str(state.company[reg]["type"])).to_lower() if reg >= 0 else "de son régiment"
		if fate == "dead":
			clear(state, str(m["kind"]))
			state.companions.list.erase(m)
			out += " %s, %s, est mort à la tête %s : la compagnie le pleure." % [m["name"], role, where]
			Chronicle.note(state, "officer_dead", {"name": str(m["name"]), "role": role, "regiment": where})
		else:
			m["wounded_until"] = state.day + 1 + Companions.WOUND_DAYS
			out += " %s, %s, est tombé blessé : absent jusqu'au jour %d." % [m["name"], role, int(m["wounded_until"])]
			Chronicle.note(state, "officer_wounded", {"name": str(m["name"]), "role": role, "regiment": where})
	return out


## Métiers des officiers des régiments de l'armée sans survivant (appelé avant que la campagne ne les retire).
static func lost_regiments(army: Array) -> Array:
	var out: Array = []
	for r in army:
		if int(r["men"]) <= 0 and of(r) != "":
			out.append(of(r))
	return out
