"""Run the shipped PowerShell installer against temporary fake game folders."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def quote(p): return "'" + str(p).replace("'", "''") + "'"

package = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='ffrs-flare-deploy-') as temporary:
    root = Path(temporary)
    def fixture(name):
        folder = root / name; folder.mkdir()
        bundle = folder / 'bundle'; shutil.copytree(package,bundle)
        game = folder / 'game'
        exe = game / 'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe'
        exe.parent.mkdir(parents=True); exe.write_bytes(b'RETAIL TEST FIXTURE; NEVER EXECUTED')
        paks = game / 'FFRS/Content/Paks'; paks.mkdir(parents=True)
        (paks/'FFRS-Windows.pak').write_bytes(b'ORIGINAL GAME ARCHIVE')
        mods=paks/'~mods';mods.mkdir();(mods/'OtherMod.pak').write_bytes(b'OTHER MOD')
        meta=json.loads((bundle/'package.json').read_text());meta['supported_retail_exe_sha256']=sha(exe)
        (bundle/'package.json').write_text(json.dumps(meta))
        return bundle,game,exe,mods/meta['pak_filename']
    def invoke(bundle,game,action,expected=0,running=False,fail_destination=None):
        exe=game/'FFRS/Binaries/Win64/FFRS-Win64-Shipping.exe'
        mocked="function Get-CimInstance { param($ClassName,$Filter) " + ("[pscustomobject]@{ExecutablePath="+quote(exe)+"}" if running else "") + " }; "
        injection=''
        if fail_destination:
            injection="$script:failed=$false; function Move-Item { param($LiteralPath,$Destination,[switch]$Force); if ($Destination -eq "+quote(fail_destination)+" -and -not $script:failed) { $script:failed=$true; throw 'Injected move failure' }; Microsoft.PowerShell.Management\\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force }; "
        command=mocked+injection+'& '+quote(bundle/'Manage-Patch.ps1')+' -Action '+action+' -GameDirectory '+quote(game)
        result=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-Command',command],capture_output=True,text=True,timeout=30)
        if result.returncode!=expected:raise AssertionError(result.stdout+'\n'+result.stderr)
        assert (game/'FFRS/Content/Paks/FFRS-Windows.pak').read_bytes()==b'ORIGINAL GAME ARCHIVE'
        assert (game/'FFRS/Content/Paks/~mods/OtherMod.pak').read_bytes()==b'OTHER MOD'
    bundle,game,exe,mod=fixture('lifecycle')
    invoke(bundle,game,'Install');assert all(mod.with_suffix(ext).exists() for ext in ['.pak','.utoc','.ucas'])
    invoke(bundle,game,'Install');exe.write_bytes(b'GAME UPDATED')
    invoke(bundle,game,'Uninstall');assert all(not mod.with_suffix(ext).exists() for ext in ['.pak','.utoc','.ucas'])
    bundle,game,exe,mod=fixture('unknown-version');exe.write_bytes(b'UNKNOWN')
    invoke(bundle,game,'Install',1);assert not mod.exists()
    bundle,game,exe,mod=fixture('foreign-file');mod.write_bytes(b'FOREIGN')
    invoke(bundle,game,'Install',1);invoke(bundle,game,'Uninstall',1);assert mod.read_bytes()==b'FOREIGN'
    bundle,game,exe,mod=fixture('running')
    invoke(bundle,game,'Install',1,running=True);assert not mod.exists()
    bundle,game,exe,mod=fixture('corrupt-payload')
    next((bundle/'payload').glob('*.pak')).write_bytes(b'CORRUPT')
    invoke(bundle,game,'Install',1);assert not mod.exists()
    for extension in ['.utoc','.ucas']:
        bundle,game,exe,mod=fixture('foreign-'+extension[1:]);mod.with_suffix(extension).write_bytes(b'FOREIGN COMPANION')
        invoke(bundle,game,'Install',1);assert not mod.exists() and mod.with_suffix(extension).read_bytes()==b'FOREIGN COMPANION'
        bundle,game,exe,mod=fixture('corrupt-'+extension[1:]);next((bundle/'payload').glob('*'+extension)).write_bytes(b'CORRUPT COMPANION')
        invoke(bundle,game,'Install',1);assert not mod.exists()
    bundle,game,exe,mod=fixture('companion-rollback')
    invoke(bundle,game,'Install',1,fail_destination=mod.with_suffix('.ucas'))
    assert all(not mod.with_suffix(ext).exists() for ext in ['.pak','.utoc','.ucas'])
    checks=['companion conflict/corruption and third-file rollback','install/idempotence/uninstall after game update','unknown build rejected','foreign file preserved','running game rejected','corrupt payload rejected']
    if len(sys.argv)>2:
        previous=Path(sys.argv[2]).resolve()
        bundle,game,exe,mod=fixture('known-upgrade')
        old=next((previous/'payload').glob('*.pak')).read_bytes();mod.write_bytes(old)
        invoke(bundle,game,'Install')
        assert mod.read_bytes()==next((bundle/'payload').glob('*.pak')).read_bytes()
        assert any(p.read_bytes()==old for p in (bundle/'backups').glob('*.pak'))
        invoke(bundle,game,'Uninstall');assert all(not mod.with_suffix(ext).exists() for ext in ['.pak','.utoc','.ucas'])
        checks.append('verified previous version backed up and upgraded')
print(json.dumps({'passed_groups':len(checks),'checks':checks,'original_archives_and_other_mods':'unchanged'}))
