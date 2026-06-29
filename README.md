# Claude Desktop Windows 简体中文汉化工具

这是 Windows 版 Claude Desktop 的简体中文本地汉化工具。

本项目不是 Claude 官方项目，也不包含 Claude 官方程序文件。使用前需要先安装官方 Windows 版 Claude Desktop。

## 怎么使用

1. 关闭正在运行的 Claude Desktop。
2. 双击 `一键安装汉化.cmd`。
3. 如果 Windows 弹出管理员权限确认，选择允许。
4. 等待脚本完成。
5. 从桌面或开始菜单的 `Claude zh-CN` 快捷方式启动。

汉化版默认安装到：

`%LOCALAPPDATA%\Programs\Claude-zh-CN`

不要移动这个目录里的 `WindowsApps`、`Claude_版本_x64__pzs8sxrjxfjjc`、`app` 等文件夹，否则 Cowork 可能会提示需要重新安装桌面应用。

## 文件说明

`一键安装汉化.cmd`

安装或重新安装简体中文汉化。

`恢复英文界面.cmd`

把 Claude 的语言偏好切回英文。它不是从备份恢复文件，只是切换界面语言。

`卸载汉化版.cmd`

删除本工具生成的汉化版 Claude 和快捷方式，不会卸载官方原版 Claude。

`修复Cowork工作区权限.cmd`

只在 Cowork / Code 工作区无法启动，并且报权限相关错误时使用。普通聊天、普通汉化安装不需要运行它。

`手动修改翻译.json`

手动修改翻译文件中有中英对照，觉得翻译的不对，或许想进一步进行翻译可自行修改后运行一键安装汉化.cmd进行覆盖即可。

`程序文件-不要改名`

汉化脚本和语言文件所在目录。不要改名，不要删除。

## 什么时候运行“修复Cowork工作区权限.cmd”

这个脚本不是一键汉化的必需步骤。只有在下面这种情况才需要运行：

- 你打开 `Cowork` 或 `Code` 时，提示无法启动 Claude 的工作区。
- 报错里出现 `HCS operation failed`。
- 报错里出现 `failed to start VM`。
- 报错里出现 `HRESULT 0x80070005`。
- 报错里出现 `rootfs.vhdx`、`拒绝访问`。
- 原版 Claude 打开 Cowork / Code 也出现类似工作区权限错误。

典型错误类似：

`HCS operation failed: failed to start VM ... 0x80070005 ... rootfs.vhdx ... 拒绝访问`

这通常是 Windows 虚拟机/容器工作区的文件权限问题，不是汉化文本本身导致的。这个脚本会给 Claude 工作区的虚拟磁盘目录补上 Windows 虚拟机账户权限。

使用方法：

1. 关闭 Claude。
2. 双击 `修复Cowork工作区权限.cmd`。
3. 如果 Windows 弹出管理员权限确认，选择允许。
4. 重新打开 `Claude zh-CN`。
5. 再试 Cowork 或 Code。

如果你只用普通聊天，不用 Cowork 和 Code，就不需要运行这个脚本。

## 自己修改翻译

打开 `手动修改翻译.json`，搜索你在界面里看到的中文或英文原文，只修改 `中文译文` 后面的内容。

修改后保存文件，再运行 `一键安装汉化.cmd`，重新打开 Claude 后生效。

## 关于原版 Claude

建议保留官方原版 Claude Desktop。这个工具会生成独立的汉化版运行目录，日常从 `Claude zh-CN` 快捷方式启动即可。

如果不想继续使用汉化版，运行 `卸载汉化版.cmd`。它只删除汉化版，不会删除官方 Claude。


## 免责声明

本项目与 Anthropic、Claude 官方没有关系。它只是本地汉化工具，Claude Desktop 更新后可能需要重新运行脚本或更新翻译文件。
