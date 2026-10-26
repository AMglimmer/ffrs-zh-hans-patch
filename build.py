"""Build a separate zh-Hans localization overlay from the user's installed game."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from locres_v3 import Locres

ROOT = Path(__file__).resolve().parent
def sha(data): return hashlib.sha256(data).hexdigest()

def build(args):
    config = json.loads((ROOT / 'changes.json').read_text(encoding='utf-8'))
    target = args.output.resolve()
    if target.exists(): raise ValueError('Output folder already exists; use a new staging directory')
    original = subprocess.check_output([str(args.repak.resolve()), 'get', str(args.pak.resolve()), config['resource']])
    if sha(original) != config['original_resource_sha256']:
        raise ValueError('Unsupported original localization resource')
    source = Locres(original)
    replacements = {}
    for change in config['changes']:
        key = (change['namespace'], change['key'])
        entry = source.by_key[key]
        if source.text(entry) != change['old'] or f'{entry.source_hash:08x}' != change['source_hash']:
            raise ValueError('Expected text/source hash did not match')
        replacements[key] = change['new']
    patched = source.patch(replacements)
    decoded = Locres(patched)
    changed = [key for key in source.by_key if source.text(source.by_key[key]) != decoded.text(decoded.by_key[key])]
    if set(changed) != set(replacements): raise ValueError('Unexpected localization changes')
    if len(source.entries) != len(decoded.entries): raise ValueError('Entry count changed')
    target.mkdir(parents=True)
    payload = target / 'payload'; payload.mkdir()
    pak = payload / config['pak_filename']
    with tempfile.TemporaryDirectory(prefix='ffrs-flare-build-') as temporary:
        staging = Path(temporary)
        resource = staging / config['resource']; resource.parent.mkdir(parents=True)
        resource.write_bytes(patched)
        subprocess.run([str(args.repak.resolve()), 'pack', '--version', 'V11', '--mount-point', '../../../', str(staging), str(pak)], check=True)
    listing = subprocess.check_output([str(args.repak.resolve()), 'list', str(pak)], text=True).splitlines()
    if listing != [config['resource']]: raise ValueError('Unexpected PAK contents')
    extracted = subprocess.check_output([str(args.repak.resolve()), 'get', str(pak), config['resource']])
    if extracted != patched: raise ValueError('PAK extraction round-trip mismatch')
    for path in (ROOT / 'portable').iterdir():
        if path.is_file():
            if path.suffix in ('.cmd', '.ps1'):
                (target / path.name).write_bytes(path.read_text(encoding='utf-8').replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))
            else: shutil.copy2(path, target / path.name)
    manifest = {k: config[k] for k in ['version','culture','resource','original_resource_sha256','supported_retail_exe_sha256','pak_filename','upgrade_from_pak_sha256'] if k in config}
    manifest.update({'pak_sha256':sha(pak.read_bytes()), 'patched_resource_sha256':sha(patched), 'total_entries':len(source.entries), 'changed_entries':len(changed), 'unchanged_entries':len(source.entries)-len(changed)})
    (target / 'package.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    (target / 'changes.json').write_text(json.dumps(config['changes'],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(manifest,indent=2))

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repak', type=Path, required=True)
    p.add_argument('--pak', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    build(p.parse_args())
