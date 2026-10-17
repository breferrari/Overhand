<#
.SYNOPSIS
    Builds Overhand for one game and installs it into that game's UE4SS Mods folder (or removes it).

.DESCRIPTION
    Assembles the mod from only what the game needs, into build\<game>\<modName>\:
        Scripts\main.lua         src\main.lua
        Scripts\core\            src\core\
        Scripts\gas\             src\gas\            (only when the manifest says usesGas)
        Scripts\game\            games\<game>\       (without manifest.json)
        assets\                 assets\             (the menu's mark, arrows, button disc, fonts)
        enabled.txt, LICENSE
    then copies it into UE4SS's Mods folder, keeping settings.cfg and teleports.txt.

    The game is found in Steam libraries, Xbox app / Game Pass folders (every drive), Epic Games and
    GOG installs, by the folder names in the manifest (installFolders). Its UE4SS Mods folder is
    <projectFolder>\Binaries\Win64 or WinGDK, then ue4ss\Mods (UE4SS 3) or Mods (older UE4SS).

    games\<game>\manifest.json names the game's folders, whether it uses GAS, which mods Overhand
    replaces (switched off: enabled.txt renamed to enabled.txt.disabled) and which earlier folders of
    this mod to migrate settings from (then removed).

    -Uninstall removes the mod and switches the replaced mods back on.
    -BuildOnly assembles build\<game>\ without installing.

.EXAMPLE
    .\tools\install.ps1 -Game valormortis
    .\tools\install.ps1 -Game valormortis -GameDir "E:\Games\Valor Mortis"
    .\tools\install.ps1 -Game valormortis -Uninstall
#>
param(
    [Parameter(Mandatory = $true)][string]$Game,
    # The game's folder, when it isn't found or more than one install is: the install folder, its
    # Content folder (Xbox app) or the Binaries\Win64 folder all work.
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
# Find the game
# ---------------------------------------------------------------------------

$names = @($manifest.installFolders)

# Folders where a store keeps this game: @{ Store; Path } for each that exists.
function Find-StoreInstalls {
    $found = @()
    # Steam: every library listed in libraryfolders.vdf, then steamapps\common\<name>.
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $libraries = @($steam)
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $libraries += Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' |
                ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            foreach ($name in $names) { $found += @{ Store = "Steam"; Path = Join-Path $library "steamapps\common\$name" } }
        }
    }
    # Xbox app / Game Pass: each drive's .GamingRoot names its game folders ("RGBX", a count, then
    # UTF-16 paths from the drive root); XboxGames is the default.
    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        $roots = @("XboxGames")
        $gamingRoot = Join-Path $drive.Root ".GamingRoot"
        if (Test-Path $gamingRoot) {
            $bytes = [System.IO.File]::ReadAllBytes($gamingRoot)
            if ($bytes.Length -gt 8) {
                $roots += [System.Text.Encoding]::Unicode.GetString($bytes, 8, $bytes.Length - 8).Split([char]0) |
                    Where-Object { $_ }
            }
        }
        foreach ($root in ($roots | Select-Object -Unique)) {
            foreach ($name in $names) { $found += @{ Store = "Xbox app"; Path = Join-Path $drive.Root "$root\$name" } }
        }
    }
    # Epic Games: the launcher's install manifests.
    $epic = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $epic) {
        foreach ($item in Get-ChildItem $epic -Filter *.item) {
            $entry = Get-Content $item.FullName -Raw | ConvertFrom-Json
            if ($entry.InstallLocation -and (($names -contains (Split-Path $entry.InstallLocation -Leaf)) -or ($names -contains $entry.DisplayName))) {
                $found += @{ Store = "Epic Games"; Path = $entry.InstallLocation }
            }
        }
    }
    # GOG: one registry key per game.
    foreach ($key in Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games" -ErrorAction SilentlyContinue) {
        $entry = Get-ItemProperty $key.PSPath
        if ($entry.path -and (($names -contains (Split-Path $entry.path -Leaf)) -or ($names -contains $entry.gameName))) {
            $found += @{ Store = "GOG"; Path = $entry.path }
        }
    }
    $found | Where-Object { Test-Path $_.Path }
}

# The game's Binaries folder under a game folder (itself, its Content folder for the Xbox app, or the
# Binaries folder given directly), and UE4SS's Mods folder in it ($null when UE4SS is missing).
function Find-Binaries($folder) {
    $candidates = @()
    if ((Split-Path $folder -Leaf) -in "Win64", "WinGDK") { $candidates += $folder }
    foreach ($base in $folder, (Join-Path $folder "Content")) {
        foreach ($platform in "Win64", "WinGDK") { $candidates += Join-Path $base "$($manifest.projectFolder)\Binaries\$platform" }
    }
    foreach ($binaries in $candidates) {
        if (-not (Test-Path $binaries)) { continue }
        $mods = @("ue4ss\Mods", "Mods") | ForEach-Object { Join-Path $binaries $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
        return @{ Binaries = $binaries; Mods = $mods }
    }
    return $null
}

if ($GameDir) {
    $install = Find-Binaries $GameDir
    if (-not $install) { throw "No $($manifest.projectFolder)\Binaries\Win64 (or WinGDK) under $GameDir" }
    $where = $GameDir
} else {
    # One entry per Binaries folder (Steam's registry path and its library list differ in case; Epic
    # has a manifest per add-on, all in the same folder).
    $seen = @{}
    $installs = @(Find-StoreInstalls | ForEach-Object {
        $binaries = Find-Binaries $_.Path
        if ($binaries -and -not $seen.ContainsKey($binaries.Binaries.ToLowerInvariant())) {
            $seen[$binaries.Binaries.ToLowerInvariant()] = $true
            $binaries.Store = $_.Store
            $binaries
        }
    })
    if ($installs.Count -eq 0) {
        throw "$($manifest.gameName) not found in Steam, Xbox app, Epic Games or GOG folders (looked for: $($names -join ', ')). Pass -GameDir <the game's folder>."
    }
    if ($installs.Count -gt 1) {
        $list = ($installs | ForEach-Object { "  $($_.Store): $($_.Binaries)" }) -join "`n"
        throw "$($manifest.gameName) is installed more than once:`n$list`nPass -GameDir with the one to use."
    }
    $install = $installs[0]
    $where = "$($install.Store) install"
}
if (-not $install.Mods) { throw "UE4SS not found in $($install.Binaries) (no ue4ss\Mods or Mods folder). Install UE4SS first." }
$mods = $install.Mods
"Found $($manifest.gameName) ($where): $mods"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

if (Get-Process -Name $manifest.processName -ErrorAction SilentlyContinue) { throw "$($manifest.gameName) is running. Close it first." }
$target = Join-Path $mods $manifest.modName

if ($Uninstall) {
    if (Test-Path $target) { Remove-Item $target -Recurse -Force; "Removed $target" }
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

foreach ($name in $manifest.replacesMods) {
    $enabled = Join-Path $mods "$name\enabled.txt"
    if (Test-Path $enabled) {
        Rename-Item $enabled "enabled.txt.disabled"
        "$name switched off ($($manifest.modName) replaces it)"
    }
}
