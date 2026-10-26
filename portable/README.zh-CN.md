# FFRS 简体中文 Flare 译名补丁 0.1.0

只修改简体中文中对应 Flare 的“火光”译名，共 9 个文本条目：

- 火光 → 核爆（两个技能条目）
- 百万火光 → 百万核爆（两个技能条目）
- 火光剑 → 核爆剑
- 3级火光 → 3级核爆
- 对应对白、技能说明中的三处引用同步替换

两处普通火光描写不修改。Flare Star 原译“耀星”也不在本次范围内。
完整条目列表见 changes.json。其他 26,716 个文本条目不变；繁体中文及其他语言不变。

## 安装

退出正式版，双击 Install.cmd，输入 Steam 游戏根目录，例如：
`D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE`

正常从 Steam 启动并使用简体中文。无需编译、额外 DLL 或 FFR Modding Tools。
只新增以下独立文件，不修改游戏原始 EXE、Pak、存档或宽屏补丁：
`FFRS\Content\Paks\~mods\FFRS-FlareZhHans_99_P.pak`

也可以手动将 payload 中的单个 Pak 复制到该目录。
仅支持已核对的 Steam 正式版 build 24250053；安装器会检查 EXE 哈希。
不建议与其他修改简体 Game.locres 的翻译包同时使用，因为会覆盖同一资源。

## 卸载

退出游戏后双击 Uninstall.cmd 并输入同一游戏根目录。
也可只删除 `FFRS-FlareZhHans_99_P.pak`，不要删除游戏自己的包或其他 MOD。

## 验证范围

已核对中、英、日文的相同文本键；保留所有键、源文本哈希及未修改译文。
已完成 Locres 解析、零修改字节级往返、全部条目差异检查，以及新 Pak 提取验证。
游戏中的显示效果仍需启动后确认；构建成功不代表已经看到实际文字替换。
