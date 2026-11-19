class_name Diplomacy
extends RefCounted
## Diplomatie : la compagnie peut prêter allégeance à une faction (CampaignState.FACTIONS), ou
## rester indépendante (liege = -1 : le comportement de la campagne ne change en rien).
##
## Vassale, elle reçoit une solde chaque mois (PAY_DAYS), lève des troupes dans les châteaux de son
## suzerain (fiefs.gd) et se voit réserver un contrat mieux payé dans sa capitale. En échange, elle
## entre en guerre avec ses ennemis : leurs villes lui ferment leurs portes, leurs patrouilles et leurs
## armées la pourchassent (Overworld : la compagnie porte la faction de son suzerain), et sa
## réputation chute auprès d'eux au serment. Combattre les troupes de son suzerain coûte cher en
## réputation. Rompre le serment est une trahison : grosse perte de réputation et de renommée.
## Branché par CampaignState (bloc « Domaine ») et WorldSim.hostile_to_player.

const SWEAR_REP := 20 ## Réputation minimale pour être reçu vassal
const PAY_DAYS := 30 ## Solde du suzerain : tous les tant de jours
const PAY_BASE := 150
const PAY_FAME := 2.0 ## ... plus tant par point de renommée
const SWEAR_ENEMY_REP := -10 ## Au serment : réputation auprès des ennemis (en guerre) du suzerain
const ALLY_FIGHT_REP := -15 ## Combattre les troupes de son suzerain
const BREAK_REP := -45 ## Rompre son serment
const BREAK_FAME := 15
const REJOIN_DAYS := 60 ## Une faction trahie ne reprend pas la compagnie avant tant de jours
const RESERVED_BONUS := 1.25 ## Prime du contrat réservé au vassal

var liege := -1 ## Faction servie (-1 : indépendante)
var sworn_day := 0
var last_pay := 0
var broken := {} ## str(faction) -> jour de la rupture


func is_vassal() -> bool:
	return liege >= 0


## La compagnie est-elle en guerre avec la faction f (par son suzerain) ?
func at_war_with(c: CampaignState, f: int) -> bool:
	return liege >= 0 and f >= 0 and f != liege and c.world.at_war(liege, f)


func monthly_pay(c: CampaignState) -> int:
	return int(round((PAY_BASE + c.fame * PAY_FAME) * Difficulty.value(c.difficulty, "reward") / 10.0)) * 10


## Raison pour laquelle f ne reçoit pas le serment de la compagnie dans la ville town ("" : possible).
func swear_refusal(c: CampaignState, f: int, town: int) -> String:
	if liege >= 0:
		return "La compagnie sert déjà %s." % CampaignState.FACTIONS[liege]["short"]
	if f < 0 or f >= CampaignState.FACTIONS.size():
		return "Faction inconnue."
	if town < 0 or c.town_owner(town) != f:
		return "Le serment se prête dans une ville de %s." % CampaignState.FACTIONS[f]["short"]
	if broken.has(str(f)) and c.day - int(broken[str(f)]) < REJOIN_DAYS:
		return "%s n'a pas oublié votre trahison (encore %d jours)." % [CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])), REJOIN_DAYS - (c.day - int(broken[str(f)]))]
	if c.reputation[f] < SWEAR_REP:
		return "%s ne reçoit le serment que d'une compagnie amie (réputation %d au moins)." % [CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"])), SWEAR_REP]
	return ""


## Prêter allégeance à f. Renvoie une erreur ou "".
func swear(c: CampaignState, f: int, town: int) -> String:
	var why := swear_refusal(c, f, town)
	if why != "":
		return why
	liege = f
	sworn_day = c.day
	last_pay = c.day
	c.overworld.player.faction = f
	var notes: Array[String] = []
	for e in c.world.enemies_of(f):
		c.change_reputation(e, SWEAR_ENEMY_REP)
		notes.append("%s %+d" % [CampaignState.FACTIONS[e]["short"], SWEAR_ENEMY_REP])
	var msg := "Jour %d : la compagnie prête allégeance à %s. Solde de %d écus par mois." % [c.day, CampaignState.faction_name(f), monthly_pay(c)]
	if not notes.is_empty():
		msg += " Ses ennemis deviennent les vôtres (%s)." % ", ".join(notes)
	c.add_log(msg)
	return ""


## Rompre le serment : trahison. Renvoie une erreur ou "".
func break_oath(c: CampaignState) -> String:
	if liege < 0:
		return "La compagnie ne sert personne."
	var f := liege
	c.change_reputation(f, BREAK_REP)
	c.fame = maxi(0, c.fame - BREAK_FAME)
	broken[str(f)] = c.day
	leave(c)
	c.add_log("Jour %d : la compagnie rompt son serment envers %s (réputation %+d, renommée -%d)." % [c.day, CampaignState.faction_name(f), BREAK_REP, BREAK_FAME])
	return ""


## La compagnie redevient indépendante (contrats réservés retirés).
func leave(c: CampaignState) -> void:
	c.contracts = c.contracts.filter(func(k: Dictionary) -> bool: return not k.get("liege", false) or is_same(k, c.pending))
	liege = -1
	c.overworld.player.faction = -1


## Message de refus d'une ville tenue par un ennemi du suzerain ("" sinon).
func closed(c: CampaignState, town: int) -> String:
	var f := c.town_owner(town)
	if at_war_with(c, f):
		return "%s est en guerre contre votre suzerain : ses villes vous sont fermées." % CampaignState.cap_first(str(CampaignState.FACTIONS[f]["short"]))
	return ""


## Un jour passe : solde mensuelle, contrat réservé, suzerain sans terre.
func day(c: CampaignState) -> void:
	c.overworld.player.faction = liege
	if liege < 0:
		return
	if c.world.towns_of(liege).is_empty():
		c.add_log("Jour %d : %s a perdu toutes ses villes ; la compagnie est libérée de son serment." % [c.day, CampaignState.faction_name(liege)])
		leave(c)
		return
	if c.day - last_pay >= PAY_DAYS:
		var pay := monthly_pay(c)
		last_pay = c.day
		c.gold += pay
		c.gold_earned += pay
		c.add_log("Jour %d : %s verse sa solde à la compagnie : %d écus." % [c.day, CampaignState.cap_first(str(CampaignState.FACTIONS[liege]["short"])), pay])
	ensure_reserved(c)


## Le suzerain réserve un contrat à la compagnie dans sa capitale (ou sa ville la mieux gardée).
func ensure_reserved(c: CampaignState) -> void:
	if c.ended != "" or liege < 0:
		return
	for k in c.contracts:
		if k.get("liege", false):
			return
	var town := c.final_town(liege)
	if town < 0:
		return
	var k := c.make_contract(town)
	k["liege"] = true
	k["reward"] = int(round(int(k["reward"]) * RESERVED_BONUS / 10.0)) * 10
	k["title"] = "Pour votre suzerain : %s" % str(k["title"])
	c.contracts.append(k)


## Après une bataille : combattre les troupes de son suzerain coûte cher.
func after_battle(c: CampaignState, _victory: bool) -> String:
	if liege < 0 or int(c.pending.get("enemy_faction", -1)) != liege:
		return ""
	c.change_reputation(liege, ALLY_FIGHT_REP)
	return " Vous avez combattu les troupes de votre suzerain : %s %+d." % [CampaignState.FACTIONS[liege]["short"], ALLY_FIGHT_REP]


func status_text(c: CampaignState) -> String:
	if liege < 0:
		return "Compagnie indépendante : elle ne sert que ses contrats."
	var next := maxi(0, PAY_DAYS - (c.day - last_pay))
	return "Vassale de %s depuis le jour %d. Solde de %d écus dans %s." % [CampaignState.faction_name(liege), sworn_day, monthly_pay(c), CampaignState.plural(next, "jour", "jours")]


func to_dict() -> Dictionary:
	return {"liege": liege, "sworn_day": sworn_day, "last_pay": last_pay, "broken": broken.duplicate()}


static func from_dict(v: Variant) -> Diplomacy:
	var d := Diplomacy.new()
	if not v is Dictionary:
		return d
	d.liege = clampi(int(v.get("liege", -1)), -1, CampaignState.FACTIONS.size() - 1)
	d.sworn_day = int(v.get("sworn_day", 0))
	d.last_pay = int(v.get("last_pay", 0))
	var b: Variant = v.get("broken", {})
	if b is Dictionary:
		for k in b:
			d.broken[str(k)] = int(b[k])
	return d
