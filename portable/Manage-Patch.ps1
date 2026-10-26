param(
    [Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Action,
    [string]$GameDirectory
)
$ErrorActionPreference = 'Stop'
function Get-PatchHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
try {
    if (-not $GameDirectory) { $GameDirectory = Read-Host 'Steam retail game root folder' }
    $GameDirectory = $GameDirectory.Trim().Trim('"')
    $gameRoot = (Resolve-Path -LiteralPath $GameDirectory).Path
    $metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json
    $exe = Join-Path $gameRoot 'FFRS\Binaries\Win64\FFRS-Win64-Shipping.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Choose the Steam retail game root folder.' }
    if ($gameRoot -match '(?i)RESONANCE DEMO(?:\\|$)') { throw 'The Demo is not a target for this patch.' }
    if ($Action -eq 'Install' -and (Get-PatchHash $exe) -ne $metadata.supported_retail_exe_sha256) {
        throw 'Unsupported game EXE. The Demo and unverified game updates are not supported.'
    }
    $running = @(Get-CimInstance Win32_Process -Filter "Name='FFRS-Win64-Shipping.exe'" | Where-Object { -not $_.ExecutablePath -or $_.ExecutablePath -eq $exe })
    if ($running.Count) { throw 'Exit the retail game before installing or removing this text patch.' }
    if ($metadata.pak_filename -ne 'FFRS-FlareZhHans_99_P.pak') { throw 'Unexpected package filename.' }
    $source = Join-Path $PSScriptRoot ('payload\' + $metadata.pak_filename)
    $folder = Join-Path $gameRoot 'FFRS\Content\Paks\~mods'
    $destination = Join-Path $folder $metadata.pak_filename
    $previousHash = $null
    if (Test-Path -LiteralPath $destination) {
        $existingHash = Get-PatchHash $destination
        if ($existingHash -ne $metadata.pak_sha256) {
            if ($Action -eq 'Install' -and @($metadata.upgrade_from_pak_sha256) -contains $existingHash) {
                $previousHash = $existingHash
            } else {
                throw 'Existing mod file differs. Preserve it and resolve the conflict before continuing.'
            }
        }
    }
    if ($Action -eq 'Install') {
        if ((Get-PatchHash $source) -ne $metadata.pak_sha256) { throw 'Payload hash mismatch.' }
        $backup = $null
        if ($previousHash) {
            $backupFolder = Join-Path $PSScriptRoot 'backups'
            New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
            $backup = Join-Path $backupFolder ($previousHash + '-' + $metadata.pak_filename)
            if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $destination -Destination $backup }
            if ((Get-PatchHash $backup) -ne $previousHash) { throw 'Previous mod backup verification failed.' }
        }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $temporary = $destination + '.install-tmp'
        try {
            Copy-Item -LiteralPath $source -Destination $temporary -Force
            if ((Get-PatchHash $temporary) -ne $metadata.pak_sha256) { throw 'Copy verification failed.' }
            Move-Item -LiteralPath $temporary -Destination $destination -Force
        } catch {
            if ($backup) { Copy-Item -LiteralPath $backup -Destination $destination -Force }
            throw
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
        Write-Host 'Installed. Start through Steam and select Simplified Chinese.'
    } else {
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination }
        Write-Host 'Removed this text patch. Original game archives were not changed.'
    }
    Write-Host $destination
} catch {
    Write-Error $_
    exit 1
}
