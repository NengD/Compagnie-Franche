# Exporte Compagnie Franche en exécutable Windows autonome (pck intégré) dans build/.
# Usage : powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1 [-Godot <chemin>]
# Le chemin de Godot peut aussi venir de la variable d'environnement GODOT.
param(
	[string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"

if (-not $Godot) {
	$Godot = "E:\_jeu perso\godot\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
	Write-Error "Godot introuvable : $Godot (passez -Godot <chemin> ou définissez `$env:GODOT)"
}

$templates = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe"
if (-not (Test-Path $templates)) {
	Write-Error "Modèles d'export 4.7.2 absents. Dans l'éditeur : Éditeur > Gérer les modèles d'export > Télécharger et installer."
}

New-Item -ItemType Directory -Force $build | Out-Null

# Importe les ressources au besoin (premier export depuis un clone neuf), puis exporte.
& $Godot --headless --path $root --import
& $Godot --headless --path $root --export-release "Windows" "build/CompagnieFranche.exe"
if ($LASTEXITCODE -ne 0) {
	Write-Error "L'export a échoué (code $LASTEXITCODE)."
}

Copy-Item (Join-Path $root "CREDITS.md") $build -Force
Copy-Item (Join-Path $root "README.md") $build -Force

$exe = Join-Path $build "CompagnieFranche.exe"
if (-not (Test-Path $exe)) {
	Write-Error "Exécutable absent après l'export : $exe"
}
$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "Export terminé : $exe ($size Mo), avec CREDITS.md et README.md."
