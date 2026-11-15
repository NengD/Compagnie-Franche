class_name Soldier
extends RefCounted
## Un soldat individuel. Il appartient à un régiment et suit sa place dans la formation.

var regiment: Regiment
var pos := Vector2.ZERO
var slot_pos := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var alive := true
var fled := false ## A quitté le champ de bataille en fuyant (il rejoindra la compagnie)
var foe: Soldier = null
var cooldown := 0.0
var retarget := 0.0
var momentum := 0.0 ## Élan de charge (cavalerie) : 0 à 1
var flash := 0.0 ## Clignotement blanc quand touché
var attack_anim := 0.0 ## Temps restant de l'animation d'attaque
var attack_dur := 0.3 ## Durée totale de cette animation
var move_dir := Vector2.DOWN ## Direction du dernier pas (pour orienter le sprite)
var anim := 0.0
var moving := false
