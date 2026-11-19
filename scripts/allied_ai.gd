class_name AlliedAI
extends EnemyAI
## IA des alliés : les régiments d'un groupe ami de la carte (patrouille, armée) qui se battent
## aux côtés de la compagnie (BattleSim.spawn_allies). Ils sont du camp du joueur (team 0) mais
## marqués « allied » : le joueur ne les commande pas, cette IA les mène droit sur l'ennemi
## (plan agressif, sans souci de l'objectif du contrat).


func _init() -> void:
	team = BattleSim.PLAYER
	plan_override = AGGRESSIVE


func controls(r: Regiment) -> bool:
	return r.team == team and r.allied


func retreat_message() -> String:
	return "Vos alliés sonnent la retraite et quittent le champ."


## Les alliés ne suivent pas l'objectif du contrat : ils combattent.
func objective_plan(_b: BattleSim) -> String:
	return ""


func objective_anchor(_b: BattleSim) -> Vector2:
	return Vector2.INF


func seek_objective(_b: BattleSim, _r: Regiment, _theirs: Array[Regiment]) -> bool:
	return false
