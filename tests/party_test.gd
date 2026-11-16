extends SceneTree
## Test du squelette des groupes de la carte (party.gd), sans fenêtre :
##   godot --headless --path . -s tests/party_test.gd
## Code de sortie : 0 si tout va bien, 1 sinon.

var fails: Array[String] = []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _initialize() -> void:
	var p := Party.new()
	p.id = 7
	p.kind = "bandits"
	p.name = "les Écorcheurs"
	p.pos = Vector2(10, 20)
	p.troops = [{"type": "spear", "men": 30, "xp": 0.0}, {"type": "archer", "men": 20, "xp": 100.0}]
	check(p.men() == 50, "effectif %d" % p.men())
	check(p.strength() > 50.0, "force %f" % p.strength())
	check(p.display_name() == "les Écorcheurs", "nom affiché")
	p.go([Vector2(10, 30), Vector2(20, 30)] as Array[Vector2])
	check(not p.advance(5.0) and p.pos == Vector2(10, 25), "avance partielle %s" % str(p.pos))
	check(p.advance(100.0) and p.pos == Vector2(20, 30), "arrivée %s" % str(p.pos))
	p.go([Vector2(50, 30)] as Array[Vector2])
	var q := Party.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check(q != null and q.id == 7 and q.kind == "bandits" and q.men() == 50 and q.path.size() == 1 and q.pos == Vector2(20, 30), "sauvegarde aller-retour")
	check(Party.from_dict({"kind": "dragons"}) == null, "sorte inconnue acceptée")
	check(Party.from_dict("n'importe quoi") == null, "données invalides acceptées")
	for k in Party.KINDS:
		check(Party.KIND_NAMES.has(k) and Party.BASE_SPEED.has(k), "sorte %s incomplète" % k)
	if fails.is_empty():
		print("Groupes de la carte : OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : ", f)
		quit(1)
