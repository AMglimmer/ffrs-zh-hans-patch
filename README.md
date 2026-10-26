# FFRS Flare → 核爆 (zh-Hans only)

This independent text overlay changes nine explicitly reviewed localization
entries. It does not modify the ultrawide project or original game archives.
Original extracted game resources are kept outside this source directory.

Build with Python 3 and [repak](https://github.com/trumank/repak):

```powershell
python build.py --repak path/to/repak.exe --pak "path/to/FFRS-Windows.pak" --output path/to/new-package-folder
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
