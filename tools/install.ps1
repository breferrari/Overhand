<#
.SYNOPSIS
    Installs ValorianSheet into Valor Mortis (UE4SS Mods folder), or removes it again.

.DESCRIPTION
    Copies mod\ValorianSheet into <game>\ValorMortis\Binaries\Win64\ue4ss\Mods\ValorianSheet.
    Your settings.cfg and teleports.txt in the installed folder are kept.
    If the Valor Mortis Cheat Menu is installed, it is switched off (its enabled.txt is renamed to
    enabled.txt.disabled) so both menus never apply cheats at the same time; its folder stays, and
    ValorianSheet imports its settings and teleports on the first start.

    -Uninstall removes ValorianSheet and switches the Cheat Menu back on.

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
$cheatMenuEnabled = Join-Path $mods "ValorCheatMenu\enabled.txt"
$cheatMenuDisabled = "$cheatMenuEnabled.disabled"

if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; "Removed $target" }
    if (Test-Path $cheatMenuDisabled) { Rename-Item $cheatMenuDisabled "enabled.txt"; "Valor Mortis Cheat Menu switched back on" }
    return
}

$source = Join-Path $PSScriptRoot "..\mod\ValorianSheet" | Resolve-Path
$keep = @("settings.cfg", "teleports.txt")

if (Test-Path $target) {
    # Replace the scripts, keep the player's files.
    Get-ChildItem $target -Force | Where-Object { $keep -notcontains $_.Name -and $_.Extension -notin ".log", ".old" } |
        Remove-Item -Recurse -Force
}
New-Item -ItemType Directory $target -Force | Out-Null
Copy-Item (Join-Path $source "*") $target -Recurse -Force
"Installed to $target"

if (Test-Path $cheatMenuEnabled) {
    Rename-Item $cheatMenuEnabled "enabled.txt.disabled"
    "Valor Mortis Cheat Menu switched off (settings will be imported on first start)"
}
