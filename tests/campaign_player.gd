extends RefCounted
## Joueur de campagne simulé (banc tests/campaign_balance.gd et campaign_bench_test.gd).
## Il recrute, marche, choisit des contrats adaptés à sa force, livre ou fuit les armées
## rencontrées et joue les batailles :
##  - « vraies » : la simulation de bataille (scenes/main.tscn) en accéléré, jouée par le joueur
##    tactique de tests/test_player.gd, qui sonne la retraite quand la bataille est perdue ;
##  - « rapides » (fast) : résolues par un modèle (auto_resolve) calibré sur les vraies batailles.
## La bataille décisive est toujours jouée pour de vrai.
## Il n'utilise que ce qu'offre la carte de campagne : recruter, compléter, marcher, camper, accepter.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05 ## Pas de simulation des vraies batailles (comme balance.gd)
const MAX_TIME := 600.0 ## Au-delà, le joueur sonne la retraite
## Valeur d'un homme pour estimer la force d'une armée (proche du prix d'enrôlement)
const VALUE := {"spear": 6.0, "archer": 7.0, "men_at_arms": 12.0, "cavalry": 20.0,
	"crossbow": 10.0, "foot_knight": 30.0, "horse_archer": 18.0}
const RANK_POWER := 0.27 ## Force par rang : +10 % de dégâts et +15 % de moral
## Rôles et composition visée (8 régiments) : 4 fantassins, 3 tireurs, 1 cavalier
const ROLE := {"spear": "foot", "men_at_arms": "foot", "foot_knight": "foot",
	"archer": "shot", "crossbow": "shot", "horse_archer": "shot", "cavalry": "horse"}
const WANT := {"foot": 4, "shot": 3, "horse": 1}
## Préférence dans un rôle (le plus fort d'abord, s'il est abordable)
const PREFER := ["foot_knight", "men_at_arms", "spear", "crossbow", "archer", "horse_archer", "cavalry"]
const ACCEPT_RATIO := 1.15 ## Force minimale (nous / eux) pour accepter un contrat...
const ACCEPT_MIN := 0.75 ## ... qui baisse chaque jour sans contrat, jusqu'à ce plancher
const ACCEPT_DECAY := 0.02
const RESERVE_DAYS := 8.0 ## Jours de solde gardés en caisse avant de recruter
const FOOD_DAYS := 12.0 ## Jours de vivres achetés à chaque passage en ville
const FINAL_PATIENCE := 45 ## Jours d'attente au plus avant de tenter la bataille décisive...
const FINAL_MIN := 0.6 ## ... si le rapport de force n'est pas pire que celui-ci
const FINAL_REST := 10 ## Après un échec, jours de reconstitution au moins avant de la retenter
const FLEE_RATIO := 1.2 ## Armée rencontrée : livrer bataille au-dessus de ce rapport de force
## Modèle des batailles rapides : P(victoire) = 1 / (1 + exp(-FAST_K * ln(rapport / FAST_R50)))
## (calibré sur ~2 000 vraies batailles du banc : vraisemblance maximale par difficulté), pertes du
## joueur selon l'issue (victoire : environ 0,3 / rapport ; défaite : 40 % en moyenne).
const FAST_K := 4.0
const FAST_R50 := {"easy": 1.0, "normal": 0.95, "hard": 0.9}

var scene: PackedScene
var root: Window
var fast := false
var trace := false ## Affiche chaque décision (diagnostic)
var all_objectives := true ## Faux : seuls les contrats « détruire l'ennemi » (et les sièges)
var rng := RandomNumberGenerator.new()
var camp: CampaignState
var idle_days := 0 ## Jours depuis le dernier contrat accepté
var offer_day := 0 ## Jour où la bataille décisive a été proposée (0 = jamais)
var final_day := 0 ## Jour de la dernière tentative de la bataille décisive (0 = jamais)
var stats := {} ## Bilan de la campagne (voir run)
var battles: Array[Dictionary] = [] ## {ratio, win, loss, real, level, final, kind}


func _init(scene_ref: PackedScene, root_ref: Window, fast_mode: bool) -> void:
	scene = scene_ref
	root = root_ref
	fast = fast_mode


## Joue une campagne jusqu'à la victoire, la ruine ou max_days. Renvoie le bilan.
func run(seed_value: int, level: String, max_days: int) -> Dictionary:
	rng.seed = hash([seed_value, "joueur"])
	camp = CampaignState.new_game(seed_value, level)
	CampaignState.current = camp
	idle_days = 0
	offer_day = 0
	final_day = 0
	battles.clear()
	stats = {"seed": seed_value, "difficulty": level, "result": "limit", "day_end": 0, "day_offer": 0,
		"day_final": 0, "final_tries": 0, "fled": 0, "curve": [], "real": 0, "cause": ""}
	var next_cp := 0
	var guard := 0
	while not camp.is_over() and camp.day < max_days and guard < 5000:
		guard += 1
		while next_cp <= camp.day:
			stats["curve"].append([next_cp, int(camp.gold), camp.fame, camp.total_men()])
			next_cp += 10
		if offer_day == 0 and not camp.final_contract().is_empty():
			offer_day = camp.day
		turn()
	while next_cp <= camp.day: # Relevés jusqu'au dernier jour
		stats["curve"].append([next_cp, int(camp.gold), camp.fame, camp.total_men()])
		next_cp += 10
	CampaignState.current = null
	if offer_day == 0 and not camp.final_contract().is_empty():
		offer_day = camp.day
	stats["result"] = camp.ended if camp.ended != "" else "limit"
	stats["day_end"] = camp.day
	stats["day_offer"] = offer_day
	stats["fame"] = camp.fame
	stats["gold"] = int(camp.gold)
	stats["men"] = camp.total_men()
	stats["wins"] = camp.victories
	stats["losses"] = camp.defeats
	stats["battles"] = battles.duplicate(true)
	stats["cause"] = failure_cause()
	return stats


func failure_cause() -> String:
	match camp.ended:
		"victory":
			return ""
		"ruin":
			return "ruine"
	if offer_day == 0:
		return "renommée insuffisante"
	if int(stats["final_tries"]) > 0:
		return "bataille décisive perdue"
	return "bataille décisive jamais tentée"


## Une décision : bataille en attente, rencontre, recrutement puis contrat, marche ou camp.
func turn() -> void:
	if trace:
		print("  j%3d %-12s or %5d  renommée %3d  %2d rég. %3d h  solde %3.0f/j  contrats %d" % [camp.day, CampaignState.TOWNS[camp.location]["name"],
			int(camp.gold), camp.fame, camp.company.size(), camp.total_men(), camp.daily_wage(), camp.contracts.size()])
	if camp.world.has_encounter():
		var a := camp.world.encounter_army()
		if a != null and ratio(company_power(), encounter_power(a.force)) >= FLEE_RATIO:
			camp.world.fight(camp)
		else:
			camp.world.flee(camp)
			stats["fled"] = int(stats["fled"]) + 1
			return
	if camp.in_battle():
		play_battle("rencontre" if camp.pending.has("world_army") else "embuscade")
		return
	if camp.is_destroyed():
		# Plus un homme : relever la compagnie ici si l'or le permet (sinon check_ruin a tranché)
		manage_company(0.0)
		if camp.is_destroyed():
			camp.pass_day()
			camp.check_ruin()
		return
	stock_up() # Rançons et vivres d'abord (supplies.gd, prisoners.gd)
	# Compagnie décimée : la relever d'abord (moins de réserve)
	manage_company(RESERVE_DAYS if camp.company.size() >= 6 else 3.0)
	var target := choose_contract()
	if not target.is_empty():
		var town := int(target["town"])
		if town == camp.location:
			if camp.accept(target) == "":
				idle_days = 0
				play_battle("final" if target.get("final", false) else "contrat")
			else:
				camp.pass_day() # Refusé (portes fermées...) : un jour perdu, on réessaiera
			return
		march_towards(town)
		return
	idle_days += 1
	# Rien à faire ici : chercher du travail ailleurs (les contrats d'une ville se renouvellent à l'arrivée)
	var next := camp.neighbours(camp.location)
	if next.is_empty():
		camp.pass_day()
		return
	march_towards(next[rng.randi() % next.size()])


func march_towards(town: int) -> void:
	var path := WorldSim.find_path(camp.location, town)
	if path.is_empty():
		camp.pass_day()
		return
	camp.travel(path[0])


# ---------------------------------------------------------------- Compagnie

## En ville : rançonne les prisonniers, puis achète de quoi tenir FOOD_DAYS jours.
func stock_up() -> void:
	if Prisoners.ransom_town(camp) < 0:
		return
	Prisoners.ransom_all(camp)
	var days := Supplies.days_left(camp)
	if days < FOOD_DAYS:
		Supplies.buy(camp, FOOD_DAYS - days)


## Complète les régiments entamés puis lève de nouveaux régiments, en gardant reserve jours de solde.
func manage_company(reserve: float) -> void:
	if camp.closed_message(camp.location) != "":
		return
	var recruits: Array = CampaignState.TOWNS[camp.location]["recruits"]
	for i in camp.company.size():
		var r := camp.company[i]
		var full := int(UnitTypes.STATS[r["type"]]["count"])
		var missing := camp.refill_missing(i)
		if missing * 4 < full or not str(r["type"]) in recruits:
			continue
		if camp.gold - camp.recruit_cost(str(r["type"]), missing) >= camp.daily_wage() * reserve:
			camp.refill(i)
	while camp.company.size() < CampaignState.MAX_REGIMENTS:
		var t := pick_type(recruits)
		if t == "":
			return
		var men := int(UnitTypes.STATS[t]["count"])
		var new_wage := float(CampaignState.WAGE[t]) * men * Difficulty.value(camp.difficulty, "wage")
		if camp.gold - camp.recruit_cost(t, men) < (camp.daily_wage() + new_wage) * reserve:
			return
		if camp.recruit(t) != "":
			return


## Type à lever ici : le rôle le plus en manque, le plus fort de ce rôle qu'on peut payer.
func pick_type(recruits: Array) -> String:
	var have := {"foot": 0, "shot": 0, "horse": 0}
	for r in camp.company:
		have[ROLE[r["type"]]] += 1
	var best_role := ""
	var best_gap := -99
	for role in WANT:
		var available := false
		for t in recruits:
			if ROLE[t] == role:
				available = true
		var gap := int(WANT[role]) - int(have[role])
		if available and gap > best_gap:
			best_gap = gap
			best_role = role
	if best_role == "":
		return ""
	var cheapest := ""
	for t in PREFER:
		if not t in recruits or ROLE[t] != best_role:
			continue
		if camp.gold >= camp.recruit_cost(t, int(UnitTypes.STATS[t]["count"])) * 1.5:
			return t # Le plus fort qu'on puisse payer largement
		cheapest = t
	return cheapest


# ---------------------------------------------------------------- Contrats

static func ratio(a: float, b: float) -> float:
	return a / maxf(b, 1.0)


static func unit_power(type: String, men: int, rank: int) -> float:
	return men * float(VALUE[type]) * (1.0 + RANK_POWER * rank)


func company_power() -> float:
	var p := 0.0
	for r in camp.battle_army():
		p += unit_power(str(r["type"]), int(r["men"]), CampaignState.rank_of(r))
	return p


## Force estimée d'une armée ennemie (difficulté comprise ; sièges : la muraille compte).
func enemy_power(contract: Dictionary) -> float:
	var p := 0.0
	for e in contract.get("enemy", []):
		var men := Difficulty.enemy_men(camp.difficulty, int(e["men"]))
		p += unit_power(str(e["type"]), men, int(e.get("rank", 0)))
	p *= Difficulty.value(camp.difficulty, "enemy_damage") * (0.5 + 0.5 * Difficulty.value(camp.difficulty, "enemy_morale"))
	match str(contract.get("siege", "")):
		"assault":
			p *= 1.3
		"defense":
			p *= 0.8
	return p


## Armée de faction rencontrée (world_sim.gd make_battle) : 3 à 6 régiments, un sur deux aguerri.
func encounter_power(men: int) -> float:
	var n := clampi(int(round(men / 40.0)), 3, 6)
	return n * 14.0 * 12.0 * (1.0 + RANK_POWER * 0.7)


## Meilleur contrat à prendre (ici ou ailleurs) : bataille décisive si la compagnie est prête,
## sinon la meilleure prime par jour parmi ceux qu'on peut gagner. {} si aucun.
func choose_contract() -> Dictionary:
	var mine := company_power()
	var final := camp.final_contract()
	if not final.is_empty() and not camp.faction_closed(int(final["faction"])):
		# Attendre d'être prêt : rapport de force suffisant, ou compagnie au complet après quelques
		# jours (après un échec : reconstituée), ou à bout de patience si le combat reste jouable
		var waited := camp.day - maxi(offer_day, final_day) if offer_day > 0 else 0
		var rf := ratio(mine, enemy_power(final))
		var rested := final_day == 0 or camp.day - final_day >= FINAL_REST
		if rested and (rf >= ACCEPT_RATIO or (company_full() and waited >= 15) or (waited >= FINAL_PATIENCE and rf >= FINAL_MIN)):
			return final
	var need := maxf(ACCEPT_MIN, ACCEPT_RATIO - ACCEPT_DECAY * idle_days)
	if camp.gold < camp.daily_wage() * 5.0:
		need = ACCEPT_MIN # Caisses vides : il faut un contrat, même risqué
	var seen: PackedStringArray = []
	var best := {}
	var best_score := 0.0
	for c in camp.contracts:
		if c.get("final", false):
			continue
		if not all_objectives and CampaignState.objective_kind(c) != "destroy":
			continue
		var town := int(c["town"])
		if camp.faction_closed(camp.town_owner(town)):
			continue
		var days := travel_estimate(town)
		if days < 0 or int(c["expires"]) < camp.day + days:
			continue
		if trace:
			seen.append("%s n%d %s %.2f" % [str(CampaignState.TOWNS[town]["name"]).left(4), int(c["difficulty"]), CampaignState.objective_kind(c).left(3), ratio(mine, enemy_power(c))])
		if ratio(mine, enemy_power(c)) < need:
			continue
		var score := camp.contract_reward(c) / float(days + 2)
		if score > best_score:
			best_score = score
			best = c
	if trace and best.is_empty():
		print("      aucun contrat (seuil %.2f) : %s" % [need, ", ".join(seen)])
	return best


## Jours de marche jusqu'à une ville (-1 si inaccessible).
func travel_estimate(town: int) -> int:
	if town == camp.location:
		return 0
	var path := WorldSim.find_path(camp.location, town)
	if path.is_empty():
		return -1
	return ceili(WorldSim.path_length(camp.location, path) / (CampaignState.TRAVEL_PX_PER_DAY * WorldSim.march_factor(camp.day))) + path.size() - 1


func company_full() -> bool:
	if camp.company.size() < CampaignState.MAX_REGIMENTS:
		return false
	for i in camp.company.size():
		if camp.refill_missing(i) * 5 > int(UnitTypes.STATS[camp.company[i]["type"]]["count"]):
			return false
	return true


# ---------------------------------------------------------------- Batailles

## Joue la bataille en attente (camp.pending) et note son issue.
func play_battle(kind: String) -> void:
	var is_final := bool(camp.pending.get("final", false))
	var r := ratio(company_power(), enemy_power(camp.pending))
	var men_before := camp.total_men()
	var level := int(camp.pending.get("difficulty", 1))
	var objective := CampaignState.objective_kind(camp.pending)
	if camp.pending.has("siege"):
		objective = "siège"
	if is_final:
		final_day = camp.day
		stats["final_tries"] = int(stats["final_tries"]) + 1
		if int(stats["day_final"]) == 0:
			stats["day_final"] = camp.day
	var real := is_final or not fast
	var won: bool
	if real:
		won = real_battle()
		stats["real"] = int(stats["real"]) + 1
	else:
		won = auto_resolve(r)
	var loss := 1.0 - float(camp.total_men()) / maxf(men_before, 1.0)
	if trace:
		print("    bataille %s niv %d rapport %.2f : %s, pertes %.0f %% — %s" % [kind, level, r, "victoire" if won else "défaite", 100.0 * loss, camp.log_lines[0] if not camp.log_lines.is_empty() else ""])
	battles.append({"ratio": r, "win": won, "loss": loss, "real": real, "level": level, "final": is_final, "kind": kind, "objective": objective})


## Vraie bataille, jouée par le joueur tactique. Renvoie vrai en cas de victoire.
func real_battle() -> bool:
	var b := scene.instantiate()
	root.add_child(b)
	b.start_battle()
	var player := TestPlayer.new("tactical")
	player.objectives = true
	var start := float(b.team_strength(0))
	var next_check := 0.0
	while b.state == BattleSim.State.BATTLE:
		player.update(b)
		b.simulate(STEP)
		if b.battle_time >= next_check:
			next_check = b.battle_time + 2.0
			# Joueur compétent : sonne la retraite quand la bataille est perdue (ou s'éternise)
			var mine := float(b.team_strength(0))
			var theirs := float(b.team_strength(1))
			if b.battle_time > MAX_TIME or (mine < start * 0.5 and theirs > mine * 1.3):
				b.order_retreat()
	var won: bool = b.state == BattleSim.State.VICTORY
	root.remove_child(b)
	b.free()
	return won


## Bataille rapide : issue tirée d'après le rapport de force, pertes selon l'issue.
func auto_resolve(r: float) -> bool:
	var r50 := float(FAST_R50.get(camp.difficulty, 1.0))
	var p := 1.0 / (1.0 + exp(-FAST_K * log(maxf(r, 0.01) / r50)))
	var won := rng.randf() < p
	var loss: float
	if won:
		loss = clampf(0.3 / maxf(r, 0.3) * rng.randf_range(0.6, 1.4), 0.05, 0.7)
	else:
		loss = clampf(0.4 * rng.randf_range(0.5, 1.5), 0.1, 0.9)
	var army := camp.battle_army()
	var survivors := []
	var kills := []
	var enemy_men := 0
	for e in camp.pending.get("enemy", []):
		enemy_men += int(e["men"])
	var killed := int(enemy_men * (0.55 if won else 0.25))
	for reg in army:
		survivors.append(int(round(int(reg["men"]) * (1.0 - loss))))
		kills.append(int(killed / maxf(army.size(), 1.0)))
	camp.finish_battle(won, survivors, kills, not won)
	return won
