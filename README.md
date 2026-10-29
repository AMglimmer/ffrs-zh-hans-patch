# FFRS 简体术语统一补丁

FF14 国服译名优先的非官方社区 MOD，适用于已核对的 Steam 正式版 build 24250053 / Windows x64。0.3.0 共修订 178 条简体文本，其余 26,547 条不变。

项目主页：https://github.com/AMglimmer/ffrs-zh-hans-patch

普通玩家请到 Releases 下载 ZIP，完整解压、退出游戏，双击“一键安装.cmd”。纯译名包不包含运行时 DLL/ASI，不修改存档。

源码提供严格的 Locres v3 读写、精确文本键清单、构建脚本和可恢复安装器。不包含原始提取资源、完整其他语言表、个人存档或诊断转储。

## Build

Python 3, repak and retoc are needed only to build; end users only need Windows PowerShell.

```powershell
python build.py --repak path/to/repak.exe --retoc path/to/retoc.exe --pak "path/to/FFRS-Windows.pak" --output path/to/new-package-folder
python test_locres.py
python test_deploy.py path/to/new-package-folder
```

The builder validates the original resource hash, patches only approved keys, preserves source hashes and string encodings, verifies every unchanged entry, and produces a V11 localization Pak with matching empty UE5.6 IoStore companions. No game archive is overwritten.

The Locres layout was cross-checked with [UnrealLocres](https://github.com/akintos/UnrealLocres) and [CUE4Parse](https://github.com/FabianFG/CUE4Parse). Container tools: [repak](https://github.com/trumank/repak), [retoc](https://github.com/trumank/retoc). Terminology reference: [FFCAFE](https://strings.ffcafe.cn/).

Game text and assets retain their original owners' rights. This project is not affiliated with or endorsed by Square Enix or FFCAFE. Choosing FF14 terminology is a community preference, not a claim that other official translations are erroneous.
