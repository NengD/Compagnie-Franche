class_name Stats
extends RefCounted
## Statistiques globales, gardées entre les campagnes, et succès débloqués (voir achievements.gd).
## Fichier JSON à part : user://statistiques.json (jamais la sauvegarde de campagne).
## Lancé par un script (-s, donc les tests), le jeu écrit dans user://test_statistiques.json.

const DEFAULT_PATH := "user://statistiques.json"
const TEST_PATH := "user://test_statistiques.json"
const VERSION := 1
const MAX_SEEN := 200 ## Campagnes terminées déjà comptées (graines), pour ne pas compter deux fois
const COUNTERS: Array[String] = ["battles", "victories", "defeats", "retreats", "enemies_killed",
	"men_lost", "gold_earned", "campaigns_won", "campaigns_lost"]

static var path := "" ## Vide = DEFAULT_PATH (ou TEST_PATH sous un script de test)
static var loaded := false
static var data := {}


static func file_path() -> String:
	if path != "":
		return path
	var args := OS.get_cmdline_args()
	return TEST_PATH if ("-s" in args or "--script" in args) else DEFAULT_PATH


static func reset() -> void:
	data = {"version": VERSION, "longest_campaign": 0, "oldest": {}, "decorated": {},
		"achievements": {}, "campaigns_seen": []}
	for k in COUNTERS:
		data[k] = 0


static func ensure_loaded() -> void:
	if not loaded:
		load_stats()


static func load_stats() -> void:
	reset()
	loaded = true
	var p := file_path()
	if not FileAccess.file_exists(p):
		return
	var json := JSON.new() # parse() ne remplit pas le journal d'erreurs si le fichier est abîmé
	if json.parse(FileAccess.get_file_as_string(p)) != OK or not json.data is Dictionary:
		return
	var d: Dictionary = json.data
	if d.is_empty():
		return # Fichier abîmé : on repart de zéro
	for k in COUNTERS:
		data[k] = maxi(0, int(d.get(k, 0)))
	data["longest_campaign"] = maxi(0, int(d.get("longest_campaign", 0)))
	for k in ["oldest", "decorated", "achievements"]:
		if d.get(k) is Dictionary:
			data[k] = d[k]
	if d.get("campaigns_seen") is Array:
		data["campaigns_seen"] = d["campaigns_seen"]


## Écriture sûre : fichier temporaire, puis remplacement.
static func save_stats() -> bool:
	var p := file_path()
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".tmp"), ProjectSettings.globalize_path(p)) == OK


static func count(key: String) -> int:
	ensure_loaded()
	return int(data.get(key, 0))


static func add(key: String, n: int) -> void:
	ensure_loaded()
	data[key] = int(data.get(key, 0)) + maxi(n, 0)


static func is_unlocked(id: String) -> bool:
	ensure_loaded()
	return (data["achievements"] as Dictionary).has(id)


static func unlock(id: String) -> bool:
	if is_unlocked(id):
		return false
	data["achievements"][id] = int(Time.get_unix_time_from_system())
	return true


## Fin de bataille (hors tutoriel). info : voir Achievements.battle_info.
## Renvoie les succès débloqués (déjà notifiés).
static func record_battle(info: Dictionary) -> Array[String]:
	ensure_loaded()
	add("battles", 1)
	match str(info.get("outcome", "")):
		"victory":
			add("victories", 1)
		"retreat":
			add("defeats", 1)
			add("retreats", 1)
		_:
			add("defeats", 1)
	add("enemies_killed", int(info.get("killed", 0)))
	add("men_lost", int(info.get("lost", 0)))
	add("gold_earned", int(info.get("gold", 0)))
	for r in info.get("regiments", []):
		update_records(r)
	return finish(info)


## Régiment le plus ancien (batailles) et le plus décoré (ennemis tués).
static func update_records(r: Dictionary) -> void:
	var entry := {"type": str(r.get("type", "")), "battles": int(r.get("battles", 0)),
		"kills": int(r.get("kills_total", 0)), "rank": int(r.get("rank_after", 0))}
	var old: Dictionary = data["oldest"]
	if entry["battles"] > int(old.get("battles", 0)):
		data["oldest"] = entry
	var dec: Dictionary = data["decorated"]
	if entry["kills"] > int(dec.get("kills", 0)):
		data["decorated"] = entry


## Campagne terminée (victoire ou ruine) : comptée une seule fois (d'après sa graine).
static func record_campaign_end(c: CampaignState) -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	if c == null or c.ended == "":
		return out
	var sig := str(c.rng.seed)
	var seen: Array = data["campaigns_seen"]
	if sig in seen:
		return out
	seen.append(sig)
	while seen.size() > MAX_SEEN:
		seen.pop_front()
	add("campaigns_won" if c.ended == "victory" else "campaigns_lost", 1)
	var days := c.end_day if c.end_day > 0 else c.day
	data["longest_campaign"] = maxi(int(data["longest_campaign"]), days)
	return finish({"campaign_end": c.ended, "campaign_difficulty": c.difficulty, "campaign_days": days})


## Vérifie les succès, sauvegarde et affiche une notification pour chaque nouveau.
static func finish(info: Dictionary) -> Array[String]:
	var fresh := Achievements.check(info)
	save_stats()
	Achievements.notify(fresh)
	return fresh
