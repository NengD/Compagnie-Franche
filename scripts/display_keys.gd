class_name DisplayShortcuts
extends Node
## Raccourcis d'affichage valables partout (menu, carte, bataille, tutoriel) :
## Alt+Entrée et F11 basculent le plein écran. Chargé en autoload (project.godot).
## Taille minimale de la fenêtre pour que les menus restent lisibles.

## Émis après une bascule par le clavier (les pages d'options mettent leur case à jour).
signal fullscreen_toggled(on: bool)

const MIN_WINDOW := Vector2i(800, 450)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Marche aussi quand l'arbre est en pause
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(MIN_WINDOW)


## _input passe avant l'interface : Alt+Entrée n'active donc pas le bouton qui a le focus,
## et ne déclenche pas la fin de bataille (Entrée).
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if is_toggle_event(k):
		get_viewport().set_input_as_handled()
		GameOptions.toggle_fullscreen()
		fullscreen_toggled.emit(GameOptions.fullscreen)


static func is_toggle_event(k: InputEventKey) -> bool:
	if k.keycode == KEY_F11:
		return true
	return k.alt_pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)
