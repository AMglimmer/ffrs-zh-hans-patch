# FFRS terminology adjustments (zh-Hans only)

This independent text overlay changes 34 explicitly reviewed localization
entries: nine Flare entries (火光 → 核爆) and 25 Moogle entries containing 39
occurrences of 莫古利 → 莫古力. It does not modify the ultrawide project or original game archives.
Original extracted game resources are kept outside this source directory.

Build with Python 3 and [repak](https://github.com/trumank/repak):

```powershell
python build.py --repak path/to/repak.exe --retoc path/to/retoc.exe --pak "path/to/FFRS-Windows.pak" --output path/to/new-package-folder
```

The builder validates the original resource hash, patches only approved keys,
preserves source hashes and string encodings, verifies every unchanged entry,
and packs a single localization resource in a separate V11 Pak. No encrypted
archives, executable offsets, game hooks or memory writes are required.

The Locres version 3 layout was cross-checked against the primary tool/source
references [UnrealLocres](https://github.com/akintos/UnrealLocres) and
[CUE4Parse](https://github.com/FabianFG/CUE4Parse).

Only the existing locally installed Steam build 24250053 is supported. Do not
commit or redistribute extracted original localization tables or crash/save data.

Version 0.2.1 corrects the missing IoStore companions in 0.2.0. The retail
loader requires a matching UToc; standalone Pak was not mounted. The Locres
remains in the Pak; retoc UE5_6 generates a separate empty asset container
(header only, zero packages). Only its UToc/UCas are retained, never its empty Pak.
See https://github.com/trumank/retoc for the companion generator.
Runtime display confirmation is still required after installation/restart.
