class_name CampaignState
extends RefCounted
## État de la campagne : jour, or, compagnie, villes et contrats.
## Il survit aux changements de scène grâce à la variable statique « current ».
## current == null (ou aucun contrat en cours) : la bataille est une escarmouche isolée.

static var current: CampaignState = null

const START_GOLD := 300
const MAX_REGIMENTS := 8
const TRAVEL_PX_PER_DAY := 130.0 ## Distance parcourue sur la carte en une journée de marche
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

## Villes de la carte (positions en pixels d'écran), faction, prix des recrues (x RECRUIT_COST)
## et types de troupes qu'on peut y lever. Nouvelles unités : les villes de la Ligue lèvent des
## arbalétriers, le Comté (Saint-Aubin) et Hautemure des chevaliers à pied, la Baronnie
## (Montfaucon, Castelroux) des archers montés.
const TOWNS := [
	{"name": "Valombre", "pos": Vector2(140, 560), "faction": 0, "price": 1.0, "recruits": ["spear", "archer"]},
	{"name": "Saint-Aubin", "pos": Vector2(330, 420), "faction": 0, "price": 0.9, "recruits": ["spear", "men_at_arms", "foot_knight"]},
	{"name": "Montfaucon", "pos": Vector2(230, 200), "faction": 1, "price": 1.15, "recruits": ["archer", "cavalry", "horse_archer"]},
	{"name": "Brévannes", "pos": Vector2(500, 600), "faction": 2, "price": 0.85, "recruits": ["spear", "archer", "crossbow"]},
	{"name": "Castelroux", "pos": Vector2(560, 290), "faction": 1, "price": 1.1, "recruits": ["men_at_arms", "cavalry", "horse_archer"]},
	{"name": "Hautemure", "pos": Vector2(770, 140), "faction": 1, "price": 1.25, "recruits": ["men_at_arms", "foot_knight", "archer", "cavalry"]},
	{"name": "Pontrieux", "pos": Vector2(760, 470), "faction": 2, "price": 0.95, "recruits": ["spear", "men_at_arms", "archer", "crossbow"]},
]
const ROADS := [[0, 1], [0, 3], [1, 2], [1, 3], [1, 4], [2, 4], [3, 6], [4, 6], [4, 5], [5, 6]]

## Modèles de contrats, du niveau 1 au niveau MAX_LEVEL : composition de l'ennemi, effectifs
## (part du plein), prime de base et expérience des régiments ennemis (« ranks » : chance d'être
## aguerri, chance d'être vétéran). « {rival} » : la faction rivale de celle de la ville.
## Nouvelles unités : arbalétriers dès le niveau 2, archers montés au niveau 4, chevaliers à pied
## au niveau 5 et dans la bataille décisive (ils remplacent des régiments, l'effectif ne grossit pas).
const CONTRACT_KINDS := [
	{
		"difficulty": 1, "foe": "brigands", "reward": 260, "fill": [0.6, 0.85], "ranks": [0.0, 0.0],
		"army": ["spear", "spear", "men_at_arms", "archer"],
		"titles": ["Brigands sur la route de %s", "Des coupe-jarrets près de %s"],
		"text": "Une bande de brigands rançonne les marchands. Le bourg paie pour qu'on l'en débarrasse.",
	},
	{
		"difficulty": 2, "foe": "routiers", "reward": 450, "fill": [0.75, 1.0], "ranks": [0.4, 0.0],
		"army": ["spear", "spear", "men_at_arms", "men_at_arms", "crossbow", "cavalry"],
		"titles": ["Routiers aux portes de %s", "Une compagnie rivale menace %s"],
		"text": "Des routiers sans contrat pillent la campagne. Ils sont aguerris et ont quelques cavaliers.",
	},
	{
		"difficulty": 3, "foe": "ost du baron", "reward": 720, "fill": [0.9, 1.0], "ranks": [0.7, 0.3],
		"army": ["spear", "spear", "spear", "men_at_arms", "men_at_arms", "archer", "crossbow", "cavalry"],
		"titles": ["La querelle du baron de %s", "Défendre %s contre l'ost du baron"],
		"text": "Un baron voisin lève son ost. La ville engage des lances pour lui tenir tête en rase campagne.",
	},
	{
		"difficulty": 4, "foe": "routiers de la Grande Compagnie", "reward": 1000, "fill": [0.9, 1.0], "ranks": [0.45, 0.55],
		"army": ["spear", "spear", "spear", "men_at_arms", "men_at_arms", "archer", "crossbow", "cavalry", "horse_archer"],
		"titles": ["La Grande Compagnie marche sur %s", "Chevauchée de routiers autour de %s"],
		"text": "Plusieurs bandes se sont unies sous un même capitaine. Nombreuse et aguerrie, la Grande Compagnie rançonne des provinces entières.",
	},
	{
		"difficulty": 5, "foe": "armées de {rival}", "reward": 1350, "fill": [0.95, 1.0], "ranks": [0.2, 0.8],
		"army": ["spear", "spear", "spear", "men_at_arms", "men_at_arms", "foot_knight", "archer", "crossbow", "cavalry", "horse_archer"],
		"titles": ["L'ost de {rival} menace %s", "Bataille rangée devant %s"],
		"text": "{Rival} lève son ost et marche sur la ville. Ses chevaliers sont des vétérans de toutes les guerres.",
	},
]
const MAX_LEVEL := 5 ## Niveau de contrat le plus élevé (atteint à FAME_STEP * 4 de renommée)
## Bataille décisive (objectif de la campagne) : la plus grande armée du jeu, presque toute vétérane.
const FINAL_CONTRACT := {
	"difficulty": 5, "reward": 2500, "fill": [0.95, 1.0], "ranks": [0.1, 0.9],
	"army": ["spear", "spear", "spear", "men_at_arms", "foot_knight", "foot_knight", "archer", "crossbow", "crossbow", "cavalry", "horse_archer"],
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


## Nouvelle partie : une petite compagnie à Valombre.
## lenient_mode : mode indulgent (la bataille en cours n'est pas sauvegardée, voir « lenient »).
static func new_game(seed_value := 0, level := Difficulty.NORMAL, lenient_mode := false) -> CampaignState:
	var c := CampaignState.new()
	c.difficulty = Difficulty.sanitize(level)
	c.lenient = lenient_mode
	if seed_value != 0:
		c.rng.seed = seed_value
	else:
		c.rng.randomize()
	c.captain = Captain.recruit(c.rng.seed)
	c.world = WorldSim.create(c.rng.seed)
	for t in ["spear", "spear", "men_at_arms", "archer", "archer", "cavalry"]:
		c.company.append({"type": t, "men": int(UnitTypes.STATS[t]["count"]), "xp": 0.0})
	for i in TOWNS.size():
		c.refresh_contracts(i)
	c.add_log("Jour 1 : la compagnie se forme à %s (difficulté : %s). Trouvez un contrat !" % [TOWNS[0]["name"], Difficulty.display_name(c.difficulty).to_lower()])
	c.add_log("Objectif : %s" % objective_text())
	return c


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
## Version 7 : monde vivant (villes conquises, guerres, armées, météo ; voir world_sim.gd).
## Version 6 : capitaine, traits et équipement des régiments.
## Version 5 : emplacements, mode indulgent, contrat ou embuscade en cours (« pending »).
## Version 4 : difficulté. Version 3 : fin de campagne, bilan, niveaux de contrat 4-5 et contrat final.
## Les versions 1 (sans expérience, réputation ni renommée), 2, 3, 4, 5 et 6 restent lisibles
## (difficulté : normal, mode indulgent désactivé, aucune bataille en cours, capitaine neuf,
## monde neuf et en paix).
const SAVE_VERSION := 7

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
	}
	if bool(k.get("final", false)):
		out["final"] = true
	if bool(k.get("ambush", false)):
		out["ambush"] = true
	if k.has("world_army"): # Bataille contre une armée rencontrée (world_sim.gd)
		out["world_army"] = int(k["world_army"])
	if str(k.get("siege", "")) in SIEGE_KINDS:
		out["siege"] = str(k["siege"])
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
	c.world = WorldSim.from_dict(d.get("world", {}), c.rng.seed, c.day) # Version 6 et avant : monde neuf
	if c.world == null:
		return null
	# Version 2 et avant : campagne en cours, bilan à zéro
	c.ended = str(d.get("ended", ""))
	if not c.ended in ENDINGS:
		return null
	c.end_day = int(d.get("end_day", 0))
	c.end_note = str(d.get("end_note", ""))
	c.men_lost = maxi(0, int(d.get("men_lost", 0)))
	c.enemies_killed = maxi(0, int(d.get("enemies_killed", 0)))
	c.gold_earned = maxi(0, int(d.get("gold_earned", 0)))
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
	for p in [path, path + ".bak", path + ".tmp"]:
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
	return "En cours, à %s" % TOWNS[location]["name"]


# ---------------------------------------------------------------- Factions et réputation

static func town_faction(town: int) -> int:
	return int(TOWNS[town]["faction"])


## Faction qui tient la ville aujourd'hui (town_faction : celle du début de la campagne).
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
	add_log("Jour %d : arrivée à %s après %s de marche." % [day, TOWNS[to]["name"], plural(done, "jour", "jours")])
	refresh_contracts(to)
	check_ruin()
	return ""


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
	}


## Un jour passe : solde, désertions si les caisses sont vides, contrats qui expirent.
func pass_day() -> void:
	day += 1
	world.advance(self) # Saisons, météo, guerres et armées
	var wage := daily_wage()
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
		contracts.append(world.adjust_contract(make_siege(make_contract(town), "defense")))


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
		enemy.append({"type": t, "men": men, "rank": roll_rank(kind["ranks"])})
	return enemy


## Prime de base tirée autour de celle du modèle, et qui croît avec la renommée.
func roll_reward(base: int) -> int:
	return int(round(base * rng.randf_range(0.9, 1.15) * (1.0 + fame * FAME_REWARD) / 10.0)) * 10


static func cap_first(s: String) -> String:
	return s if s == "" else s[0].to_upper() + s.substr(1)


func make_contract(town: int) -> Dictionary:
	var top := max_level()
	var d := rng.randi_range(maxi(1, top - 1), top)
	var kind: Dictionary = CONTRACT_KINDS[d - 1]
	var enemy := roll_army(kind)
	var titles: Array = kind["titles"]
	var reward := roll_reward(int(kind["reward"]))
	var rival := str(FACTIONS[int(FACTIONS[town_faction(town)]["rival"])]["short"])
	var title := str(titles[rng.randi() % titles.size()]).replace("{rival}", rival) % TOWNS[town]["name"]
	return {
		"town": town,
		"faction": town_faction(town),
		"title": title,
		"text": str(kind["text"]).replace("{Rival}", cap_first(rival)).replace("{rival}", rival),
		"foe": str(kind["foe"]).replace("{rival}", rival),
		"difficulty": d,
		"enemy": enemy,
		"reward": reward,
		"expires": day + CONTRACT_DAYS,
		"seed": rng.randi_range(1, 1 << 30),
	}


# ---------------------------------------------------------------- Contrats de siège (siege.gd)

const SIEGE_KINDS := ["assault", "defense"] ## « siege » d'un contrat : assiéger ou défendre une ville
const SIEGE_CHANCE := 0.12 ## Part des contrats de niveau 2 et plus qui sont des sièges (rares)
const SIEGE_REWARD := 1.6 ## Prime d'un siège par rapport à un contrat ordinaire du même niveau
const SIEGE_TITLES := {
	"assault": ["Assiéger la place forte de {rival} près de %s", "Prendre d'assaut le bourg rebelle de %s"],
	"defense": ["Défendre les murs de %s", "%s assiégée par {rival}"],
}
const SIEGE_TEXTS := {
	"assault": "La ville paie cher pour qu'on prenne la place : bélier pour la porte, échelles pour le rempart. Il faudra tenir la place de la ville.",
	"defense": "L'ennemi vient avec des échelles et un bélier. Garnissez les murs et tenez jusqu'à ce qu'il lève le siège.",
}


## Fait parfois d'un contrat ordinaire un siège, rare et bien payé. Le tirage dépend de la graine du
## contrat : il ne consomme pas le hasard de la campagne (les autres tirages ne changent pas).
## Assaut : la garnison a des archers en plus ; défense : l'assaillant a un régiment de plus.
func maybe_siege(c: Dictionary) -> Dictionary:
	if int(c.get("difficulty", 1)) < 2 or c.get("final", false) or c.has("siege"):
		return c
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(c["seed"]), "siege"])
	if r.randf() >= SIEGE_CHANCE:
		return c
	return make_siege(c, "assault" if r.randf() < 0.5 else "defense")


## Transforme le contrat c en siège (kind : « assault » ou « defense »).
func make_siege(c: Dictionary, kind: String) -> Dictionary:
	var town := int(c["town"])
	var rival := str(FACTIONS[int(FACTIONS[town_faction(town)]["rival"])]["short"])
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(c["seed"]), "siege_army"])
	var titles: Array = SIEGE_TITLES[kind]
	c["siege"] = kind
	c["title"] = str(titles[r.randi() % titles.size()]).replace("{rival}", rival) % TOWNS[town]["name"]
	c["text"] = SIEGE_TEXTS[kind]
	c["reward"] = int(round(int(c["reward"]) * SIEGE_REWARD / 10.0)) * 10
	var extra := "archer" if kind == "assault" else "spear"
	var enemy: Array = c["enemy"]
	enemy.append({"type": extra, "men": int(UnitTypes.STATS[extra]["count"]), "rank": 0})
	return c


# ---------------------------------------------------------------- Objectif : la bataille décisive

## Faction qui convoquerait la compagnie : la mieux disposée parmi celles qui ne lui ferment pas
## leurs portes (le Comté en cas d'égalité). -1 si toutes sont hostiles.
func final_patron() -> int:
	var best := -1
	for f in FACTIONS.size():
		if not faction_closed(f) and (best < 0 or reputation[f] > reputation[best]):
			best = f
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


## À FINAL_FAME de renommée, la faction la plus amie propose la bataille décisive dans sa capitale.
## Ce contrat n'expire pas ; si la faction devient hostile, une autre le reprend.
func offer_final() -> void:
	if ended != "":
		return
	var cur := final_contract()
	if not cur.is_empty():
		if not faction_closed(int(cur["faction"])):
			return
		contracts.erase(cur)
	if fame < FINAL_FAME:
		return
	var f := final_patron()
	if f < 0:
		return
	var k := make_final(f)
	contracts.append(k)
	add_log("Jour %d : %s vous convoque à %s pour la bataille qui décidera de la guerre !" % [day, cap_first(str(FACTIONS[f]["short"])), TOWNS[int(k["town"])]["name"]])


func make_final(f: int) -> Dictionary:
	var town := int(FACTIONS[f]["capital"])
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
func finish_battle(victory: bool, survivors: Array, kills: Array = [], retreat := false) -> Dictionary:
	var army := battle_army()
	var lost := 0
	var healed := 0
	var promoted: Array[String] = []
	var killed := 0
	var out := {"gold_before": gold, "fame_before": fame, "reputation_before": reputation.duplicate(),
		"regiments": [], "reward": 0, "loot": 0, "pillage": 0}
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
		out["reward"] = reward
		out["loot"] = loot
		gold += reward + loot
		gold_earned += reward + loot
		fame += 5 + 5 * int(pending.get("difficulty", 1))
		var healed_s := plural(healed, "blessé relevé", "blessés relevés")
		if pending.get("ambush", false):
			report = "Embuscade repoussée ! Butin %d écus. %s (%s)." % [loot, losses, healed_s]
		else:
			report = "Victoire contre les %s ! Prime %d écus, butin %d écus. %s (%s)." % [pending["foe"], reward, loot, losses, healed_s]
		if pending.get("final", false):
			ended = "victory"
			end_day = day
			end_note = "Au jour %d, la victoire de %s décide de la guerre. %s triomphe, et votre compagnie est la plus célèbre du comté." % [day, TOWNS[int(pending["town"])]["name"], cap_first(str(FACTIONS[f]["short"]))]
			report += " La guerre est gagnée : la compagnie entre dans la légende !"
		if f >= 0:
			var rival := int(FACTIONS[f]["rival"])
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
		if f >= 0:
			var loss := REP_RETREAT if retreat else REP_LOSS
			change_reputation(f, loss)
			rep_note = " Réputation : %s %+d." % [FACTIONS[f]["short"], loss]
	rep_note += world.after_battle(self, victory) # Armée rencontrée : dispersée ou non
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
