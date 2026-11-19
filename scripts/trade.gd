class_name Trade
extends RefCounted
## Commerce : cinq marchandises (grain, vin, draps, fer, sel) achetées et revendues dans les villes.
##
## Chaque ville a ses prix : bon marché ce qu'elle produit (PRODUCES), cher ce qui lui manque
## (LACKS). L'offre de chaque marchandise dans chaque ville (« supply », de -1 : pénurie, à +1 :
## abondance) fait bouger le prix ; elle revient d'elle-même vers 0 chaque jour. Les achats de la
## compagnie la creusent, ses ventes la gonflent ; les caravanes (Party.goods) qui arrivent en ville y
## déchargent ce que produit leur ville d'origine ; un siège affame la ville (grain et vin manquent,
## tout est plus cher).
##
## La compagnie porte sa cargaison (« cargo ») dans la limite de sa charge : un peu par homme, et
## beaucoup plus avec des chariots achetés en ville. Une défaite fait perdre la moitié de la cargaison.
## Branché par CampaignState (bloc « Domaine ») : day(), after_battle(), to_dict() et from_dict().

const GOODS := ["grain", "wine", "cloth", "iron", "salt"]
const GOOD_NAMES := {"grain": "grain", "wine": "vin", "cloth": "draps", "iron": "fer", "salt": "sel"}
const UNITS := {"grain": "sacs de grain", "wine": "tonneaux de vin", "cloth": "balles de draps", "iron": "charges de fer", "salt": "sacs de sel"}
const BASE_PRICE := {"grain": 6.0, "wine": 16.0, "cloth": 24.0, "iron": 14.0, "salt": 10.0}
## Ce que produit et ce que manque chaque ville (indices de CampaignState.TOWNS).
const PRODUCES := [["grain"], ["wine"], ["iron"], ["cloth", "salt"], ["iron", "grain"], ["iron"], ["cloth", "wine"]]
const LACKS := [["iron"], ["salt", "cloth"], ["wine", "grain"], ["grain", "iron"], ["cloth"], ["grain", "wine"], ["iron", "salt"]]
const PRODUCER := 0.65 ## Prix d'une marchandise dans une ville qui la produit
const SHORTAGE := 1.6 ## ... dans une ville qui en manque
const SUPPLY_EFFECT := 0.4 ## Prix x (1 - SUPPLY_EFFECT x offre)
const UNIT_IMPACT := 0.02 ## Une charge achetée (vendue) baisse (monte) l'offre de tant
const RECOVERY := 0.85 ## Chaque jour, l'offre garde cette part de son écart à 0
const SELL_SPREAD := 0.88 ## Le marchand rachète à cette part du prix
const SIEGE_PRICE := 1.3 ## Ville assiégée : tout est plus cher...
const SIEGE_HUNGER := 0.15 ## ... et grain et vin s'y épuisent chaque jour de tant
const CARAVAN_EFFECT := 1.0 / 1500.0 ## Offre apportée par écu de marchandises d'une caravane qui arrive
const CARGO_PER_MAN := 0.5 ## Charges portées par homme
const WAGON_LOAD := 25 ## Charges par chariot
const WAGON_PRICE := 60
const MAX_WAGONS := 6
const DEFEAT_LOSS := 0.5 ## Part de la cargaison perdue dans une défaite

var supply: Array = [] ## supply[ville][marchandise] (ordre de GOODS), de -1 à 1
var cargo := {} ## marchandise -> charges portées
var wagons := 0
var bought := {} ## marchandise -> prix moyen payé (indicatif, pour le panneau)


func _init() -> void:
	supply.clear()
	for t in CampaignState.TOWNS.size():
		var row: Array = []
		for g in GOODS:
			row.append(0.0)
		supply.append(row)


static func good_name(g: String) -> String:
	return str(GOOD_NAMES.get(g, g))


## Facteur de prix d'une marchandise dans une ville selon ce qu'elle produit ou lui manque.
static func town_factor(town: int, g: String) -> float:
	if g in PRODUCES[town]:
		return PRODUCER
	if g in LACKS[town]:
		return SHORTAGE
	return 1.0


## Prix d'achat d'une charge (écus, arrondi, au moins 1).
func buy_price(c: CampaignState, town: int, g: String) -> int:
	var s := float(supply[town][GOODS.find(g)])
	var p := float(BASE_PRICE[g]) * town_factor(town, g) * (1.0 - SUPPLY_EFFECT * s)
	if c.world.besieged(town):
		p *= SIEGE_PRICE
	return maxi(1, int(round(p)))


## Prix de vente d'une charge.
func sell_price(c: CampaignState, town: int, g: String) -> int:
	return maxi(1, int(floor(buy_price(c, town, g) * SELL_SPREAD)))


func carried(g: String) -> int:
	return int(cargo.get(g, 0))


func load_total() -> int:
	var n := 0
	for g in cargo:
		n += int(cargo[g])
	return n


## Charge que la compagnie peut porter : ses hommes et ses chariots.
func capacity(c: CampaignState) -> int:
	return int(floor(c.total_men() * CARGO_PER_MAN)) + wagons * WAGON_LOAD


func room(c: CampaignState) -> int:
	return maxi(0, capacity(c) - load_total())


func shift(town: int, g: String, delta: float) -> void:
	var k := GOODS.find(g)
	supply[town][k] = clampf(float(supply[town][k]) + delta, -1.0, 1.0)


## Message de refus du marché de la ville (portes fermées), "" sinon.
static func market_closed(c: CampaignState, town: int) -> String:
	return c.closed_message(town)


## Achète n charges de g dans la ville town (le prix monte à chaque charge). Renvoie une erreur ou "".
func buy(c: CampaignState, town: int, g: String, n: int) -> String:
	if not g in GOODS or n <= 0:
		return "Marchandise inconnue."
	var closed := market_closed(c, town)
	if closed != "":
		return closed
	n = mini(n, room(c))
	if n <= 0:
		return "Plus de place dans les chariots (charge %d / %d)." % [load_total(), capacity(c)]
	var total := 0
	var got := 0
	for i in n:
		var p := buy_price(c, town, g)
		if c.gold < total + p:
			break
		total += p
		got += 1
		shift(town, g, -UNIT_IMPACT)
	if got == 0:
		return "Pas assez d'or (%d écus la charge)." % buy_price(c, town, g)
	c.gold -= total
	var before := carried(g)
	bought[g] = (float(bought.get(g, 0.0)) * before + total) / float(before + got)
	cargo[g] = before + got
	c.add_log("Jour %d : la compagnie achète %d %s à %s (-%d écus)." % [c.day, got, UNITS[g], CampaignState.TOWNS[town]["name"], total])
	return ""


## Vend n charges de g (le prix baisse à chaque charge). Renvoie une erreur ou "".
func sell(c: CampaignState, town: int, g: String, n: int) -> String:
	if not g in GOODS:
		return "Marchandise inconnue."
	var closed := market_closed(c, town)
	if closed != "":
		return closed
	n = mini(n, carried(g))
	if n <= 0:
		return "Vous n'en portez pas."
	var total := 0
	for i in n:
		total += sell_price(c, town, g)
		shift(town, g, UNIT_IMPACT)
	c.gold += total
	c.gold_earned += total
	take(g, n)
	c.add_log("Jour %d : la compagnie vend %d %s à %s (+%d écus)." % [c.day, n, UNITS[g], CampaignState.TOWNS[town]["name"], total])
	return ""


## Retire n charges de la cargaison (livraison, perte).
func take(g: String, n: int) -> void:
	var left := carried(g) - n
	if left > 0:
		cargo[g] = left
	else:
		cargo.erase(g)
		bought.erase(g)


func buy_wagon(c: CampaignState, town: int) -> String:
	var closed := market_closed(c, town)
	if closed != "":
		return closed
	if wagons >= MAX_WAGONS:
		return "La compagnie a déjà %d chariots." % MAX_WAGONS
	if c.gold < WAGON_PRICE:
		return "Pas assez d'or (%d écus)." % WAGON_PRICE
	c.gold -= WAGON_PRICE
	wagons += 1
	c.add_log("Jour %d : la compagnie achète un chariot (-%d écus)." % [c.day, WAGON_PRICE])
	return ""


## Revend un chariot (moitié prix), s'il n'est pas plein.
func sell_wagon(c: CampaignState) -> String:
	if wagons <= 0:
		return "La compagnie n'a pas de chariot."
	if load_total() > capacity(c) - WAGON_LOAD:
		return "Ce chariot est chargé : vendez d'abord des marchandises."
	wagons -= 1
	@warning_ignore("integer_division")
	c.gold += WAGON_PRICE / 2
	return ""


## Un jour passe : l'offre revient vers la normale, les caravanes en ville déchargent leurs
## marchandises, les villes assiégées s'affament.
func day(c: CampaignState) -> void:
	for t in supply.size():
		for k in GOODS.size():
			supply[t][k] = float(supply[t][k]) * RECOVERY
		if c.world.besieged(t):
			shift(t, "grain", -SIEGE_HUNGER)
			shift(t, "wine", -SIEGE_HUNGER)
	for p in c.overworld.parties:
		if p.kind != "caravan" or p.goods <= 0:
			continue
		var t := MapData.nearest_town(p.pos)
		if t == p.home or p.pos.distance_to(MapData.place_pos(t)) > MapData.PLACE_RADIUS * 2.0:
			continue
		var home := p.home if p.home >= 0 and p.home < PRODUCES.size() else t
		for g in PRODUCES[home]:
			shift(t, g, p.goods * CARAVAN_EFFECT)


## Après une bataille perdue : une partie de la cargaison reste aux mains de l'ennemi.
func after_battle(c: CampaignState, victory: bool) -> String:
	if victory or load_total() <= 0:
		return ""
	var lost := 0
	for g in cargo.keys():
		var n := int(ceil(int(cargo[g]) * DEFEAT_LOSS))
		take(g, n)
		lost += n
	return " L'ennemi emporte %s de marchandises." % CampaignState.plural(lost, "charge", "charges")


## Garde la cargaison dans la charge possible (après des pertes, la compagnie abandonne le surplus).
func fit_load(c: CampaignState) -> void:
	var over := load_total() - capacity(c)
	if over <= 0:
		return
	for g in GOODS:
		if over <= 0:
			break
		var n := mini(over, carried(g))
		if n > 0:
			take(g, n)
			over -= n


func cargo_text() -> String:
	var parts: Array[String] = []
	for g in GOODS:
		if carried(g) > 0:
			parts.append("%d %s" % [carried(g), good_name(g)])
	return ", ".join(parts) if not parts.is_empty() else "rien"


func to_dict() -> Dictionary:
	return {"supply": supply.duplicate(true), "cargo": cargo.duplicate(), "wagons": wagons, "bought": bought.duplicate()}


static func from_dict(v: Variant) -> Trade:
	var t := Trade.new()
	if not v is Dictionary:
		return t
	var s: Variant = v.get("supply", [])
	if s is Array and (s as Array).size() == t.supply.size():
		for i in t.supply.size():
			var row: Variant = s[i]
			if row is Array and (row as Array).size() == GOODS.size():
				for k in GOODS.size():
					t.supply[i][k] = clampf(float(row[k]), -1.0, 1.0)
	var cg: Variant = v.get("cargo", {})
	if cg is Dictionary:
		for g in cg:
			if str(g) in GOODS and int(cg[g]) > 0:
				t.cargo[str(g)] = int(cg[g])
	var b: Variant = v.get("bought", {})
	if b is Dictionary:
		for g in b:
			if t.cargo.has(str(g)):
				t.bought[str(g)] = float(b[g])
	t.wagons = clampi(int(v.get("wagons", 0)), 0, MAX_WAGONS)
	return t
