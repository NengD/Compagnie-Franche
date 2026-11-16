extends SceneTree
## Mini-cas du banc de campagne (tests/campaign_balance.gd, trop long pour run_tests.ps1) :
## une courte campagne en mode rapide, puis une vraie bataille de contrat jouée par le joueur
## de campagne simulé. Vérifie que le banc tourne et que ses relevés sont cohérents.

const CampaignPlayer := preload("res://tests/campaign_player.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error(msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	CampaignState.slot_prefix = "user://test_banc_mini"
	CampaignState.use_slot(1)


func _process(_delta: float) -> bool:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var player := CampaignPlayer.new(scene, root, true)

	# Campagne courte, batailles rapides : elle avance, se bat et se relève tous les 10 jours
	var res := player.run(7, Difficulty.NORMAL, 60)
	print("campagne rapide : %s au jour %d, %d V / %d D, renommée %d, or %d, %d hommes" % [
		res["result"], int(res["day_end"]), int(res["wins"]), int(res["losses"]), int(res["fame"]), int(res["gold"]), int(res["men"])])
	check(int(res["day_end"]) >= 60 or str(res["result"]) != "limit", "la campagne s'arrête avant la limite sans être finie")
	var battles: Array = res["battles"]
	check(battles.size() >= 3, "trop peu de batailles en 60 jours (%d)" % battles.size())
	check(battles.size() == int(res["wins"]) + int(res["losses"]), "batailles notées (%d) et bilan (%d V, %d D) divergent" % [battles.size(), int(res["wins"]), int(res["losses"])])
	check(int(res["fame"]) > 0, "aucune renommée gagnée")
	var curve: Array = res["curve"]
	@warning_ignore("integer_division")
	check(curve.size() == int(res["day_end"]) / 10 + 1 and int(curve[0][0]) == 0 and int(curve[0][1]) == CampaignState.START_GOLD, "courbes : relevés manquants (%d)" % curve.size())
	check(CampaignState.current == null, "la campagne simulée reste « current »")

	# Une vraie bataille de contrat, jouée en accéléré par le joueur tactique
	var camp := CampaignState.new_game(11)
	player.camp = camp
	CampaignState.current = camp
	var k: Dictionary = camp.contracts_at(camp.location)[0]
	k["objective"] = {"kind": "destroy"}
	check(camp.accept(k) == "", "contrat refusé")
	var t0 := Time.get_ticks_msec()
	var won := player.real_battle()
	print("vraie bataille : %s en %.1f s (%s)" % ["victoire" if won else "défaite", (Time.get_ticks_msec() - t0) / 1000.0, camp.log_lines[0]])
	check(not camp.in_battle(), "la bataille n'a pas été reportée sur la campagne")
	check(camp.victories + camp.defeats == 1, "bilan de bataille absent")
	check(won == (camp.victories == 1), "issue de la bataille et campagne divergent")
	CampaignState.current = null
	CampaignState.delete_slot(1)

	if failures.is_empty():
		print("campaign_bench_test : OK")
		quit(0)
	else:
		print("campaign_bench_test : %d échec(s)" % failures.size())
		quit(1)
	return true
