param(
    [ValidateSet('Install','Disable','Enable','Uninstall','Status','Detect')][string]$Action='Install',
    [string]$GameDirectory,
    [string]$SteamDirectory,
    [switch]$NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$bundleRoot=$PSScriptRoot
$statePath=Join-Path $bundleRoot '.ffrs-terminology-state.json'
$package=Get-Content -LiteralPath (Join-Path $bundleRoot 'package.json') -Raw | ConvertFrom-Json
$package.files=$package.managedFiles
$allowed=@('FFRS/Content/Paks/~mods/FFRS-FlareZhHans_99_P.pak','FFRS/Content/Paks/~mods/FFRS-FlareZhHans_99_P.utoc','FFRS/Content/Paks/~mods/FFRS-FlareZhHans_99_P.ucas')

function Digest([string]$Path) {
    $stream=[IO.File]::OpenRead($Path); $hash=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hash.Dispose() }
}
function Machine-Key {
    $identity=[Environment]::MachineName+'|'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $hash=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','') }
    finally { $hash.Dispose() }
}
function Toggleable([string]$Relative) { return $Relative.EndsWith('.asi') -or $Relative.EndsWith('.pak') -or $Relative.EndsWith('.utoc') -or $Relative.EndsWith('.ucas') }
function Target([string]$Root,[string]$Relative) {
    if ($allowed -notcontains $Relative) { throw 'Unexpected managed path.' }
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped the selected game.' }
    $parent=$Root
    foreach ($part in $Relative.Split('/')) {
        $parent=Join-Path $parent $part
        if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Linked managed paths are not supported.' }
    }
    return $path
}
function Backup-Path([string]$Relative) {
    if (-not $Relative.StartsWith('.ffrs-terminology-backups/')) { throw 'Unexpected backup path.' }
    $base=[IO.Path]::GetFullPath($bundleRoot).TrimEnd('\')+'\'
    $path=[IO.Path]::GetFullPath((Join-Path $bundleRoot $Relative))
    if (-not $path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Backup escaped this portable folder.' }
    return $path
}
function Copy-Safe([string]$Source,[string]$Destination) {
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    $temporary=$Destination+'.ffrs-terminology-tmp'
    if (Test-Path -LiteralPath $temporary) { throw "Temporary file already exists: $temporary" }
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary
        if ((Digest $temporary) -ne (Digest $Source)) { throw 'Copy checksum mismatch.' }
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Save-State($State) {
    $temporary=$statePath+'.tmp'
    [IO.File]::WriteAllText($temporary,($State | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($true))
    Move-Item -LiteralPath $temporary -Destination $statePath -Force
}
function Normalize-Game([string]$Path) {
    $root=(Resolve-Path -LiteralPath $Path.Trim().Trim('"')).Path
    if (Test-Path -LiteralPath (Join-Path $root 'FFRS-Win64-Shipping.exe')) {
        $root=Split-Path (Split-Path (Split-Path $root -Parent) -Parent) -Parent
    }
    if ($root -match '(?i)RESONANCE DEMO(?:\\|$)') { throw 'The Demo is not supported.' }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe') -PathType Leaf)) { throw 'Select the Steam retail game root or FFRS/Binaries/Win64.' }
    return $root
}
function Discover-Game {
    $steamRoots=@()
    if ($SteamDirectory) { $steamRoots+= $SteamDirectory }
    else {
        foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')) {
            $value=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($value) { foreach ($name in @('SteamPath','InstallPath')) { if ($value.PSObject.Properties[$name]) { $steamRoots+=$value.PSObject.Properties[$name].Value } } }
        }
        foreach ($prefix in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) { if ($prefix) { $steamRoots+=Join-Path $prefix 'Steam' } }
    }
    $libraries=@($steamRoots)
    foreach ($steam in @($steamRoots | Sort-Object -Unique)) {
        $vdf=Join-Path $steam 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text=[IO.File]::ReadAllText($vdf)
            foreach ($match in [regex]::Matches($text,'"path"\s+"([^"]+)"')) { $libraries+=$match.Groups[1].Value.Replace('\\','\') }
        }
    }
    $found=@()
    foreach ($library in @($libraries | Sort-Object -Unique)) {
        $manifest=Join-Path $library 'steamapps/appmanifest_3259780.acf'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s+"([^"]+)"')
        if ($match.Success) {
            $root=Join-Path (Join-Path $library 'steamapps/common') $match.Groups[1].Value
            if (Test-Path -LiteralPath (Join-Path $root 'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe')) { $found+=Normalize-Game $root }
        }
    }
    return @($found | Sort-Object -Unique)
}
function Select-Game {
    if ($GameDirectory) { return Normalize-Game $GameDirectory }
    $found=@(Discover-Game)
    if ($found.Count -eq 1) { return $found[0] }
    if ($NonInteractive) { throw 'Provide -GameDirectory when Steam detection is ambiguous or empty.' }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description='Select FINAL FANTASY RESONANCE Steam retail game folder'
    $dialog.ShowNewFolderButton=$false
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No game folder selected.' }
        return Normalize-Game $dialog.SelectedPath
    } finally { $dialog.Dispose() }
}
function Assert-Stopped([string]$Root) {
    $exe=Join-Path $Root 'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe'
    $running=@(Get-CimInstance Win32_Process -Filter "Name='FFRS-Win64-Shipping.exe'" | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath -eq $exe })
    if ($running.Count) { throw 'Exit the retail game before changing patch files.' }
}
function Variants([string]$Root,[string]$Relative) {
    $base=Target $Root $Relative
    $paths=@($base)
    if (Toggleable $Relative) { $paths+= $base+'.disabled' }
    $existing=@($paths | Where-Object { Test-Path -LiteralPath $_ })
    foreach ($path in $existing) { if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'A managed file is a link.' } }
    return $existing
}
function Load-State {
    $saved=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($saved.version -ne $package.version) { throw 'Extract a new version into a separate portable folder.' }
    if ($saved.machineKey -ne (Machine-Key)) { throw 'This used portable folder belongs to another Windows account/computer. Extract the original ZIP on this PC.' }
    if (@($saved.files).Count -ne $allowed.Count) { throw 'Invalid installation record.' }
    foreach ($relative in $allowed) {
        if (@($saved.files | Where-Object { $_.relative -eq $relative }).Count -ne 1) { throw 'Invalid managed-file record.' }
        $null=Target $saved.gameDirectory $relative
    }
    return $saved
}
function Assert-Restorable($State) {
    foreach ($entry in $State.files) {
        if ($entry.originalVariant -notin @('absent','enabled','disabled')) { throw 'Invalid original variant.' }
        if ($entry.originalVariant -ne 'absent') {
            if ((Digest (Backup-Path $entry.backup)) -ne $entry.originalSha256) { throw 'Backup checksum mismatch; nothing restored.' }
        }
        foreach ($path in @(Variants $State.gameDirectory $entry.relative)) {
            if (-not $entry.relative.EndsWith('.toml')) {
                $hash=Digest $path
                if ($hash -ne $entry.installedSha256 -and $hash -ne $entry.originalSha256) { throw "Managed file changed; refusing to remove it: $($entry.relative)" }
            }
        }
    }
}
function Restore-Initial($State) {
    Assert-Restorable $State
    foreach ($entry in $State.files) {
        $target=Target $State.gameDirectory $entry.relative
        if ($entry.relative.EndsWith('.toml') -and (Test-Path -LiteralPath $target) -and (Digest $target) -ne $entry.installedSha256) {
            Copy-Safe $target (Backup-Path ('.ffrs-terminology-backups/user-config-'+[Guid]::NewGuid().ToString('N')+'.toml'))
        }
        foreach ($path in @(Variants $State.gameDirectory $entry.relative)) { Remove-Item -LiteralPath $path }
        if ($entry.originalVariant -ne 'absent') {
            if ($entry.originalVariant -eq 'disabled') { $target+='.disabled' }
            Copy-Safe (Backup-Path $entry.backup) $target
        }
    }
}
function Set-Enabled($State,[bool]$Enabled) {
    $moves=@()
    foreach ($entry in $State.files) {
        $paths=@(Variants $State.gameDirectory $entry.relative)
        if ($paths.Count -ne 1) { throw 'A managed file is missing or duplicated; no changes made.' }
        if (-not $entry.relative.EndsWith('.toml') -and (Digest $paths[0]) -ne $entry.installedSha256) { throw 'Managed file changed; no changes made.' }
        if (Toggleable $entry.relative) {
            $destination=Target $State.gameDirectory $entry.relative
            if (-not $Enabled) { $destination+='.disabled' }
            if ($paths[0] -ne $destination) { $moves+=[pscustomobject]@{source=$paths[0];destination=$destination} }
        }
    }
    $done=@()
    try { foreach ($move in $moves) { Move-Item -LiteralPath $move.source -Destination $move.destination; $done+=$move } }
    catch { foreach ($move in @($done | Sort-Object source -Descending)) { Move-Item -LiteralPath $move.destination -Destination $move.source }; throw }
    $State.status='disabled'; if ($Enabled) { $State.status='installed' }; Save-State $State
}

try {
    if ($Action -eq 'Status') { if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath } else { Write-Output 'No installation record in this portable folder.' }; exit 0 }
    if ($Action -eq 'Detect') { Write-Output (Select-Game); exit 0 }
    $state=$null
    if (Test-Path -LiteralPath $statePath) { $state=Load-State }
    if ($Action -ne 'Install' -or ($state -and $state.status -in @('installed','disabled'))) {
        if (-not $state -or $state.status -notin @('installed','disabled','preparing','recovery-needed')) { throw 'No active installation record; use the folder that installed this pack.' }
        Assert-Stopped $state.gameDirectory
        if ($Action -eq 'Uninstall') { Restore-Initial $state; $state.status='uninstalled'; Save-State $state }
        elseif ($state.status -in @('installed','disabled')) { Set-Enabled $state ($Action -ne 'Disable') }
        else { throw 'Interrupted installation: run Uninstall to restore its backups first.' }
    } else {
        if ($state -and $state.status -in @('preparing','recovery-needed')) { throw 'Interrupted installation: run Uninstall first.' }
        $root=Select-Game
        Assert-Stopped $root
        $rootPrefix=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
        $bundleFull=[IO.Path]::GetFullPath($bundleRoot).TrimEnd('\')
        if ($bundleFull -eq $root.TrimEnd('\') -or $bundleFull.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Extract the portable ZIP outside the game folder.' }
        if ((Digest (Join-Path $root 'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe')) -ne $package.retailExeSha256) { throw 'Unsupported game version. Only the documented Steam retail EXE is accepted.' }
        foreach ($relative in $allowed) {
            if (-not $package.files.PSObject.Properties[$relative]) { throw 'Package manifest is incomplete.' }
            if ((Digest (Join-Path (Join-Path $bundleRoot 'payload') ([IO.Path]::GetFileName($relative)))) -ne $package.files.PSObject.Properties[$relative].Value) { throw 'Payload checksum mismatch; nothing installed.' }
            $paths=@(Variants $root $relative)
            if ($paths.Count -gt 1) { throw 'Both enabled and disabled copies exist; resolve before installing.' }
            if ($paths.Count -and ((Get-Item -LiteralPath $paths[0]).Attributes -band [IO.FileAttributes]::ReadOnly)) { throw 'A managed file is read-only; no changes made.' }
            if ($paths.Count -eq 1 -and -not $relative.EndsWith('.toml')) {
                $known=@($package.acceptedExisting.PSObject.Properties[$relative].Value)
                if ($known -notcontains (Digest $paths[0])) { throw "Conflicting existing file; nothing installed: $relative" }
            }
        }
        $backupRoot='.ffrs-terminology-backups/'+[Guid]::NewGuid().ToString('N')
        $entries=@()
        foreach ($relative in $allowed) {
            $paths=@(Variants $root $relative); $variant='absent'; $oldHash=$null
            $backup=$backupRoot+'/'+$relative
            if ($paths.Count) {
                $variant='enabled'; if ($paths[0].EndsWith('.disabled')) { $variant='disabled' }
                $oldHash=Digest $paths[0]; Copy-Safe $paths[0] (Backup-Path $backup)
            }
            $installedHash=$package.files.PSObject.Properties[$relative].Value
            if ($paths.Count -and $relative.EndsWith('.toml')) { $installedHash=$oldHash }
            $entries+=[pscustomobject]@{relative=$relative;originalVariant=$variant;originalSha256=$oldHash;backup=$backup;installedSha256=$installedHash}
        }
        $state=[pscustomobject]@{version=$package.version;machineKey=(Machine-Key);gameDirectory=$root;status='preparing';created=(Get-Date).ToString('o');files=$entries}
        Save-State $state
        try {
            Assert-Stopped $root
            foreach ($entry in $entries) {
                $target=Target $root $entry.relative
                if (-not ($entry.originalVariant -ne 'absent' -and $entry.relative.EndsWith('.toml'))) { Copy-Safe (Join-Path (Join-Path $bundleRoot 'payload') ([IO.Path]::GetFileName($entry.relative))) $target }
                if ((Digest $target) -ne $entry.installedSha256) { throw 'Installed file checksum mismatch.' }
                if ($entry.originalVariant -eq 'disabled') { Remove-Item -LiteralPath ($target+'.disabled') }
            }
            $state.status='installed'; Save-State $state
        } catch {
            $cause=$_
            try { Restore-Initial $state; $state.status='rolled-back'; Save-State $state }
            catch { $state.status='recovery-needed'; Save-State $state; throw 'Restore failed. Keep this portable folder and its backups for recovery.' }
            throw $cause
        }
    }
    Write-Output ("{0}: {1}" -f $state.status,$state.gameDirectory)
    Write-Output 'Keep this portable folder for Disable/Enable/Uninstall. Select Simplified Chinese in game for the text changes.'
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
