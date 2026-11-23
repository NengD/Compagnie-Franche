class_name Regiment
extends RefCounted
## Un régiment : un groupe de soldats du même type qui reçoit des ordres ensemble.

enum Formation { LINE, COLUMN, SQUARE }
const FORMATION_NAMES := ["ligne", "colonne", "carré"]

var id := 0
var company_index := -1 ## Indice dans l'armée de campagne (-1 hors campagne)
var team := 0 ## 0 = joueur, 1 = ennemi
var allied := false ## Régiment allié (camp du joueur, mené par AlliedAI, pas commandable)
var ally_group := -1 ## Groupe allié de la carte (indice dans BattleSim.allies), -1 sinon
var type := ""
var stats: Dictionary = {}
var soldiers: Array = []
var alive_n := 0
var cols_override := 0 ## Largeur du front choisie par le joueur (0 = valeur par défaut du type)
var formation: Formation = Formation.LINE
var running := false ## Ordre de course en cours (double clic droit)
var stamina := 1.0 ## Endurance : 1 = frais, 0 = épuisé

var dest := Vector2.ZERO ## Point visé par la formation
var facing := Vector2.UP ## Direction du front
var center := Vector2.ZERO
var target: Regiment = null ## Ordre d'attaque
var fire_target: Regiment = null ## Cible des archers

var morale := 100.0
var max_morale := 100.0
var routing := false
var rallied_once := false
var selected := false
var engaged := false
var engaged_flag := false
var holding := false ## Archers : à portée de leur cible, ils s'arrêtent pour tirer
var hold_position := false ## Ordre « tenir la position » (G) : ne poursuit pas, ne s'engage pas seul
var fire_at_will := true ## Archers : tir à volonté (X) ; sinon, tir seulement sur une cible ordonnée
var think := 0.0
var flank_time := 0.0
var evading := 0.0 ## Tirailleurs montés : temps restant du décrochage en cours (voir BattleSim.update_skirmish)

var in_forest := false
var hidden := false ## Caché à l'ennemi (en forêt, non repéré)
var revealed := 0.0
var fog_alpha := 1.0 ## Brouillard : netteté vue du camp adverse (1 : net, 0 : invisible), voir battle_weather.gd
var fogged := false ## Brouillard : trop loin pour que l'adversaire le voie

## Usure et relève (voir BattleSim.relieve / fall_back)
var contact_time := 0.0 ## Secondes de mêlée récentes : plus elles s'accumulent, plus le régiment s'use vite
var relief := 0.0 ## Décrochage en cours (relève ou repli) : les soldats ne cherchent plus le contact
var rest_until := -1.0 ## Repos après une relève, jusqu'à ce temps de bataille (l'IA le laisse souffler)

## Rang d'expérience : 0 = recrues, 1 = aguerris, 2 = vétérans
const RANK_NAMES := ["recrues", "aguerris", "vétérans"]
const RANK_DAMAGE := 0.10 ## Bonus de dégâts par rang
const RANK_MORALE := 0.15 ## Bonus de moral maximal par rang
var rank := 0
var kills := 0 ## Ennemis tués pendant la bataille (mêlée et flèches)
var morale_mult := 1.0 ## Difficulté : multiplicateur du moral maximal (régiments ennemis)
var damage_mult := 1.0 ## Difficulté : multiplicateur des dégâts (régiments ennemis)
var gear: Array = [] ## Équipement porté (identifiants d'Equipment.ITEMS) : se voit sur les soldats (battle_renderer.gd)
var drill_mult := 1.0 ## Vitesse en colonne et en carré (capitaine tacticien, voir captain.gd)
var officer: Dictionary = {} ## Compagnon officier à la tête du régiment (voir officers.gd), vide sinon
var officer_fate := "" ## L'officier est tombé pendant la bataille : "dead" ou "wounded"
var officer_seen := 0 ## Hommes debout au dernier contrôle de l'officier
var speed_mult := 1.0 ## Objectif : multiplicateur de vitesse (bande chargée de butin, voir battle_objectives.gd)


## Fixe le rang d'expérience : le moral maximal monte avec le rang.
func set_rank(k: int) -> void:
	rank = clampi(k, 0, RANK_NAMES.size() - 1)
	max_morale = float(stats["morale"]) * (1.0 + RANK_MORALE * rank) * morale_mult
	morale = max_morale


## Multiplicateur de dégâts dû à l'expérience (et à la difficulté).
func rank_damage() -> float:
	return (1.0 + RANK_DAMAGE * rank) * damage_mult


## Qualité de la pièce slot (« helmet », « weapon », « armor ») portée par le régiment (0 : aucune).
func gear_tier(slot: String) -> int:
	for id in gear:
		if Equipment.ITEMS.has(id) and Equipment.ITEMS[id]["slot"] == slot:
			return int(Equipment.ITEMS[id]["tier"])
	return 0


func is_dead() -> bool:
	return alive_n <= 0


func update_center() -> void:
	var sum := Vector2.ZERO
	var n := 0
	for s in soldiers:
		if s.alive:
			sum += s.pos
			n += 1
	alive_n = n
	if n > 0:
		center = sum / n


func alive_soldiers() -> Array:
	var out := []
	for s in soldiers:
		if s.alive:
			out.append(s)
	return out


func columns(n: int) -> int:
	var c: int
	match formation:
		Formation.COLUMN:
			c = UnitTypes.COLUMN_WIDTH
		Formation.SQUARE:
			c = square_side(n)
		_:
			c = cols_override if cols_override > 0 else int(stats["cols"])
	return mini(c, maxi(n, 1))


## Nombre de soldats par côté d'un carré creux de n soldats (4 x (côté - 1) places sur le pourtour).
static func square_side(n: int) -> int:
	return maxi(2, ceili(n / 4.0) + 1)


## Nombre de rangs de la formation (profondeur), pour n soldats.
func depth_rows(n: int) -> int:
	if formation == Formation.SQUARE:
		return square_side(n)
	return ceili(float(maxi(n, 1)) / float(columns(n)))


## Formation suivante pour la touche F : ligne → colonne → carré → ligne.
func next_formation() -> Formation:
	return ((int(formation) + 1) % 3) as Formation


func formation_name() -> String:
	return FORMATION_NAMES[formation]


## Front le plus étroit autorisé : 6 rangs de profondeur au maximum.
func min_columns() -> int:
	return maxi(2, ceili(maxi(alive_n, 1) / 6.0))


## Front le plus large autorisé : un seul rang.
func max_columns() -> int:
	return maxi(min_columns(), alive_n)


func width() -> float:
	var sp: float = stats["spacing"]
	return columns(maxi(alive_n, 1)) * sp


func slot_position(i: int, n: int) -> Vector2:
	if formation == Formation.SQUARE:
		return square_slot(i, n, dest, facing)
	return formation_slot(i, n, columns(n), dest, facing)


## Place du soldat i dans un carré creux : les soldats sont répartis régulièrement sur le pourtour,
## en partant du coin avant gauche.
func square_slot(i: int, n: int, at: Vector2, face: Vector2) -> Vector2:
	var side := square_side(n)
	var sp: float = stats["spacing"]
	var half := (side - 1) * 0.5
	var perimeter := 4 * (side - 1)
	# Places réparties sur tout le pourtour même si le carré n'est pas plein
	var k := floori(float(i) * perimeter / float(maxi(n, 1)))
	@warning_ignore("integer_division")
	var edge := k / (side - 1)
	var t := k % (side - 1)
	var local: Vector2
	match edge:
		0: local = Vector2(-half + t, -half) # Face avant
		1: local = Vector2(half, -half + t) # Flanc droit
		2: local = Vector2(half - t, half) # Arrière
		_: local = Vector2(-half, half - t) # Flanc gauche
	var right := Vector2(-face.y, face.x)
	# local.y < 0 = vers l'avant
	return at + (right * local.x - face * local.y) * sp


## Place du soldat i (sur n) pour une formation donnée, sans modifier le régiment.
## Sert aussi à l'aperçu fantôme pendant le tracé d'une ligne.
func formation_slot(i: int, n: int, cols: int, at: Vector2, face: Vector2) -> Vector2:
	cols = clampi(cols, 1, maxi(n, 1))
	var sp: float = stats["spacing"]
	var rows := int(ceil(float(n) / float(cols)))
	var col := i % cols
	@warning_ignore("integer_division")
	var row := i / cols
	var in_row := cols
	if row == rows - 1 and n % cols != 0:
		in_row = n % cols
	var right := Vector2(-face.y, face.x)
	var off := right * (col - (in_row - 1) * 0.5) * sp - face * (row - (rows - 1) * 0.5) * sp
	return at + off


## État de fatigue affiché sur la carte du régiment.
func stamina_label() -> String:
	if stamina >= UnitTypes.STAMINA_TIRED:
		return "frais"
	if stamina >= UnitTypes.STAMINA_TIRED * 0.4:
		return "fatigués"
	return "épuisés"


## Vrai pendant le repos qui suit une relève ou un repli.
func is_resting(battle_time: float) -> bool:
	return relief > 0.0 or battle_time < rest_until


func display_name() -> String:
	return str(stats["name"])
