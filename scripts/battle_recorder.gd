class_name BattleRecorder
extends RefCounted
## Enregistreur des statistiques d'une bataille, pour le bilan de fin (battle_report.gd) :
##   - effectifs debout des deux camps dans le temps (un relevé toutes les INTERVAL secondes) ;
##   - lieux des morts, par camp (carte de chaleur des pertes) ;
##   - ennemis tués par régiment, des deux camps (à la fin).
## Bon marché : rien n'est fait entre deux relevés ; un relevé parcourt une fois les soldats
## (quelques centaines) et ne retient que les nouveaux morts. Battle.simulate l'avance.

const INTERVAL := 2.0 ## Secondes simulées entre deux relevés
const MAX_SAMPLES := 400 ## Au-delà, on garde un relevé sur deux (et l'intervalle double)
const HEAT_COLS := 32 ## Carte de chaleur : cases en largeur
const HEAT_ROWS := 20 ## ... et en hauteur (même rapport que le champ, 3200 × 2000)

var interval := INTERVAL
var clock := 0.0 ## Temps simulé depuis le dernier relevé
var samples: Array = [] ## [temps de bataille, debout joueur, debout ennemi]
var deaths: Array = [[], []] ## Par camp : positions (Vector2) des morts
var seen := {} ## Soldats morts déjà comptés (identifiant d'instance -> vrai)
var finished := false


## Un pas de simulation : relevé toutes les `interval` secondes de bataille (pas au déploiement).
func step(sim: BattleSim, dt: float) -> void:
	if finished or sim.state != BattleSim.State.BATTLE:
		return
	if samples.is_empty():
		sample(sim) # Effectifs au coup d'envoi
	clock += dt
	if clock >= interval:
		clock = 0.0
		sample(sim)


## Un relevé : effectifs debout des deux camps et nouveaux morts.
func sample(sim: BattleSim) -> void:
	samples.append([sim.battle_time, sim.team_strength(BattleSim.PLAYER), sim.team_strength(BattleSim.ENEMY)])
	if samples.size() > MAX_SAMPLES:
		var kept: Array = []
		for i in range(0, samples.size(), 2):
			kept.append(samples[i])
		samples = kept
		interval *= 2.0
	for r in sim.regiments:
		var team := clampi(r.team, 0, 1)
		for s: Soldier in r.soldiers:
			if not s.alive and not s.fled:
				var id := s.get_instance_id()
				if not seen.has(id):
					seen[id] = true
					deaths[team].append(s.pos)


## Fin de bataille : dernier relevé (les suivants sont ignorés).
func finish(sim: BattleSim) -> void:
	if finished:
		return
	sample(sim)
	finished = true


## Carte de chaleur d'un camp : HEAT_COLS × HEAT_ROWS cases (morts par case).
func heat(team: int) -> PackedInt32Array:
	return heat_of(deaths[team])


static func heat_of(points: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(HEAT_COLS * HEAT_ROWS)
	for p in points:
		var v: Vector2 = p
		var cx := clampi(int(v.x / BattleSim.WORLD_SIZE.x * HEAT_COLS), 0, HEAT_COLS - 1)
		var cy := clampi(int(v.y / BattleSim.WORLD_SIZE.y * HEAT_ROWS), 0, HEAT_ROWS - 1)
		out[cy * HEAT_COLS + cx] += 1
	return out


## Données pour le bilan (Battle.build_end_report, clé « stats ») : relevés, morts par camp et
## ennemis tués par chaque régiment ({"name", "team", "kills", "index"} ; index : numéro de la
## carte pour le joueur, -1 pour l'ennemi).
func to_dict(sim: BattleSim, roster: Array[Regiment] = []) -> Dictionary:
	var kills: Array = []
	for r in sim.regiments:
		kills.append({"name": r.display_name(), "team": r.team, "kills": r.kills, "index": roster.find(r)})
	return {"samples": samples.duplicate(true), "deaths": [deaths[0].duplicate(), deaths[1].duplicate()],
		"kills": kills, "interval": interval}
