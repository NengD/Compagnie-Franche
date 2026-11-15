#!/usr/bin/env bash
# Lance tous les tests headless de tests/ (*_test.gd) et affiche un récapitulatif.
# Usage : tools/run_tests.sh            (Godot : variable GODOT, sinon « godot » dans le PATH)
#         TERRAINS="plain siege" ONLY="smoke menu" TIMEOUT=600 tools/run_tests.sh
# Le test de fumée est joué sur chaque terrain de TERRAINS (défaut : les 6 terrains).
# Journaux dans build/test-logs/. Code de sortie : 0 si tout passe, 1 sinon.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"
terrains="${TERRAINS:-plain forest hills river village siege}"
only="${ONLY:-}"
timeout_s="${TIMEOUT:-600}"
logs="$root/build/test-logs"
mkdir -p "$logs"

if ! command -v "$godot" >/dev/null 2>&1 && [ ! -x "$godot" ]; then
	echo "Godot introuvable : $godot (définissez GODOT=<chemin>)" >&2
	exit 1
fi

run_godot() { # run_godot <journal> <arguments...>
	local log="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$timeout_s" "$godot" "$@" >"$log" 2>&1
	else
		"$godot" "$@" >"$log" 2>&1
	fi
}

echo "Import du projet..."
if ! run_godot "$logs/import.log" --headless --path "$root" --import; then
	echo "L'import a échoué, voir build/test-logs/import.log" >&2
	exit 1
fi

pass=0
fail=0
failed=""
run_one() { # run_one <libellé> <journal> <script> [arguments après --]
	local label="$1" log="$logs/$2" script="$3"
	shift 3
	local start end code
	start=$(date +%s)
	if [ $# -gt 0 ]; then
		run_godot "$log" --headless --path "$root" -s "$script" -- "$@"
	else
		run_godot "$log" --headless --path "$root" -s "$script"
	fi
	code=$?
	end=$(date +%s)
	if [ $code -eq 0 ]; then
		printf '%-22s OK      %4d s\n' "$label" $((end - start))
		pass=$((pass + 1))
	else
		printf '%-22s ÉCHEC   %4d s  (code %d)\n' "$label" $((end - start)) $code
		tail -n 15 "$log" | sed 's/^/    /'
		fail=$((fail + 1))
		failed="$failed $label"
	fi
}

for f in "$root"/tests/*_test.gd; do
	file="$(basename "$f")"
	name="${file%_test.gd}"
	if [ -n "$only" ] && ! [[ " $only " == *" $name "* ]]; then
		continue
	fi
	if [ "$name" = "smoke" ]; then
		for t in $terrains; do
			run_one "smoke ($t)" "smoke_$t.log" "tests/$file" "--terrain=$t"
		done
	else
		run_one "$name" "$name.log" "tests/$file"
	fi
done

echo
echo "Récapitulatif : $pass/$((pass + fail)) réussis (journaux : build/test-logs/)"
if [ $fail -gt 0 ] || [ $pass -eq 0 ]; then
	echo "Échecs :$failed"
	exit 1
fi
exit 0
