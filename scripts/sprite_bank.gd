class_name SpriteBank
extends RefCounted
## Sprites pixel art « MiniWorld Sprites » de Shade (CC0, voir CREDITS.md).
## Si un fichier manque, has_unit() / has_trees() renvoient false et le jeu
## revient au dessin en code.

const DOWN := 0
const UP := 1
const RIGHT := 2
const LEFT := 3

const UNIT_DIR := "res://assets/sprites/units/"
const TEAM_SUFFIX := ["Cyan", "Red"] ## Joueur, ennemi

## Description des planches. Lignes indexées par direction [bas, haut, droite, gauche].
## « idle » absent = première image de la marche.
const UNITS := {
	"men_at_arms": {
		"file": "Swordsman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 6, 7], "attack_n": 4,
	},
	"spear": {
		"file": "Spearman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [], "attack_n": 0, # Planche d'attaque irrégulière : on fait une fente en code
	},
	"archer": {
		"file": "Bowman%s.png", "cell": 16, "foot": Vector2(8, 15),
		"walk": [0, 1, 2, 3], "walk_n": 5,
		"attack": [4, 5, 7, 6], "attack_n": 3,
	},
	"cavalry": {
		"file": "%sKnight.png", "cell": 32, "foot": Vector2(16, 25),
		"walk": [1, 10, 4, 7], "walk_n": 4,
		"idle": [0, 9, 3, 6],
		"attack": [2, 11, 5, 8], "attack_n": 4,
	},
}

var unit_tex := {} ## "type/équipe" -> Texture2D
var trees: Array[Dictionary] = [] ## {"tex", "src"} pour chaque variante d'arbre
var grass_tiles: Array[Texture2D] = []
var ok := false ## Vrai si toutes les unités sont disponibles


func _init() -> void:
	var all := true
	for type in UNITS:
		var file: String = UNITS[type]["file"]
		for team in 2:
			var path := UNIT_DIR + (file % TEAM_SUFFIX[team])
			var t := _load(path)
			if t != null:
				unit_tex["%s/%d" % [type, team]] = t
			else:
				all = false
	ok = all

	# Arbres : Trees.png (cases 1 à 3) et PineTrees.png (case 1) ;
	# la case 0 est une souche et le pin de la case 2 est enneigé.
	var leafy := _load("res://assets/sprites/nature/Trees.png")
	if leafy != null:
		for i in [1, 2, 3, 3]:
			trees.append({"tex": leafy, "src": Rect2(i * 16, 0, 16, 16)})
	var pine := _load("res://assets/sprites/nature/PineTrees.png")
	if pine != null:
		trees.append({"tex": pine, "src": Rect2(16, 0, 16, 16)})


func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Sprite manquant, dessin en code utilisé : " + path)
		return null
	return load(path) as Texture2D


func has_unit(type: String, team: int) -> bool:
	return unit_tex.has("%s/%d" % [type, team])


func has_trees() -> bool:
	return not trees.is_empty()


## Direction de la planche la plus proche d'un vecteur.
static func dir_of(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return RIGHT if v.x > 0.0 else LEFT
	return DOWN if v.y > 0.0 else UP


## Image à afficher : {"tex", "src" (zone de la planche), "foot" (point des pieds)}.
## anim : "idle", "walk" ou "attack" ; t : temps d'animation (images) ou progression (0..1) pour l'attaque.
func frame(type: String, team: int, dir: int, anim: String, t: float) -> Dictionary:
	var d: Dictionary = UNITS[type]
	var cell: int = d["cell"]
	var row: int
	var col := 0
	match anim:
		"attack":
			var n: int = d["attack_n"]
			if n > 0:
				row = d["attack"][dir]
				col = clampi(int(t * n), 0, n - 1)
			else:
				row = d["walk"][dir]
		"walk":
			row = d["walk"][dir]
			col = int(t) % int(d["walk_n"])
		_:
			if d.has("idle"):
				row = d["idle"][dir]
			else:
				row = d["walk"][dir]
	return {
		"tex": unit_tex["%s/%d" % [type, team]],
		"src": Rect2(col * cell, row * cell, cell, cell),
		"foot": d["foot"],
	}


## Variante d'arbre stable pour une position donnée.
func tree_at(p: Vector2) -> Dictionary:
	var h := absi(int(p.x) * 73856093 ^ int(p.y) * 19349663)
	return trees[h % trees.size()]
