extends SceneTree
## Banc d'équilibrage de la campagne (sans fenêtre, hors de tools/run_tests.ps1 : il est long).
## Un joueur de campagne simulé (tests/campaign_player.gd) recrute, marche, accepte des contrats
## adaptés à sa force et joue les batailles, jusqu'à la victoire, la ruine ou la limite de jours.
##   godot --headless --path . -s tests/campaign_balance.gd -- --seeds=8 --difficulty=all
## Options :
##   --seeds=N        nombre de campagnes par difficulté (défaut 4)
##   --first=N        première graine (défaut 1)
##   --difficulty=D   easy, normal (défaut), hard, ou « all » (chacune tour à tour)
##   --days=N         limite de jours d'une campagne (défaut 240)
##   --fast           batailles ordinaires résolues par un modèle (la bataille décisive reste jouée)
##   --objectives=destroy  n'accepte que les contrats « détruire l'ennemi » (défaut : tous les objectifs)
##   --trace          affiche chaque décision du joueur et chaque bataille
##   --out=FICHIER    ajoute une ligne JSON par campagne à ce fichier (pour --merge)
##   --merge=F1,F2    n'exécute rien : relit ces fichiers et affiche le rapport commun
## Pour aller vite, lancer un processus par difficulté (ou par tranche de graines avec --first) avec
## --out, puis --merge. Rapporte, par difficulté : taux de victoire, causes d'échec, jours jusqu'à
## l'offre et jusqu'à la bataille décisive, courbes d'or, de renommée et d'effectifs, et la calibration
## des batailles (victoires et pertes selon le rapport de force estimé).

const CampaignPlayer := preload("res://tests/campaign_player.gd")

var n_seeds := 4
var first_seed := 1
var difficulties: PackedStringArray = ["normal"]
var max_days := 240
var fast := false
var all_objectives := true
var trace := false
var out_path := ""
var merge: PackedStringArray = []


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			n_seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--first="):
			first_seed = int(a.trim_prefix("--first="))
		elif a.begins_with("--difficulty="):
			var d := a.trim_prefix("--difficulty=")
			difficulties = PackedStringArray(Difficulty.IDS) if d == "all" else d.split(",")
		elif a.begins_with("--days="):
			max_days = int(a.trim_prefix("--days="))
		elif a == "--trace":
			trace = true
		elif a == "--fast":
			fast = true
		elif a == "--objectives=destroy":
			all_objectives = false
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--merge="):
			merge = a.trim_prefix("--merge=").split(",")
	# Sauvegardes de test (la bataille sauvegarde la campagne), jamais celles du joueur ; une par
	# processus, pour pouvoir en lancer plusieurs à la fois
	CampaignState.slot_prefix = "user://test_banc_campagne_%d" % OS.get_process_id()
	CampaignState.use_slot(1)


func _process(_delta: float) -> bool:
	var results: Array[Dictionary] = []
	if not merge.is_empty():
		for path in merge:
			results.append_array(read_results(path))
		report(results)
		quit(0)
		return true
	var t0 := Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var player := CampaignPlayer.new(scene, root, fast)
	player.all_objectives = all_objectives
	player.trace = trace
	for dk in difficulties:
		for i in n_seeds:
			var t1 := Time.get_ticks_msec()
			var res := player.run(first_seed + i, Difficulty.sanitize(dk), max_days)
			res["secs"] = (Time.get_ticks_msec() - t1) / 1000.0
			print(campaign_line(res))
			results.append(res)
			if out_path != "":
				append_result(res)
	CampaignState.delete_slot(1)
	report(results)
	print("(%.1f s de calcul)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
	return true


func append_result(res: Dictionary) -> void:
	var f: FileAccess
	if FileAccess.file_exists(out_path):
		f = FileAccess.open(out_path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_warning("Impossible d'écrire %s" % out_path)
		return
	f.store_line(JSON.stringify(res))
	f.close()


func read_results(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Fichier illisible : %s" % path)
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			out.append(v)
	return out


func campaign_line(res: Dictionary) -> String:
	var r := str(res["result"])
	var label := str({"victory": "VICTOIRE", "ruin": "RUINE", "limit": "LIMITE"}.get(r, r))
	return "%-9s graine %3d  %-8s jour %3d  offre %3s  décisive %3s (%d essai(s))  %2d V / %2d D  renommée %3d  or %5d  hommes %3d  %s  [%d vraies batailles, %.0f s]" % [
		Difficulty.display_name(str(res["difficulty"])), int(res["seed"]), label, int(res["day_end"]),
		day_text(int(res["day_offer"])), day_text(int(res["day_final"])), int(res["final_tries"]),
		int(res["wins"]), int(res["losses"]), int(res["fame"]), int(res["gold"]), int(res["men"]),
		str(res["cause"]), int(res["real"]), float(res.get("secs", 0.0))]


static func day_text(d: int) -> String:
	return "—" if d <= 0 else str(d)


static func mean(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var s := 0.0
	for x in list:
		s += float(x)
	return s / list.size()


static func median(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var l := list.duplicate()
	l.sort()
	return float(l[l.size() / 2])


func report(results: Array[Dictionary]) -> void:
	var by_diff := {}
	for res in results:
		var d := str(res["difficulty"])
		if not by_diff.has(d):
			by_diff[d] = []
		by_diff[d].append(res)
	print("")
	print("=========== Banc de campagne : %d campagne(s)" % results.size())
	for d in Difficulty.IDS:
		if by_diff.has(d):
			report_level(d, by_diff[d])


func report_level(d: String, list: Array) -> void:
	var wins := 0
	var causes := {}
	var offers: Array = []
	var finals: Array = []
	var victory_days: Array = []
	var tries: Array = []
	for res in list:
		if res["result"] == "victory":
			wins += 1
			victory_days.append(int(res["day_end"]))
			tries.append(int(res["final_tries"]))
		else:
			var c := str(res["cause"])
			causes[c] = int(causes.get(c, 0)) + 1
		if int(res["day_offer"]) > 0:
			offers.append(int(res["day_offer"]))
		if int(res["day_final"]) > 0:
			finals.append(int(res["day_final"]))
	print("")
	print("--- %s : %d campagne(s), victoire %d/%d (%.0f %%)" % [Difficulty.display_name(d), list.size(), wins, list.size(), 100.0 * wins / list.size()])
	var cause_parts: PackedStringArray = []
	for c in causes:
		cause_parts.append("%s %d" % [c, causes[c]])
	print("    échecs : %s" % (", ".join(cause_parts) if not cause_parts.is_empty() else "aucun"))
	print("    offre de la bataille décisive : %d/%d, jour moyen %.0f (médiane %.0f)" % [offers.size(), list.size(), mean(offers), median(offers)])
	print("    première bataille décisive : %d/%d, jour moyen %.0f (médiane %.0f)" % [finals.size(), list.size(), mean(finals), median(finals)])
	if wins > 0:
		print("    victoire : jour moyen %.0f, %.1f essai(s) de la bataille décisive en moyenne" % [mean(victory_days), mean(tries)])
	# Courbes : moyenne des campagnes encore en cours à chaque relevé (tous les 10 jours)
	var rows := {}
	for res in list:
		for p in res["curve"]:
			var day := int(p[0])
			if not rows.has(day):
				rows[day] = [[], [], []]
			rows[day][0].append(int(p[1]))
			rows[day][1].append(int(p[2]))
			rows[day][2].append(int(p[3]))
	var days := rows.keys()
	days.sort()
	print("    jour | en cours |   or moyen | renommée | hommes")
	for day in days:
		if int(day) % 20 != 0 and int(day) != 10:
			continue
		var r: Array = rows[day]
		print("    %4d | %8d | %10.0f | %8.0f | %6.0f" % [int(day), r[0].size(), mean(r[0]), mean(r[1]), mean(r[2])])
	# Calibration : issue des batailles selon le rapport de force estimé (vraies batailles seulement)
	var buckets := [0.6, 0.8, 1.0, 1.2, 1.5, 2.0, 3.0, INF]
	var counts := []
	for i in buckets.size():
		counts.append([0, 0, 0.0, 0, 0])
	for res in list:
		for b in res["battles"]:
			var i := 0
			while float(b["ratio"]) >= float(buckets[i]):
				i += 1
			if bool(b["real"]):
				counts[i][0] += 1
				counts[i][1] += 1 if bool(b["win"]) else 0
				counts[i][2] += float(b["loss"])
			if bool(b["final"]):
				counts[i][3] += 1
				counts[i][4] += 1 if bool(b["win"]) else 0
	print("    rapport de force | vraies batailles | victoires | pertes moy | dont décisives (gagnées)")
	var lo := 0.0
	for i in buckets.size():
		var c: Array = counts[i]
		if int(c[0]) > 0:
			print("    %4.1f à %-6s     | %16d | %8.0f%% | %9.0f%% | %d (%d)" % [lo, "+" if buckets[i] == INF else "%.1f" % buckets[i],
				int(c[0]), 100.0 * int(c[1]) / int(c[0]), 100.0 * float(c[2]) / int(c[0]), int(c[3]), int(c[4])])
		lo = float(buckets[i]) if buckets[i] != INF else lo
	# Vraies batailles par sorte (objectif du contrat, siège, embuscade, rencontre, décisive)
	var kinds := {}
	for res in list:
		for b in res["battles"]:
			if not bool(b["real"]):
				continue
			var k := str(b.get("objective", "destroy"))
			if str(b["kind"]) != "contrat":
				k = str(b["kind"])
			if not kinds.has(k):
				kinds[k] = [0, 0, 0.0]
			kinds[k][0] += 1
			kinds[k][1] += 1 if bool(b["win"]) else 0
			kinds[k][2] += float(b["ratio"])
	var parts: PackedStringArray = []
	for k in kinds:
		parts.append("%s %d/%d (rapport moy %.2f)" % [k, kinds[k][1], kinds[k][0], float(kinds[k][2]) / int(kinds[k][0])])
	if not parts.is_empty():
		print("    vraies batailles gagnées par sorte : %s" % ", ".join(parts))
