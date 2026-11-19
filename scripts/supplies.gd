class_name Supplies
extends RefCounted
## Vivres, fatigue, repos et blessés de la compagnie (CampaignState.supplies, sauvegardé).
##
## - Vivres : comptés en rations (un homme nourri un jour), affichés en jours de marche pour
##   l'effectif du moment (hommes, blessés, prisonniers à demi-ration, compagnons). Achetés en
##   ville (et aux villageois ou caravanes, voir encounter.gd), ils baissent chaque jour. Sans
##   vivres : moral bas en bataille, puis désertions à partir du troisième jour.
## - Fatigue (0 à 100) : la marche fatigue un peu, la marche forcée (vitesse x2 sur la carte)
##   beaucoup ; le repos en ville ou au camp (« Camper ») la fait baisser. Elle réduit l'endurance
##   de départ des régiments en bataille.
## - Blessés graves : après une bataille, une part des tombés suit dans les chariots ; ils guérissent
##   au repos (ville, camp) et rejoignent un régiment de leur type qui a de la place.
##
## Accroches : CampaignState (var supplies, new_game, to_dict, from_dict, pass_day, finish_battle),
## Overworld.step (tick et allure), Battle (enter_battle), Encounter (achat de vivres).

const FOOD_START_DAYS := 10.0 ## Vivres de départ, en jours pour START_COMPANY
const FOOD_MAX_DAYS := 30.0 ## Capacité des chariots, en jours pour l'effectif du moment
const RATION_PRICE := 0.08 ## Prix d'une ration en ville (modulé par la ville et le quartier-maître)
const CLOSED_PRICE := 1.5 ## Ville qui vous ferme ses portes : on vous vend quand même, plus cher
const PRISONER_RATION := 0.5 ## Un prisonnier mange une demi-ration
const HUNGER_MORALE := 0.75 ## Moral de départ en bataille quand la compagnie a faim
const HUNGER_DESERT_DAYS := 3 ## Jours sans vivres avant les premières désertions
const HUNGER_DESERT := 0.06 ## Part des hommes qui désertent chaque jour de famine
const FATIGUE_MAX := 100.0
const FATIGUE_MARCH := 0.3 ## Fatigue par heure de marche
const FATIGUE_FORCED := 3.0 ## ... de marche forcée (environ 30 h pour épuiser une compagnie fraîche)
const REST_TOWN := 4.0 ## Fatigue perdue par heure dans un lieu (ville, village, château)
const REST_CAMP := 3.0 ## ... au camp
const REST_FIELD := 1.0 ## ... à la halte, sans camper
const FORCED_PACE := 2.0 ## Vitesse de la marche forcée
const STAMINA_LOSS := 0.6 ## Endurance de départ perdue à fatigue maximale (1 → 0,4)
const WOUNDED_WIN := 0.15 ## Part des tombés (non relevés) qui suivent blessés après une victoire
const WOUNDED_LOSS := 0.05 ## ... après une défaite (on abandonne le champ)
const HEAL_TOWN := 0.35 ## Part des blessés guéris par jour de repos en ville
const HEAL_CAMP := 0.25 ## ... au camp

var food := 0.0 ## Rations
var fatigue := 0.0
var forced := false ## Marche forcée
var camping := false ## La compagnie campe (arrêtée hors des murs)
var hungry_days := 0 ## Jours de suite sans vivres
var wounded := {} ## Type -> blessés graves dans les chariots
var rest_hours := 0.0 ## Heures de repos de la journée (pondérées : ville 1, camp 0,75)
var last_pos := Vector2.INF ## Position de la compagnie au dernier pas (non sauvegardé)


## Vivres d'une nouvelle campagne : FOOD_START_DAYS jours pour la compagnie de départ.
static func start(state: CampaignState) -> void:
	var men := 0
	for t in CampaignState.START_COMPANY:
		men += int(UnitTypes.STATS[t]["count"])
	state.supplies = Supplies.new()
	state.supplies.food = men * FOOD_START_DAYS


func to_dict() -> Dictionary:
	return {"food": food, "fatigue": fatigue, "forced": forced, "camping": camping,
		"hungry_days": hungry_days, "wounded": wounded.duplicate(), "rest_hours": rest_hours}


## Relit les vivres ; d vide (sauvegarde de version 9 et avant) : de quoi tenir FOOD_START_DAYS jours.
static func from_dict(d: Variant, state: CampaignState) -> Supplies:
	var s := Supplies.new()
	if not d is Dictionary or (d as Dictionary).is_empty():
		s.food = maxf(1.0, float(state.total_men())) * FOOD_START_DAYS
		return s
	s.food = maxf(0.0, float(d.get("food", 0.0)))
	s.fatigue = clampf(float(d.get("fatigue", 0.0)), 0.0, FATIGUE_MAX)
	s.forced = bool(d.get("forced", false))
	s.camping = bool(d.get("camping", false))
	s.hungry_days = maxi(0, int(d.get("hungry_days", 0)))
	s.rest_hours = clampf(float(d.get("rest_hours", 0.0)), 0.0, 24.0)
	var w: Variant = d.get("wounded", {})
	if w is Dictionary:
		for t in w:
			if UnitTypes.STATS.has(str(t)) and int(w[t]) > 0:
				s.wounded[str(t)] = int(w[t])
	return s


# ---------------------------------------------------------------- Vivres

func wounded_total() -> int:
	var n := 0
	for t in wounded:
		n += int(wounded[t])
	return n


## Rations mangées chaque jour.
static func consumption(state: CampaignState) -> float:
	return state.total_men() + state.supplies.wounded_total() + state.prisoners.total() * PRISONER_RATION \
		+ state.companions.list.size()


## Jours de vivres pour l'effectif du moment.
static func days_left(state: CampaignState) -> float:
	var need := consumption(state)
	return state.supplies.food / need if need > 0.0 else FOOD_MAX_DAYS


static func capacity(state: CampaignState) -> float:
	return maxf(consumption(state), 1.0) * FOOD_MAX_DAYS


static func is_full(state: CampaignState) -> bool:
	return state.supplies.food >= capacity(state) - 0.5


static func hungry(state: CampaignState) -> bool:
	return state.supplies.hungry_days > 0


## Prix d'une ration dans une ville (par défaut celle où l'on se trouve).
static func ration_price(state: CampaignState, town := -1) -> float:
	if town < 0:
		town = state.location
	var p := RATION_PRICE * float(CampaignState.TOWNS[town]["price"]) * Companions.food_factor(state)
	if state.closed_message(town) != "":
		p *= CLOSED_PRICE
	return p


## Rations pour days jours (au plus ce qui manque pour remplir les chariots).
static func rations_for(state: CampaignState, days: float) -> float:
	return clampf(maxf(consumption(state), 1.0) * days, 0.0, maxf(0.0, capacity(state) - state.supplies.food))


static func buy_cost(state: CampaignState, days: float) -> int:
	return ceili(rations_for(state, days) * ration_price(state))


## Achète days jours de vivres dans la ville actuelle (days <= 0 : remplir les chariots).
## Renvoie un message d'erreur ou "".
static func buy(state: CampaignState, days: float) -> String:
	if days <= 0.0:
		days = FOOD_MAX_DAYS
	var rations := rations_for(state, days)
	if rations < 1.0:
		return "Vos chariots sont déjà pleins."
	var cost := buy_cost(state, days)
	if state.gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	state.gold -= cost
	state.supplies.food += rations
	state.supplies.hungry_days = 0
	state.add_log("Jour %d : %s de vivres achetés (-%d écus)." % [state.day, CampaignState.plural(roundi(rations / maxf(consumption(state), 1.0)), "jour", "jours"), cost])
	return ""


## Ajoute des rations (achat aux villageois ou aux caravanes), sans dépasser la capacité.
static func add(state: CampaignState, rations: float) -> void:
	state.supplies.food = minf(state.supplies.food + maxf(rations, 0.0), capacity(state))
	if rations > 0.0:
		state.supplies.hungry_days = 0


# ---------------------------------------------------------------- Le jour passe

## Un jour passe (CampaignState.pass_day, après la solde) : on mange, la faim, les blessés
## guérissent si l'on s'est reposé, des prisonniers s'évadent.
static func pass_day(state: CampaignState) -> void:
	var s := state.supplies
	var need := consumption(state)
	if s.food >= need or need <= 0.0:
		s.food -= need
		s.hungry_days = 0
	else:
		s.food = 0.0
		s.hungry_days += 1
		if s.hungry_days == 1:
			state.add_log("Jour %d : plus de vivres ! La compagnie a faim, le moral flanche." % state.day)
		if s.hungry_days >= HUNGER_DESERT_DAYS:
			starve(state)
	heal(state)
	s.rest_hours = 0.0
	Prisoners.pass_day(state)


## Famine : une part des hommes s'en va (moins avec un sergent).
static func starve(state: CampaignState) -> void:
	var rate := HUNGER_DESERT * Companions.desert_factor(state)
	var lost := 0
	for r in state.company:
		var n := maxi(1, roundi(int(r["men"]) * rate))
		n = mini(n, int(r["men"]))
		r["men"] = int(r["men"]) - n
		lost += n
	state.company = state.company.filter(func(r: Dictionary) -> bool: return int(r["men"]) > 0)
	state.men_lost += lost
	if lost > 0:
		state.add_log("Jour %d : la faim ronge la compagnie, %s !" % [state.day, CampaignState.plural(lost, "homme déserte", "hommes désertent")])


## Les blessés guérissent selon le repos de la journée et rejoignent un régiment de leur type.
static func heal(state: CampaignState) -> void:
	var s := state.supplies
	if s.wounded.is_empty() or s.rest_hours <= 0.0:
		return
	var frac := clampf(s.rest_hours / 24.0, 0.0, 1.0)
	var back := 0
	for t in s.wounded.keys():
		var n := int(s.wounded[t])
		var k := mini(n, maxi(1, roundi(n * HEAL_TOWN * frac * Companions.heal_factor(state))))
		var placed := place_men(state, str(t), k)
		back += placed
		if n - placed > 0:
			s.wounded[t] = n - placed
		else:
			s.wounded.erase(t)
	if back > 0:
		state.add_log("Jour %d : %s les rangs." % [state.day, CampaignState.plural(back, "blessé guéri rejoint", "blessés guéris rejoignent")])


## Place n hommes d'un type dans les régiments de ce type qui ont de la place. Renvoie le nombre placé.
static func place_men(state: CampaignState, type: String, n: int) -> int:
	var placed := 0
	for r in state.company:
		if placed >= n:
			break
		if str(r["type"]) != type:
			continue
		var room := int(UnitTypes.STATS[type]["count"]) - int(r["men"])
		var k := mini(room, n - placed)
		if k > 0:
			CampaignState.add_men(r, k, float(r.get("xp", 0.0))) # Ils reviennent avec leur expérience
			placed += k
	return placed


# ---------------------------------------------------------------- Carte en temps réel

## Allure de la compagnie sur la carte (Overworld.step) : marche forcée, éclaireur.
static func pace(state: CampaignState) -> float:
	return (FORCED_PACE if state.supplies.forced else 1.0) * Companions.pace_factor(state)


## Un pas de la carte (Overworld.step, après la marche des groupes) : fatigue ou repos,
## fin du camp quand la compagnie repart, éclaireur qui repère les bandits cachés.
static func tick(state: CampaignState, ow: Overworld, h: float) -> void:
	var s := state.supplies
	var pos := ow.player.pos
	var moved := s.last_pos != Vector2.INF and pos.distance_to(s.last_pos) > 0.01
	s.last_pos = pos
	if ow.inside >= 0: # Dans les murs : repos, même juste après l'arrivée
		s.camping = false
		s.fatigue -= REST_TOWN * h
		s.rest_hours += h
	elif moved:
		s.camping = false
		s.fatigue += (FATIGUE_FORCED if s.forced else FATIGUE_MARCH) * h
		if s.fatigue >= FATIGUE_MAX and s.forced:
			s.forced = false
			state.add_log("Jour %d : la compagnie est épuisée et reprend le pas." % state.day)
	elif s.camping:
		s.fatigue -= REST_CAMP * h
		s.rest_hours += h * (HEAL_CAMP / HEAL_TOWN)
	else:
		s.fatigue -= REST_FIELD * h
	s.fatigue = clampf(s.fatigue, 0.0, FATIGUE_MAX)
	Companions.spot(state, ow)


## Bouton « Marche forcée » de la barre. Renvoie un message.
static func toggle_forced(state: CampaignState) -> String:
	var s := state.supplies
	if not s.forced and s.fatigue >= FATIGUE_MAX * 0.95:
		return "La compagnie est trop épuisée pour forcer l'allure."
	s.forced = not s.forced
	return "Marche forcée : la compagnie avance deux fois plus vite, mais se fatigue." if s.forced else "La compagnie reprend le pas."


## Bouton « Camper » : la compagnie s'arrête et monte le camp (ou le lève). Renvoie un message.
static func toggle_camp(state: CampaignState, ow: Overworld) -> String:
	var s := state.supplies
	if s.camping:
		s.camping = false
		return "La compagnie lève le camp."
	if ow.inside >= 0:
		return "La compagnie se repose déjà à l'abri des murs."
	ow.halt()
	s.camping = true
	s.last_pos = ow.player.pos
	return "La compagnie monte le camp : elle se repose et soigne ses blessés."


# ---------------------------------------------------------------- Bataille

## Endurance de départ des régiments : 1 pour une compagnie fraîche, 0,4 à fatigue maximale.
static func start_stamina(state: CampaignState) -> float:
	return 1.0 - STAMINA_LOSS * state.supplies.fatigue / FATIGUE_MAX


static func fatigue_label(state: CampaignState) -> String:
	var f := state.supplies.fatigue
	if f < 20.0:
		return "fraîche"
	if f < 50.0:
		return "un peu lasse"
	if f < 80.0:
		return "fatiguée"
	return "épuisée"


## Début d'une bataille de campagne (Battle, après le placement) : fatigue, faim, prisonniers
## enrôlés, sergent. Sans effet en escarmouche et au tutoriel.
static func enter_battle(battle: Battle) -> void:
	var state := battle.campaign
	if state == null or battle.is_tutorial:
		return
	var army := state.battle_army()
	var stamina := start_stamina(state)
	var hunger := HUNGER_MORALE if hungry(state) else 1.0
	var max_k := Companions.morale_factor(state)
	for r in battle.sim.regiments:
		if r.team != BattleSim.PLAYER or r.company_index < 0 or r.company_index >= army.size():
			continue
		r.stamina = minf(r.stamina, stamina)
		r.max_morale *= max_k
		r.morale = r.max_morale * hunger * Prisoners.morale_factor(army[r.company_index])
	var notes: Array[String] = []
	if stamina < 0.8:
		notes.append("la compagnie arrive %s (endurance réduite)" % fatigue_label(state))
	if hunger < 1.0:
		notes.append("elle a le ventre vide (moral bas)")
	if not notes.is_empty():
		battle.add_message(CampaignState.cap_first(" et ".join(notes)) + ".")


## Après une bataille (finish_battle) : une part des tombés suit blessée dans les chariots.
## Renvoie une phrase pour le compte rendu.
static func after_battle(state: CampaignState, victory: bool, out: Dictionary) -> String:
	var share := (WOUNDED_WIN if victory else WOUNDED_LOSS) + Companions.wagon_bonus(state)
	var n := 0
	for row in out.get("regiments", []):
		var fallen := int(row["before"]) - int(row["after"])
		var k := int(floor(fallen * share))
		if k > 0:
			var t := str(row["type"])
			state.supplies.wounded[t] = int(state.supplies.wounded.get(t, 0)) + k
			n += k
	out["wounded"] = n
	if n <= 0:
		return ""
	return " %s dans les chariots (ils guériront au repos)." % CampaignState.plural(n, "blessé grave suit", "blessés graves suivent")
