class_name BattleCamera
extends Camera2D
## Caméra de la bataille : défilement au clavier (touches de caméra des Options, ZQSD en AZERTY
## par position physique, et flèches), zoom à la molette vers le curseur, glisser au clic du
## milieu, cadrage sur une sélection, bornes du champ de bataille et secousse (charges de cavalerie).
## Les évènements souris arrivent par battle_orders.gd ; le clavier est lu à chaque image.
##
## Zoom : view_zoom est le zoom voulu par le joueur (1 = taille normale du terrain), indépendant
## de la taille de l'interface (GameOptions.ui_scale agrandit toute la fenêtre : on le compense).
## Le zoom réel est arrondi pour qu'un pixel du monde fasse un nombre entier de pixels de l'écran
## (ou 1/2, 1/3 en vue lointaine) : tous les pixels des sprites gardent la même largeur.

const WORLD_SIZE := BattleSim.WORLD_SIZE
const SCROLL_SPEED := 450.0 ## Défilement au clavier (pixels écran par seconde)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const SHAKE_MAX_PX := 7.0 ## Amplitude maximale de la secousse (pixels écran)
const SHAKE_DECAY := 2.2 ## Perte d'intensité de la secousse par seconde
## Échelles permises (pixels de l'écran par pixel du monde).
const SCREEN_LEVELS: Array[float] = [0.25, 1.0 / 3.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]

var shake := 0.0 ## Intensité de la secousse (0 à 1), décroît avec le temps
var shake_enabled := true ## Désactivée sans fenêtre (tests)
var view_zoom := 1.0 ## Zoom voulu (sans la taille de l'interface), entre ZOOM_MIN et ZOOM_MAX
var last_scale := -1.0 ## Échelle de la fenêtre au dernier calcul du zoom


func _init() -> void:
	zoom = Vector2(1, 1)
	position = Vector2(WORLD_SIZE.x * 0.5, 1560)
	shake_enabled = DisplayServer.get_name() != "headless"


func _ready() -> void:
	apply_zoom()


## Pixels de la fenêtre par unité du canevas (étirement de la fenêtre × taille de l'interface).
## Sans affichage (tests), on suppose une fenêtre de la taille de base (1280×720).
func window_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return maxf(GameOptions.ui_scale, 0.01)
	var k := get_tree().root.get_stretch_transform().get_scale().x
	return k if k > 0.0 else maxf(GameOptions.ui_scale, 0.01)


## Échelle d'écran permise la plus proche de e (en rapport, pas en écart).
static func snap_screen_scale(e: float) -> float:
	var best := SCREEN_LEVELS[0]
	for l in SCREEN_LEVELS:
		if absf(log(l / e)) < absf(log(best / e)):
			best = l
	return best


## Échelles d'écran utilisables pour la fenêtre actuelle (bornes ZOOM_MIN / ZOOM_MAX).
func allowed_levels() -> Array[float]:
	var base := window_scale() / maxf(GameOptions.ui_scale, 0.01) # Étirement seul
	var out: Array[float] = []
	for l in SCREEN_LEVELS:
		if l >= ZOOM_MIN * base * 0.99 and l <= ZOOM_MAX * base * 1.01:
			out.append(l)
	if out.is_empty():
		out.append(snap_screen_scale(base))
	return out


## Pose le zoom réel d'après view_zoom : taille de l'interface compensée, pixels entiers.
func apply_zoom() -> void:
	var s := window_scale()
	last_scale = s
	var base := s / maxf(GameOptions.ui_scale, 0.01)
	var levels := allowed_levels()
	var want := view_zoom * base
	var best := levels[0]
	for l in levels:
		if absf(log(l / want)) < absf(log(best / want)):
			best = l
	zoom = Vector2.ONE * (best / s)


## Pixels de l'écran par pixel du monde (vérifié par les tests : entier ou 1/n).
func screen_scale() -> float:
	return zoom.x * window_scale()


## Une image : défilement au clavier, bornes, puis secousse.
func update_view(delta: float) -> void:
	if not is_equal_approx(window_scale(), last_scale):
		apply_zoom() # Fenêtre redimensionnée, plein écran ou taille de l'interface changée
	var v := Vector2.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if GameOptions.camera_pressed("cam_up") or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if GameOptions.camera_pressed("cam_down") or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
		if GameOptions.camera_pressed("cam_left") or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if GameOptions.camera_pressed("cam_right") or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
	position += v * SCROLL_SPEED * delta / zoom.x
	clamp_to_world()
	# Secousse : décalage aléatoire (sans toucher à la position) qui s'éteint en une fraction de seconde
	shake = maxf(shake - delta * SHAKE_DECAY, 0.0)
	if shake > 0.0:
		var amp := shake * shake * SHAKE_MAX_PX / zoom.x
		offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round()
	else:
		offset = Vector2.ZERO


## Garde la vue dans le champ de bataille (centrée si le champ est plus petit que l'écran).
func clamp_to_world() -> void:
	var half := get_viewport_rect().size / zoom * 0.5
	var p := position
	if half.x * 2.0 >= WORLD_SIZE.x:
		p.x = WORLD_SIZE.x * 0.5
	else:
		p.x = clampf(p.x, half.x, WORLD_SIZE.x - half.x)
	if half.y * 2.0 >= WORLD_SIZE.y:
		p.y = WORLD_SIZE.y * 0.5
	else:
		p.y = clampf(p.y, half.y, WORLD_SIZE.y - half.y)
	position = p


## Zoom (molette) en gardant fixe le point du monde sous le curseur : passe à l'échelle
## permise suivante (factor > 1 : plus près, < 1 : plus loin).
func zoom_at(factor: float) -> void:
	var vs := get_viewport_rect().size
	var m := get_viewport().get_mouse_position() - vs * 0.5
	var world := position + m / zoom
	var s := window_scale()
	var base := s / maxf(GameOptions.ui_scale, 0.01)
	var cur := screen_scale()
	var levels := allowed_levels()
	var next := cur
	if factor > 1.0:
		for l in levels:
			if l > cur * 1.01:
				next = l
				break
	else:
		for i in range(levels.size() - 1, -1, -1):
			if levels[i] < cur * 0.99:
				next = levels[i]
				break
	view_zoom = clampf(next / base, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2.ONE * (next / s)
	last_scale = s
	position = world - m / zoom
	clamp_to_world()


## Glisser la vue (clic du milieu) : relative en pixels écran.
func pan(relative: Vector2) -> void:
	position -= relative / zoom


## Centre la vue sur le milieu des régiments donnés.
func center_on(list: Array[Regiment]) -> void:
	if list.is_empty():
		return
	var c := Vector2.ZERO
	for r in list:
		c += r.center
	position = c / list.size()
	clamp_to_world()


## Secousse autour d'un point du monde, atténuée par la distance au centre de l'écran.
func add_shake(world_pos: Vector2, amount: float) -> void:
	if not shake_enabled:
		return
	var half := get_viewport_rect().size / zoom * 0.5
	var d := (world_pos - position).abs() / half.max(Vector2(1, 1))
	var k := maxf(d.x, d.y) # 1 = bord de l'écran
	var att := clampf(1.25 - k * 0.5, 0.0, 1.0) # Plein à l'écran, nul à 2,5 demi-écrans
	att *= clampf(zoom.x, 0.5, 1.5) / 1.5 # Vue lointaine : moins de secousse
	shake = minf(shake + amount * att, 1.0)
