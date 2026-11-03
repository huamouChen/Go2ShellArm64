# Go2Shell (Apple Silicon 原生版)

Go2Shell 的 Swift 重写版本，原生支持 Apple Silicon（arm64），不依赖 Rosetta 2。
功能与原版一致：在 Finder 工具栏放一个按钮，点击后在当前 Finder 窗口所在目录打开终端。

> 本项目为独立实现，与原软件作者无关；沿用原版 Bundle ID（`com.zipzapmac.Go2Shell`）以便复用原有偏好设置。

## 下载安装

1. 下载 `Go2Shell-2.5-arm64.dmg`。
2. 打开 dmg，把 `Go2Shell.app` 拖入 `Applications`。
3. 首次打开会因 ad-hoc 签名被 Gatekeeper 拦截，任选其一：
   - 右键点击应用 → 打开；
   - 或在终端执行：`xattr -dr com.apple.quarantine /Applications/Go2Shell.app`

## 使用

1. 启动 `Go2Shell.app`，在偏好设置中选择终端（Terminal / iTerm2 / xterm）并设置命令模板。
2. 点击 “Install to Finder Toolbar”，程序会把 Helper 装到 Finder 工具栏。
3. 之后在任意 Finder 窗口点击工具栏图标，即可在该目录打开终端。

支持的终端：Terminal、iTerm2、iTerm、xterm（需安装 X11）。命令模板用 `%PATH%` 占位当前目录。

默认配置（与原版兼容）：

| 键 | 默认值 |
| --- | --- |
| Terminal Identifier | `com.apple.Terminal` |
| Terminal Command | `cd %PATH%; clear; pwd` |
| Use Window | `true` |

## 从源码构建

依赖：Xcode Command Line Tools（`xcode-select --install`）。

```bash
./build.sh      # 编译并组装 build/Go2Shell.app
./make-dmg.sh   # 编译并生成 Go2Shell-2.5-arm64.dmg
```

产物为 arm64 单架构、ad-hoc 签名，未做 Apple 公证。

## 目录结构

```
Sources/Go2Shell.swift        配置界面 + Finder 工具栏安装
Sources/Go2ShellHelper.swift  被工具栏调用的 Helper，负责定位目录并启动终端
Info.plist                    主程序 Info.plist
HelperInfo.plist              Helper Info.plist
Resources/Icon.icns           应用图标
Resources/moj.icns            Helper 图标
build.sh                      构建脚本
make-dmg.sh                   打包脚本
```

## 已知限制

- Finder 工具栏属于 Finder 私有机制，通过修改 `com.apple.finder` 的 `FXTaskbarApplications` 实现，macOS 大版本升级后可能需要重新安装。
- 首次读取 Finder 目录需要授予自动化权限。
- 如需分发给他人，建议使用开发者证书签名并公证。
