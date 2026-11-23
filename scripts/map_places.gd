class_name MapPlaces
extends RefCounted
## Villes, villages et châteaux de la carte de campagne, dessinés selon leur taille et leur
## propriétaire (appelé par campaign_map.gd, draw_place) :
## - ville : remparts, tours et maisons ; une cité (capitale d'une faction) a une double enceinte,
##   quatre tours et une cathédrale ; bannière de la faction qui la tient (change à la conquête) ;
## - château : donjon crénelé dans une petite enceinte ; bannière du seigneur, ou les armoiries de
##   la compagnie si c'est son fief ;
## - village : trois à cinq maisons (selon le nom), parfois une église, un fanion du seigneur
##   (celui de la ville ou du château auquel il est rattaché) ;
## - siège (ville, ou fief de la compagnie) : camp de tentes aux couleurs de l'assiégeant, feux
##   et fumées.
## Les pixels sont dessinés à l'échelle 2 (une case = 2 pixels de carte), comme les figurines.

const STONE := Color(0.7, 0.68, 0.62)
const STONE_DARK := Color(0.3, 0.28, 0.26)
const WALL_LIGHT := Color(0.85, 0.78, 0.6)
const ROOF := Color(0.66, 0.24, 0.16)
const SLATE := Color(0.32, 0.36, 0.44)
const THATCH := Color(0.62, 0.48, 0.24)
const WOOD := Color(0.48, 0.32, 0.17)
const NEUTRAL := Color(0.6, 0.6, 0.6)
const SIZE_VILLAGE := 1
const SIZE_TOWN := 2
const SIZE_CITY := 3


# ---------------------------------------------------------------- Propriétaire et taille

## Faction qui tient un lieu : la ville (WorldSim), le château (Fiefs : Fiefs.PLAYER pour la
## compagnie), le village et les autres lieux suivent le lieu auquel ils sont rattachés (ville ou
## château) ; sinon leur seigneur de départ (-1 : aucun).
static func owner_of(state: CampaignState, i: int) -> int:
	if i < CampaignState.TOWNS.size():
		return state.town_owner(i)
	var pl := MapData.place(i)
	if str(pl["kind"]) == "castle":
		return state.fiefs.owner_of(i)
	var link := link_of(i)
	if link >= 0 and link != i:
		var lk := str(MapData.place(link)["kind"])
		if lk == "town":
			return state.town_owner(link)
		if lk == "castle":
			var o := state.fiefs.owner_of(link)
			return int(pl["faction"]) if o == Fiefs.PLAYER else o # Le fief ne s'étend pas aux villages
	return int(pl["faction"])


## Lieu auquel un lieu secondaire est rattaché (son chemin), -1 s'il n'y en a pas.
static func link_of(i: int) -> int:
	var k := i - CampaignState.TOWNS.size()
	if k < 0 or k >= MapData.PLACES.size():
		return -1
	return MapData.place_named(str(MapData.PLACES[k].get("link", "")))


## Taille d'un lieu habité : cité (capitale d'une faction), ville, village (et le reste).
static func size_of(i: int) -> int:
	if i >= CampaignState.TOWNS.size():
		return SIZE_VILLAGE
	for f in CampaignState.FACTIONS:
		if int(f["capital"]) == i:
			return SIZE_CITY
	return SIZE_TOWN


## Bannière d'un lieu : {"owner", "color", "arms"} ; « arms » : armoiries de la compagnie pour
## son fief, {} sinon (bannière unie à la couleur de la faction).
static func banner(state: CampaignState, i: int) -> Dictionary:
	var o := owner_of(state, i)
	if o == Fiefs.PLAYER:
		return {"owner": o, "color": Heraldry.color(state.arms, 0), "arms": state.arms}
	return {"owner": o, "color": CampaignState.FACTIONS[o]["color"] if o >= 0 else NEUTRAL, "arms": {}}


## Siège en cours au lieu : faction assiégeante, -1 sans siège (villes, et fiefs de la compagnie).
static func besieger(state: CampaignState, i: int) -> int:
	if i < CampaignState.TOWNS.size():
		if state.town_besieged(i):
			return int(state.town_siege(i).get("faction", -1))
		return -1
	var e := state.fiefs.fief(i)
	if not e.is_empty() and not (e["siege"] as Dictionary).is_empty():
		return int((e["siege"] as Dictionary).get("faction", -1))
	return -1


# ---------------------------------------------------------------- Dessin

## Bannière sur une hampe : unie, ou aux armoiries de la compagnie (fief), avec une queue.
static func draw_flag(map: Node2D, foot: Vector2, b: Dictionary, big := false) -> void:
	var h := 18.0 if big else 13.0
	var size := Vector2(14, 10) if big else Vector2(10, 7)
	var top := foot - Vector2(0, h)
	map.draw_line(foot, top, WOOD.darkened(0.2), 1.5)
	var r := Rect2(top + Vector2(1, 0), size)
	map.draw_rect(r.grow(1), Color(0.08, 0.06, 0.04, 0.9))
	var arms: Dictionary = b.get("arms", {})
	if arms.is_empty():
		var c: Color = b["color"]
		map.draw_rect(r, c)
		map.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.6), Vector2(r.size.x, r.size.y * 0.2)), c.darkened(0.35))
	else:
		Heraldry.draw(map, r, arms)
		map.draw_rect(r.grow(2), Color(1, 0.84, 0.4), false, 1.0) # Liseré d'or : le fief de la compagnie
	# Queue d'aronde
	var tail := r.position + Vector2(r.size.x, 0)
	map.draw_colored_polygon(PackedVector2Array([tail, tail + Vector2(4, r.size.y * 0.5), tail + Vector2(0, r.size.y)]), b["color"])


## Ville ou cité : enceinte, tours, maisons et clochers ; bannière de son propriétaire.
static func draw_town(map: Node2D, state: CampaignState, i: int) -> void:
	var p := MapData.place_pos(i).round()
	var city := size_of(i) == SIZE_CITY
	var roof: Color = map.snowy(ROOF)
	var slate: Color = map.snowy(SLATE)
	var b := banner(state, i)
	var tower_roof: Color = map.snowy((b["color"] as Color).darkened(0.2)) # Toits des tours aux couleurs du maître
	map.draw_set_transform(p, 0.0, Vector2(2, 2))
	var hw := 14 if city else 10 # Demi-largeur de l'enceinte (cases)
	# Ombre portée
	map.draw_rect(Rect2(-hw - 1, -1, hw * 2 + 3, 8), Color(0, 0, 0, 0.3))
	# Maisons derrière les remparts (rangée du fond), toits alternés
	var n := 6 if city else 4
	for k in n:
		var x := -hw + 2 + k * float(hw * 2 - 4) / n
		var hh := 4 + (k * 7 + i) % 3
		map.draw_rect(Rect2(x, -3 - hh, 4, hh), WALL_LIGHT.darkened(0.06 * (k % 2)))
		map.draw_rect(Rect2(x - 1, -4 - hh, 6, 2), roof if (k + i) % 3 else slate)
	# Église ou cathédrale
	if city:
		map.draw_rect(Rect2(-4, -15, 8, 12), STONE.lightened(0.08))
		map.draw_rect(Rect2(-2, -22, 4, 8), STONE.lightened(0.08))
		map.draw_colored_polygon(PackedVector2Array([Vector2(-3, -22), Vector2(0, -28), Vector2(3, -22)]), slate)
		map.draw_rect(Rect2(-1, -12, 2, 3), Color(0.35, 0.45, 0.7)) # Rosace
	else:
		map.draw_rect(Rect2(2, -13, 3, 9), STONE.lightened(0.05))
		map.draw_colored_polygon(PackedVector2Array([Vector2(1, -13), Vector2(3.5, -18), Vector2(6, -13)]), slate)
	# Rempart de façade et créneaux
	map.draw_rect(Rect2(-hw, -2, hw * 2, 7), STONE_DARK)
	map.draw_rect(Rect2(-hw + 1, -3, hw * 2 - 2, 7), STONE)
	for k in range(-hw + 1, hw - 1, 3):
		map.draw_rect(Rect2(k, -4, 2, 1), STONE)
	# Porte
	map.draw_rect(Rect2(-2, 0, 4, 4), STONE_DARK)
	map.draw_rect(Rect2(-1, 1, 2, 3), Color(0.18, 0.12, 0.08))
	# Tours d'angle (et deux de plus pour une cité)
	var towers: Array[int] = [-hw - 2, hw - 2]
	if city:
		towers.append_array([-6, 3])
	for t in towers:
		var front := t == -hw - 2 or t == hw - 2
		var top := -9 if front else -8
		map.draw_rect(Rect2(t, top, 4, 13 if front else 8), STONE.darkened(0.04))
		map.draw_rect(Rect2(t + 1, top + 3, 1, 2), STONE_DARK) # Archère
		map.draw_colored_polygon(PackedVector2Array([Vector2(t - 1, top), Vector2(t + 2, top - 4), Vector2(t + 5, top)]), tower_roof)
	if city: # Seconde enceinte, plus basse, devant
		map.draw_rect(Rect2(-hw - 3, 5, hw * 2 + 6, 2), STONE.darkened(0.12))
	map.draw_set_transform(Vector2.ZERO)
	# Bannière au sommet de la tour de gauche (et de la cathédrale pour une cité)
	draw_flag(map, p + Vector2((-hw) * 2, -26), b, city)
	if city:
		draw_flag(map, p + Vector2(0, -56), b, false)
	var siege := besieger(state, i)
	if siege >= 0:
		draw_camp(map, p, siege, hw * 2 + 14)


## Château : donjon crénelé dans une enceinte basse à deux tourelles ; bannière du seigneur, ou
## grande bannière aux armoiries de la compagnie pour son fief.
static func draw_castle(map: Node2D, state: CampaignState, i: int) -> void:
	var p := MapData.place_pos(i).round()
	var b := banner(state, i)
	var mine := int(b["owner"]) == Fiefs.PLAYER
	var stone := Color(0.62, 0.6, 0.56)
	map.draw_set_transform(p, 0.0, Vector2(2, 2))
	map.draw_rect(Rect2(-8, 0, 17, 5), Color(0, 0, 0, 0.3))
	# Enceinte basse
	map.draw_rect(Rect2(-8, -2, 16, 6), stone.darkened(0.08))
	for k in range(-8, 8, 3):
		map.draw_rect(Rect2(k, -3, 2, 1), stone.darkened(0.08))
	map.draw_rect(Rect2(-10, -5, 3, 9), stone)
	map.draw_rect(Rect2(7, -5, 3, 9), stone)
	map.draw_rect(Rect2(-11, -6, 5, 1), stone)
	map.draw_rect(Rect2(6, -6, 5, 1), stone)
	# Donjon
	map.draw_rect(Rect2(-4, -14, 8, 13), stone.lightened(0.1))
	map.draw_rect(Rect2(-4, -14, 2, 13), stone.lightened(0.18))
	for k in 3:
		map.draw_rect(Rect2(-4 + k * 3, -16, 2, 2), stone.lightened(0.1))
	map.draw_rect(Rect2(-1, -11, 2, 3), STONE_DARK)
	map.draw_rect(Rect2(-1, 1, 2, 3), Color(0.2, 0.15, 0.12)) # Porte de l'enceinte
	map.draw_set_transform(Vector2.ZERO)
	draw_flag(map, p + Vector2(0, -32), b, mine)
	var siege := besieger(state, i)
	if siege >= 0:
		draw_camp(map, p, siege, 34)


## Village : maisons (trois à cinq, selon le nom), église pour les plus gros, fanion du seigneur.
static func draw_village(map: Node2D, state: CampaignState, i: int) -> void:
	var p := MapData.place_pos(i).round()
	var name := str(MapData.place(i)["name"])
	var hv := absi(hash(name))
	var n := 3 + hv % 3
	var spots := [Vector2(-10, 0), Vector2(4, -4), Vector2(-2, 6), Vector2(9, 5), Vector2(-14, -7)]
	var roofs: Array[Color] = [THATCH, Color(0.55, 0.35, 0.2), Color(0.6, 0.3, 0.2)]
	# Champ (sillons) derrière les maisons
	var field := p + Vector2(-20 if hv % 2 else 6, 10)
	for k in 3:
		map.draw_rect(Rect2(field + Vector2(0, k * 3), Vector2(14, 1)), Color(0.55, 0.45, 0.25, 0.5))
	for k in n:
		var h: Vector2 = spots[k]
		map.draw_rect(Rect2(p + h + Vector2(0, 1), Vector2(10, 7)), Color(0, 0, 0, 0.3))
		map.draw_rect(Rect2(p + h, Vector2(9, 6)), WALL_LIGHT)
		map.draw_rect(Rect2(p + h + Vector2(-1, -3), Vector2(11, 3)), map.snowy(roofs[((hv >> 2) + k) % roofs.size()]))
		map.draw_rect(Rect2(p + h + Vector2(4, 3), Vector2(2, 3)), Color(0.3, 0.2, 0.12))
	if n == 5: # Église
		var c := p + Vector2(14, -10)
		map.draw_rect(Rect2(c, Vector2(5, 9)), STONE)
		map.draw_colored_polygon(PackedVector2Array([c + Vector2(-1, 0), c + Vector2(2.5, -6), c + Vector2(6, 0)]), map.snowy(SLATE))
	var b := banner(state, i)
	if int(b["owner"]) != -1:
		var foot := p + Vector2(-16, 6)
		map.draw_line(foot, foot - Vector2(0, 11), WOOD.darkened(0.2), 1.0)
		map.draw_colored_polygon(PackedVector2Array([foot - Vector2(0, 11), foot - Vector2(-8, 9), foot - Vector2(0, 7)]), b["color"])


## Camp d'assiégeants autour d'un lieu : tentes aux couleurs de la faction, feux et fumées.
static func draw_camp(map: Node2D, p: Vector2, faction: int, radius: float) -> void:
	var col: Color = CampaignState.FACTIONS[faction]["color"] if faction >= 0 else NEUTRAL
	var t := Time.get_ticks_msec() / 1000.0
	var canvas := Color(0.9, 0.86, 0.74)
	# Tentes sur les deux flancs (le nom du lieu reste lisible dessous)
	for k in 8:
		var side := 1.0 if k % 2 == 0 else -1.0
		var a := (-0.12 + floori(k / 2.0) * 0.16) * PI
		var at := (p + Vector2(side * cos(a) * radius * 1.45, sin(a) * radius * 0.9)).round()
		map.draw_colored_polygon(PackedVector2Array([at + Vector2(-8, 5), at + Vector2(0, -8), at + Vector2(8, 5)]), canvas)
		map.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 5), at + Vector2(0, -8), at + Vector2(3, 5)]), col)
		map.draw_rect(Rect2(at + Vector2(-1, 1), Vector2(2, 4)), Color(0.15, 0.1, 0.06))
		map.draw_line(at + Vector2(0, -8), at + Vector2(0, -13), WOOD, 1.0)
		map.draw_rect(Rect2(at + Vector2(0, -13), Vector2(4, 3)), col)
	for k in 2:
		var fire := (p + Vector2((k * 2 - 1) * radius * 1.15, radius * 0.2)).round()
		map.draw_rect(Rect2(fire + Vector2(-2, 0), Vector2(4, 2)), WOOD)
		map.draw_rect(Rect2(fire + Vector2(-1, -2), Vector2(2, 2)), Color(1, 0.55 + 0.2 * sin(t * 9.0 + k), 0.1))
		for s in 3:
			var rise := fposmod(t * 8.0 + s * 9.0 + k * 4.0, 26.0)
			var puff := fire + Vector2(sin(t + s) * 2.0 + rise * 0.3, -4 - rise)
			map.draw_circle(puff, 2.0 + rise * 0.12, Color(0.3, 0.28, 0.26, 0.55 * (1.0 - rise / 26.0)))
