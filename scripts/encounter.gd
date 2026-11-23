class_name Encounter
extends RefCounted
## Rencontres de la carte en temps réel : quand la compagnie du joueur entre en contact avec un
## groupe (Party), un panneau propose des choix selon la sorte du groupe et son attitude.
##
## Interface (utilisée par le moteur de la carte) :
## - options(state, player, other) : choix possibles, {"id", "label", "hint", "enabled", "reason"}.
##   Aucun tirage au sort : l'affichage ne touche pas au rng de la campagne.
## - resolve(state, player, other, option_id) : applique le choix et renvoie
##   {"battle", "contract", "text", "remove_other", "other_flees", "player_flees"} plus
##   « option » (le choix), « close » (la rencontre est finie ; faux pour commercer, parler,
##   recruter : le panneau reste ouvert), « escort » et « join » (voir plus bas).
##   Les tirages se font ici, avec une graine dérivée du groupe, du jour et du choix.
## - greeting(state, player, other) : phrase d'accueil selon la sorte et l'attitude.
## - open(parent, state, player, other) : ouvre le panneau (encounter_panel.gd), qui émet
##   closed(result) quand la rencontre se termine. L'appelant lance la bataille si result.battle
##   (state.pending = result.contract, puis la scène de bataille ; après finish_battle, appeler
##   state.apply_party_battle(other, bilan)), retire ou fait fuir les groupes, et reprend le temps.
##
## La compagnie du joueur : player.troops si le moteur les remplit, sinon state.company.

## Attitudes d'un groupe envers la compagnie.
const ATTACKING := "attacking" ## Il fond sur la compagnie : combattre, payer ou fuir
const HOSTILE := "hostile"
const NEUTRAL := "neutral"
const FRIENDLY := "friendly"

## États (Party.state) d'un groupe qui poursuit sa cible pour l'attaquer.
const ATTACK_STATES := ["chase", "attack", "ambush"]

const INTIMIDATE_RATIO := 0.5 ## Intimider : ils sont au plus moitié moins forts
const EXTORT_RATIO := 1.5 ## Rançonner : la compagnie est au moins 1,5 fois plus forte
const TURN_IN_RATIO := 0.7 ## Livrer des déserteurs sans combat : ils sont nettement plus faibles
const PLUNDER_RATIO := 0.25 ## Piller une caravane presque sans gardes : elle se rend sans combat
const SURRENDER_GOLD := 0.25 ## Se rendre à une armée : part de l'or confisquée
const FOOD_PRICE := 0.9 ## Vivres : prix par rapport à la ville...
const FOOD_DAYS := 3 ## ... et jours de vivres vendus
const SELL_RATE := {"villagers": 0.6, "caravan": 0.9} ## Prix du butin revendu
const VOLUNTEER_PRICE := 0.8 ## Volontaires : prix d'un homme (x RECRUIT_COST)
const DESERTER_PRICE := 0.4 ## Déserteurs : à bas prix...
const DESERTER_MORALE_XP := 30.0 ## ... mais le moral bas : moitié moins aguerris que des déserteurs de route
const BOUNTY_PER_MAN := 3 ## Prime par déserteur livré à sa faction
const MIN_FLEE := 0.1 ## Sous cette chance, la fuite n'est pas proposée


# ---------------------------------------------------------------- Estimations

## Effectif de la compagnie du joueur.
static func player_men(state: CampaignState, player: Party) -> int:
	if player != null and not player.troops.is_empty():
		return player.men()
	return state.total_men()


## Force de la compagnie du joueur (même mesure que Party.strength).
static func player_strength(state: CampaignState, player: Party) -> float:
	if player != null and not player.troops.is_empty():
		return player.strength()
	var s := 0.0
	for r in state.company:
		s += float(r.get("men", 0)) * (1.0 + float(r.get("xp", 0.0)) / 200.0)
	return s


## Rapport de force : leur force / la nôtre (> 1 : ils sont plus forts).
static func ratio(state: CampaignState, player: Party, other: Party) -> float:
	return other.strength() / maxf(1.0, player_strength(state, player))


## « environ 60, surtout des archers » : effectif arrondi et type dominant.
static func estimate(troops: Array) -> String:
	var men := 0
	var by_type := {}
	for r in troops:
		var n := int(r.get("men", 0))
		men += n
		by_type[r["type"]] = int(by_type.get(r["type"], 0)) + n
	if men <= 0:
		return "personne en armes"
	var shown := men
	if men > 100:
		shown = int(round(men / 10.0)) * 10
	elif men > 20:
		shown = int(round(men / 5.0)) * 5
	var main := ""
	var best := 0
	for t in UnitTypes.ORDER:
		if int(by_type.get(t, 0)) > best:
			best = int(by_type[t])
			main = t
	var s := ("environ %d" % shown) if men > 20 else str(men)
	if main != "" and best * 2 >= men:
		s += ", surtout des %s" % str(UnitTypes.STATS[main]["name"]).to_lower()
	elif main != "":
		s += ", des %s et d'autres" % str(UnitTypes.STATS[main]["name"]).to_lower()
	return s


## Ligne de force affichée : « Ils sont environ 60, surtout des archers. »
static func strength_line(other: Party) -> String:
	if other.men() <= 0:
		return "Ils ne portent pas d'armes."
	return "Ils sont %s." % estimate(other.troops)


static func player_line(state: CampaignState, player: Party) -> String:
	var troops: Array = player.troops if player != null and not player.troops.is_empty() else state.company
	return "Vous êtes %s." % estimate(troops)


## Chance de fuir : la vitesse compte le plus, puis la taille (une petite troupe se dérobe mieux).
static func flee_chance(state: CampaignState, player: Party, other: Party) -> float:
	var ps := player.base_speed() if player != null else float(Party.BASE_SPEED["player"])
	var os := maxf(0.1, other.base_speed())
	var pm := float(player_men(state, player))
	var om := float(other.men())
	var c := 0.5 + 2.0 * (ps - os) / os
	if pm + om > 0.0:
		c += 0.4 * (om - pm) / (pm + om)
	return clampf(c, 0.05, 0.95)


## Faction locale (celle qui tient la ville d'attache du groupe, sinon celle où se trouve la compagnie).
static func local_faction(state: CampaignState, other: Party) -> int:
	if other.faction >= 0:
		return other.faction
	var t := other.home if other.home >= 0 and other.home < CampaignState.TOWNS.size() else state.location
	return state.town_owner(t)


static func faction_short(f: int) -> String:
	return str(CampaignState.FACTIONS[f]["short"]) if f >= 0 else ""


# ---------------------------------------------------------------- Attitude

## Le groupe fond-il sur la compagnie ?
static func is_attacking(player: Party, other: Party) -> bool:
	return player != null and other.target_id == player.id and other.state in ATTACK_STATES


## La compagnie est-elle en guerre avec la faction du groupe ? (le joueur sert une faction)
static func at_war(state: CampaignState, player: Party, other: Party) -> bool:
	return player != null and player.faction >= 0 and other.faction >= 0 and state.world.at_war(player.faction, other.faction)


## Attitude du groupe : ATTACKING, HOSTILE, NEUTRAL ou FRIENDLY.
static func attitude(state: CampaignState, player: Party, other: Party) -> String:
	var hostile := false
	var friendly := false
	var rep := state.reputation[other.faction] if other.faction >= 0 else 0
	match other.kind:
		"bandits":
			hostile = true
		"deserters":
			hostile = false
		"villagers", "caravan":
			hostile = other.faction >= 0 and state.faction_closed(other.faction)
			friendly = other.faction >= 0 and rep >= WorldSim.REP_FRIEND
		"patrol", "army":
			if other.faction >= 0:
				hostile = at_war(state, player, other) or rep <= CampaignState.REP_CLOSED
				if not hostile and rep < 0:
					for f in state.world.enemies_of(other.faction):
						if state.reputation[f] >= WorldSim.REP_FRIEND:
							hostile = true
				friendly = not hostile and rep >= WorldSim.REP_FRIEND
	if is_attacking(player, other) and (hostile or other.kind in ["deserters", "patrol", "army"]):
		return ATTACKING
	if hostile:
		return HOSTILE
	return FRIENDLY if friendly else NEUTRAL


# ---------------------------------------------------------------- Accueil

const GREETINGS := {
	"bandits": {
		ATTACKING: ["« La bourse ou la vie ! » Des hommes en guenilles surgissent, lames au clair.", "Des brigands vous barrent le chemin en ricanant : il va falloir payer le passage."],
		HOSTILE: ["Une bande de brigands campe au bord du chemin et vous jauge de loin.", "Des coupe-jarrets se figent en vous voyant approcher."],
	},
	"villagers": {
		HOSTILE: ["Les villageois serrent leurs fourches : ils n'ont pas oublié vos méfaits.", "« Passez au large, routiers ! » crie un ancien."],
		NEUTRAL: ["Des villageois mènent leurs bêtes sur la route et vous saluent prudemment.", "Une charrette de paysans s'écarte pour laisser passer la compagnie."],
		FRIENDLY: ["Les villageois vous reconnaissent et vous offrent à boire.", "« Voilà la compagnie qui nous protège ! » lance une fermière."],
	},
	"caravan": {
		HOSTILE: ["Les gardes de la caravane tirent l'épée : on vous tient pour des pillards.", "Le maître de la caravane fait serrer les chariots en vous voyant."],
		NEUTRAL: ["Une caravane de marchands avance au pas lourd des bœufs. Son maître vous fait signe.", "Des chariots bâchés cahotent sur la route, escortés de quelques lances."],
		FRIENDLY: ["Le maître de la caravane vous salue comme un vieil ami.", "« Des lances de confiance ! » se réjouit un marchand."],
	},
	"patrol": {
		ATTACKING: ["La patrouille vous somme de jeter les armes !", "Des cavaliers vous encerclent : « Au nom de {f}, rendez-vous ! »"],
		HOSTILE: ["Une patrouille de {f} vous observe, la main sur la garde.", "Les sergents de {f} vous regardent d'un mauvais œil."],
		NEUTRAL: ["Une patrouille de {f} s'arrête pour vous interroger.", "Les sergents de {f} vous demandent qui vous servez."],
		FRIENDLY: ["Une patrouille de {f} vous salue : vos exploits sont connus.", "Le sergent de {f} vous serre la main."],
	},
	"army": {
		ATTACKING: ["L'ost de {f} se déploie face à vous : rendez-vous ou combattez !", "Les bannières de {f} s'avancent, les trompettes sonnent la charge."],
		HOSTILE: ["L'armée de {f} couvre la route, menaçante.", "Les éclaireurs de {f} vous ont repérés et l'ost s'arrête."],
		NEUTRAL: ["L'ost de {f} passe en longue colonne. Un héraut vient à votre rencontre.", "Une armée de {f} fait halte ; ses capitaines vous jaugent."],
		FRIENDLY: ["L'ost de {f} vous accueille : on cherche toujours de bonnes lances.", "Un capitaine de {f} vous invite sous sa tente."],
	},
	"deserters": {
		ATTACKING: ["Des déserteurs aux abois tirent l'épée : ils ne seront pas pris vivants."],
		NEUTRAL: ["Des déserteurs fourbus se cachent dans un fossé. Ils lèvent les mains.", "Une poignée de soldats sans bannière vous demande du travail."],
	},
}


static func greeting(state: CampaignState, player: Party, other: Party) -> String:
	var att := attitude(state, player, other)
	var table: Dictionary = GREETINGS.get(other.kind, {})
	var list: Array = table.get(att, [])
	if list.is_empty():
		list = table.get(HOSTILE if att == ATTACKING else NEUTRAL, [])
	if list.is_empty():
		for k in table:
			list = table[k]
			break
	if list.is_empty():
		return "Vous croisez %s." % other.display_name()
	# Variante fixée par le groupe (sans tirage : l'affichage ne touche pas au hasard)
	var s := str(list[absi(other.id) % list.size()])
	var f := faction_short(other.faction)
	return s.replace("{f}", f if f != "" else "la région")


# ---------------------------------------------------------------- Choix

static func opt(id: String, label: String, hint: String, enabled := true, reason := "") -> Dictionary:
	return {"id": id, "label": label, "hint": hint, "enabled": enabled, "reason": reason if not enabled else ""}


## Tribut demandé par des bandits (ou rançon de passage).
static func toll(other: Party) -> int:
	return clampi(int(round(other.men() * 3.0 / 10.0)) * 10, 20, 500)


## Prix et rations des vivres vendus en chemin : FOOD_DAYS jours pour l'effectif (supplies.gd),
## un peu moins cher qu'en ville.
static func food_price(state: CampaignState) -> int:
	return maxi(1, ceili(food_cover(state) * Supplies.RATION_PRICE * FOOD_PRICE * Companions.food_factor(state)))


static func food_cover(state: CampaignState) -> float:
	return maxf(Supplies.consumption(state), 1.0) * FOOD_DAYS


## Butin revendu : ce que le groupe peut payer.
static func sale_value(state: CampaignState, other: Party) -> int:
	return mini(int(floor(state.loot * float(SELL_RATE.get(other.kind, 0.5)))), other.gold)


## Volontaires d'un village : piquiers, ou archers si la compagnie y est appréciée.
static func volunteer_type(state: CampaignState, other: Party) -> String:
	var f := local_faction(state, other)
	return "archer" if f >= 0 and state.reputation[f] >= WorldSim.REP_FRIEND else "spear"


static func volunteer_count(state: CampaignState, other: Party) -> int:
	var f := local_faction(state, other)
	var rep := state.reputation[f] if f >= 0 else 0
	@warning_ignore("integer_division")
	return clampi(other.men() / 4 + rep / 10, 0, 12)


static func volunteer_cost(type: String, n: int, unit_price: float) -> int:
	return int(ceil(int(CampaignState.RECRUIT_COST[type]) * n * unit_price))


## Combien la compagnie peut accueillir d'hommes d'un type (régiments entamés, puis un nouveau).
static func room_for(state: CampaignState, type: String) -> int:
	if Challenges.forbids_type(state.challenges, type):
		return 0 # Défi « Sans cavalerie »
	var room := 0
	for r in state.company:
		if r["type"] == type:
			room += int(UnitTypes.STATS[type]["count"]) - int(r["men"])
	if state.company.size() < CampaignState.MAX_REGIMENTS:
		room += int(UnitTypes.STATS[type]["count"])
	return room


## Recrues ajoutées aux régiments de leur type, puis en un nouveau régiment. Renvoie le nombre pris.
static func add_to_company(state: CampaignState, type: String, n: int, xp: float) -> int:
	var left := n
	for r in state.company:
		if left <= 0:
			break
		if r["type"] == type:
			var k := mini(left, int(UnitTypes.STATS[type]["count"]) - int(r["men"]))
			if k > 0:
				CampaignState.add_men(r, k, xp)
				left -= k
	if left > 0 and state.company.size() < CampaignState.MAX_REGIMENTS:
		var k := mini(left, int(UnitTypes.STATS[type]["count"]))
		state.company.append({"type": type, "men": k, "xp": xp})
		left -= k
	return n - left


## Retire n hommes d'un groupe (des régiments les plus nombreux d'abord).
static func take_men(other: Party, n: int) -> void:
	var left := n
	while left > 0 and other.men() > 0:
		var best := 0
		for i in other.troops.size():
			if int(other.troops[i]["men"]) > int(other.troops[best]["men"]):
				best = i
		other.troops[best]["men"] = int(other.troops[best]["men"]) - 1
		left -= 1
	other.troops = other.troops.filter(func(r: Dictionary) -> bool: return int(r["men"]) > 0)


static func options(state: CampaignState, player: Party, other: Party) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var att := attitude(state, player, other)
	var r := ratio(state, player, other)
	var fc := flee_chance(state, player, other)
	var gold := int(state.gold)
	var fight_hint := "Bataille. %s" % strength_line(other)
	var flee_opt := opt("flee", "Fuir", "Chance de vous dérober : %d %%. Sinon, il faudra se battre." % int(round(fc * 100.0)),
		fc >= MIN_FLEE, "Ils sont bien plus rapides que vous.")
	if att == ATTACKING:
		out.append(opt("attack", "Combattre", fight_hint))
		if other.kind in ["patrol", "army"]:
			var lose := int(floor(state.gold * SURRENDER_GOLD))
			out.append(opt("surrender", "Se rendre", "Ils confisquent %d écus et vous laissent repartir." % lose))
		else:
			var t := toll(other)
			out.append(opt("pay", "Payer %d écus" % t, "Ils vous laissent passer.", gold >= t, "Il vous faut %d écus." % t))
		out.append(flee_opt)
		return out
	match other.kind:
		"bandits":
			out.append(opt("attack", "Attaquer", fight_hint))
			var t := toll(other)
			out.append(opt("pay", "Payer un tribut (%d écus)" % t, "Ils vous laissent passer.", gold >= t, "Il vous faut %d écus." % t))
			out.append(opt("intimidate", "Les intimider", "Ils fuient ou se rendent (et leur bourse avec).",
				r <= INTIMIDATE_RATIO, "Ils sont trop nombreux pour avoir peur de vous."))
			out.append(flee_opt)
		"villagers":
			var closed := att == HOSTILE
			add_trade(state, other, out, closed)
			var vt := volunteer_type(state, other)
			var vn := mini(volunteer_count(state, other), room_for(state, vt))
			var vc := volunteer_cost(vt, vn, VOLUNTEER_PRICE)
			var why := ""
			if closed:
				why = "Ils ne veulent pas vous suivre."
			elif volunteer_count(state, other) <= 0:
				why = "Personne ne veut s'engager."
			elif vn <= 0:
				why = "La compagnie est au complet."
			elif gold < vc:
				why = "Il vous faut %d écus." % vc
			out.append(opt("recruit", "Recruter des volontaires", "%s pour %d écus." % [CampaignState.type_count(vt, vn), vc] if vn > 0 else "Des %s." % CampaignState.type_name(vt).to_lower(), why == "", why))
			var f := local_faction(state, other)
			out.append(opt("extort", "Les rançonner", "%d écus ; %s vous en voudra." % [extort_value(other), faction_short(f) if f >= 0 else "le pays"],
				r * EXTORT_RATIO <= 1.0, "Ils sont prêts à se défendre."))
			out.append(opt("attack", "Les attaquer", fight_hint + " %s vous en voudra." % CampaignState.cap_first(faction_short(f)) if f >= 0 else fight_hint))
			out.append(opt("leave", "Passer son chemin", ""))
		"caravan":
			var closed := att == HOSTILE
			add_trade(state, other, out, closed)
			var reward := escort_reward(other)
			var why := ""
			if closed:
				why = "Le marchand se méfie de vous."
			elif other.goal < 0:
				why = "La caravane ne va nulle part."
			elif not state.escort_for(other.id).is_empty():
				why = "Vous l'escortez déjà."
			out.append(opt("escort", "Proposer une escorte", "%d écus à l'arrivée%s." % [reward, destination_text(other)], why == "", why))
			var f := other.faction
			out.append(opt("plunder", "La piller", "%s %s" % [strength_line(other), ("%s ne vous le pardonnera pas." % CampaignState.cap_first(faction_short(f))) if f >= 0 else "Toute la région l'apprendra."]))
			out.append(opt("leave", "Passer son chemin", ""))
		"patrol", "army":
			var hostile := att == HOSTILE
			out.append(opt("talk", "Parler", "Nouvelles et contrats.", not hostile, "Ils ne veulent rien entendre."))
			var rep := state.reputation[other.faction] if other.faction >= 0 else 0
			out.append(opt("join", "Se joindre à eux", "Suivre leur marche et combattre à leurs côtés.",
				other.faction >= 0 and not hostile and rep >= WorldSim.REP_FRIEND,
				"Il faut être en bons termes avec %s." % faction_short(other.faction) if other.faction >= 0 else "Ils ne servent personne."))
			out.append(opt("attack", "Attaquer", fight_hint, hostile, "Vous n'êtes pas en guerre contre %s." % faction_short(other.faction) if other.faction >= 0 else "Rien ne justifie l'attaque."))
			if hostile and r > 1.0:
				var lose := int(floor(state.gold * SURRENDER_GOLD))
				out.append(opt("surrender", "Se rendre", "Ils confisquent %d écus et vous laissent repartir." % lose))
				out.append(flee_opt)
			else:
				out.append(opt("leave", "Passer son chemin", ""))
		"deserters":
			var room := room_for(state, deserter_type(other))
			var n := mini(other.men(), room)
			var cost := volunteer_cost(deserter_type(other), n, DESERTER_PRICE)
			var why := ""
			if other.men() <= 0:
				why = "Il n'y a personne à recruter."
			elif n <= 0:
				why = "La compagnie est au complet."
			elif gold < cost:
				why = "Il vous faut %d écus." % cost
			out.append(opt("recruit", "Les recruter", "%s pour %d écus (moral bas)." % [CampaignState.type_count(deserter_type(other), n), cost] if n > 0 else "À bas prix, mais le moral est bas.", why == "", why))
			var f := local_faction(state, other)
			var bounty := other.men() * BOUNTY_PER_MAN
			out.append(opt("turn_in", "Les livrer", "Prime de %d écus de %s." % [bounty, faction_short(f) if f >= 0 else "la prévôté"],
				f >= 0 and r <= TURN_IN_RATIO, "Ils sont trop nombreux pour être pris sans combat." if f >= 0 else "Personne ne les réclame."))
			out.append(opt("attack", "Les attaquer", fight_hint))
			out.append(opt("leave", "Passer son chemin", ""))
		_:
			out.append(opt("attack", "Attaquer", fight_hint))
			out.append(opt("leave", "Passer son chemin", ""))
	return out


## Commerce (villageois, caravane) : acheter des vivres, vendre du butin.
static func add_trade(state: CampaignState, other: Party, out: Array[Dictionary], closed: bool) -> void:
	var price := food_price(state)
	var why := ""
	if closed:
		why = "Ils refusent de commercer avec vous."
	elif other.goods <= 0:
		why = "Ils n'ont rien à vendre."
	elif Supplies.is_full(state):
		why = "Vos chariots sont déjà pleins."
	elif state.gold < price:
		why = "Il vous faut %d écus." % price
	out.append(opt("buy_food", "Acheter des vivres", "%d écus : %s de vivres." % [price, CampaignState.plural(FOOD_DAYS, "jour", "jours")], why == "", why))
	var value := sale_value(state, other)
	why = ""
	if closed:
		why = "Ils refusent de commercer avec vous."
	elif state.loot <= 0:
		why = "Vous n'avez pas de butin à vendre."
	elif value <= 0:
		why = "Ils n'ont pas de quoi payer."
	out.append(opt("sell_loot", "Vendre du butin", "%d écus pour %d écus de butin." % [value, state.loot] if value > 0 else "", why == "", why))


static func extort_value(other: Party) -> int:
	@warning_ignore("integer_division")
	return maxi(10, other.gold + other.goods / 2)


static func escort_reward(other: Party) -> int:
	return clampi(int(round(other.goods / 100.0)) * 10 + 40, 40, 250)


static func destination_text(other: Party) -> String:
	if other.goal >= 0 and other.goal < CampaignState.TOWNS.size():
		return " à %s" % CampaignState.TOWNS[other.goal]["name"]
	return ""


## Type des déserteurs recrutés : leur régiment le plus nombreux.
static func deserter_type(other: Party) -> String:
	var best := "spear"
	var n := 0
	for r in other.troops:
		if int(r["men"]) > n:
			n = int(r["men"])
			best = str(r["type"])
	return best


# ---------------------------------------------------------------- Résolution

## Hasard d'une rencontre : graine dérivée du groupe, du jour et du choix (jamais state.rng).
static func roll_rng(state: CampaignState, other: Party, option_id: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([other.id, state.day, option_id])
	return r


static func empty_result(option_id: String) -> Dictionary:
	return {"battle": false, "contract": {}, "text": "", "remove_other": false, "other_flees": false,
		"player_flees": false, "option": option_id, "close": true, "escort": false, "join": false}


## Un groupe qui poursuivait la compagnie la laisse tranquille.
static func calm(player: Party, other: Party) -> void:
	if player != null and other.target_id == player.id:
		other.target_id = -1
		other.state = "idle"


static func battle_result(state: CampaignState, other: Party, option_id: String, text: String) -> Dictionary:
	var out := empty_result(option_id)
	var terrain := str(WorldSim.ROAD_TERRAINS[roll_rng(state, other, "terrain").randi() % WorldSim.ROAD_TERRAINS.size()])
	out["battle"] = true
	out["contract"] = state.party_contract(other, terrain)
	out["text"] = text
	return out


static func resolve(state: CampaignState, player: Party, other: Party, option_id: String) -> Dictionary:
	var out := empty_result(option_id)
	var chosen: Dictionary = {}
	for o in options(state, player, other):
		if o["id"] == option_id:
			chosen = o
	if chosen.is_empty() or not bool(chosen["enabled"]):
		out["close"] = false
		out["text"] = "Impossible : %s" % (str(chosen.get("reason", "")) if not chosen.is_empty() else "ce choix n'est pas proposé.")
		return out
	var who := other.display_name()
	var rng := roll_rng(state, other, option_id)
	match option_id:
		"attack":
			if other.is_dead():
				return take_all(state, other, out, "Ils n'opposent aucune résistance.")
			return battle_result(state, other, option_id, "La compagnie se jette sur %s !" % who)
		"pay":
			var t := toll(other)
			state.gold -= t
			other.gold += t
			calm(player, other)
			out["text"] = "Vous payez %d écus à %s, qui vous laissent passer." % [t, who]
		"surrender":
			var lose := int(floor(state.gold * SURRENDER_GOLD))
			state.gold -= lose
			other.gold += lose
			calm(player, other)
			out["player_flees"] = true
			out["text"] = "Vous rendez les armes. %s confisque %d écus puis vous laisse repartir." % [CampaignState.cap_first(who), lose]
		"flee":
			var c := flee_chance(state, player, other)
			if rng.randf() < c:
				out["player_flees"] = true
				out["text"] = "La compagnie se dérobe et distance %s." % who
			else:
				return battle_result(state, other, option_id, "Trop lents ! %s vous rattrape : il faut se battre." % CampaignState.cap_first(who))
		"intimidate":
			var r := ratio(state, player, other)
			if rng.randf() < clampf(0.9 - r * 1.6, 0.1, 0.8):
				var f := local_faction(state, other)
				var loot := other.gold
				state.gold += loot
				state.gold_earned += loot
				out["remove_other"] = true
				out["text"] = "%s jettent leurs armes et se rendent. Vous saisissez %d écus." % [CampaignState.cap_first(who), loot]
				if f >= 0:
					state.change_reputation(f, CampaignState.REP_BANDITS)
					out["text"] += " Réputation : %s %+d." % [faction_short(f), CampaignState.REP_BANDITS]
			else:
				out["other_flees"] = true
				calm(player, other)
				out["text"] = "%s détalent sans demander leur reste." % CampaignState.cap_first(who)
		"buy_food":
			var price := food_price(state)
			state.gold -= price
			other.gold += price
			other.goods = maxi(0, other.goods - price)
			Supplies.add(state, food_cover(state))
			out["close"] = false
			out["text"] = "Vous achetez des vivres pour %d écus : %s de plus dans les chariots." % [price, CampaignState.plural(FOOD_DAYS, "jour", "jours")]
		"sell_loot":
			var value := sale_value(state, other)
			var rate := float(SELL_RATE.get(other.kind, 0.5))
			var sold := mini(state.loot, int(ceil(value / rate)))
			state.loot -= sold
			state.gold += value
			state.gold_earned += value
			other.gold -= value
			other.goods += sold
			out["close"] = false
			out["text"] = "Vous vendez %d écus de butin pour %d écus." % [sold, value]
		"recruit":
			if other.kind == "deserters":
				var type := deserter_type(other)
				var n := mini(other.men(), room_for(state, type))
				var cost := volunteer_cost(type, n, DESERTER_PRICE)
				state.gold -= cost
				var got := add_to_company(state, type, n, DESERTER_MORALE_XP)
				take_men(other, got)
				out["remove_other"] = other.is_dead()
				out["close"] = other.is_dead()
				out["text"] = "%s rejoignent la compagnie pour %d écus. Ils traînent les pieds." % [CampaignState.type_count(type, got), cost]
			else:
				var type := volunteer_type(state, other)
				var n := mini(volunteer_count(state, other), room_for(state, type))
				var cost := volunteer_cost(type, n, VOLUNTEER_PRICE)
				state.gold -= cost
				other.gold += cost
				var got := add_to_company(state, type, n, 0.0)
				take_men(other, got)
				out["close"] = false
				out["text"] = "%s du village s'engagent pour %d écus." % [CampaignState.cap_first(CampaignState.type_count(type, got)), cost]
		"extort":
			var take := extort_value(other)
			@warning_ignore("integer_division")
			other.goods = maxi(0, other.goods - (take - other.gold) * 2)
			other.gold = 0
			state.gold += take
			state.gold_earned += take
			out["other_flees"] = true
			out["text"] = "Vous rançonnez %s : %d écus." % [who, take]
			var f := local_faction(state, other)
			if f >= 0:
				state.change_reputation(f, CampaignState.REP_EXTORT)
				out["text"] += " Réputation : %s %+d." % [faction_short(f), CampaignState.REP_EXTORT]
		"plunder":
			if other.is_dead() or ratio(state, player, other) <= PLUNDER_RATIO:
				var f := other.faction
				out = take_all(state, other, out, "Les gardes de la caravane jettent leurs armes.")
				if f >= 0:
					state.change_reputation(f, CampaignState.REP_PLUNDER)
					out["text"] += " Réputation : %s %+d." % [faction_short(f), CampaignState.REP_PLUNDER]
				return out
			return battle_result(state, other, option_id, "La compagnie fond sur la caravane !")
		"escort":
			var e := state.start_escort(other, escort_reward(other))
			out["escort"] = true
			calm(player, other)
			out["text"] = "Marché conclu : %d écus si la caravane arrive%s. Elle compte sur vous." % [int(e["reward"]), destination_text(other)]
		"talk":
			out["close"] = false
			out["text"] = news(state, other)
		"join":
			out["join"] = true
			if player != null:
				player.target_id = other.id
				player.state = "follow"
			out["text"] = "La compagnie se range derrière les bannières de %s." % faction_short(other.faction)
		"turn_in":
			var f := local_faction(state, other)
			var bounty := other.men() * BOUNTY_PER_MAN
			state.gold += bounty
			state.gold_earned += bounty
			state.change_reputation(f, CampaignState.REP_TURN_IN)
			out["remove_other"] = true
			out["text"] = "Vous livrez %s à %s : prime de %d écus. Réputation : %s %+d." % [who, faction_short(f), bounty, faction_short(f), CampaignState.REP_TURN_IN]
		"leave":
			out["text"] = "Vous passez votre chemin."
		_:
			out["close"] = false
			out["text"] = "Choix inconnu."
	if out["text"] != "" and option_id != "talk":
		state.add_log("Jour %d : %s" % [state.day, out["text"]])
	return out


## Le groupe se rend sans combat : la compagnie prend son or et ses marchandises.
static func take_all(state: CampaignState, other: Party, out: Dictionary, why: String) -> Dictionary:
	state.gold += other.gold
	state.gold_earned += other.gold
	state.loot += other.goods
	out["text"] = "%s Vous prenez %d écus et %d écus de marchandises." % [why, other.gold, other.goods]
	other.gold = 0
	other.goods = 0
	out["remove_other"] = true
	return out


## Nouvelles d'une patrouille ou d'une armée : guerres en cours et contrats de sa faction.
static func news(state: CampaignState, other: Party) -> String:
	var s := "« La guerre ? %s. »" % CampaignState.cap_first(state.world.wars_text())
	if other.faction >= 0:
		var n := 0
		for c in state.contracts:
			if int(c.get("faction", -1)) == other.faction:
				n += 1
		if n > 0:
			s += " %s cherche des lances : %s." % [CampaignState.cap_first(faction_short(other.faction)), CampaignState.plural(n, "contrat ouvert", "contrats ouverts")]
		else:
			s += " %s n'a pas de contrat pour vous en ce moment." % CampaignState.cap_first(faction_short(other.faction))
	return s


# ---------------------------------------------------------------- Panneau

static func open(parent: Node, state: CampaignState, player: Party, other: Party) -> Node:
	var panel := EncounterPanel.new()
	panel.setup(state, player, other)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "Rencontre"
	parent.add_child(layer)
	layer.add_child(panel)
	panel.closed.connect(func(_r: Dictionary) -> void: layer.queue_free())
	return panel
