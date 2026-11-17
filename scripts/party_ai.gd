class_name PartyAI
extends RefCounted
## Comportements des groupes de la carte en temps réel (point d'accroche) : Overworld.step appelle
## think(c, ow, party, heures) pour chaque groupe (sauf la compagnie et les armées de faction, que
## le monde vivant mène). think choisit d'après party.kind ; party.state garde ce que fait le
## groupe (« idle », « travel », « rest », « chase »...), party.busy_hours le temps qu'il reste sur
## place. Pour un nouveau comportement : écrire think_<sorte>(c, ow, p, hours) et l'ajouter au match.
##
## Par défaut, un groupe erre de lieu en lieu (wander) ; les bandits poursuivent la compagnie
## quand elle passe à portée de vue.


static func think(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	match p.kind:
		"bandits":
			think_bandits(c, ow, p, hours)
		_:
			wander(c, ow, p, hours)


## Errer : aller à un lieu, s'y reposer quelques heures, repartir vers un autre.
## Villageois : autour de leur village ; caravanes : de ville en ville ; autres : n'importe où.
static func wander(c: CampaignState, ow: Overworld, p: Party, _hours: float) -> void:
	if p.busy_hours > 0.0 or not p.path.is_empty():
		return
	if p.state == "travel" or p.state == "chase":
		p.state = "rest"
		p.busy_hours = ow.rng.randf_range(4.0, 12.0)
		return
	var goal := pick_goal(c, ow, p)
	if goal < 0:
		p.busy_hours = 6.0
		return
	p.goal = goal
	p.go(MapData.find_path(p.pos, MapData.place_pos(goal)))
	p.state = "travel"


## Lieu où un groupe errant se rend (-1 : aucun).
static func pick_goal(_c: CampaignState, ow: Overworld, p: Party) -> int:
	var pool: Array[int] = []
	var from := p.pos if p.home < 0 else MapData.place_pos(p.home)
	for pl in MapData.places():
		var i := int(pl["id"])
		if MapData.place_pos(i).distance_to(p.pos) < MapData.PLACE_RADIUS:
			continue # Pas le lieu où il est déjà
		match p.kind:
			"caravan":
				if pl["kind"] != "town":
					continue
			"villagers":
				if MapData.place_pos(i).distance_to(from) > 900.0:
					continue
			"bandits":
				if MapData.place_pos(i).distance_to(from) > 700.0:
					continue
		pool.append(i)
	return -1 if pool.is_empty() else pool[ow.rng.randi() % pool.size()]


## Bandits : ils fondent sur la compagnie quand elle passe à portée de vue (hors des murs) et
## qu'ils ne sont pas trop faibles ; sinon ils errent autour de leur repaire.
static func think_bandits(c: CampaignState, ow: Overworld, p: Party, hours: float) -> void:
	var prey := ow.player
	var sees := ow.inside < 0 and not ow.cooldown.has(str(p.id)) and p.pos.distance_to(prey.pos) < Overworld.SIGHT \
		and p.strength() >= c.total_men() * 0.4 and not c.is_destroyed()
	if sees:
		p.state = "chase"
		p.busy_hours = 0.0
		if p.path.is_empty() or p.path[-1].distance_to(prey.pos) > Overworld.REPATH_DIST * 0.5:
			p.go(MapData.find_path(p.pos, prey.pos))
		return
	if p.state == "chase":
		p.path.clear() # Proie perdue de vue : retour à l'errance
		p.state = "idle"
	wander(c, ow, p, hours)
