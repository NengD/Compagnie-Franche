class_name BattleCamera
extends Camera2D
## Caméra de la bataille : défilement au clavier (ZQSD par touches physiques, flèches),
## zoom à la molette vers le curseur, glisser au clic du milieu, cadrage sur une sélection,
## bornes du champ de bataille et secousse (charges de cavalerie).
## Les évènements souris arrivent par battle_orders.gd ; le clavier est lu à chaque image.

const WORLD_SIZE := BattleSim.WORLD_SIZE
const SCROLL_SPEED := 450.0 ## Défilement au clavier (pixels écran par seconde)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const SHAKE_MAX_PX := 7.0 ## Amplitude maximale de la secousse (pixels écran)
const SHAKE_DECAY := 2.2 ## Perte d'intensité de la secousse par seconde

var shake := 0.0 ## Intensité de la secousse (0 à 1), décroît avec le temps
var shake_enabled := true ## Désactivée sans fenêtre (tests)


func _init() -> void:
	zoom = Vector2(1, 1)
	position = Vector2(WORLD_SIZE.x * 0.5, 1560)
	shake_enabled = DisplayServer.get_name() != "headless"


## Une image : défilement au clavier, bornes, puis secousse.
func update_view(delta: float) -> void:
	var v := Vector2.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
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


## Zoom (molette) en gardant fixe le point du monde sous le curseur.
func zoom_at(factor: float) -> void:
	var vs := get_viewport_rect().size
	var m := get_viewport().get_mouse_position() - vs * 0.5
	var world := position + m / zoom
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
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
