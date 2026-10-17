<#
.SYNOPSIS
    Installs ValorianSheet into Valor Mortis (UE4SS Mods folder), or removes it again.

.DESCRIPTION
    Copies mod\ValorianSheet into <game>\ValorMortis\Binaries\Win64\ue4ss\Mods\ValorianSheet.
    Your settings.cfg and teleports.txt in the installed folder are kept.

    ValorianSheet replaces the Valor Mortis Cheat Menu and AeonGreyh's Passive Health Regen. If they
    are installed they are switched off (enabled.txt renamed to enabled.txt.disabled) so nothing is
    applied twice; their folders stay.

    -Uninstall removes ValorianSheet and switches those mods back on.

.EXAMPLE
    .\tools\install.ps1
    .\tools\install.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Valor Mortis"
    .\tools\install.ps1 -Uninstall
#>
param(
    # The game folder (the one containing ValorMortis\). Default: the Game Pass install.
    [string]$GameDir = "C:\XboxGames\Valor Mortis\Content",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$mods = Join-Path $GameDir "ValorMortis\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS Mods folder not found: $mods (is UE4SS installed? is -GameDir right?)" }
if (Get-Process -Name "ValorMortis*" -ErrorAction SilentlyContinue) { throw "Valor Mortis is running. Close it first." }

$target = Join-Path $mods "ValorianSheet"
$replacedMods = @("ValorCheatMenu", "PassiveHealthRegen")

if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; "Removed $target" }
    foreach ($name in $replacedMods) {
        $disabled = Join-Path $mods "$name\enabled.txt.disabled"
        if (Test-Path $disabled) { Rename-Item $disabled "enabled.txt"; "$name switched back on" }
    }
    return
}

$source = Join-Path $PSScriptRoot "..\mod\ValorianSheet" | Resolve-Path
$keep = @("settings.cfg", "teleports.txt")

if (Test-Path $target) {
    # Replace the scripts, keep the player's files and logs.
    Get-ChildItem $target -Force | Where-Object { $keep -notcontains $_.Name -and $_.Extension -notin ".log", ".old" } |
        Remove-Item -Recurse -Force
}
New-Item -ItemType Directory $target -Force | Out-Null
Copy-Item (Join-Path $source "*") $target -Recurse -Force
"Installed to $target"

foreach ($name in $replacedMods) {
    $enabled = Join-Path $mods "$name\enabled.txt"
    if (Test-Path $enabled) {
        Rename-Item $enabled "enabled.txt.disabled"
        "$name switched off (ValorianSheet replaces it)"
    }
}
