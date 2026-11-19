class_name Heraldry
extends RefCounted
## Armoiries de la compagnie : un dictionnaire simple {"field", "charge", "colors"}, tiré au sort
## au départ d'une campagne et sauvegardé (CampaignState.arms).
## - field : partition de l'écu (FIELDS) ;
## - charge : meuble posé dessus (CHARGES) ;
## - colors : [émail du champ, émail de la partition, émail du meuble], noms de TINCTURES.
## Règle des émaux : le meuble (métal) tranche toujours sur le champ (couleur), et inversement.
##
## draw() peint les armoiries dans un rectangle de « pixels » (bannières de bataille) : la carte
## de campagne peut s'en servir telle quelle.

const FIELDS := ["plain", "per_pale", "per_fess", "quarterly", "bend", "chevron"]
const CHARGES := ["none", "cross", "saltire", "roundel", "star", "crescent", "tower"]
const FIELD_NAMES := {"plain": "plein", "per_pale": "parti", "per_fess": "coupé", "quarterly": "écartelé", "bend": "à la bande", "chevron": "au chevron"}
const CHARGE_NAMES := {"none": "", "cross": "une croix", "saltire": "un sautoir", "roundel": "un besant", "star": "une étoile", "crescent": "un croissant", "tower": "une tour"}

const METALS := ["or", "argent"]
const COLOURS := ["gueules", "azur", "sinople", "sable", "pourpre"]
const TINCTURES := {
	"or": Color(0.95, 0.78, 0.25),
	"argent": Color(0.93, 0.93, 0.9),
	"gueules": Color(0.75, 0.13, 0.12),
	"azur": Color(0.16, 0.32, 0.78),
	"sinople": Color(0.16, 0.5, 0.24),
	"sable": Color(0.13, 0.12, 0.12),
	"pourpre": Color(0.5, 0.2, 0.5),
}
## Armoiries par défaut (escarmouche, sans campagne) : de sable à la tour d'or.
const DEFAULT := {"field": "plain", "charge": "tower", "colors": ["sable", "sable", "or"]}


## Armoiries tirées au sort (graine fixe = mêmes armoiries). Générateur à part : le hasard de la
## campagne n'est pas tiré, les parties à graine fixe restent identiques.
static func random(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x41524D53 # « ARMS »
	var field: String = FIELDS[rng.randi() % FIELDS.size()]
	var charge: String = CHARGES[1 + rng.randi() % (CHARGES.size() - 1)]
	var metal: String = METALS[rng.randi() % METALS.size()]
	var colour: String = COLOURS[rng.randi() % COLOURS.size()]
	var colour2: String = COLOURS[rng.randi() % COLOURS.size()]
	# Champ de couleur, partition de métal, meuble de métal sur la couleur (ou l'inverse une fois sur deux)
	var colors := [colour, metal, metal] if rng.randf() < 0.5 else [metal, colour, colour]
	if field == "plain":
		colors[1] = colors[0]
		if colors[0] in COLOURS:
			colors[2] = METALS[rng.randi() % METALS.size()]
		else:
			colors[2] = colour2
	return {"field": field, "charge": charge, "colors": colors}


## Relit des armoiries sauvegardées ; invalides ou absentes : celles tirées de la graine.
static func read(saved: Variant, seed_value: int) -> Dictionary:
	if not saved is Dictionary:
		return random(seed_value)
	var d: Dictionary = saved
	var field := str(d.get("field", ""))
	var charge := str(d.get("charge", ""))
	var cols: Variant = d.get("colors", [])
	if not field in FIELDS or not charge in CHARGES or not cols is Array or (cols as Array).size() != 3:
		return random(seed_value)
	var out: Array = []
	for c in cols:
		if not TINCTURES.has(str(c)):
			return random(seed_value)
		out.append(str(c))
	return {"field": field, "charge": charge, "colors": out}


static func color(arms: Dictionary, i: int) -> Color:
	var cols: Array = arms.get("colors", DEFAULT["colors"])
	return TINCTURES.get(str(cols[clampi(i, 0, cols.size() - 1)]), Color.WHITE)


## Blasonnement court : « parti d'azur et d'or, à une étoile d'argent ».
static func blazon(arms: Dictionary) -> String:
	var cols: Array = arms.get("colors", DEFAULT["colors"])
	var field := str(arms.get("field", "plain"))
	var text: String
	if field == "plain":
		text = "de %s" % cols[0]
	elif field in ["bend", "chevron"]:
		text = "de %s %s de %s" % [cols[0], FIELD_NAMES[field], cols[1]]
	else:
		text = "%s de %s et de %s" % [FIELD_NAMES[field], cols[0], cols[1]]
	var charge := str(arms.get("charge", "none"))
	if charge != "none":
		text += ", à %s de %s" % [CHARGE_NAMES[charge], cols[2]]
	return text


## Peint les armoiries dans r (coordonnées du repère courant ; r de 7×5 au moins conseillé).
## Les traits font une unité du repère (« pixel ») : à agrandir avec draw_set_transform.
static func draw(c: CanvasItem, r: Rect2, arms: Dictionary, alpha := 1.0) -> void:
	var a := Color(color(arms, 0), alpha)
	var b := Color(color(arms, 1), alpha)
	var m := Color(color(arms, 2), alpha)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	c.draw_rect(r, a)
	var hw := floorf(w * 0.5)
	var hh := floorf(h * 0.5)
	match str(arms.get("field", "plain")):
		"per_pale":
			c.draw_rect(Rect2(x + hw, y, w - hw, h), b)
		"per_fess":
			c.draw_rect(Rect2(x, y + hh, w, h - hh), b)
		"quarterly":
			c.draw_rect(Rect2(x + hw, y, w - hw, hh), b)
			c.draw_rect(Rect2(x, y + hh, hw, h - hh), b)
		"bend":
			for i in int(w):
				var yy := floorf(i * h / w)
				c.draw_rect(Rect2(x + i, y + yy, 1, 1), b)
				if yy + 1 < h:
					c.draw_rect(Rect2(x + i, y + yy + 1, 1, 1), b)
		"chevron":
			for i in int(w):
				# Pointe en haut au centre, branches qui descendent vers les bords
				var d := minf(i, w - 1 - i)
				var yy := roundf((h - 2) - d * (h - 2) / maxf((w - 1) * 0.5, 1.0))
				c.draw_rect(Rect2(x + i, y + clampf(yy, 0, h - 2), 1, 2), b)
	# Meuble au centre (3×3)
	var cx := x + floorf((w - 3) * 0.5)
	var cy := y + floorf((h - 3) * 0.5)
	match str(arms.get("charge", "none")):
		"cross":
			c.draw_rect(Rect2(cx + 1, cy, 1, 3), m)
			c.draw_rect(Rect2(cx, cy + 1, 3, 1), m)
		"saltire":
			for i in 3:
				c.draw_rect(Rect2(cx + i, cy + i, 1, 1), m)
				c.draw_rect(Rect2(cx + 2 - i, cy + i, 1, 1), m)
		"roundel":
			c.draw_rect(Rect2(cx + 0.5, cy, 2, 3), m)
			c.draw_rect(Rect2(cx, cy + 0.5, 3, 2), m)
		"star":
			c.draw_rect(Rect2(cx + 1, cy, 1, 3), m)
			c.draw_rect(Rect2(cx, cy + 1, 3, 1), m)
			c.draw_rect(Rect2(cx, cy, 0.6, 0.6), m)
			c.draw_rect(Rect2(cx + 2.4, cy, 0.6, 0.6), m)
			c.draw_rect(Rect2(cx, cy + 2.4, 0.6, 0.6), m)
			c.draw_rect(Rect2(cx + 2.4, cy + 2.4, 0.6, 0.6), m)
		"crescent":
			c.draw_rect(Rect2(cx, cy, 1, 2), m)
			c.draw_rect(Rect2(cx + 2, cy, 1, 2), m)
			c.draw_rect(Rect2(cx, cy + 2, 3, 1), m)
		"tower":
			c.draw_rect(Rect2(cx, cy + 1, 3, 2), m)
			c.draw_rect(Rect2(cx, cy, 1, 1), m)
			c.draw_rect(Rect2(cx + 2, cy, 1, 1), m)
