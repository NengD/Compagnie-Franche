# Exporte Compagnie Franche en exécutable Windows autonome (pck intégré) dans build/,
# puis l'empaquette dans build/CompagnieFranche-<version>-windows.zip (avec CREDITS.md et README.md).
# Si le modèle d'export Linux 4.7.2 est installé (ou avec -Linux), exporte aussi
# build/linux/CompagnieFranche.x86_64 et build/CompagnieFranche-<version>-linux.zip.
# Usage : powershell -ExecutionPolicy Bypass -File tools\export_windows.ps1 [-Godot <chemin>] [-NoLinux]
# Le chemin de Godot peut aussi venir de la variable d'environnement GODOT.
# La version vient de application/config/version dans project.godot.
param(
	[string]$Godot = $env:GODOT,
	[switch]$NoLinux
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

$templatesDir = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
if (-not (Test-Path (Join-Path $templatesDir "windows_release_x86_64.exe"))) {
	Write-Error "Modèles d'export 4.7.2 absents. Dans l'éditeur : Éditeur > Gérer les modèles d'export > Télécharger et installer."
}

# Numéro de version lu dans project.godot
$version = "0.0.0"
$match = Select-String -Path (Join-Path $root "project.godot") -Pattern '^config/version="([^"]+)"'
if ($match) {
	$version = $match.Matches[0].Groups[1].Value
}

New-Item -ItemType Directory -Force $build | Out-Null

# Exporte un préréglage puis empaquette le binaire avec CREDITS.md et README.md.
function Export-Preset([string]$preset, [string]$relPath, [string]$zipSuffix) {
	$bin = Join-Path $root $relPath
	New-Item -ItemType Directory -Force (Split-Path -Parent $bin) | Out-Null
	& $Godot --headless --path $root --export-release $preset $relPath
	if ($LASTEXITCODE -ne 0) {
		Write-Error "L'export « $preset » a échoué (code $LASTEXITCODE)."
	}
	if (-not (Test-Path $bin)) {
		Write-Error "Binaire absent après l'export : $bin"
	}
	$dir = Split-Path -Parent $bin
	Copy-Item (Join-Path $root "CREDITS.md") $dir -Force
	Copy-Item (Join-Path $root "README.md") $dir -Force
	$zip = Join-Path $build "CompagnieFranche-$version-$zipSuffix.zip"
	if (Test-Path $zip) {
		Remove-Item $zip -Force
	}
	$files = @($bin, (Join-Path $dir "CREDITS.md"), (Join-Path $dir "README.md"))
	$python = Get-Command python -ErrorAction SilentlyContinue
	if ($python) {
		# Droits Unix dans le zip : le binaire Linux reste exécutable une fois décompressé
		& $python.Source (Join-Path $PSScriptRoot "make_zip.py") $zip @files --exec $bin
	} else {
		Write-Warning "Python introuvable : zip sans droits Unix (sous Linux, il faudra « chmod +x »)."
		Compress-Archive -Path $files -DestinationPath $zip
	}
	$size = [math]::Round((Get-Item $bin).Length / 1MB, 1)
	$zsize = [math]::Round((Get-Item $zip).Length / 1MB, 1)
	Write-Host "Export « $preset » terminé : $bin ($size Mo) ; archive $zip ($zsize Mo)."
}

# Importe les ressources au besoin (premier export depuis un clone neuf), puis exporte.
& $Godot --headless --path $root --import
Export-Preset "Windows" "build/CompagnieFranche.exe" "windows"

if (-not $NoLinux) {
	if (Test-Path (Join-Path $templatesDir "linux_release.x86_64")) {
		Export-Preset "Linux" "build/linux/CompagnieFranche.x86_64" "linux"
	} else {
		Write-Host "Modèle d'export Linux absent : export Linux ignoré."
	}
}
Write-Host "Version $version."
