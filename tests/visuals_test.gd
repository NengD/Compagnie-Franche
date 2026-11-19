extends SceneTree
## Test du rendu des batailles (équipement visible, armoiries, bannières, corps), sans fenêtre :
##   godot --headless --path . -s tests/visuals_test.gd
## - un régiment équipé en campagne porte son équipement en bataille (Regiment.gear, qualités,
##   apparence retenue par le rendu) ; un régiment sans équipement n'a rien ;
## - les planches repeintes changent bien le casque et l'armure (formes et couleurs selon la
##   qualité) sans toucher aux couleurs du camp ;
## - armoiries : tirage reproductible, valides, sauvegardées et relues (absentes : tirées de la graine) ;
## - bannières ennemies aux couleurs de la faction du contrat ;
## - un soldat tué laisse un corps qui garde son régiment et l'heure de sa chute.
## Code de sortie : 0 si tout va bien, 1 sinon.

const SEED := 9191
const SHEET := "res://assets/sprites/units/SwordsmanCyan.png"

var fails: Array[String] = []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.ensure_loaded()


func _process(_delta: float) -> bool:
	check_heraldry()
	check_dressing()
	check_battle()
	if fails.is_empty():
		print("Rendu des batailles : OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : ", f)
		quit(1)
	return true


# ---------------------------------------------------------------- Armoiries

func check_heraldry() -> void:
	var a := Heraldry.random(SEED)
	check(a == Heraldry.random(SEED), "armoiries : même graine, armoiries différentes")
	var seen := {}
	for i in 40:
		var r := Heraldry.random(1000 + i)
		check(r["field"] in Heraldry.FIELDS and r["charge"] in Heraldry.CHARGES and (r["colors"] as Array).size() == 3, "armoiries invalides : %s" % r)
		check(Heraldry.read(r, 0) == r, "armoiries mal relues : %s" % r)
		# Règle des émaux : le meuble ne se confond pas avec le champ
		check(r["colors"][2] != r["colors"][0], "meuble de l'émail du champ : %s" % r)
		seen[Heraldry.blazon(r)] = true
	check(seen.size() > 15, "armoiries trop peu variées (%d)" % seen.size())
	check(Heraldry.read({"field": "nimbus"}, SEED) == Heraldry.random(SEED), "armoiries invalides non remplacées")
	# Campagne : tirées au départ, sauvegardées, relues ; vieille sauvegarde : tirées de la graine
	var c := CampaignState.new_game(SEED)
	check(Heraldry.read(c.arms, 0) == c.arms, "armoiries de campagne invalides")
	var d := c.to_dict()
	check(d.has("arms"), "armoiries absentes de la sauvegarde")
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back != null and back.arms == c.arms, "armoiries perdues à la relecture")
	d.erase("arms")
	d["version"] = 9
	var old := CampaignState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(old != null and Heraldry.read(old.arms, 0) == old.arms, "vieille sauvegarde : pas d'armoiries valides")


# ---------------------------------------------------------------- Planches repeintes

func check_dressing() -> void:
	var bytes := FileAccess.get_file_as_bytes(SHEET)
	var base := Image.new()
	if bytes.is_empty() or base.load_png_from_buffer(bytes) != OK:
		check(false, "planche illisible : " + SHEET)
		return
	base.convert(Image.FORMAT_RGBA8)
	var looks: Array[Image] = []
	for tier in 4:
		var img := base.duplicate()
		SpriteBank.dress_image(img, 16, tier, tier)
		looks.append(img)
	check(looks[0].get_data() == base.get_data(), "sans équipement, la planche ne doit pas changer")
	for tier in range(1, 4):
		check(looks[tier].get_data() != base.get_data(), "qualité %d : planche inchangée" % tier)
		for other in range(1, tier):
			check(looks[tier].get_data() != looks[other].get_data(), "qualités %d et %d identiques" % [other, tier])
	# Casque (haut de la case) et armure (corps) repeints ; couleurs du camp (bleu) intactes
	var cell := Vector2i(0, 0)
	var helmet_changed := [0, 0, 0, 0]
	var body_changed := [0, 0, 0, 0]
	var team_kept := true
	for tier in range(1, 4):
		for y in 16:
			for x in 16:
				var a := base.get_pixel(cell.x + x, cell.y + y)
				var b := looks[tier].get_pixel(cell.x + x, cell.y + y)
				if a.is_equal_approx(b):
					continue
				if y < SpriteBank.HEAD_BAND[16]:
					helmet_changed[tier] += 1
				else:
					body_changed[tier] += 1
				if a.a > 0.5 and a.s > 0.35 and a.b > a.r + 0.1:
					team_kept = false
		check(helmet_changed[tier] >= 10, "qualité %d : casque à peine repeint (%d pixels)" % [tier, helmet_changed[tier]])
		check(body_changed[tier] >= 4, "qualité %d : armure à peine repeinte (%d pixels)" % [tier, body_changed[tier]])
	check(team_kept, "l'équipement repeint les couleurs du camp")
	# Formes : bord du chapel de fer (pixels hors de la tête d'origine), pointe du bassinet
	check(count_new_pixels(base, looks[1]) >= 2, "chapel de fer sans bord")
	check(count_new_pixels(base, looks[2]) >= 1, "bassinet sans pointe")


## Pixels opaques qui étaient transparents dans la première case (formes ajoutées).
func count_new_pixels(a: Image, b: Image) -> int:
	var n := 0
	for y in 16:
		for x in 16:
			if a.get_pixel(x, y).a < 0.5 and b.get_pixel(x, y).a > 0.5:
				n += 1
	return n


# ---------------------------------------------------------------- Bataille de campagne

func check_battle() -> void:
	var c := CampaignState.new_game(SEED)
	c.company.clear()
	c.company.append({"type": "men_at_arms", "men": 30, "xp": 0.0, "gear": ["helmet_3", "weapon_3", "armor_2"]})
	c.company.append({"type": "spear", "men": 30, "xp": 0.0})
	var contract: Dictionary = c.contracts[0].duplicate(true)
	contract["enemy_faction"] = 1
	c.pending = contract
	CampaignState.current = c
	var battle: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	var sim: BattleSim = battle.sim
	var equipped: Regiment = null
	var bare: Regiment = null
	var foe: Regiment = null
	for r in sim.regiments:
		if r.team == BattleSim.PLAYER and r.company_index == 0:
			equipped = r
		elif r.team == BattleSim.PLAYER and r.company_index == 1:
			bare = r
		elif r.team == BattleSim.ENEMY and foe == null:
			foe = r
	check(equipped != null and bare != null and foe != null, "régiments absents de la bataille")
	if equipped != null and bare != null and foe != null:
		check(equipped.gear == ["helmet_3", "weapon_3", "armor_2"], "équipement absent du régiment de bataille : %s" % [equipped.gear])
		check(equipped.gear_tier("helmet") == 3 and equipped.gear_tier("weapon") == 3 and equipped.gear_tier("armor") == 2, "qualités de l'équipement mal lues")
		check(bare.gear.is_empty() and bare.gear_tier("helmet") == 0, "régiment sans équipement équipé")
		var renderer: BattleRenderer = battle.renderer
		var lk := renderer.look_of(equipped)
		check(int(lk["helmet"]) == 3 and int(lk["armor"]) == 2 and int(lk["weapon"]) == 3, "le rendu ne voit pas l'équipement : %s" % lk)
		check(lk["tex"] != null, "pas de planche pour le régiment équipé")
		var bare_lk := renderer.look_of(bare)
		check(int(bare_lk["helmet"]) == 0 and int(bare_lk["armor"]) == 0 and int(bare_lk["weapon"]) == 0, "le rendu équipe un régiment nu")
		# Bannières : armoiries de la compagnie, couleurs de la faction ennemie
		check(renderer.arms == c.arms, "bannières sans les armoiries de la compagnie")
		check(renderer.flag_color(foe).is_equal_approx(CampaignState.FACTIONS[1]["color"]), "bannière ennemie sans la couleur de sa faction")
		check(renderer.flag_color(equipped).is_equal_approx(Heraldry.color(c.arms, 0)), "bannière du joueur sans ses armoiries")
		# Corps : garde son régiment (et donc son équipement) et l'heure de sa chute
		battle.start_battle()
		battle.simulate(0.5)
		var s: Soldier = equipped.alive_soldiers()[0]
		var killer: Soldier = foe.alive_soldiers()[0]
		sim.damage(s, 99999.0, killer)
		var corpse: Array = sim.corpses.back()
		check(corpse.size() >= 7 and corpse[5] == equipped and is_equal_approx(float(corpse[4]), sim.battle_time), "corps sans régiment ni heure de mort : %s" % [corpse])
		# Le rendu dessine sans erreur (chute en cours, puis corps couché)
		renderer.queue_redraw()
	root.remove_child(battle)
	battle.free()
	CampaignState.current = null
