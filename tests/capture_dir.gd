extends RefCounted
## Dossier de sortie des scripts de capture (menu_capture, terrain_shots, report_capture).
## Option après « -- » : --out=<dossier>. Par défaut user://captures (hors du dépôt).
## Un chemin relatif est pris depuis la racine du projet : --out=captures met à jour les captures
## versionnées du dépôt.

const DEFAULT := "user://captures"


## Dossier de sortie absolu (créé au besoin).
static func resolve() -> String:
	var out := DEFAULT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var path: String
	if out.begins_with("user://") or out.begins_with("res://"):
		path = ProjectSettings.globalize_path(out)
	elif out.is_absolute_path():
		path = out
	else:
		path = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(path)
	return path


## Enregistre l'image de la fenêtre dans le dossier de sortie.
static func save(tree: SceneTree, file: String) -> void:
	var path := resolve().path_join(file)
	tree.root.get_texture().get_image().save_png(path)
	print("Capture : ", path)
