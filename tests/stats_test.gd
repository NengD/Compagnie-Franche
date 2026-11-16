extends SceneTree
## Test headless des statistiques globales et des succès :
##   godot --headless --path . -s tests/stats_test.gd
## - compteurs, records de régiments, sauvegarde et relecture, fichier abîmé ;
## - succès débloqués une seule fois, notification posée sur la racine ;
## - fin de campagne comptée une seule fois ;
## - campagne : âge et ennemis tués de chaque régiment, gardés dans la sauvegarde ;
## - bataille réelle : la retraite est enregistrée par l'observateur (Achievements.Watch) ;
## - faits d'armes : embuscade du joueur, carré qui repousse une charge ;
## - menu principal : page « Statistiques et succès ».
## N'écrit que dans user://test_stats.json (jamais le vrai fichier). Code de sortie : 0 si tout va bien.

const STATS_TEST := "user://test_stats.json"
const OPTIONS_TEST := "user://test_stats_options.cfg"
const SLOT_TEST := "user://test_stats_campagne"

var fails: Array[String] = []
var frame := 0
var node: Node


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	Stats.path = STATS_TEST
	remove(STATS_TEST)
	Stats.loaded = false
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.slot_prefix = SLOT_TEST
	CampaignState.use_slot(1)
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	check(Stats.file_path() == STATS_TEST, "chemin de test")
	Stats.path = ""
	check(Stats.file_path() == Stats.TEST_PATH, "sous un script, jamais le vrai fichier")
	Stats.path = STATS_TEST
	_test_counters()
	_test_achievements()
	_test_campaign()
	_test_feats()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			Stats.reset()
			node = load("res://scenes/main.tscn").instantiate()
			node.set("seed_override", 5)
			node.set("terrain_override", "plain")
			root.add_child(node)
		3:
			node.sim.start()
			node.order_retreat()
		6:
			check(Stats.count("battles") == 1 and Stats.count("retreats") == 1 and Stats.count("defeats") == 1, "retraite enregistrée par l'observateur (%d batailles)" % Stats.count("battles"))
			check(Stats.is_unlocked("retraite"), "succès de la retraite")
			check(root.get_node_or_null("Succes_retraite") != null, "notification de la retraite affichée")
			root.remove_child(node)
			node.free()
			node = load("res://scenes/menu.tscn").instantiate()
			node.set("change_scenes", false)
			root.add_child(node)
		8:
			node.open_stats()
		10:
			check(node.page == "stats", "page Statistiques et succès")
			check(node.find_child("Statistiques", true, false) != null and node.find_child("Succes", true, false) != null, "statistiques et liste des succès affichées")
			var list: Node = node.find_child("Succes", true, false)
			check(list != null and list.get_child_count() == Achievements.LIST.size(), "un succès par ligne")
			node.back_to_main()
		12:
			check(node.page == "main", "retour au menu principal")
			root.remove_child(node)
			node.free()
			_finish()
			return true
	return false


func _finish() -> void:
	remove(STATS_TEST)
	remove(OPTIONS_TEST)
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	for n in root.get_children():
		if n.name.begins_with("Succes_"):
			n.free()
	if fails.is_empty():
		print("TEST STATISTIQUES OK")
	else:
		print("TEST STATISTIQUES : %d échec(s)" % fails.size())
	quit(0 if fails.is_empty() else 1)


func _test_counters() -> void:
	Stats.load_stats()
	check(Stats.count("battles") == 0, "fichier absent : tout à zéro")
	var got := Stats.record_battle({"outcome": "victory", "killed": 40, "lost": 3, "gold": 120, "regiments_lost": 0,
		"regiments": [{"type": "spear", "battles": 4, "kills_total": 30, "rank_after": 1}, {"type": "archer", "battles": 2, "kills_total": 50, "rank_after": 0}]})
	check("premiere_victoire" in got and "sans_perte_regiment" in got and not "sans_un_mort" in got, "succès de la première victoire : %s" % [got])
	Stats.record_battle({"outcome": "defeat", "killed": 10, "lost": 20})
	check(Stats.count("battles") == 2 and Stats.count("victories") == 1 and Stats.count("defeats") == 1, "batailles gagnées et perdues")
	check(Stats.count("enemies_killed") == 50 and Stats.count("men_lost") == 23 and Stats.count("gold_earned") == 120, "ennemis tués, hommes perdus, or gagné")
	check(str(Stats.data["oldest"]["type"]) == "spear" and str(Stats.data["decorated"]["type"]) == "archer", "régiments le plus ancien et le plus décoré")
	check(Achievements.regiment_text(Stats.data["oldest"]).contains("4 batailles"), "texte du régiment le plus ancien")
	# Relecture
	Stats.load_stats()
	check(Stats.count("battles") == 2 and Stats.is_unlocked("premiere_victoire") and int(Stats.data["decorated"]["kills"]) == 50, "statistiques relues depuis le fichier")
	check(not FileAccess.file_exists(STATS_TEST + ".tmp"), "pas de fichier temporaire oublié")
	# Fichier abîmé : on repart de zéro sans erreur
	var f := FileAccess.open(STATS_TEST, FileAccess.WRITE)
	f.store_string("{pas du json")
	f.close()
	Stats.load_stats()
	check(Stats.count("battles") == 0 and not Stats.is_unlocked("premiere_victoire"), "fichier abîmé → zéro")
	print("Compteurs : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_achievements() -> void:
	Stats.reset()
	check(Achievements.LIST.size() >= 20, "une vingtaine de succès")
	var ids := {}
	for a in Achievements.LIST:
		check(not ids.has(a["id"]) and str(a["name"]) != "" and str(a["desc"]) != "", "succès bien défini : %s" % a["id"])
		ids[a["id"]] = true
	var got := Stats.record_battle({"outcome": "victory", "killed": 1000, "lost": 0, "regiments_lost": 0, "terrain": "siege",
		"duration": 90.0, "player_before": 100, "enemy_before": 160, "new_veteran": true, "ambush_by_player": true,
		"square_repelled": true, "campaign": false, "difficulty": Difficulty.HARD})
	for id in ["sans_un_mort", "carre", "embuscade", "siege", "eclair", "un_contre_deux", "elite", "escarmouche_difficile", "tues_100", "tues_1000"]:
		check(id in got, "succès %s débloqué" % id)
	check(not "retraite" in got and not "campagne_gagnee" in got, "pas de succès immérité")
	var again := Stats.record_battle({"outcome": "victory", "killed": 0, "lost": 5, "regiments_lost": 1})
	check(again.is_empty(), "un succès ne se débloque qu'une fois : %s" % [again])
	for i in 8:
		Stats.record_battle({"outcome": "defeat"})
	check(Stats.is_unlocked("batailles_10"), "10 batailles livrées")
	check(root.get_node_or_null("Succes_carre") == null, "notification posée en différé")
	print("Succès : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_campaign() -> void:
	Stats.reset()
	var c := CampaignState.new_game(77, Difficulty.HARD)
	c.refresh_contracts(c.location)
	check(c.accept(c.contracts_at(c.location)[0]) == "", "contrat accepté")
	var n := c.battle_army().size()
	var surv := []
	var kills := []
	for i in n:
		surv.append(int(c.battle_army()[i]["men"]))
		kills.append(3)
	var res := c.finish_battle(true, surv, kills)
	check(int(c.company[0]["battles"]) == 1 and int(c.company[0]["kills"]) == 3, "âge et ennemis tués du régiment")
	check(int(res["regiments"][0]["battles"]) == 1 and int(res["regiments"][0]["kills_total"]) == 3, "bilan : âge et ennemis tués")
	var back := CampaignState.from_dict(c.to_dict())
	check(back != null and int(back.company[0]["battles"]) == 1 and int(back.company[0]["kills"]) == 3, "âge et ennemis tués sauvegardés")
	check(Achievements.company_best(back.company, "kills")["kills"] == 3, "régiment le plus décoré de la campagne")
	# Fin de campagne : comptée une seule fois
	c.ended = "victory"
	c.end_day = 40
	var got := Stats.record_campaign_end(c)
	check("campagne_gagnee" in got and "campagne_difficile" in got and "campagne_rapide" in got, "succès de campagne : %s" % [got])
	Stats.record_campaign_end(c)
	check(Stats.count("campaigns_won") == 1 and Stats.count("longest_campaign") == 40, "campagne comptée une fois, plus longue campagne")
	var d := CampaignState.new_game(78)
	d.ended = "ruin"
	d.end_day = 55
	Stats.record_campaign_end(d)
	check(Stats.count("campaigns_lost") == 1 and Stats.count("longest_campaign") == 55 and Stats.is_unlocked("dissous"), "campagne perdue")
	print("Campagne : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


## Faits d'armes émis par la simulation et interprétés par l'observateur.
func _test_feats() -> void:
	var b := Battle.new() # Hors de l'arbre : seule la simulation sert
	var w := Achievements.watch(b)
	var sq := b.sim.add_regiment(BattleSim.PLAYER, "spear", Vector2(1600, 1500), Vector2.UP)
	var cav := b.sim.add_regiment(BattleSim.ENEMY, "cavalry", Vector2(1600, 1300), Vector2.DOWN)
	sq.formation = Regiment.Formation.SQUARE
	# Charge sur le carré, puis embuscade du joueur, par la vraie fonction de coup
	var a: Soldier = cav.soldiers[0]
	a.momentum = 1.0
	b.sim.strike(a, sq.soldiers[0])
	sq.hidden = true
	b.sim.strike(sq.soldiers[1], cav.soldiers[1])
	check(w.charges.size() == 1 and w.ambush_by_player, "charge sur un carré et embuscade du joueur signalées")
	cav.routing = true
	sq.update_center()
	w._on_ended()
	check(w.square_repelled, "le carré a repoussé la charge")
	b.sim.clear()
	b.free()
	print("Faits d'armes : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))
