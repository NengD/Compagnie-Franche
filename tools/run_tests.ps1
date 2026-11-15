# Lance tous les tests headless de tests/ (*_test.gd) et affiche un récapitulatif.
# Usage : powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 [-Godot <chemin>] [-Only smoke,menu]
#         [-Terrains plain,siege] [-Timeout 600] [-NoImport]
# - Le test de fumée est joué sur chaque terrain de -Terrains (défaut : les 6 terrains).
# - Les journaux complets vont dans build/test-logs/ (ignoré par git).
# - Code de sortie : 0 si tout passe, 1 sinon.
# Le chemin de Godot peut aussi venir de la variable d'environnement GODOT.
param(
	[string]$Godot = $env:GODOT,
	[string[]]$Only = @(),
	[string[]]$Terrains = @("plain", "forest", "hills", "river", "village", "siege"),
	[int]$Timeout = 600,
	[switch]$NoImport
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $root "build\test-logs"

if (-not $Godot) {
	$Godot = "E:\_jeu perso\godot\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
	Write-Error "Godot introuvable : $Godot (passez -Godot <chemin> ou définissez `$env:GODOT)"
}
New-Item -ItemType Directory -Force $logs | Out-Null
# Avec « -File », « -Only a,b » arrive en une seule chaîne : on découpe sur les virgules.
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
$Terrains = @($Terrains | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })

# Lance Godot avec un délai maximal ; renvoie le code de sortie (124 si le délai est dépassé).
function Invoke-Godot([string[]]$arguments, [string]$log) {
	$quoted = $arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
	$p = Start-Process -FilePath $Godot -ArgumentList $quoted -NoNewWindow -PassThru `
		-RedirectStandardOutput $log -RedirectStandardError "$log.err"
	$null = $p.Handle # Garde le processus ouvert pour lire son code de sortie
	if (-not $p.WaitForExit($Timeout * 1000)) {
		$p.Kill()
		return 124
	}
	$p.WaitForExit()
	Add-Content -Path $log -Value (Get-Content "$log.err" -Raw -ErrorAction SilentlyContinue)
	Remove-Item "$log.err" -ErrorAction SilentlyContinue
	return $p.ExitCode
}

if (-not $NoImport) {
	Write-Host "Import du projet..."
	$code = Invoke-Godot @("--headless", "--path", $root, "--import") (Join-Path $logs "import.log")
	if ($code -ne 0) {
		Write-Host "L'import a échoué (code $code), voir build\test-logs\import.log" -ForegroundColor Red
		exit 1
	}
}

# Liste des exécutions : un test de fumée par terrain, puis chaque autre *_test.gd.
$runs = @()
foreach ($f in Get-ChildItem (Join-Path $root "tests") -Filter "*_test.gd" | Sort-Object Name) {
	$name = $f.BaseName -replace "_test$", ""
	if ($Only.Count -gt 0 -and -not ($Only -contains $name)) {
		continue
	}
	if ($name -eq "smoke") {
		foreach ($t in $Terrains) {
			$runs += [pscustomobject]@{ Label = "smoke ($t)"; Script = "tests/$($f.Name)"; Args = @("--terrain=$t"); Log = "smoke_$t.log" }
		}
	} else {
		$runs += [pscustomobject]@{ Label = $name; Script = "tests/$($f.Name)"; Args = @(); Log = "$name.log" }
	}
}
if ($runs.Count -eq 0) {
	Write-Host "Aucun test à lancer." -ForegroundColor Red
	exit 1
}

$results = @()
foreach ($r in $runs) {
	Write-Host -NoNewline ("{0,-22}" -f $r.Label)
	$log = Join-Path $logs $r.Log
	$argv = @("--headless", "--path", $root, "-s", $r.Script)
	if ($r.Args.Count -gt 0) {
		$argv += "--"
		$argv += $r.Args
	}
	$watch = [Diagnostics.Stopwatch]::StartNew()
	$code = Invoke-Godot $argv $log
	$secs = [math]::Round($watch.Elapsed.TotalSeconds, 1)
	$ok = $code -eq 0
	if ($ok) {
		Write-Host ("OK      {0,6} s" -f $secs) -ForegroundColor Green
	} else {
		$why = if ($code -eq 124) { "délai dépassé" } else { "code $code" }
		Write-Host ("ÉCHEC   {0,6} s  ({1})" -f $secs, $why) -ForegroundColor Red
		Get-Content $log -Tail 15 | ForEach-Object { Write-Host "    $_" }
	}
	$results += [pscustomobject]@{ Label = $r.Label; Ok = $ok; Secs = $secs }
}

$failed = @($results | Where-Object { -not $_.Ok })
$total = [math]::Round(($results | Measure-Object Secs -Sum).Sum, 1)
Write-Host ""
Write-Host ("Récapitulatif : {0}/{1} réussis en {2} s (journaux : build\test-logs\)" -f ($results.Count - $failed.Count), $results.Count, $total)
if ($failed.Count -gt 0) {
	Write-Host ("Échecs : " + (($failed | ForEach-Object { $_.Label }) -join ", ")) -ForegroundColor Red
	exit 1
}
exit 0
