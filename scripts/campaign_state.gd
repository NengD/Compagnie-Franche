class_name CampaignState
extends RefCounted
## État de la campagne : jour, or, compagnie, villes et contrats.
## Il survit aux changements de scène grâce à la variable statique « current ».
## current == null (ou aucun contrat en cours) : la bataille est une escarmouche isolée.

static var current: CampaignState = null

const START_GOLD := 300
## Compagnie de départ des tests et des bancs ; une vraie campagne part sans un homme et lève ses
## régiments avec l'or équivalent (new_game, empty).
const START_COMPANY := ["spear", "spear", "men_at_arms", "archer", "archer", "cavalry"]
const MAX_REGIMENTS := 8
const TRAVEL_PX_PER_DAY := 130.0 * MapData.SCALE ## Distance parcourue en une journée de marche abstraite (travel)
const CONTRACT_DAYS := 14 ## Validité d'un contrat, en jours
const DESERT_RATE := 0.15 ## Part des hommes qui désertent chaque jour sans solde
const WOUNDED_RECOVER := 0.3 ## Part des tombés relevés blessés après une victoire
const LOOT_PER_KILL := 2 ## Butin ramassé sur chaque ennemi tué, après une victoire
## Solde quotidienne d'un homme, en écus
## (nouvelles unités : arbalétriers, chevaliers à pied, archers montés en fin de ligne)
const WAGE := {"spear": 0.3, "archer": 0.35, "men_at_arms": 0.6, "cavalry": 1.0,
	"crossbow": 0.45, "foot_knight": 1.4, "horse_archer": 0.9}
## Prix d'enrôlement d'un homme, en écus (modulé par la ville, voir TOWNS « price »)
const RECRUIT_COST := {"spear": 6, "archer": 7, "men_at_arms": 12, "cavalry": 20,
	"crossbow": 10, "foot_knight": 30, "horse_archer": 18}

## Expérience : seuils des rangs (recrues, aguerris, vétérans) et gains après une bataille
const RANK_XP := [0.0, 100.0, 250.0]
const XP_MAX := 400.0
const XP_BATTLE := 25.0 ## Avoir combattu
const XP_VICTORY := 25.0 ## Avoir vaincu
const XP_KILLS := 60.0 ## Avoir tué autant d'ennemis que le régiment compte d'hommes au complet

## Factions qui se partagent les villes. « rival » : faction lésée quand on sert celle-ci.
## « capital » : ville où la faction convoque la compagnie pour la bataille décisive.
const FACTIONS := [
	{"name": "Comté de Valfrène", "short": "le Comté", "rival": 1, "capital": 1, "color": Color(0.92, 0.76, 0.3)},
	{"name": "Baronnie de Montfaucon", "short": "la Baronnie", "rival": 0, "capital": 2, "color": Color(0.62, 0.25, 0.55)},
	{"name": "Ligue des villes", "short": "la Ligue", "rival": 1, "capital": 6, "color": Color(0.3, 0.62, 0.38)},
]
const REP_MIN := -100
const REP_MAX := 100
const REP_WIN := 10 ## Contrat gagné : réputation auprès de la faction qui paie
const REP_RIVAL := -5 ## ... et auprès de sa rivale
const REP_CLOSED := -30 ## À ce niveau, la faction ne propose plus de contrat et refuse de recruter
const REP_REWARD := 0.005 ## Prime : +0,5 % par point de réputation (de x0,5 à x1,5)
const REP_LOSS := -8 ## Contrat perdu : la faction qui payait est déçue
const REP_RETREAT := -4 ## ... moins après une retraite ordonnée
const PILLAGE := 0.3 ## Part de l'or pillée dans les bagages après une défaite
const PILLAGE_RETREAT := 0.1 ## ... après une retraite (les bagages sont en partie sauvés)
const FAME_LOSS := 10
const FAME_RETREAT := 5
const FAME_STEP := 25 ## Renommée nécessaire pour chaque niveau de difficulté des contrats
const FAME_REWARD := 0.002 ## Prime : +0,2 % par point de renommée (une compagnie célèbre se paie cher)

## Objectif de la campagne : à FINAL_FAME de renommée, la faction la plus amie convoque la
## compagnie pour la bataille qui décidera de la guerre du comté. La gagner termine la campagne.
const FINAL_FAME := 150
## Game over : la compagnie n'a plus un homme et ne peut plus lever de régiment (ruinée).
const ENDINGS := ["", "victory", "ruin"]

## Villes de la carte (voir MapData, seule source de vérité de la géographie) : nom, position
## sur la grande carte, faction de départ, prix des recrues (x RECRUIT_COST) et troupes qu'on y lève.
const TOWNS := MapData.TOWNS
const ROADS := MapData.TOWN_ROADS ## Grandes routes entre les villes (marche abstraite, armées)

## Modèles de contrats, du niveau 1 au niveau MAX_LEVEL : composition de l'ennemi, effectifs
## (part du plein), prime de base et expérience des régiments ennemis (« ranks » : chance d'être
## aguerri, chance d'être vétéran). « {rival} » : la faction ennemie tirée pour le contrat
## (roll_enemy_faction, le plus souvent la rivale de celle de la ville). « band » : qui lève
## l'armée, ce qui la colore (flavor_army) : brigands, routiers (plus de cavalerie) ou faction.
## Nouvelles unités : arbalétriers dès le niveau 2, archers montés au niveau 4, chevaliers à pied
## au niveau 5 et dans la bataille décisive (ils remplacent des régiments, l'effectif ne grossit pas).
const CONTRACT_KINDS := [
	{
		"difficulty": 1, "foe": "brigands", "band": "brigands", "reward": 260, "fill": [0.6, 0.85], "ranks": [0.0, 0.0],
		"army": ["spear", "spear", "men_at_arms", "archer"],
		"titles": ["Brigands sur la route de %s", "Des coupe-jarrets près de %s"],
		"text": "Une bande de brigands rançonne les marchands. Le bourg paie pour qu'on l'en débarrasse.",
	},
	{
		"difficulty": 2, "foe": "routiers", "band": "routiers", "reward": 450, "fill": [0.75, 1.0], "ranks": [0.4, 0.0],
		"army": ["spear", "spear", "men_at_arms", "crossbow", "cavalry"],
		"titles": ["Routiers aux portes de %s", "Une compagnie rivale menace %s"],
		"text": "Des routiers sans contrat pillent la campagne. Ils sont aguerris et ont quelques cavaliers.",
	},
	{
		"difficulty": 3, "foe": "gens de {rival}", "band": "faction", "reward": 720, "fill": [0.8, 0.95], "ranks": [0.5, 0.0],
		"army": ["spear", "spear", "men_at_arms", "men_at_arms", "archer", "crossbow", "cavalry"],
		"titles": ["Querelle de frontière devant %s", "Défendre %s contre {rival}"],
		"text": "Un seigneur de {rival} lève son ost contre la ville, qui engage des lances pour lui tenir tête en rase campagne.",
	},
	{
		"difficulty": 4, "foe": "routiers de la Grande Compagnie", "band": "routiers", "reward": 1000, "fill": [0.85, 1.0], "ranks": [0.45, 0.15],
		"army": ["spear", "spear", "men_at_arms", "men_at_arms", "archer", "crossbow", "horse_archer"],
		"titles": ["La Grande Compagnie marche sur %s", "Chevauchée de routiers autour de %s"],
		"text": "Plusieurs bandes se sont unies sous un même capitaine. Nombreuse et aguerrie, la Grande Compagnie rançonne des provinces entières.",
	},
	{
		"difficulty": 5, "foe": "armées de {rival}", "band": "faction", "reward": 1350, "fill": [0.8, 0.95], "ranks": [0.5, 0.2],
		"army": ["spear", "spear", "men_at_arms", "men_at_arms", "foot_knight", "archer", "crossbow", "cavalry"],
		"titles": ["L'ost de {rival} menace %s", "Bataille rangée devant %s"],
		"text": "{Rival} lève son ost et marche sur la ville. Ses chevaliers sont des vétérans de toutes les guerres.",
	},
]
const MAX_LEVEL := 5 ## Niveau de contrat le plus élevé (atteint à FAME_STEP * 4 de renommée)
## Bataille décisive (objectif de la campagne) : 9 régiments contre 8 au plus pour la compagnie, dont
## deux de chevaliers à pied, presque tous aguerris ou vétérans.
## Équilibrage (N6, mesuré par le banc tests/campaign_balance.gd) : régiments entamés (« fill ») et plus
## petits qu'avant (régiment de couleur compris : 6, 8, 8 et 9 aux niveaux 2 à 5 au lieu de 7, 9, 10 et
## 11 ; décisive : 9 au lieu de 11), moins de vétérans, et leur part dépend de la difficulté
## (Difficulty.enemy_ranks : en facile et en normal, une partie des vétérans ne sont qu'aguerris).
const FINAL_CONTRACT := {
	"difficulty": 5, "reward": 2500, "fill": [0.75, 0.9], "ranks": [0.5, 0.3],
	"army": ["spear", "spear", "men_at_arms", "foot_knight", "foot_knight", "archer", "archer", "crossbow", "cavalry"],
}

var day := 1
var gold := float(START_GOLD)
var location := 0 ## Ville où se trouve la compagnie
var company: Array[Dictionary] = [] ## Régiments : {"type", "men", "xp"}
var contracts: Array[Dictionary] = [] ## {"town", "faction", "title", "text", "difficulty", "enemy", "reward", "expires", "seed"}
var pending: Dictionary = {} ## Contrat en cours de bataille (vide sinon)
var victories := 0
var defeats := 0
var fame := 0 ## Renommée : fait grimper la difficulté (et la prime) des contrats proposés
var reputation: Array[int] = [0, 0, 0] ## Réputation auprès de chaque faction (REP_MIN à REP_MAX)
var log_lines: Array[String] = [] ## Derniers évènements, du plus récent au plus ancien
var difficulty := Difficulty.NORMAL ## Niveau choisi à la création (voir difficulty.gd)
var rng := RandomNumberGenerator.new()
## Fin de campagne : "" (en cours), "victory" (bataille décisive gagnée) ou "ruin" (game over)
var ended := ""
var end_day := 0 ## Jour où la campagne s'est terminée
var end_note := "" ## Phrase qui raconte la fin (écran de fin)
## Bilan : cumuls depuis le début de la campagne
var men_lost := 0
var enemies_killed := 0
var gold_earned := 0 ## Primes, butin et escortes
var captain := Captain.new() ## Capitaine de la compagnie (voir captain.gd)
var world := WorldSim.new() ## Monde vivant : saisons, météo, guerres et armées (voir world_sim.gd)
var overworld := Overworld.new() ## Carte en temps réel : heure, compagnie et groupes (voir overworld.gd)


## Nouvelle partie : une petite compagnie à Valombre.
## lenient_mode : mode indulgent (la bataille en cours n'est pas sauvegardée, voir « lenient »).
## empty : la compagnie part sans un homme, avec de quoi lever ses premiers régiments
## (START_GOLD + le prix de START_COMPANY) ; sinon elle part avec START_COMPANY (tests, bancs).
static func new_game(seed_value := 0, level := Difficulty.NORMAL, lenient_mode := false, empty := false) -> CampaignState:
	var c := CampaignState.new()
	c.difficulty = Difficulty.sanitize(level)
	c.lenient = lenient_mode
	if seed_value != 0:
		c.rng.seed = seed_value
	else:
		c.rng.randomize()
	c.captain = Captain.recruit(c.rng.seed)
	c.world = WorldSim.create(c.rng.seed)
	if empty:
		c.gold = float(START_GOLD + c.start_company_value())
	else:
		for t in START_COMPANY:
			c.company.append({"type": t, "men": int(UnitTypes.STATS[t]["count"]), "xp": 0.0})
	for i in TOWNS.size():
		c.refresh_contracts(i)
	c.overworld = Overworld.create(c)
	if empty:
		c.add_log("Jour 1 : vous arrivez à %s avec %d écus et pas un homme (difficulté : %s). Levez vos premiers régiments, puis trouvez un contrat !" % [TOWNS[0]["name"], int(c.gold), Difficulty.display_name(c.difficulty).to_lower()])
	else:
		c.add_log("Jour 1 : la compagnie se forme à %s (difficulté : %s). Trouvez un contrat !" % [TOWNS[0]["name"], Difficulty.display_name(c.difficulty).to_lower()])
	c.add_log("Objectif : %s" % objective_text())
	return c


## Prix des régiments de START_COMPANY à la ville de départ : l'or d'une compagnie qui part
## sans un homme (elle peut lever la même troupe, ou une autre).
func start_company_value() -> int:
	var v := 0
	for t in START_COMPANY:
		v += recruit_cost(t, int(UnitTypes.STATS[t]["count"]), 0)
	return int(ceil(v / 10.0)) * 10


## But de la campagne, annoncé dès le premier jour.
static func objective_text() -> String:
	return "faire de la compagnie la plus célèbre du comté. À %d de renommée, la faction qui vous estime le plus vous appellera pour la bataille qui décidera de la guerre : gagnez-la." % FINAL_FAME


func add_log(s: String) -> void:
	log_lines.push_front(s)
	if log_lines.size() > 8:
		log_lines.pop_back()


## « 1 homme », « 3 hommes » (0 et 1 au singulier, comme en français).
static func plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if absi(n) <= 1 else many]


## Nom d'un type d'unité au singulier.
const TYPE_SINGULAR := {"spear": "piquier", "men_at_arms": "homme d'armes", "archer": "archer", "cavalry": "cavalier",
	"crossbow": "arbalétrier", "foot_knight": "chevalier à pied", "horse_archer": "archer monté"}


## « 1 archer », « 2 hommes d'armes » (en minuscules).
static func type_count(type: String, n: int) -> String:
	return plural(n, str(TYPE_SINGULAR.get(type, type)), type_name(type).to_lower())


# ---------------------------------------------------------------- Sauvegarde

## Emplacements de sauvegarde : SLOT_COUNT fichiers <base>_1.json, <base>_2.json...
## Chaque écriture garde la version précédente dans <fichier>.bak (relue si le fichier est abîmé).
const SLOT_COUNT := 3
## Base des noms d'emplacement ("" : user://campagne, ou user://test_emplacement quand un script
## de test tourne, pour ne jamais toucher aux sauvegardes du joueur).
static var slot_prefix := ""
static var slot := 1 ## Emplacement utilisé par la campagne en cours
static var save_path := "user://campagne_1.json" ## Fichier de l'emplacement en cours (les tests en changent)
static var loaded_from_backup := false ## Vrai si le dernier chargement a dû relire le .bak
## Version 9 : carte en temps réel (heure, position et chemin de la compagnie, groupes ; voir
## overworld.gd) sur une carte trois fois plus grande (positions des armées agrandies à la relecture).
## Version 8 : objectif des contrats (« objective ») et faction ennemie (« enemy_faction »).
## Version 7 : monde vivant (villes conquises, guerres, armées, météo ; voir world_sim.gd).
## Version 6 : capitaine, traits et équipement des régiments.
## Version 5 : emplacements, mode indulgent, contrat ou embuscade en cours (« pending »).
## Version 4 : difficulté. Version 3 : fin de campagne, bilan, niveaux de contrat 4-5 et contrat final.
## Les versions 1 (sans expérience, réputation ni renommée) à 8 restent lisibles
## (difficulté : normal, mode indulgent désactivé, aucune bataille en cours, capitaine neuf,
## monde neuf et en paix, contrats « détruire l'ennemi », compagnie dans sa ville au matin).
const SAVE_VERSION := 9

## Mode indulgent : la bataille en cours n'est pas sauvegardée. Fermer le jeu pendant un contrat
## revient à l'état d'avant la bataille, et une embuscade interrompue est oubliée.
var lenient := false
var saved_at := 0.0 ## Heure de la dernière sauvegarde (secondes Unix), pour « Continuer »


static func slot_base() -> String:
	if slot_prefix != "":
		return slot_prefix
	return "user://test_emplacement" if GameOptions.is_test_run() else "user://campagne"


static func slot_path(i: int) -> String:
	return "%s_%d.json" % [slot_base(), i]


## Ancien fichier unique (versions 4 et avant) : devient l'emplacement 1.
static func legacy_path() -> String:
	return slot_base() + ".json"


## Choisit l'emplacement utilisé par les sauvegardes suivantes.
static func use_slot(i: int) -> void:
	slot = clampi(i, 1, SLOT_COUNT)
	save_path = slot_path(slot)


## Migration : l'ancien campagne.json devient l'emplacement 1 (s'il est libre). Renvoie vrai si déplacé.
static func migrate_legacy() -> bool:
	var old := legacy_path()
	var first := slot_path(1)
	if not FileAccess.file_exists(old) or FileAccess.file_exists(first) or FileAccess.file_exists(first + ".bak"):
		return false
	var err := DirAccess.rename_absolute(old, first)
	if err != OK:
		push_warning("Migration de la sauvegarde impossible : %s" % error_string(err))
		return false
	return true


## Données à sauvegarder (types simples uniquement, pour JSON).
func to_dict() -> Dictionary:
	var cs: Array = []
	for c in contracts:
		cs.append(contract_to_dict(c))
	var d := {
		"version": SAVE_VERSION,
		"difficulty": difficulty,
		"lenient": lenient,
		"day": day, "gold": gold, "location": location,
		"victories": victories, "defeats": defeats,
		"fame": fame, "reputation": reputation.duplicate(),
		"company": company.duplicate(true),
		"contracts": cs,
		"log": log_lines.duplicate(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"ended": ended, "end_day": end_day, "end_note": end_note,
		"men_lost": men_lost, "enemies_killed": enemies_killed, "gold_earned": gold_earned,
		"captain": captain.to_dict(),
		"world": world.to_dict(),
		"overworld": overworld.to_dict(),
		"encounters": encounters_to_dict(), # Rencontres de la carte (bloc en fin de fichier)
	}
	# Bataille en cours (B3) : un contrat de la liste (par son rang) ou une embuscade (en entier).
	# En mode indulgent, elle n'est pas sauvegardée : fermer le jeu revient à l'état d'avant.
	if in_battle() and not lenient:
		var idx := contracts.find(pending)
		if idx >= 0:
			d["pending_index"] = idx
		else:
			d["pending"] = contract_to_dict(pending)
	return d


static func contract_to_dict(c: Dictionary) -> Dictionary:
	var d := c.duplicate(true)
	d["seed"] = str(c.get("seed", 1)) # Entier 64 bits : en texte pour ne pas perdre de précision
	return d


## Relit un contrat (ou une embuscade) sauvegardé. Renvoie {} s'il est invalide.
static func contract_from_dict(k: Variant) -> Dictionary:
	if not k is Dictionary:
		return {}
	var town := int(k.get("town", -1))
	if town < 0 or town >= TOWNS.size():
		return {}
	var enemy: Array[Dictionary] = []
	for e in k.get("enemy", []):
		if not e is Dictionary or not UnitTypes.STATS.has(str(e.get("type", ""))):
			return {}
		enemy.append({"type": str(e["type"]), "men": maxi(1, int(e.get("men", 1))), "rank": clampi(int(e.get("rank", 0)), 0, 2)})
	var out := {
		"town": town, "faction": clampi(int(k.get("faction", TOWNS[town]["faction"])), -1, FACTIONS.size() - 1),
		"title": str(k.get("title", "")), "text": str(k.get("text", "")),
		"foe": str(k.get("foe", "ennemis")), "difficulty": clampi(int(k.get("difficulty", 1)), 1, MAX_LEVEL),
		"enemy": enemy, "reward": int(k.get("reward", 0)), "expires": int(k.get("expires", 0)),
		"seed": str(k.get("seed", "1")).to_int(),
		# Version 6 et avant : détruire l'ennemi, faction ennemie inconnue
		"objective": objective_from_dict(k.get("objective", {})),
		"enemy_faction": clampi(int(k.get("enemy_faction", -1)), -1, FACTIONS.size() - 1),
	}
	if bool(k.get("final", false)):
		out["final"] = true
	if bool(k.get("ambush", false)):
		out["ambush"] = true
	if k.has("world_army"): # Bataille contre une armée rencontrée (world_sim.gd)
		out["world_army"] = int(k["world_army"])
	if k.has("party_id"): # Bataille contre un groupe de la carte (party_contract)
		out["party_id"] = int(k["party_id"])
	if str(k.get("siege", "")) in SIEGE_KINDS:
		out["siege"] = str(k["siege"])
		var target := int(k.get("target", -1)) # Assaut d'une ville de la carte (make_siege)
		if out["siege"] == "assault" and target >= 0 and target < TOWNS.size():
			out["target"] = target
	if str(k.get("terrain", "")) in WorldSim.ROAD_TERRAINS: # Rencontre sur la route (make_battle)
		out["terrain"] = str(k["terrain"])
	if str(k.get("terrain", "")) in MapData.BATTLE_TERRAINS: # Carte en temps réel : terrain de l'endroit
		out["terrain"] = str(k["terrain"])
	if k.has("party"): # Bataille contre un groupe de la carte (overworld.gd)
		out["party"] = int(k["party"])
	return out


## Reconstruit une campagne depuis to_dict(). Renvoie null si les données sont invalides.
static func from_dict(d: Dictionary) -> CampaignState:
	var version := int(d.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		return null
	var c := CampaignState.new()
	c.difficulty = Difficulty.sanitize(str(d.get("difficulty", Difficulty.NORMAL))) # Versions 1 et 2 : normal
	c.lenient = bool(d.get("lenient", false)) # Version 4 et avant : non indulgent
	c.saved_at = float(d.get("saved_at", 0.0))
	c.day = int(d.get("day", 1))
	c.gold = float(d.get("gold", 0.0))
	c.location = int(d.get("location", 0))
	c.victories = int(d.get("victories", 0))
	c.defeats = int(d.get("defeats", 0))
	# Version 1 : pas de renommée (on la déduit des victoires) ni de réputation (neutre partout)
	c.fame = maxi(0, int(d.get("fame", c.victories * 15)))
	var rep: Array = d.get("reputation", [0, 0, 0])
	if rep.size() != FACTIONS.size():
		return null
	for f in FACTIONS.size():
		c.reputation[f] = clampi(int(rep[f]), REP_MIN, REP_MAX)
	if c.location < 0 or c.location >= TOWNS.size():
		return null
	for r in d.get("company", []):
		if not r is Dictionary or not UnitTypes.STATS.has(str(r.get("type", ""))):
			return null
		var type := str(r["type"])
		var men := clampi(int(r.get("men", 0)), 0, int(UnitTypes.STATS[type]["count"]))
		if men > 0:
			var entry := {"type": type, "men": men, "xp": clampf(float(r.get("xp", 0.0)), 0.0, XP_MAX)}
			Traits.read_entry(entry, r) # Version 6 : traits et équipement
			for key in ["battles", "kills"]: # Statistiques du régiment (absentes avant sa première bataille)
				if r.has(key):
					entry[key] = maxi(0, int(r[key]))
			c.company.append(entry)
	for k in d.get("contracts", []):
		var contract := contract_from_dict(k)
		if contract.is_empty():
			return null
		contract.erase("ambush") # Une embuscade n'est jamais dans la liste des contrats
		c.contracts.append(contract)
	# Version 5 : bataille en cours. Le contrat est repris dans la liste (même dictionnaire,
	# pour que finish_battle le retire), l'embuscade est relue telle quelle.
	if d.has("pending_index"):
		var idx := int(d["pending_index"])
		if idx < 0 or idx >= c.contracts.size():
			return null
		c.pending = c.contracts[idx]
	elif d.has("pending"):
		c.pending = contract_from_dict(d["pending"])
		if c.pending.is_empty():
			return null
	for s in d.get("log", []):
		c.log_lines.append(str(s))
	c.rng.seed = str(d.get("rng_seed", "1")).to_int()
	c.rng.state = str(d.get("rng_state", "1")).to_int()
	c.captain = Captain.from_dict(d.get("captain", {}), c.rng.seed) # Version 5 et avant : capitaine neuf
	# Version 6 et avant : monde neuf ; version 8 et avant : petite carte (positions agrandies)
	c.world = WorldSim.from_dict(d.get("world", {}), c.rng.seed, c.day, MapData.SCALE if version <= 8 else 1.0)
	if c.world == null:
		return null
	# Version 8 et avant : la compagnie est placée dans sa ville, au matin
	c.overworld = Overworld.from_dict(d.get("overworld", {}) if version >= 9 else {}, c)
	# Version 2 et avant : campagne en cours, bilan à zéro
	c.ended = str(d.get("ended", ""))
	if not c.ended in ENDINGS:
		return null
	c.end_day = int(d.get("end_day", 0))
	c.end_note = str(d.get("end_note", ""))
	c.men_lost = maxi(0, int(d.get("men_lost", 0)))
	c.enemies_killed = maxi(0, int(d.get("enemies_killed", 0)))
	c.gold_earned = maxi(0, int(d.get("gold_earned", 0)))
	c.encounters_from_dict(d.get("encounters", {})) # Rencontres de la carte (bloc en fin de fichier)
	if c.ended == "":
		c.keep_final_in_patron_town() # Sauvegarde d'avant le correctif : bataille décisive en ville ennemie
	return c


## Écrit la sauvegarde sans risque de la corrompre : fichier temporaire, l'ancienne version
## devient la copie de secours (.bak), puis le temporaire remplace le fichier.
func save() -> bool:
	var path := save_path
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	saved_at = Time.get_unix_time_from_system()
	var d := to_dict()
	d["saved_at"] = saved_at
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		# Seule une sauvegarde lisible devient la copie de secours (un fichier abîmé ne l'écrase pas)
		if read_file(path) != null:
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			var e := DirAccess.rename_absolute(path, bak)
			if e != OK:
				push_warning("Copie de secours impossible : %s" % error_string(e))
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("Sauvegarde impossible : %s" % error_string(err))
		return false
	SavePreview.write(self, path) # En-tête lu par le menu sans charger la campagne
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")


## Lit un seul fichier de sauvegarde. Renvoie null s'il manque ou est illisible.
static func read_file(path: String) -> CampaignState:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("Sauvegarde illisible (%s, ligne %d) : %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		return null
	return from_dict(json.data)


## Charge un fichier de sauvegarde, ou sa copie de secours s'il est abîmé ou absent.
static func load_from(path: String) -> CampaignState:
	loaded_from_backup = false
	var c := read_file(path)
	if c == null and FileAccess.file_exists(path + ".bak"):
		c = read_file(path + ".bak")
		if c != null:
			loaded_from_backup = true
			push_warning("Sauvegarde abîmée : copie de secours relue (%s.bak)" % path)
	return c


## Charge l'emplacement en cours. Renvoie null si le fichier manque ou est illisible.
static func load_game() -> CampaignState:
	return load_from(save_path)


static func delete_save() -> void:
	delete_file(save_path)


static func delete_file(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp", SavePreview.path_for(path)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Efface un emplacement (fichier et copie de secours).
static func delete_slot(i: int) -> void:
	delete_file(slot_path(i))


static func slot_used(i: int) -> bool:
	var p := slot_path(i)
	return FileAccess.file_exists(p) or FileAccess.file_exists(p + ".bak")


## Campagne d'un emplacement (null si vide ou illisible).
static func load_slot(i: int) -> CampaignState:
	return load_from(slot_path(i))


## Emplacement sauvegardé le plus récemment (0 si aucun n'est lisible).
static func latest_slot() -> int:
	var best := 0
	var best_t := -1.0
	for i in range(1, SLOT_COUNT + 1):
		var c := load_slot(i)
		if c != null and c.saved_at > best_t:
			best = i
			best_t = c.saved_at
	return best


## Premier emplacement libre (0 si tous sont pris).
static func free_slot() -> int:
	for i in range(1, SLOT_COUNT + 1):
		if not slot_used(i):
			return i
	return 0


## Résumé d'une campagne pour le menu : jour, or, hommes, difficulté, état.
func summary() -> String:
	var s := "Jour %d · %d écus · %s · %s" % [day, int(gold), plural(total_men(), "homme", "hommes"), Difficulty.display_name(difficulty)]
	if lenient:
		s += " · indulgent"
	return s


## État d'une campagne pour le menu.
func status_text() -> String:
	match ended:
		"victory":
			return "Terminée : victoire au jour %d" % end_day
		"ruin":
			return "Terminée : compagnie ruinée au jour %d" % end_day
	if in_battle():
		return "Bataille en cours : %s" % str(pending.get("title", ""))
	if overworld.inside >= 0:
		return "En cours, à %s" % MapData.place(overworld.inside)["name"]
	return "En cours, en route près de %s" % TOWNS[MapData.nearest_town(overworld.player.pos)]["name"]


# ---------------------------------------------------------------- Factions et réputation

## Faction qui tenait la ville au début de la campagne (données de TOWNS). Pour les contrats,
## utiliser town_owner : les villes changent de mains.
static func initial_faction(town: int) -> int:
	return int(TOWNS[town]["faction"])


## Faction qui tient la ville aujourd'hui (initial_faction : celle du début de la campagne).
func town_owner(town: int) -> int:
	return world.owner_of(town)


## Une armée assiège-t-elle la ville ? (pour proposer un contrat de siège)
func town_besieged(town: int) -> bool:
	return world.besieged(town)


## Détails du siège : {"faction" (assiégeant), "defender", "men", "days", "garrison", "army"}, {} sinon.
func town_siege(town: int) -> Dictionary:
	return world.siege_info(town)


static func faction_name(f: int) -> String:
	return str(FACTIONS[f]["name"])


func change_reputation(f: int, delta: int) -> void:
	reputation[f] = clampi(reputation[f] + delta, REP_MIN, REP_MAX)


## Une faction trop mécontente ne propose plus de contrat et refuse qu'on recrute chez elle.
func faction_closed(f: int) -> bool:
	return f >= 0 and reputation[f] <= REP_CLOSED


func reputation_label(f: int) -> String:
	var r := reputation[f]
	if r <= REP_CLOSED:
		return "hostile"
	if r < 0:
		return "méfiante"
	if r < 20:
		return "neutre"
	if r < 50:
		return "amicale"
	return "alliée"


## Prime réellement payée : la prime de base modulée par la réputation auprès de la faction.
func contract_reward(contract: Dictionary) -> int:
	var f := int(contract.get("faction", -1))
	var base := int(contract["reward"]) * Difficulty.value(difficulty, "reward")
	if f < 0:
		return int(round(base / 10.0)) * 10
	var mult := clampf(1.0 + reputation[f] * REP_REWARD, 0.5, 1.5)
	return int(round(base * mult / 10.0)) * 10


## Message de refus si la faction de la ville actuelle nous ferme ses portes, sinon "".
func closed_message(town: int) -> String:
	var f := town_owner(town)
	if faction_closed(f):
		return "%s vous ferme ses portes (réputation %d)." % [str(FACTIONS[f]["short"]).capitalize(), reputation[f]]
	return ""


# ---------------------------------------------------------------- Compagnie et or

func total_men() -> int:
	var n := 0
	for r in company:
		n += int(r["men"])
	return n


## Solde quotidienne de toute la compagnie.
func daily_wage() -> float:
	var w := 0.0
	for r in company:
		w += float(WAGE[r["type"]]) * int(r["men"]) * Traits.wage_factor(r)
	return w * Difficulty.value(difficulty, "wage") * captain.wage_factor()


func is_destroyed() -> bool:
	return company.is_empty()


## Peut-on lever au moins un régiment complet dans la ville actuelle ?
func can_recruit_here() -> bool:
	if closed_message(location) != "":
		return false
	for t in TOWNS[location]["recruits"]:
		if gold >= recruit_cost(t, int(UnitTypes.STATS[t]["count"])):
			return true
	return false


## Game over : plus un homme, et pas de quoi (ou pas le droit de) lever un régiment ici.
## Sans troupes, la compagnie ne peut plus marcher vers une autre ville.
func is_ruined() -> bool:
	return is_destroyed() and not can_recruit_here()


func is_over() -> bool:
	return ended != ""


## Vérifie si la compagnie est ruinée (après une bataille, une marche ou une épidémie).
func check_ruin() -> void:
	if ended != "" or not is_ruined():
		return
	ended = "ruin"
	end_day = day
	end_note = "Sans un homme sous sa bannière ni de quoi en payer, la compagnie se disperse à %s." % TOWNS[location]["name"]
	add_log("Jour %d : la compagnie est dissoute." % day)


## Lever un nouveau régiment complet dans la ville actuelle. Renvoie un message d'erreur ou "".
func recruit(type: String) -> String:
	var closed := closed_message(location)
	if closed != "":
		return closed
	if not type in TOWNS[location]["recruits"]:
		return "On ne lève pas ce type de troupe ici."
	if company.size() >= MAX_REGIMENTS:
		return "La compagnie compte déjà %d régiments." % MAX_REGIMENTS
	var men: int = UnitTypes.STATS[type]["count"]
	var cost := recruit_cost(type, men)
	if gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	gold -= cost
	company.append({"type": type, "men": men, "xp": 0.0})
	add_log("Jour %d : %s rejoignent la compagnie (-%d écus)." % [day, type_count(type, men), cost])
	return ""


## Compléter un régiment entamé (si son type se lève dans la ville actuelle).
func refill(index: int) -> String:
	var closed := closed_message(location)
	if closed != "":
		return closed
	var r := company[index]
	var type: String = r["type"]
	if not type in TOWNS[location]["recruits"]:
		return "On ne lève pas ce type de troupe ici."
	var missing := refill_missing(index)
	if missing <= 0:
		return "Ce régiment est déjà au complet."
	var cost := recruit_cost(type, missing)
	if gold < cost:
		return "Pas assez d'or (%d écus)." % cost
	gold -= cost
	add_men(r, missing, 0.0)
	add_log("Jour %d : %s %s les %s (-%d écus)." % [day, plural(missing, "recrue", "recrues"), "complète" if missing <= 1 else "complètent", type_name(type).to_lower(), cost])
	return ""


func refill_missing(index: int) -> int:
	var r := company[index]
	return int(UnitTypes.STATS[r["type"]]["count"]) - int(r["men"])


## Ajoute n hommes d'expérience new_xp à un régiment : son expérience est la moyenne des deux.
## Des recrues (new_xp = 0) diluent donc l'expérience d'un régiment aguerri.
static func add_men(r: Dictionary, n: int, new_xp: float) -> void:
	var men := int(r["men"])
	if n <= 0:
		return
	r["xp"] = (float(r.get("xp", 0.0)) * men + new_xp * n) / float(men + n)
	r["men"] = men + n


static func rank_from_xp(xp: float) -> int:
	var k := 0
	for i in RANK_XP.size():
		if xp >= float(RANK_XP[i]):
			k = i
	return k


## Rang d'un régiment de campagne ({"xp"}) ou d'un régiment ennemi ({"rank"}).
static func rank_of(entry: Dictionary) -> int:
	if entry.has("rank"):
		return clampi(int(entry["rank"]), 0, RANK_XP.size() - 1)
	return rank_from_xp(float(entry.get("xp", 0.0)))


static func rank_name(k: int) -> String:
	return str(Regiment.RANK_NAMES[k])


## Prix de men recrues d'un type, dans une ville (par défaut celle où l'on se trouve).
func recruit_cost(type: String, men: int, town := -1) -> int:
	if town < 0:
		town = location
	return int(ceil(int(RECRUIT_COST[type]) * men * float(TOWNS[town]["price"]) * Difficulty.value(difficulty, "recruit")))


static func type_name(type: String) -> String:
	return str(UnitTypes.STATS[type]["name"])


# ---------------------------------------------------------------- Déplacements

func neighbours(town: int) -> Array[int]:
	var out: Array[int] = []
	for road in ROADS:
		if road[0] == town:
			out.append(road[1])
		elif road[1] == town:
			out.append(road[0])
	return out


func travel_days(to: int) -> int:
	var a: Vector2 = TOWNS[location]["pos"]
	var b: Vector2 = TOWNS[to]["pos"]
	return maxi(1, ceili(a.distance_to(b) / (TRAVEL_PX_PER_DAY * WorldSim.march_factor(day)))) # Hiver : plus lent


## Marche vers une ville voisine : chaque jour coûte la solde et peut amener un évènement de route.
## Une embuscade laisse une bataille en attente (in_battle()) à livrer dès l'arrivée.
## Renvoie un message d'erreur ou "" ; les évènements du voyage sont dans travel_events.
func travel(to: int) -> String:
	if not to in neighbours(location):
		return "Aucune route directe vers %s." % TOWNS[to]["name"]
	if is_over():
		return "La campagne est terminée."
	if is_destroyed():
		return "Vous n'avez plus de troupes."
	travel_events.clear()
	var days := travel_days(to)
	var done := 0
	var happened := {} # Une embuscade et une journée d'intempéries au plus par voyage
	while done < days:
		pass_day()
		done += 1
		world.on_march_day(self, location, to, float(done) / days) # Froid, armée rencontrée
		if is_destroyed():
			break
		if forced_event == "" and rng.randf() >= event_chance:
			continue
		var kind := forced_event if forced_event != "" else roll_event()
		if happened.has(kind) and (kind == "ambush" or kind == "storm"):
			continue
		happened[kind] = true
		road_event(kind, to)
		if kind == "storm":
			days += 1
	location = to
	overworld.halt()
	overworld.enter(self, to)
	add_log("Jour %d : arrivée à %s après %s de marche." % [day, TOWNS[to]["name"], plural(done, "jour", "jours")])
	refresh_contracts(to)
	check_ruin()
	return ""


## Carte en temps réel : la journée s'achève et la compagnie a marché (Overworld.end_of_day).
## Froid de l'hiver et évènements de route, comme un jour de marche de travel. to : ville vers
## laquelle on marche. Une embuscade laisse une bataille en attente, sur le terrain de l'endroit ;
## des intempéries immobilisent la compagnie une demi-journée.
func march_day(to: int, ow: Overworld) -> void:
	world.cold_day(self)
	if is_destroyed() or in_battle():
		return
	if forced_event == "" and rng.randf() >= event_chance:
		return
	var kind := forced_event if forced_event != "" else roll_event()
	road_event(kind, to)
	match kind:
		"ambush":
			pending["terrain"] = MapData.battle_terrain_at(ow.player.pos)
		"storm":
			ow.player.busy_hours = 12.0


# ---------------------------------------------------------------- Évènements de route

static var event_chance := 0.12 ## Chance d'un évènement par jour de marche (les tests la mettent à 0)
static var forced_event := "" ## Pour les tests : impose cet évènement chaque jour de marche
const EVENT_WEIGHTS := {"ambush": 0.25, "merchant": 0.2, "plague": 0.15, "deserters": 0.15, "storm": 0.15, "village": 0.1}
const PLAGUE_RATE := 0.08 ## Part des hommes emportés par une épidémie
const DESERTER_XP := 60.0 ## Les déserteurs d'autres compagnies ont déjà vu le feu
var travel_events: Array[String] = [] ## Évènements du dernier voyage (non sauvegardé)


func roll_event() -> String:
	var x := rng.randf()
	for kind in EVENT_WEIGHTS:
		x -= float(EVENT_WEIGHTS[kind])
		if x < 0.0:
			return kind
	return "merchant"


## Applique un évènement de route (pendant la marche vers to) et l'inscrit au journal.
func road_event(kind: String, to: int) -> void:
	var where: String = TOWNS[to]["name"]
	var msg := ""
	match kind:
		"ambush":
			pending = make_ambush(to)
			msg = "des brigands vous tendent une embuscade sur la route de %s ! Il faut se battre." % where
		"merchant":
			var pay := rng.randi_range(4, 9) * 10
			gold += pay
			gold_earned += pay
			msg = "un marchand paie %d écus pour être escorté jusqu'à %s." % [pay, where]
		"plague":
			var lost := 0
			for r in company:
				var n := int(round(int(r["men"]) * PLAGUE_RATE))
				if lost == 0 and n == 0 and int(r["men"]) > 1:
					n = 1 # Au moins une victime
				r["men"] = int(r["men"]) - n
				lost += n
			company = company.filter(func(r): return int(r["men"]) > 0)
			men_lost += lost
			msg = "une épidémie frappe le camp, %s." % ("un homme en meurt" if lost == 1 else "%d hommes en meurent" % lost)
		"deserters":
			var best := -1
			for i in company.size():
				if refill_missing(i) > 0 and (best < 0 or refill_missing(i) > refill_missing(best)):
					best = i
			if best < 0:
				msg = "des déserteurs demandent à rejoindre la compagnie, mais elle est au complet."
			else:
				var n := mini(rng.randi_range(3, 8), refill_missing(best))
				add_men(company[best], n, DESERTER_XP)
				msg = "%s vos %s." % [plural(n, "déserteur rejoint", "déserteurs rejoignent"), type_name(company[best]["type"]).to_lower()]
		"storm":
			msg = "des intempéries noient la route, un jour de marche est perdu."
		"village":
			msg = village_event(where)
		_:
			return
	travel_events.append(msg[0].to_upper() + msg.substr(1))
	add_log("Jour %d : %s" % [day, msg])


## Évènement « village » : un régiment pille un hameau abandonné et y gagne le trait « pillards ».
func village_event(where: String) -> String:
	for r in company:
		if Traits.add(r, "pillards"):
			return "vos %s pillent un hameau abandonné près de %s : les voilà pillards." % [type_name(r["type"]).to_lower(), where]
	var pay := rng.randi_range(2, 5) * 10
	gold += pay
	gold_earned += pay
	return "la compagnie fouille un hameau abandonné près de %s et y trouve %d écus." % [where, pay]


## Bataille forcée par une embuscade de brigands : ni prime ni faction, seulement le butin.
func make_ambush(to: int) -> Dictionary:
	var kind: Dictionary = CONTRACT_KINDS[0]
	var enemy: Array[Dictionary] = []
	for t in kind["army"]:
		var full: int = UnitTypes.STATS[t]["count"]
		enemy.append({"type": t, "men": maxi(3, int(round(full * rng.randf_range(0.5, 0.8)))), "rank": 0})
	return {
		"town": to, "faction": -1, "ambush": true,
		"title": "Embuscade sur la route de %s" % TOWNS[to]["name"],
		"text": "Des brigands surgissent des fourrés.",
		"foe": "brigands", "difficulty": 1, "enemy": enemy, "reward": 0,
		"expires": day, "seed": rng.randi_range(1, 1 << 30),
		"objective": {"kind": "destroy"}, "enemy_faction": -1,
	}


## Un jour passe : solde, désertions si les caisses sont vides, contrats qui expirent.
func pass_day() -> void:
	day += 1
	world.advance(self) # Saisons, météo, guerres et armées
	var wage := take_provisions(daily_wage()) # Vivres achetés en rencontre (bloc en fin de fichier)
	if gold >= wage:
		gold -= wage
	else:
		# Solde impayée : une partie des hommes s'en va
		var paid := gold / wage if wage > 0.0 else 1.0
		gold = 0.0
		var lost := 0
		for r in company:
			var n := int(round(int(r["men"]) * DESERT_RATE * (1.0 - paid)))
			if n == 0 and int(r["men"]) > 0:
				n = 1
			r["men"] = int(r["men"]) - n
			lost += n
		company = company.filter(func(r): return int(r["men"]) > 0)
		men_lost += lost
		add_log("Jour %d : solde impayée, %s !" % [day, plural(lost, "homme déserte", "hommes désertent")])
	contracts = contracts.filter(func(c): return int(c["expires"]) >= day)
	# Les rancunes s'apaisent lentement
	if day % 2 == 0:
		for f in FACTIONS.size():
			if reputation[f] < 0:
				reputation[f] += 1
	for i in TOWNS.size():
		if rng.randf() < 0.15:
			refresh_contracts(i)
	offer_final()


# ---------------------------------------------------------------- Contrats

func contracts_at(town: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in contracts:
		if int(c["town"]) == town:
			out.append(c)
	return out


## Chaque ville propose un ou deux contrats ; la difficulté grimpe avec la renommée.
## (Le contrat final ne compte pas : il s'ajoute aux contrats ordinaires de sa ville.)
func refresh_contracts(town: int) -> void:
	var have := contracts_at(town).filter(func(c): return not c.get("final", false)).size()
	var want := 1 + (1 if rng.randf() < 0.5 else 0) + world.extra_contracts(town) # En guerre : un de plus
	for i in maxi(0, want - have):
		contracts.append(world.adjust_contract(maybe_siege(make_contract(town))))
	# Ville assiégée sur la carte (world_sim.gd) : elle embauche des défenseurs
	if world.besieged(town) and contracts_at(town).filter(func(c): return c.has("siege")).is_empty():
		var besieger := int(world.siege_info(town)["faction"])
		contracts.append(world.adjust_contract(make_siege(make_contract(town, besieger), "defense")))


## Niveau le plus élevé des contrats proposés : un de plus tous les FAME_STEP de renommée.
func max_level() -> int:
	@warning_ignore("integer_division")
	return clampi(1 + fame / FAME_STEP, 1, MAX_LEVEL)


## Tire le rang d'un régiment ennemi : ranks = [chance d'être aguerri, chance d'être vétéran].
func roll_rank(ranks: Array) -> int:
	var x := rng.randf()
	if x < float(ranks[1]):
		return 2
	if x < float(ranks[1]) + float(ranks[0]):
		return 1
	return 0


## Armée ennemie d'un modèle de contrat (régiments entamés selon « fill », rangs selon « ranks »).
func roll_army(kind: Dictionary) -> Array[Dictionary]:
	var fill: Array = kind["fill"]
	var enemy: Array[Dictionary] = []
	for t in kind["army"]:
		var full: int = UnitTypes.STATS[t]["count"]
		var men := maxi(3, int(round(full * rng.randf_range(fill[0], fill[1]))))
		enemy.append({"type": t, "men": men, "rank": roll_rank(Difficulty.enemy_ranks(difficulty, kind["ranks"]))})
	return enemy


## Prime de base tirée autour de celle du modèle, et qui croît avec la renommée.
func roll_reward(base: int) -> int:
	return int(round(base * rng.randf_range(0.9, 1.15) * (1.0 + fame * FAME_REWARD) / 10.0)) * 10


static func cap_first(s: String) -> String:
	return s if s == "" else s[0].to_upper() + s.substr(1)


## Contrat proposé par une ville : niveau (d'après la renommée), faction ennemie et armée colorée
## par celui qui la lève, objectif (détruire, tenir, escorter, prendre, poursuivre) avec ses textes,
## prime modulée par l'objectif. La ville parle au nom de la faction qui la tient aujourd'hui
## (town_owner) ; foe_override impose la faction ennemie (l'assiégeant d'une ville assiégée), sinon tirée.
func make_contract(town: int, foe_override := -1) -> Dictionary:
	var top := max_level()
	var d := rng.randi_range(maxi(1, top - 1), top)
	var kind: Dictionary = CONTRACT_KINDS[d - 1]
	var foe_f := roll_enemy_faction(town)
	if foe_override >= 0 and foe_override != town_owner(town):
		foe_f = foe_override
	var band := str(kind.get("band", "brigands"))
	var enemy := flavor_army(roll_army(kind), band, foe_f, d)
	var objective := roll_objective(town, d)
	var spec: Dictionary = OBJECTIVES[objective["kind"]]
	var reward := roll_reward(int(round(int(kind["reward"]) * float(spec["reward"]))))
	var rival := str(FACTIONS[foe_f]["short"])
	var foe := str(kind["foe"]).replace("{rival}", rival)
	var town_name := str(TOWNS[town]["name"])
	var title: String
	var text: String
	if objective["kind"] == "destroy":
		var titles: Array = kind["titles"]
		title = str(titles[rng.randi() % titles.size()]).replace("{rival}", rival) % town_name
		text = str(kind["text"]).replace("{Rival}", cap_first(rival)).replace("{rival}", rival)
	else:
		var titles: Array = spec["titles"]
		var texts: Array = spec["texts"]
		title = fill_objective_text(str(titles[rng.randi() % titles.size()]), objective, foe, town_name)
		text = fill_objective_text(str(texts[rng.randi() % texts.size()]), objective, foe, town_name)
	return {
		"town": town,
		"faction": town_owner(town),
		"title": title,
		"text": text,
		"foe": foe,
		"difficulty": d,
		"enemy": enemy,
		"reward": reward,
		"expires": day + CONTRACT_DAYS,
		"seed": rng.randi_range(1, 1 << 30),
		"objective": objective,
		"enemy_faction": foe_f if band == "faction" else -1,
	}


# ---------------------------------------------------------------- Contrats de siège (siege.gd)

const SIEGE_KINDS := ["assault", "defense"] ## « siege » d'un contrat : assiéger ou défendre une ville
const SIEGE_CHANCE := 0.12 ## Part des contrats de niveau 2 et plus qui sont des sièges (rares)
const SIEGE_REWARD := 1.6 ## Prime d'un siège par rapport à un contrat ordinaire du même niveau
const SIEGE_TITLES := {
	"assault": ["Assiéger la place forte de {rival} près de %s", "Prendre d'assaut le bourg rebelle de %s"],
	"assault_town": ["Prendre {target} à {rival}", "Assiéger {target}, ville de {rival}"],
	"defense": ["Défendre les murs de %s", "%s assiégée par {rival}"],
}
const SIEGE_TEXTS := {
	"assault": "La ville paie cher pour qu'on prenne la place : bélier pour la porte, échelles pour le rempart. Il faudra tenir la place de la ville.",
	"assault_town": "La ville paie cher pour qu'on prenne {target} : bélier pour la porte, échelles pour le rempart. Tenez la place de la ville, et {target} changera de maître.",
	"defense": "L'ennemi vient avec des échelles et un bélier. Garnissez les murs et tenez jusqu'à ce qu'il lève le siège.",
}


## Fait parfois d'un contrat ordinaire un siège, rare et bien payé. Le tirage dépend de la graine du
## contrat : il ne consomme pas le hasard de la campagne (les autres tirages ne changent pas).
## Assaut : la garnison a des archers en plus ; défense : l'assaillant a un régiment de plus.
func maybe_siege(c: Dictionary) -> Dictionary:
	if int(c.get("difficulty", 1)) < 2 or c.get("final", false) or c.has("siege"):
		return c
	if str((c.get("objective", {}) as Dictionary).get("kind", "destroy")) != "destroy":
		return c # Contrat à objectif (tenir, escorter...) : pas un siège
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(c["seed"]), "siege"])
	if r.randf() >= SIEGE_CHANCE:
		return c
	return make_siege(c, "assault" if r.randf() < 0.5 else "defense")


## Transforme le contrat c en siège (kind : « assault » ou « defense »), vu de la faction qui tient
## la ville aujourd'hui. Défense d'une ville assiégée sur la carte : l'ennemi est l'assiégeant réel.
## Assaut : si une ville voisine appartient à une faction en guerre avec la ville, c'est elle qu'on
## prend (« target » : la victoire la donne au patron, voir WorldSim.after_battle) ; sinon une place
## forte ou un bourg rebelle sans effet sur la carte.
func make_siege(c: Dictionary, kind: String) -> Dictionary:
	var town := int(c["town"])
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(c["seed"]), "siege_army"])
	var foe_f := siege_foe(c, kind, r)
	var key := kind
	var target := -1
	if kind == "assault":
		target = assault_target(town, foe_f, r)
		if target >= 0:
			foe_f = town_owner(target)
			key = "assault_town"
			c["target"] = target
	var rival := str(FACTIONS[foe_f]["short"])
	var target_name := str(TOWNS[target]["name"]) if target >= 0 else ""
	var titles: Array = SIEGE_TITLES[key]
	var title := str(titles[r.randi() % titles.size()]).replace("{rival}", rival).replace("{target}", target_name)
	c["siege"] = kind
	c["objective"] = {"kind": "destroy"} # La victoire d'un siège est décidée par siege.gd
	c["title"] = title % TOWNS[town]["name"] if "%s" in title else title
	c["text"] = str(SIEGE_TEXTS[key]).replace("{target}", target_name)
	if target >= 0 or (kind == "defense" and world.besieged(town)):
		c["enemy_faction"] = foe_f # Une vraie faction de la carte : l'armée porte ses couleurs
		c["foe"] = "troupes de %s" % rival
	c["reward"] = int(round(int(c["reward"]) * SIEGE_REWARD / 10.0)) * 10
	var extra := "archer" if kind == "assault" else "spear"
	var enemy: Array = c["enemy"]
	enemy.append({"type": extra, "men": int(UnitTypes.STATS[extra]["count"]), "rank": 0})
	return c


## Faction ennemie d'un siège : l'assiégeant réel de la ville, sinon celle du contrat, sinon une
## faction en guerre avec la ville (ou sa rivale). Jamais la faction qui tient la ville.
func siege_foe(c: Dictionary, kind: String, r: RandomNumberGenerator) -> int:
	var town := int(c["town"])
	var own := town_owner(town)
	if kind == "defense" and world.besieged(town):
		return int(world.siege_info(town)["faction"])
	var f := int(c.get("enemy_faction", -1))
	if f >= 0 and f != own:
		return f
	var foes := world.enemies_of(own)
	if not foes.is_empty():
		return foes[r.randi() % foes.size()]
	return int(FACTIONS[own]["rival"])


## Ville voisine de town (par la route) qu'un assaut peut prendre : tenue par une faction en guerre
## avec la ville, de préférence prefer. -1 s'il n'y en a pas (en paix, ou pas de voisine ennemie).
func assault_target(town: int, prefer: int, r: RandomNumberGenerator) -> int:
	var own := town_owner(town)
	var all: Array[int] = []
	var best: Array[int] = []
	for t in WorldSim.neighbours_of(town):
		var o := town_owner(t)
		if world.at_war(own, o):
			all.append(t)
			if o == prefer:
				best.append(t)
	var pool := best if not best.is_empty() else all
	return -1 if pool.is_empty() else pool[r.randi() % pool.size()]


# ---------------------------------------------------------------- Objectifs des contrats

## Objectifs des contrats (voir battle_objectives.gd) : poids du tirage, niveau minimal, prime
## (x la prime de base du niveau) et textes. Dans les textes : %s = la ville, {foe} = l'ennemi,
## {Foe} = l'ennemi avec majuscule, {time} = durée, {wagons} / {need} = chariots du convoi.
## « bonus » (escorte) : part de la prime payée en plus pour chaque chariot sauvé.
const OBJECTIVES := {
	"destroy": {"weight": 3.0, "min_level": 1, "reward": 1.0},
	"hold": {
		"weight": 2.0, "min_level": 1, "reward": 1.1,
		"titles": ["Tenir la position devant %s", "Le poste avancé de %s", "Barrer la route de %s"],
		"texts": [
			"Les {foe} marchent sur %s. Tenez la position marquée pendant {time}, le temps que la milice prenne les armes.",
			"La ville veut garder la hauteur qui commande la route. Tenez-la {time} face aux {foe} : les renforts suivront.",
		],
	},
	"escort": {
		"weight": 2.0, "min_level": 1, "reward": 0.85, "bonus": 0.08,
		"titles": ["Escorter le convoi de %s", "Les chariots de %s", "Le sel et le grain de %s"],
		"texts": [
			"Un convoi de {wagons} chariots quitte %s, et les {foe} l'attendent sur la route. Il en faut {need} au moins à bon port ; chaque chariot sauvé rapporte un supplément.",
			"Les marchands de %s paient une escorte pour leurs {wagons} chariots. Des {foe} rôdent : protégez la route d'un bout à l'autre ({need} chariots au moins).",
		],
	},
	"capture": {
		"weight": 1.5, "min_level": 2, "reward": 1.2,
		"titles": ["Reprendre un village de %s", "Chasser les {foe} d'un hameau de %s"],
		"texts": [
			"Les {foe} se sont retranchés dans un village du pays de %s. Occupez la place du village avant la nuit ({time}).",
			"Un village qui doit l'impôt à %s est tenu par les {foe}. Prenez la place avant la nuit ({time}) : la garnison ne lâchera pas facilement les maisons.",
		],
	},
	"pursue": {
		"weight": 2.0, "min_level": 1, "reward": 0.95,
		"titles": ["Rattraper les pillards de %s", "Poursuite autour de %s"],
		"texts": [
			"Les {foe} ont pillé les fermes de %s et s'enfuient, chargés de butin. Rattrapez-les avant que la moitié d'entre eux ne quitte le pays.",
			"Des {foe} ont rançonné un marché de %s et filent vers le nord. Leur butin les ralentit : rattrapez-les avant que la moitié ne s'échappe.",
		],
	},
}
## Textes de victoire du journal, selon l'objectif (%s = l'ennemi).
const OBJECTIVE_VICTORY := {
	"destroy": "Victoire contre les %s !", "hold": "Position tenue face aux %s !",
	"escort": "Convoi escorté malgré les %s !", "capture": "Village pris aux %s !",
	"pursue": "Les %s sont rattrapés !",
}


## Faction ennemie d'un contrat, vue de la faction qui tient la ville aujourd'hui : une de celles
## avec qui elle est en guerre ; en paix, sa rivale le plus souvent, sinon la troisième faction
## (c'est ainsi que la Ligue des villes entre en guerre). Jamais la faction de la ville.
func roll_enemy_faction(town: int) -> int:
	var own := town_owner(town)
	var rival := int(FACTIONS[own]["rival"])
	var x := rng.randf()
	var foes := world.enemies_of(own)
	if not foes.is_empty():
		return foes[int(x * foes.size()) % foes.size()]
	if x < 0.7:
		return rival
	for f in FACTIONS.size():
		if f != own and f != rival:
			return f
	return rival


## Couleur de l'armée selon qui la lève (un régiment de plus, jamais de moins : la taille de l'armée
## suit toujours le niveau) : les routiers ont plus de cavalerie, la Ligue des villes arme ses milices
## d'arbalètes, la Baronnie a des archers montés, le Comté des chevaliers à pied.
func flavor_army(enemy: Array[Dictionary], band: String, foe_f: int, _level: int) -> Array[Dictionary]:
	var extra := ""
	match band:
		"routiers":
			extra = "cavalry"
		"faction":
			match foe_f:
				0:
					extra = "foot_knight"
				1:
					extra = "horse_archer"
				2:
					extra = "crossbow"
					for e in enemy:
						if e["type"] == "archer":
							swap_type(e, "crossbow") # Arbalètes partout
	if extra != "":
		var men := maxi(3, int(round(int(UnitTypes.STATS[extra]["count"]) * rng.randf_range(0.75, 1.0))))
		enemy.append({"type": extra, "men": men, "rank": int(enemy[0]["rank"])})
	return enemy


## Change le type d'un régiment ennemi (effectif ramené au plein du nouveau type).
static func swap_type(e: Dictionary, type: String) -> void:
	e["type"] = type
	e["men"] = mini(int(e["men"]), int(UnitTypes.STATS[type]["count"]))



## Tire l'objectif d'un contrat et ses réglages ({"kind", ...}). Les villes fortifiées défendent
## leur palissade (détruire l'assaillant) dès le niveau 3.
func roll_objective(town: int, level: int) -> Dictionary:
	if level >= 3 and str(TOWNS[town]["name"]) in Terrain.SIEGE_TOWNS:
		return {"kind": "destroy"}
	var total := 0.0
	for k in OBJECTIVES:
		if level >= int(OBJECTIVES[k]["min_level"]):
			total += float(OBJECTIVES[k]["weight"])
	var roll := rng.randf() * total
	var kind := "destroy"
	for k in OBJECTIVES:
		if level < int(OBJECTIVES[k]["min_level"]):
			continue
		roll -= float(OBJECTIVES[k]["weight"])
		if roll < 0.0:
			kind = k
			break
	match kind:
		"hold":
			return {"kind": "hold", "time": 180.0 if level <= 2 else (240.0 if level <= 4 else 300.0), "loss": 30.0}
		"escort":
			return {"kind": "escort", "wagons": 4, "need": 3 if level >= 4 else 2}
		"capture":
			return {"kind": "capture", "time": 360.0, "hold": 25.0}
		"pursue":
			return {"kind": "pursue", "escape": 0.5}
	return {"kind": "destroy"}


## Remplit un texte de contrat (voir OBJECTIVES).
static func fill_objective_text(s: String, objective: Dictionary, foe: String, town_name: String) -> String:
	var out := s.replace("{Foe}", cap_first(foe)).replace("{foe}", foe)
	out = out.replace("{time}", BattleObjectives.duration_words(float(objective.get("time", 0.0))))
	out = out.replace("{wagons}", str(int(objective.get("wagons", 0)))).replace("{need}", str(int(objective.get("need", 0))))
	return out % town_name if "%s" in out else out


## Relit l'objectif d'un contrat sauvegardé (inconnu ou absent : détruire l'ennemi).
static func objective_from_dict(v: Variant) -> Dictionary:
	if not v is Dictionary or not str(v.get("kind", "")) in BattleObjectives.KINDS:
		return {"kind": "destroy"}
	var out := {"kind": str(v["kind"])}
	for key in ["time", "loss", "hold", "escape"]:
		if v.has(key):
			out[key] = float(v[key])
	for key in ["wagons", "need"]:
		if v.has(key):
			out[key] = int(v[key])
	return out


## Sorte d'objectif d'un contrat (« destroy » par défaut).
static func objective_kind(contract: Dictionary) -> String:
	var o: Variant = contract.get("objective", {})
	return str(o.get("kind", "destroy")) if o is Dictionary else "destroy"


## Ligne « Objectif : ... » de la carte de campagne.
static func objective_line(contract: Dictionary) -> String:
	match str(contract.get("siege", "")): # La victoire d'un siège est décidée par siege.gd
		"assault":
			var line := "Objectif : prendre la ville et tenir sa place %d s" % int(Siege.HOLD_TIME)
			var target := int(contract.get("target", -1))
			if target >= 0 and target < TOWNS.size():
				line += " (%s change de maître)" % TOWNS[target]["name"]
			return line
		"defense":
			return "Objectif : tenir les murs %s, ou repousser l'assaut" % BattleObjectives.duration_words(Siege.DEFENSE_TIME)
	var v: Variant = contract.get("objective", {})
	var o: Dictionary = v if v is Dictionary else {}
	match objective_kind(contract):
		"hold":
			return "Objectif : tenir la position %s" % BattleObjectives.duration_words(float(o.get("time", 180.0)))
		"escort":
			return "Objectif : escorter %d chariots (%d au moins doivent arriver, supplément par chariot sauvé)" % [int(o.get("wagons", 4)), int(o.get("need", 2))]
		"capture":
			return "Objectif : prendre la place du village avant la nuit (%s)" % BattleObjectives.duration_words(float(o.get("time", 360.0)))
		"pursue":
			return "Objectif : rattraper la bande avant que la moitié ne s'échappe"
	return "Objectif : détruire l'armée ennemie"


## Supplément d'objectif payé après une victoire : pour l'escorte, une part de la prime par chariot sauvé.
## result : bilan de l'objectif (BattleObjectives.Objective.result). Renvoie [écus, libellé].
func objective_bonus(contract: Dictionary, result: Dictionary, reward: int) -> Array:
	if objective_kind(contract) == "escort" and str(result.get("kind", "")) == "escort":
		var saved := maxi(0, int(result.get("saved", 0)))
		var gold_bonus := int(round(reward * float(OBJECTIVES["escort"]["bonus"]) * saved))
		return [gold_bonus, "Prime du convoi (%s)" % plural(saved, "chariot sauvé", "chariots sauvés")]
	return [0, ""]


# ---------------------------------------------------------------- Objectif : la bataille décisive

## Faction qui convoquerait la compagnie : la mieux disposée parmi celles qui ne lui ferment pas
## leurs portes et tiennent encore une ville (le Comté en cas d'égalité). -1 s'il n'y en a pas.
func final_patron() -> int:
	var best := -1
	for f in FACTIONS.size():
		if faction_closed(f) or final_town(f) < 0:
			continue
		if best < 0 or reputation[f] > reputation[best]:
			best = f
	return best


## Ville où le patron f convoque la compagnie : sa capitale s'il la tient encore, sinon sa ville
## la mieux gardée. -1 si f n'a plus de ville.
func final_town(f: int) -> int:
	var capital := int(FACTIONS[f]["capital"])
	if town_owner(capital) == f:
		return capital
	var best := -1
	for t in world.towns_of(f):
		if best < 0 or world.garrison[t] > world.garrison[best]:
			best = t
	return best


## Le contrat final proposé ({} s'il n'y en a pas).
func final_contract() -> Dictionary:
	for c in contracts:
		if c.get("final", false):
			return c
	return {}


## Progression vers l'objectif, de 0 à 1.
func objective_progress() -> float:
	return clampf(float(fame) / FINAL_FAME, 0.0, 1.0)


## Ligne courte qui résume l'objectif et sa progression (carte et panneau).
func objective_status() -> String:
	var k := final_contract()
	if not k.is_empty():
		return "Bataille décisive à %s : %s vous attend !" % [TOWNS[int(k["town"])]["name"], FACTIONS[int(k["faction"])]["short"]]
	if fame >= FINAL_FAME:
		return "Renommée atteinte, mais aucune faction ne veut plus de vous : regagnez leur confiance."
	return "Renommée %d / %d pour être appelé à la bataille décisive." % [fame, FINAL_FAME]


## À FINAL_FAME de renommée, la faction la plus amie propose la bataille décisive dans une de ses
## villes (final_town). Ce contrat n'expire pas ; il suit son patron quand sa ville tombe, et si
## le patron devient hostile ou perd toutes ses villes, une autre faction le reprend.
func offer_final() -> void:
	if ended != "":
		return
	keep_final_in_patron_town()
	if not final_contract().is_empty() or fame < FINAL_FAME:
		return
	var f := final_patron()
	if f < 0:
		return
	var k := make_final(f)
	contracts.append(k)
	add_log("Jour %d : %s vous convoque à %s pour la bataille qui décidera de la guerre !" % [day, cap_first(str(FACTIONS[f]["short"])), TOWNS[int(k["town"])]["name"]])


## Garde le contrat final signable : toujours dans une ville tenue par son patron (il s'y déplace
## quand sa ville tombe), annulé si le patron ferme ses portes ou n'a plus de ville (offer_final le
## repropose alors, au besoin par une autre faction). Sans hasard : appelé aussi par une prise de
## ville (WorldSim.capture) et à la relecture d'une sauvegarde. La bataille en cours n'est pas touchée.
func keep_final_in_patron_town() -> void:
	var cur := final_contract()
	if cur.is_empty() or is_same(cur, pending):
		return
	var f := int(cur["faction"])
	var who := cap_first(str(FACTIONS[f]["short"]))
	var town := final_town(f)
	if faction_closed(f) or town < 0:
		contracts.erase(cur)
		if town < 0:
			add_log("Jour %d : %s a perdu toutes ses villes : la bataille décisive n'aura pas lieu sous sa bannière." % [day, who])
		return
	var old := int(cur["town"])
	if town_owner(old) != f:
		cur["town"] = town
		add_log("Jour %d : %s a perdu %s ; la bataille décisive se prépare désormais à %s." % [day, who, TOWNS[old]["name"], TOWNS[town]["name"]])


func make_final(f: int) -> Dictionary:
	var town := final_town(f)
	var foe_f := int(FACTIONS[f]["rival"])
	var foe := str(FACTIONS[foe_f]["short"])
	return {
		"town": town, "faction": f, "final": true,
		"title": "La bataille décisive : %s contre %s" % [cap_first(str(FACTIONS[f]["short"])), foe],
		"text": "%s jette toutes ses forces contre %s. Cette bataille décidera de la guerre, et la compagnie qui la gagnera sera la plus célèbre du comté." % [cap_first(foe), FACTIONS[f]["short"]],
		"foe": "armées de %s" % foe,
		"difficulty": int(FINAL_CONTRACT["difficulty"]),
		"enemy": roll_army(FINAL_CONTRACT),
		"reward": roll_reward(int(FINAL_CONTRACT["reward"])),
		"expires": 1 << 30,
		"seed": rng.randi_range(1, 1 << 30),
		"objective": {"kind": "destroy"}, "enemy_faction": foe_f,
	}



## Résumé lisible d'une armée : « 2 piquiers, 1 archer... » (en régiments et en hommes).
static func army_summary(list: Array) -> String:
	var counts := {}
	var men := 0
	var ranks := [0, 0, 0]
	for r in list:
		counts[r["type"]] = int(counts.get(r["type"], 0)) + 1
		men += int(r["men"])
		ranks[rank_of(r)] += 1
	var parts: Array[String] = []
	for t in UnitTypes.ORDER:
		if counts.has(t):
			parts.append(type_count(t, int(counts[t])))
	var s := "%s — %s" % [", ".join(parts), plural(men, "homme", "hommes")]
	if ranks[1] + ranks[2] > 0:
		var exp: Array[String] = []
		if ranks[1] > 0:
			exp.append(plural(ranks[1], "aguerri", "aguerris"))
		if ranks[2] > 0:
			exp.append(plural(ranks[2], "vétéran", "vétérans"))
		s += " (%s %s)" % ["régiment" if ranks[1] + ranks[2] == 1 else "régiments", ", ".join(exp)]
	return s


## Accepte un contrat de la ville actuelle : la bataille peut commencer.
func accept(contract: Dictionary) -> String:
	if int(contract["town"]) != location:
		return "Ce contrat se signe à %s." % TOWNS[contract["town"]]["name"]
	if is_over():
		return "La campagne est terminée."
	if is_destroyed():
		return "Vous n'avez plus de troupes."
	var closed := closed_message(location)
	if closed != "":
		return closed
	pending = contract
	return ""


func in_battle() -> bool:
	return not pending.is_empty()


## Régiments engagés dans la bataille (au plus MAX_REGIMENTS, ceux qui ont encore des hommes).
func battle_army() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in company:
		if int(r["men"]) > 0 and out.size() < MAX_REGIMENTS:
			out.append(r)
	return out


## Fin de bataille. survivors[i] = hommes encore debout (ou enfuis) du régiment battle_army()[i],
## kills[i] = ennemis qu'il a tués. Les pertes et l'expérience sont reportées sur la compagnie.
## retreat : défaite par retraite ordonnée (pénalités réduites).
## Renvoie le bilan structuré (voir finish_report) ; son « text » est le compte rendu du journal.
## objective : bilan de l'objectif de la bataille (BattleObjectives.Objective.result ; vide = détruire),
## pour le supplément de prime (escorte) et le compte rendu.
func finish_battle(victory: bool, survivors: Array, kills: Array = [], retreat := false, objective: Dictionary = {}) -> Dictionary:
	var army := battle_army()
	var lost := 0
	var healed := 0
	var promoted: Array[String] = []
	var killed := 0
	var out := {"gold_before": gold, "fame_before": fame, "reputation_before": reputation.duplicate(),
		"regiments": [], "reward": 0, "loot": 0, "pillage": 0, "bonus": 0, "bonus_label": "", "objective": objective.duplicate(true)}
	for i in army.size():
		var r := army[i]
		var before: int = r["men"]
		var after: int = clampi(int(survivors[i]) if i < survivors.size() else before, 0, before)
		var stood := after
		if victory:
			var h := int(floor((before - after) * WOUNDED_RECOVER))
			after += h
			healed += h
		lost += before - after
		r["men"] = after
		# Expérience : participation, victoire, ennemis tués (rapportés à la taille du régiment)
		var k: int = int(kills[i]) if i < kills.size() else 0
		killed += k
		var full := float(UnitTypes.STATS[r["type"]]["count"])
		var rank0 := rank_of(r)
		var xp0 := float(r.get("xp", 0.0))
		r["xp"] = minf(float(r.get("xp", 0.0)) + XP_BATTLE + (XP_VICTORY if victory else 0.0) + XP_KILLS * k / full, XP_MAX)
		r["battles"] = int(r.get("battles", 0)) + 1 # Statistiques : âge et décorations du régiment
		r["kills"] = int(r.get("kills", 0)) + k
		if after > 0 and rank_of(r) > rank0:
			var gained := Traits.on_promotion(r)
			promoted.append("les %s (%d) deviennent %s%s" % [type_name(r["type"]).to_lower(), i + 1, rank_name(rank_of(r)), " et %s" % gained if gained != "" else ""])
		out["regiments"].append({"type": r["type"], "before": before, "after": after, "healed": after - stood,
			"kills": k, "xp_before": xp0, "xp_after": float(r["xp"]), "rank_before": rank0, "rank_after": rank_of(r),
			"promoted": after > 0 and rank_of(r) > rank0})
		out["regiments"][-1].merge({"battles": r["battles"], "kills_total": r["kills"]})
	company = company.filter(func(r): return int(r["men"]) > 0)
	men_lost += lost
	enemies_killed += killed
	var losses := "Pertes : %s" % plural(lost, "homme", "hommes")
	var report: String
	var f := int(pending.get("faction", -1))
	var rep_note := ""
	if victory:
		victories += 1
		var reward := contract_reward(pending)
		var loot := killed * LOOT_PER_KILL + Traits.extra_loot(army, kills)
		var extra := objective_bonus(pending, objective, reward)
		out["reward"] = reward
		out["loot"] = loot
		out["bonus"] = int(extra[0])
		out["bonus_label"] = str(extra[1])
		gold += reward + loot + int(extra[0])
		gold_earned += reward + loot + int(extra[0])
		fame += 5 + 5 * int(pending.get("difficulty", 1))
		var healed_s := plural(healed, "blessé relevé", "blessés relevés")
		if pending.get("ambush", false):
			report = "Embuscade repoussée ! Butin %d écus. %s (%s)." % [loot, losses, healed_s]
		else:
			var won := str(OBJECTIVE_VICTORY.get(objective_kind(pending), OBJECTIVE_VICTORY["destroy"])) % pending["foe"]
			report = "%s Prime %d écus, butin %d écus. %s (%s)." % [won, reward, loot, losses, healed_s]
			if int(extra[0]) > 0:
				report = report.replace(", butin", ", %s %d écus, butin" % [str(extra[1]).to_lower(), int(extra[0])])
		if pending.get("final", false):
			ended = "victory"
			end_day = day
			end_note = "Au jour %d, la victoire de %s décide de la guerre. %s triomphe, et votre compagnie est la plus célèbre du comté." % [day, TOWNS[int(pending["town"])]["name"], cap_first(str(FACTIONS[f]["short"]))]
			report += " La guerre est gagnée : la compagnie entre dans la légende !"
		if f >= 0:
			var rival := int(pending.get("enemy_faction", -1)) # La faction battue, sinon la rivale du patron
			if rival < 0 or rival == f:
				rival = int(FACTIONS[f]["rival"])
			change_reputation(f, REP_WIN)
			change_reputation(rival, REP_RIVAL)
			rep_note = " Réputation : %s %+d, %s %+d." % [FACTIONS[f]["short"], REP_WIN, FACTIONS[rival]["short"], REP_RIVAL]
	else:
		defeats += 1
		# Défaite : les bagages sont pillés, la renommée et la faction qui payait en pâtissent
		var pillage := int(floor(gold * (PILLAGE_RETREAT if retreat else PILLAGE)))
		gold -= pillage
		out["pillage"] = pillage
		fame = maxi(0, fame - (FAME_RETREAT if retreat else FAME_LOSS))
		if retreat:
			report = "Retraite face aux %s. %s. Bagages abandonnés : -%d écus." % [pending["foe"], losses, pillage]
		else:
			report = "Défaite face aux %s... %s. L'ennemi pille vos bagages : -%d écus." % [pending["foe"], losses, pillage]
		if objective_kind(pending) != "destroy" and str(objective.get("summary", "")) != "":
			report += " (%s)" % str(objective["summary"])

		if f >= 0:
			var loss := REP_RETREAT if retreat else REP_LOSS
			change_reputation(f, loss)
			rep_note = " Réputation : %s %+d." % [FACTIONS[f]["short"], loss]
	rep_note += world.after_battle(self, victory) # Armée rencontrée : dispersée ou non
	rep_note += overworld.after_battle(self, victory, out) # Groupe de la carte en temps réel
	report += rep_note
	if not promoted.is_empty():
		report += " Promotions : %s." % ", ".join(promoted)
	report += captain.after_battle(self, victory)
	out["gold_battle"] = gold # Or juste après la bataille, avant la solde du jour
	out["men_battle"] = total_men()
	finish_report(out, victory, retreat, lost, healed, killed, report)
	contracts.erase(pending)
	pending = {}
	add_log("Jour %d : %s" % [day, report])
	if ended == "":
		pass_day() # La bataille et ses suites prennent la journée
		check_ruin()
		if ended == "ruin":
			report += " La compagnie est anéantie et ruinée : la campagne est perdue."
			out["text"] = report
	out["ended"] = ended
	out["wage"] = maxf(float(out["gold_battle"]) - gold, 0.0)
	out["deserted"] = int(out["men_battle"]) - total_men()
	out["gold_after"] = gold
	out["fame_after"] = fame
	out["reputation_after"] = reputation.duplicate()
	return out


## Complète le bilan de finish_battle : issue, contrat, totaux et compte rendu texte.
## Clés : victory, retreat, ambush, title, foe, faction, lost, healed, killed, text,
## regiments (un par régiment de battle_army() : type, before, after, healed, kills,
## xp_before, xp_after, rank_before, rank_after, promoted), reward, loot, pillage,
## gold_before, gold_battle, wage, gold_after, men_battle, deserted,
## fame_before, fame_after, reputation_before, reputation_after.
func finish_report(out: Dictionary, victory: bool, retreat: bool, lost: int, healed: int, killed: int, text: String) -> void:
	out["victory"] = victory
	out["retreat"] = retreat and not victory
	out["ambush"] = bool(pending.get("ambush", false))
	out["title"] = str(pending.get("title", ""))
	out["foe"] = str(pending.get("foe", ""))
	out["faction"] = int(pending.get("faction", -1))
	out["lost"] = lost
	out["healed"] = healed
	out["killed"] = killed
	out["text"] = text


# ---------------------------------------------------------------- Rencontres de la carte en temps réel
# Bloc des rencontres (encounter.gd) : bataille contre un groupe de la carte (Party), butin en
# marchandises, vivres et escortes. Branché ailleurs par quatre lignes seulement : to_dict et
# from_dict (« encounters »), pass_day (take_provisions) et contract_from_dict (« party_id »).

const REP_VILLAGERS := -8 ## Attaquer des villageois d'une faction
const REP_PLUNDER := -15 ## Piller une caravane d'une faction
const REP_EXTORT := -6 ## Rançonner des villageois
const REP_BANDITS := 4 ## Détruire (ou soumettre) des bandits : la faction locale apprécie
const REP_TURN_IN := 3 ## Livrer des déserteurs à leur faction
const REP_ESCORT := 3 ## Caravane escortée à bon port
const ESCORT_DAYS := 6 ## Durée d'une escorte avant que le marché soit caduc
const PARTY_REGIMENTS := 10 ## Régiments ennemis au plus dans une bataille contre un groupe
## Nom de l'ennemi dans le compte rendu (« Victoire sur les %s »).
const PARTY_FOES := {
	"villagers": "villageois", "bandits": "bandits", "caravan": "gardes de la caravane",
	"patrol": "sergents de {f}", "army": "troupes de {f}", "deserters": "déserteurs", "player": "ennemis",
}

var loot := 0 ## Butin en marchandises (valeur en écus), à revendre aux villageois et caravanes
var provisions := 0.0 ## Vivres achetés : écus de solde couverts au prochain jour
var escorts: Array[Dictionary] = [] ## Escortes en cours : {"party_id", "reward", "faction", "goal", "expires"}


## Contrat de bataille contre un groupe de la carte (même forme que make_contract, lu par battle.gd
## via pending) : ennemi tiré de other.troops (découpé en régiments complets), terrain imposé,
## ni prime ni faction qui paie. « party_id » : le groupe, à retrouver après la bataille.
func party_contract(other: Party, terrain: String) -> Dictionary:
	var enemy: Array[Dictionary] = []
	for r in other.troops:
		var type := str(r["type"])
		var men := int(r.get("men", 0))
		if men <= 0 or not UnitTypes.STATS.has(type):
			continue
		var full := int(UnitTypes.STATS[type]["count"])
		var parts := ceili(men / float(full))
		for i in parts:
			@warning_ignore("integer_division")
			var n := men / parts + (1 if i < men % parts else 0)
			enemy.append({"type": type, "men": n, "rank": rank_from_xp(float(r.get("xp", 0.0)))})
	enemy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["men"]) > int(b["men"]))
	enemy.resize(mini(enemy.size(), PARTY_REGIMENTS))
	var foe := str(PARTY_FOES.get(other.kind, "ennemis"))
	if other.faction >= 0:
		foe = foe.replace("{f}", str(FACTIONS[other.faction]["short"]))
	if not terrain in Terrain.KINDS or terrain == "siege":
		terrain = "plain"
	return {
		"town": clampi(location, 0, TOWNS.size() - 1), "faction": -1, "party_id": other.id, "terrain": terrain,
		"title": "Rencontre : %s" % other.display_name(),
		"text": "%s. Pas de prime : seulement le butin." % cap_first(other.display_name()),
		"foe": foe, "difficulty": clampi(ceili(other.men() / 60.0), 1, MAX_LEVEL),
		"enemy": enemy, "reward": 0, "expires": day,
		"seed": absi(hash([other.id, day, "bataille"])) % (1 << 30) + 1,
		"objective": {"kind": "destroy"},
		"enemy_faction": other.faction if other.kind in ["patrol", "army"] else -1,
	}


const PARTY_REGROUP := 0.3 ## Groupe vaincu : au plus cette part de ses hommes engagés se regroupe
const PARTY_MIN_MEN := 6 ## Groupe vaincu réduit à moins d'hommes : il se disperse


## Après la bataille contre un groupe (à appeler après finish_battle, avec son bilan) : pertes
## reportées sur other.troops, butin et réputation. result : « victory » et, pour l'effectif ennemi
## restant, « enemy_survivors » (debout + fuyards revenus), ou « totals » du bilan de bataille
## (enemy_standing + enemy_fled), sinon « killed » (tués par la compagnie). Renvoie la note.
func apply_party_battle(other: Party, result: Dictionary) -> String:
	var victory := bool(result.get("victory", false))
	var before := other.men()
	var engaged := 0 # Hommes réellement engagés (au plus PARTY_REGIMENTS régiments)
	for e in party_contract(other, "plain")["enemy"]:
		engaged += int(e["men"])
	var survivors := engaged
	if result.has("enemy_survivors"):
		survivors = int(result["enemy_survivors"])
	elif result.has("totals"):
		var t: Dictionary = result["totals"]
		survivors = int(t.get("enemy_standing", 0)) + int(t.get("enemy_fled", 0))
	else:
		survivors = engaged - int(result.get("killed", 0))
	if victory: # Vaincus : seule une partie des fuyards se regroupe
		survivors = mini(survivors, int(engaged * PARTY_REGROUP))
	# Les hommes restés hors de la bataille survivent
	survivors = clampi(survivors + before - engaged, 0, before)
	if victory and survivors < PARTY_MIN_MEN:
		survivors = 0 # Trop peu pour tenir la campagne : le groupe se disperse
	scale_troops(other, survivors, before)
	for r in other.troops:
		r["xp"] = minf(float(r.get("xp", 0.0)) + XP_BATTLE + (0.0 if victory else XP_VICTORY), XP_MAX)
	var notes: Array[String] = []
	if victory:
		var g := other.gold
		gold += g
		gold_earned += g
		loot += other.goods
		if g + other.goods > 0:
			notes.append("Butin pris à %s : %d écus et %d écus de marchandises." % [other.display_name(), g, other.goods])
		other.gold = 0
		other.goods = 0
	else:
		other.gold += int(result.get("pillage", 0)) # Les bagages pillés de la compagnie
	var rep: Array[String] = []
	var f := other.faction
	match other.kind:
		"villagers":
			if f >= 0:
				change_reputation(f, REP_VILLAGERS)
				rep.append("%s %+d" % [FACTIONS[f]["short"], REP_VILLAGERS])
		"caravan":
			if f >= 0:
				change_reputation(f, REP_PLUNDER)
				rep.append("%s %+d" % [FACTIONS[f]["short"], REP_PLUNDER])
		"bandits":
			var local := town_owner(other.home if other.home >= 0 and other.home < TOWNS.size() else clampi(location, 0, TOWNS.size() - 1))
			if victory and local >= 0:
				change_reputation(local, REP_BANDITS)
				rep.append("%s %+d" % [FACTIONS[local]["short"], REP_BANDITS])
		"patrol", "army":
			if victory and f >= 0:
				change_reputation(f, -WorldSim.REP_ARMY)
				rep.append("%s %+d" % [FACTIONS[f]["short"], -WorldSim.REP_ARMY])
				for e in world.enemies_of(f):
					change_reputation(e, WorldSim.REP_ARMY)
					rep.append("%s %+d" % [FACTIONS[e]["short"], WorldSim.REP_ARMY])
	if not rep.is_empty():
		notes.append("Réputation : %s." % ", ".join(rep))
	if other.is_dead():
		notes.append("%s n'existe plus." % cap_first(other.display_name()))
		finish_escort(other.id, false)
	var note := " ".join(notes)
	if note != "":
		add_log("Jour %d : %s" % [day, note])
	return note


## Ramène l'effectif d'un groupe de before à survivors, régiment par régiment (proportionnellement).
static func scale_troops(other: Party, survivors: int, before: int) -> void:
	if before <= 0:
		return
	var k := survivors / float(before)
	var left := survivors
	for r in other.troops:
		var n := mini(int(floor(int(r["men"]) * k)), left)
		r["men"] = n
		left -= n
	var i := 0
	while left > 0 and not other.troops.is_empty():
		var r: Dictionary = other.troops[i % other.troops.size()]
		r["men"] = int(r["men"]) + 1
		left -= 1
		i += 1
	other.troops = other.troops.filter(func(r: Dictionary) -> bool: return int(r["men"]) > 0)


## Vivres achetés : ils couvrent une partie de la solde (appelé par pass_day). Renvoie la solde due.
func take_provisions(wage: float) -> float:
	var used := minf(provisions, wage)
	provisions = 0.0
	return wage - used


## Escorte d'une caravane jusqu'à son but (other.goal) : payée par finish_escort à l'arrivée.
func start_escort(other: Party, reward: int) -> Dictionary:
	var e := {"party_id": other.id, "reward": reward, "faction": other.faction, "goal": other.goal, "expires": day + ESCORT_DAYS}
	escorts.append(e)
	add_log("Jour %d : la compagnie escorte %s." % [day, other.display_name()])
	return e


func escort_for(party_id: int) -> Dictionary:
	for e in escorts:
		if int(e["party_id"]) == party_id:
			return e
	return {}


## Fin d'une escorte : le moteur l'appelle quand la caravane arrive (arrived vrai) ou disparaît.
## Renvoie le message ("" si aucune escorte).
func finish_escort(party_id: int, arrived: bool) -> String:
	var e := escort_for(party_id)
	if e.is_empty():
		return ""
	escorts.erase(e)
	var msg: String
	if arrived and int(e["expires"]) >= day:
		var pay := int(e["reward"])
		gold += pay
		gold_earned += pay
		msg = "la caravane arrive à bon port : %d écus pour l'escorte." % pay
		var f := int(e["faction"])
		if f >= 0:
			change_reputation(f, REP_ESCORT)
			msg += " Réputation : %s %+d." % [FACTIONS[f]["short"], REP_ESCORT]
	else:
		msg = "l'escorte de la caravane a échoué."
	add_log("Jour %d : %s" % [day, msg])
	return cap_first(msg)


func encounters_to_dict() -> Dictionary:
	return {"loot": loot, "provisions": provisions, "escorts": escorts.duplicate(true)}


## Relit les rencontres (sauvegarde sans rencontres : rien en cours).
func encounters_from_dict(v: Variant) -> void:
	if not v is Dictionary:
		return
	loot = maxi(0, int(v.get("loot", 0)))
	provisions = maxf(0.0, float(v.get("provisions", 0.0)))
	escorts.clear()
	for e in v.get("escorts", []):
		if e is Dictionary and e.has("party_id"):
			escorts.append({"party_id": int(e["party_id"]), "reward": maxi(0, int(e.get("reward", 0))),
				"faction": clampi(int(e.get("faction", -1)), -1, FACTIONS.size() - 1),
				"goal": int(e.get("goal", -1)), "expires": int(e.get("expires", 0))})
