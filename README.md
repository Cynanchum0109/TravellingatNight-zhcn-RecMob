# 《入夜狂飙》Demo 简体中文补丁

Travelling at Night (Demo) 的简体中文汉化补丁，由 **Reckoner Mob 汉化组** 制作。

**下载：[Releases](../../releases) 页面取最新的 zip。**

反馈 QQ 群：**815655398**

---

## 安装

1. 完全退出游戏。
2. 下载 zip 并解压。
3. 双击里面的 **「【双击安装】夜游漫记汉化.cmd」**。

安装器会自己从 Steam 的库记录里找到游戏目录，成功或失败都会弹窗提示。

自动定位失败时（非 Steam 版、Steam 装在不常见的位置、装了多份游戏），
把解压出来的整个文件夹放进游戏目录再双击安装 —— 放对的标志是，
这个文件夹的上一级能看到 `travelling.exe`。

没有 PowerShell 的电脑，看包内的《【没有PowerShell请看】手动安装说明.txt》。

## 卸载

完全退出游戏，双击 **「【双击卸载】夜游漫记汉化.cmd」**。

卸载器按安装记录删除本包文件、还原安装时备份的同名文件，并清理自己新建的空文件夹。
你手动改过的文件会保留，不会被删。

## 说明

- **不修改游戏任何原始文件**，走 BepInEx 运行时注入。
- Steam 的「验证游戏文件完整性」不会破坏本补丁。
- 完全离线，不联网、不调用任何在线翻译接口。
- 游戏内没有语言开关，装上即中文。

## 游戏内快捷键

| 按键 | 作用 |
|---|---|
| `ALT + R` | 重新载入翻译文件 |
| `ALT + T` | 在译文与原文之间切换 |

## 换字体

包内自带霞鹜文楷。想换别的，把字体包放进游戏根目录，
再编辑 `BepInEx\config\AutoTranslatorConfig.ini` 的这一行，改成该文件名，重启游戏：

```ini
FallbackFontTextMeshPro=lxgwwenkai_6000
```

## 遇到问题

带上**截图**到 QQ 群反馈，说明是在哪个界面看到的。

## 授权与致谢

- 翻译基于 [Paratranz](https://paratranz.cn/) 项目协作完成。
- 本补丁包含 [BepInEx](https://github.com/BepInEx/BepInEx) 与
  [XUnity.AutoTranslator](https://github.com/bbepis/XUnity.AutoTranslator)，均为开源可再分发组件。
- 字体为[霞鹜文楷](https://github.com/lxgw/LxgwWenKai)，SIL Open Font License。
- 游戏本体版权归 Weather Factory 所有；本补丁不包含任何游戏原始文件。
