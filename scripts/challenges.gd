class_name Challenges
extends RefCounted
## Défis (modificateurs) de campagne, cochés à « Nouvelle campagne » (main_menu.gd) et gardés
## dans la sauvegarde (CampaignState.challenges, liste d'identifiants). Toutes les règles sont
## lues ici ou par un appel à CampaignState.has_challenge :
##   « Homme de fer »   : une seule sauvegarde (pas de copie de secours), effacée à la ruine de la
##                        compagnie ; le mode indulgent est interdit (fermer le jeu en bataille ne
##                        la rejoue pas) : pas de rechargement possible (CampaignState.save) ;
##   « Sans cavalerie » : on ne lève ni ne complète de régiment monté (cavaliers, archers montés),
##                        ni en ville (recruit, refill), ni au château (fiefs.gd), ni parmi les
##                        prisonniers ou les volontaires (Encounter.add_to_company) ;
##   « Hiver éternel »  : la saison reste l'hiver (WorldSim.season, MapSky.season) ;
##   « Bourse plate »   : la compagnie part avec la moitié de l'or ;
##   « Contrats maigres » : primes des contrats réduites d'un quart.

const IRONMAN := "ironman"
const NO_CAVALRY := "no_cavalry"
const ETERNAL_WINTER := "eternal_winter"
const POOR_START := "poor_start"
const LEAN_CONTRACTS := "lean_contracts"
const IDS: Array[String] = [IRONMAN, NO_CAVALRY, ETERNAL_WINTER, POOR_START, LEAN_CONTRACTS]

const INFO := {
	IRONMAN: {"name": "Homme de fer", "text": "Une seule sauvegarde, sans copie de secours ni mode indulgent ; elle est effacée si la compagnie est ruinée."},
	NO_CAVALRY: {"name": "Sans cavalerie", "text": "Impossible de lever ou de compléter des régiments montés (cavaliers, archers montés)."},
	ETERNAL_WINTER: {"name": "Hiver éternel", "text": "La saison reste l'hiver : marches lentes, froid et armées qui fondent."},
	POOR_START: {"name": "Bourse plate", "text": "La compagnie part avec la moitié de l'or."},
	LEAN_CONTRACTS: {"name": "Contrats maigres", "text": "Les primes des contrats sont réduites d'un quart."},
}
const START_GOLD_FACTOR := 0.5 ## « Bourse plate » : part de l'or de départ
const REWARD_FACTOR := 0.75 ## « Contrats maigres » : part de la prime


## Liste d'identifiants valides, sans doublon, dans l'ordre de IDS (sauvegarde, cases cochées).
static func sanitize(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if not v is Array:
		return out
	for id in IDS:
		if id in (v as Array):
			out.append(id)
	return out


static func display_name(id: String) -> String:
	return str(INFO.get(id, {}).get("name", id))


static func hint(id: String) -> String:
	return str(INFO.get(id, {}).get("text", ""))


## « Homme de fer, Sans cavalerie » (vide sans défi).
static func names(list: Array) -> String:
	var out: Array[String] = []
	for id in sanitize(list):
		out.append(display_name(id))
	return ", ".join(out)


## Vrai si ce type d'unité est interdit par les défis (régiment monté et « Sans cavalerie »).
static func forbids_type(list: Array, type: String) -> bool:
	return NO_CAVALRY in list and UnitTypes.STATS.has(type) and bool(UnitTypes.STATS[type]["mounted"])


const NO_CAVALRY_REFUSAL := "Défi « Sans cavalerie » : la compagnie ne lève pas de régiment monté."
