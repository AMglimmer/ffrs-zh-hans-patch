param(
    [Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Action,
    [string]$GameDirectory
)
$ErrorActionPreference='Stop'
function Get-PatchHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path);$algorithm=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose();$algorithm.Dispose() }
}
function Copy-Verified([string]$Source,[string]$Destination) {
    $temporary=$Destination+'.install-tmp'
    if(Test-Path -LiteralPath $temporary){throw 'Temporary file already exists.'}
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary
        if((Get-PatchHash $temporary) -ne (Get-PatchHash $Source)){throw 'Copy verification failed.'}
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } finally { if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary} }
}
try {
    if(-not $GameDirectory){$GameDirectory=Read-Host 'Steam retail game root folder'}
    $gameRoot=(Resolve-Path -LiteralPath $GameDirectory.Trim().Trim('"')).Path
    $metadata=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json
    $exe=Join-Path $gameRoot 'FFRS\Binaries\Win64\FFRS-Win64-Shipping.exe'
    if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Choose the Steam retail game root folder.'}
    if($gameRoot -match '(?i)RESONANCE DEMO(?:\\|$)'){throw 'The Demo is not supported.'}
    if($Action -eq 'Install' -and (Get-PatchHash $exe) -ne $metadata.supported_retail_exe_sha256){throw 'Unsupported game EXE.'}
    $running=@(Get-CimInstance Win32_Process -Filter "Name='FFRS-Win64-Shipping.exe'" | Where-Object {-not $_.ExecutablePath -or $_.ExecutablePath -eq $exe})
    if($running.Count){throw 'Exit the retail game before changing text patch files.'}
    $names=@('FFRS-FlareZhHans_99_P.pak','FFRS-FlareZhHans_99_P.utoc','FFRS-FlareZhHans_99_P.ucas')
    if(@($metadata.files.PSObject.Properties).Count -ne 3){throw 'Invalid payload manifest.'}
    $folder=Join-Path $gameRoot 'FFRS\Content\Paks\~mods'
    $entries=@()
    foreach($name in $names){
        $property=$metadata.files.PSObject.Properties[$name]
        if(-not $property){throw 'Incomplete payload manifest.'}
        $source=Join-Path (Join-Path $PSScriptRoot 'payload') $name
        if($Action -eq 'Install' -and (Get-PatchHash $source) -ne $property.Value){throw 'Payload hash mismatch.'}
        $destination=Join-Path $folder $name
        $oldHash=$null
        if(Test-Path -LiteralPath $destination){
            if((Get-Item -LiteralPath $destination).Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::ReadOnly)){throw 'Linked or read-only mod file.'}
            $oldHash=Get-PatchHash $destination
            if($oldHash -ne $property.Value -and -not($Action -eq 'Install' -and $name.EndsWith('.pak') -and @($metadata.upgrade_from_pak_sha256) -contains $oldHash)){throw 'Conflicting existing mod file; no changes made.'}
        }
        $entries+=[pscustomobject]@{name=$name;source=$source;destination=$destination;oldHash=$oldHash;backup=$null}
    }
    # Preserve every existing file before any mutation; rollback handles all three.
    $backupFolder=Join-Path $PSScriptRoot 'backups'
    foreach($entry in $entries){
        if($entry.oldHash){
            New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
            $entry.backup=Join-Path $backupFolder ($entry.oldHash+'-'+$entry.name)
            if(-not(Test-Path -LiteralPath $entry.backup)){Copy-Item -LiteralPath $entry.destination -Destination $entry.backup}
            if((Get-PatchHash $entry.backup) -ne $entry.oldHash){throw 'Backup verification failed.'}
        }
    }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $changed=@()
    try {
        foreach($entry in $entries){
            if($Action -eq 'Install'){Copy-Verified $entry.source $entry.destination;$changed+=$entry}
            elseif(Test-Path -LiteralPath $entry.destination){Remove-Item -LiteralPath $entry.destination;$changed+=$entry}
        }
    } catch {
        $cause=$_
        foreach($entry in $changed){
            if($entry.backup){Copy-Verified $entry.backup $entry.destination}
            elseif(Test-Path -LiteralPath $entry.destination){Remove-Item -LiteralPath $entry.destination}
        }
        throw $cause
    }
    Write-Host ($Action+': '+$folder)
    Write-Host 'Three companion files are managed together. Start through Steam with Simplified Chinese.'
} catch {Write-Error $_ -ErrorAction Continue;exit 1}
