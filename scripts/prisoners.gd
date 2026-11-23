class_name Prisoners
extends RefCounted
## Prisonniers de la compagnie (CampaignState.prisoners, sauvegardé).
##
## Après une victoire, une part des ennemis vaincus est faite prisonnière : surtout des fuyards
## rattrapés, et quelques blessés relevés sur le champ (le bilan de finish_battle donne les tués,
## les fuyards sont le reste de l'armée ennemie). Ensuite, au choix :
## - les rançonner en ville (or selon le type et le rang ; plus si la ville est de leur faction) ;
## - en enrôler une partie : ils complètent les régiments de leur type, ou en forment un nouveau,
##   avec un moral bas au début (« sullen » sur le régiment, qui s'efface avec les jours) ;
## - les relâcher (réputation auprès de leur faction).
## Les garder coûte des vivres (une demi-ration chacun, voir supplies.gd), et certains s'évadent
## chaque jour, davantage quand ils sont nombreux face à leurs gardes ou quand on a faim.

const CAPTURE_FLED := 0.3 ## Part des fuyards rattrapés après une victoire
const CAPTURE_FALLEN := 0.15 ## Part des tombés relevés vivants
const GUARD_RATIO := 0.75 ## Au plus tant de prisonniers par homme de la compagnie
const ESCAPE_RATE := 0.03 ## Part des prisonniers qui s'évadent chaque jour
const ESCAPE_CROWDED := 0.08 ## ... quand ils sont plus de la moitié de l'effectif de la compagnie
const ESCAPE_HUNGRY := 0.15 ## ... quand la compagnie n'a plus de vivres
const RANSOM_RATE := 0.8 ## Rançon d'un homme : part de son prix de recrue...
const RANSOM_RANK := 0.5 ## ... +50 % par rang
const RANSOM_OWN := 1.3 ## Ville de leur faction : leur seigneur les rachète plus cher
const RANSOM_BANDITS := 0.5 ## Brigands : une simple prime de la prévôté
const ENLIST_SHARE := 0.5 ## Part d'un groupe qui accepte de servir
const SULLEN_MORALE := 0.5 ## Moral de départ perdu par un régiment entièrement fait d'anciens prisonniers
const SULLEN_DAY := 0.05 ## Rancœur effacée chaque jour
const SULLEN_BATTLE := 0.25 ## ... et à chaque bataille livrée ensemble
const RELEASE_MEN := 8 ## Relâcher : +1 de réputation par tant d'hommes...
const RELEASE_MAX := 5 ## ... au plus

var list: Array[Dictionary] = [] ## {"type", "men", "rank", "faction"}


func total() -> int:
	var n := 0
	for g in list:
		n += int(g["men"])
	return n


func to_dict() -> Array:
	return list.duplicate(true)


static func from_dict(v: Variant) -> Prisoners:
	var p := Prisoners.new()
	if not v is Array:
		return p
	for g in v:
		if g is Dictionary and UnitTypes.STATS.has(str(g.get("type", ""))) and int(g.get("men", 0)) > 0:
			p.add(str(g["type"]), int(g["men"]), clampi(int(g.get("rank", 0)), 0, 2),
				clampi(int(g.get("faction", -1)), -1, CampaignState.FACTIONS.size() - 1))
	return p


## Ajoute des prisonniers (regroupés par type, rang et faction).
func add(type: String, men: int, rank: int, faction: int) -> void:
	if men <= 0:
		return
	for g in list:
		if str(g["type"]) == type and int(g["rank"]) == rank and int(g["faction"]) == faction:
			g["men"] = int(g["men"]) + men
			return
	list.append({"type": type, "men": men, "rank": rank, "faction": faction})


## « 12 piquiers aguerris (Baronnie) »
static func group_name(g: Dictionary) -> String:
	var s := CampaignState.type_count(str(g["type"]), int(g["men"]))
	if int(g["rank"]) > 0:
		s += " (%s)" % CampaignState.rank_name(int(g["rank"])).to_lower()
	var f := int(g["faction"])
	s += ", %s" % (str(CampaignState.FACTIONS[f]["short"]) if f >= 0 else "sans bannière")
	return s


# ---------------------------------------------------------------- Capture

## Après une bataille (finish_battle, pending encore en place) : prisonniers d'une victoire.
## Renvoie une phrase pour le compte rendu ; out["prisoners"] : nombre de prisonniers faits.
static func after_battle(state: CampaignState, victory: bool, out: Dictionary) -> String:
	out["prisoners"] = 0
	for e in state.company:
		if e.has("sullen"):
			e["sullen"] = maxf(0.0, float(e["sullen"]) - SULLEN_BATTLE)
	if not victory or state.pending.get("final", false):
		return ""
	var enemy: Array = state.pending.get("enemy", [])
	var enemy_men := 0
	for e in enemy:
		enemy_men += int(e["men"])
	var killed := 0
	for row in out.get("regiments", []):
		killed += int(row.get("kills", 0))
	killed = mini(killed, enemy_men)
	var fled := enemy_men - killed
	var want := int(floor(fled * CAPTURE_FLED + killed * CAPTURE_FALLEN))
	var room := int(floor(state.total_men() * GUARD_RATIO)) - state.prisoners.total()
	var n := clampi(want, 0, maxi(room, 0))
	if n <= 0 or enemy_men <= 0:
		return ""
	var faction := int(state.pending.get("enemy_faction", -1))
	var left := n
	for i in enemy.size():
		var e: Dictionary = enemy[i]
		var k := left if i == enemy.size() - 1 else mini(left, roundi(n * int(e["men"]) / float(enemy_men)))
		state.prisoners.add(str(e["type"]), k, CampaignState.rank_of(e), faction)
		left -= k
	out["prisoners"] = n
	return " %s." % CampaignState.plural(n, "prisonnier fait", "prisonniers faits")


## Un jour passe (Supplies.pass_day) : évasions, rancœur des enrôlés qui s'efface.
static func pass_day(state: CampaignState) -> void:
	var sullen_step := SULLEN_DAY * Companions.sullen_speed(state)
	for e in state.company:
		if e.has("sullen"):
			e["sullen"] = maxf(0.0, float(e["sullen"]) - sullen_step)
			if float(e["sullen"]) <= 0.0:
				e.erase("sullen")
	var p := state.prisoners
	var total := p.total()
	if total <= 0:
		return
	var rate := ESCAPE_RATE
	if Supplies.hungry(state):
		rate = ESCAPE_HUNGRY
	elif total * 2 > state.total_men():
		rate = ESCAPE_CROWDED
	var gone := 0
	for g in p.list:
		var men := int(g["men"])
		var k := 0
		for i in men:
			if state.rng.randf() < rate:
				k += 1
		g["men"] = men - k
		gone += k
	p.list = p.list.filter(func(g: Dictionary) -> bool: return int(g["men"]) > 0)
	if gone > 0:
		state.add_log("Jour %d : %s pendant la nuit." % [state.day, CampaignState.plural(gone, "prisonnier s'évade", "prisonniers s'évadent")])


# ---------------------------------------------------------------- Rançon, enrôlement, libération

## Ville où l'on peut rançonner : celle où la compagnie est entrée (-1 sinon).
static func ransom_town(state: CampaignState) -> int:
	var i := state.overworld.inside
	return i if i >= 0 and i < CampaignState.TOWNS.size() else -1


## Rançon d'un groupe dans une ville.
static func ransom_value(state: CampaignState, g: Dictionary, town: int) -> int:
	var per := float(CampaignState.RECRUIT_COST[str(g["type"])]) * RANSOM_RATE * (1.0 + RANSOM_RANK * int(g["rank"]))
	var f := int(g["faction"])
	if f < 0:
		per *= RANSOM_BANDITS
	elif town >= 0 and state.town_owner(town) == f:
		per *= RANSOM_OWN
	return roundi(per * int(g["men"]) * Companions.ransom_factor(state))


## Rançonne le groupe index dans la ville où l'on se trouve. Renvoie un message d'erreur ou "".
static func ransom(state: CampaignState, index: int) -> String:
	var town := ransom_town(state)
	if town < 0:
		return "Les rançons se négocient en ville."
	var closed := state.closed_message(town)
	if closed != "":
		return closed
	if index < 0 or index >= state.prisoners.list.size():
		return "Ces prisonniers ne sont plus là."
	var g: Dictionary = state.prisoners.list[index]
	var pay := ransom_value(state, g, town)
	state.prisoners.list.remove_at(index)
	state.gold += pay
	state.gold_earned += pay
	state.add_log("Jour %d : rançon de %s : %d écus." % [state.day, group_name(g), pay])
	return ""


## Rançonne tous les prisonniers. Renvoie un message d'erreur ou "".
static func ransom_all(state: CampaignState) -> String:
	while not state.prisoners.list.is_empty():
		var err := ransom(state, 0)
		if err != "":
			return err
	return ""


## Hommes d'un groupe prêts à servir.
static func willing(state: CampaignState, g: Dictionary) -> int:
	var men := int(g["men"])
	return clampi(int(floor(men * Companions.enlist_share(state))), mini(men, 1), men)


## Places pour des hommes d'un type : régiments entamés, et un nouveau régiment si possible.
static func room_for(state: CampaignState, type: String) -> int:
	if Challenges.forbids_type(state.challenges, type):
		return 0 # Défi « Sans cavalerie »
	var full := int(UnitTypes.STATS[type]["count"])
	var room := 0
	for r in state.company:
		if str(r["type"]) == type:
			room += full - int(r["men"])
	if state.company.size() < CampaignState.MAX_REGIMENTS:
		room += full
	return room


## Enrôle les volontaires du groupe index : ils complètent les régiments de leur type, puis en
## forment un nouveau ; les autres restent prisonniers. Renvoie un message d'erreur ou "".
static func enlist(state: CampaignState, index: int) -> String:
	if index < 0 or index >= state.prisoners.list.size():
		return "Ces prisonniers ne sont plus là."
	var g: Dictionary = state.prisoners.list[index]
	var type := str(g["type"])
	if Challenges.forbids_type(state.challenges, type):
		return Challenges.NO_CAVALRY_REFUSAL
	var n := mini(willing(state, g), room_for(state, type))
	if n <= 0:
		return "Plus de place dans la compagnie pour des %s." % CampaignState.type_name(type).to_lower()
	var xp := float(CampaignState.RANK_XP[int(g["rank"])])
	var full := int(UnitTypes.STATS[type]["count"])
	var left := n
	for r in state.company:
		if left <= 0:
			break
		if str(r["type"]) != type:
			continue
		var k := mini(full - int(r["men"]), left)
		if k > 0:
			add_sullen(r, k)
			CampaignState.add_men(r, k, xp)
			left -= k
	if left > 0:
		state.company.append({"type": type, "men": left, "xp": xp, "sullen": 1.0})
	g["men"] = int(g["men"]) - n
	if int(g["men"]) <= 0:
		state.prisoners.list.remove_at(index)
	state.add_log("Jour %d : %s anciens prisonniers rejoignent la compagnie, la mine sombre." % [state.day, CampaignState.type_count(type, n)])
	return ""


## Rancœur d'un régiment qui reçoit n anciens prisonniers (moyenne pondérée, avant add_men).
static func add_sullen(r: Dictionary, n: int) -> void:
	var men := int(r["men"])
	r["sullen"] = (float(r.get("sullen", 0.0)) * men + 1.0 * n) / float(maxi(men + n, 1))


## Relâche le groupe index : réputation auprès de leur faction. Renvoie un message d'erreur ou "".
static func release(state: CampaignState, index: int) -> String:
	if index < 0 or index >= state.prisoners.list.size():
		return "Ces prisonniers ne sont plus là."
	var g: Dictionary = state.prisoners.list[index]
	state.prisoners.list.remove_at(index)
	var f := int(g["faction"])
	var note := ""
	if f >= 0:
		var rep := release_reputation(g)
		state.change_reputation(f, rep)
		note = " Réputation : %s %+d." % [CampaignState.FACTIONS[f]["short"], rep]
	state.add_log("Jour %d : vous relâchez %s.%s" % [state.day, group_name(g), note])
	return ""


static func release_reputation(g: Dictionary) -> int:
	return clampi(ceili(int(g["men"]) / float(RELEASE_MEN)), 1, RELEASE_MAX)


# ---------------------------------------------------------------- Bataille

## Moral de départ d'un régiment de campagne : bas s'il compte d'anciens prisonniers.
static func morale_factor(entry: Dictionary) -> float:
	return 1.0 - SULLEN_MORALE * clampf(float(entry.get("sullen", 0.0)), 0.0, 1.0)


## Relit la rancœur d'un régiment sauvegardé (CampaignState.from_dict).
static func read_entry(entry: Dictionary, saved: Dictionary) -> void:
	if saved.has("sullen") and float(saved["sullen"]) > 0.0:
		entry["sullen"] = clampf(float(saved["sullen"]), 0.0, 1.0)
