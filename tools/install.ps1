<#
.SYNOPSIS
    Builds Overhand for one game and installs it into that game's UE4SS Mods folder (or removes it).

.DESCRIPTION
    Assembles the mod from only what the game needs, into build\<game>\<modName>\:
        Scripts\main.lua         src\main.lua
        Scripts\core\            src\core\
        Scripts\gas\             src\gas\            (only when the manifest says usesGas)
        Scripts\game\            games\<game>\       (without manifest.json)
        assets\                 assets\             (the menu's mark)
        enabled.txt, LICENSE
    then copies it into <gameDir>\<modsPath>\<modName>\, keeping settings.cfg and teleports.txt.

    games\<game>\manifest.json says where the game is, whether it uses GAS, which mods Overhand
    replaces (switched off: enabled.txt renamed to enabled.txt.disabled) and which earlier folders of
    this mod to migrate settings from (then removed).

    -Uninstall removes the mod and switches the replaced mods back on.
    -BuildOnly assembles build\<game>\ without installing.

.EXAMPLE
    .\tools\install.ps1 -Game valormortis
    .\tools\install.ps1 -Game valormortis -GameDir "D:\SteamLibrary\steamapps\common\Valor Mortis"
    .\tools\install.ps1 -Game valormortis -Uninstall
#>
param(
    [Parameter(Mandatory = $true)][string]$Game,
    # The game folder (the one containing the game's own folder). Default: the manifest's.
    [string]$GameDir,
    [switch]$Uninstall,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$gameSource = Join-Path $repo "games\$Game"
$manifestPath = Join-Path $gameSource "manifest.json"
if (-not (Test-Path $manifestPath)) { throw "No game '$Game' (missing $manifestPath)" }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if (-not $GameDir) { $GameDir = $manifest.defaultGameDir }

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

$build = Join-Path $repo "build\$Game\$($manifest.modName)"
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
$scripts = Join-Path $build "Scripts"
New-Item -ItemType Directory $scripts -Force | Out-Null
Copy-Item (Join-Path $repo "src\main.lua") $scripts
Copy-Item (Join-Path $repo "src\core") $scripts -Recurse
if ($manifest.usesGas) { Copy-Item (Join-Path $repo "src\gas") $scripts -Recurse }
Copy-Item $gameSource (Join-Path $scripts "game") -Recurse
Remove-Item (Join-Path $scripts "game\manifest.json")
Copy-Item (Join-Path $repo "assets") $build -Recurse
New-Item -ItemType File (Join-Path $build "enabled.txt") | Out-Null
Copy-Item (Join-Path $repo "LICENSE") $build
"Built $build"
if ($BuildOnly) { return }

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

$mods = Join-Path $GameDir $manifest.modsPath
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods (is UE4SS installed? is -GameDir right?)" }
if (Get-Process -Name $manifest.processName -ErrorAction SilentlyContinue) { throw "$($manifest.gameName) is running. Close it first." }
$target = Join-Path $mods $manifest.modName
# The menu's fonts live in the game's Content folder (core/ui/fonts.lua): <contentPath>\<modName>\Fonts
$contentTarget = if ($manifest.contentPath) { Join-Path (Join-Path $GameDir $manifest.contentPath) $manifest.modName }

if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; "Removed $target" }
    if ($contentTarget -and (Test-Path $contentTarget)) { Remove-Item $contentTarget -Recurse -Force; "Removed $contentTarget" }
    foreach ($name in $manifest.replacesMods) {
        $disabled = Join-Path $mods "$name\enabled.txt.disabled"
        if (Test-Path $disabled) { Rename-Item $disabled "enabled.txt"; "$name switched back on" }
    }
    return
}

$keep = @("settings.cfg", "teleports.txt")

# Settings from an earlier folder of this mod (an older name), then that folder goes.
foreach ($previous in $manifest.previousModFolders) {
    $previousFolder = Join-Path $mods $previous
    if (-not (Test-Path $previousFolder)) { continue }
    New-Item -ItemType Directory $target -Force | Out-Null
    foreach ($file in $keep) {
        $from = Join-Path $previousFolder $file
        if ((Test-Path $from) -and -not (Test-Path (Join-Path $target $file))) { Copy-Item $from $target; "Kept $file from $previous" }
    }
    Remove-Item $previousFolder -Recurse -Force
    "Removed the earlier folder $previous"
}

if (Test-Path $target) {
    # Replace the scripts, keep the player's files and logs.
    Get-ChildItem $target -Force | Where-Object { $keep -notcontains $_.Name -and $_.Extension -notin ".log", ".old" } |
        Remove-Item -Recurse -Force
}
New-Item -ItemType Directory $target -Force | Out-Null
Copy-Item (Join-Path $build "*") $target -Recurse -Force
"Installed to $target"

# Fonts: a cooked .ufont is the plain font file, read from where the font's package name points.
# (tools/smoke_test.py lays the fonts out the same way.)
if ($contentTarget) {
    $fonts = Join-Path $contentTarget "Fonts"
    if (Test-Path $fonts) { Remove-Item $fonts -Recurse -Force }
    New-Item -ItemType Directory $fonts -Force | Out-Null
    foreach ($font in Get-ChildItem (Join-Path $repo "assets\fonts") -Filter "*.ttf") {
        Copy-Item $font.FullName (Join-Path $fonts ($font.BaseName + ".ufont"))
    }
    "Fonts installed to $fonts"
}

foreach ($name in $manifest.replacesMods) {
    $enabled = Join-Path $mods "$name\enabled.txt"
    if (Test-Path $enabled) {
        Rename-Item $enabled "enabled.txt.disabled"
        "$name switched off ($($manifest.modName) replaces it)"
    }
}
