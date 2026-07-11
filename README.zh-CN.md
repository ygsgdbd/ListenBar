<p align="center">
  <img src="Design/AppIcon/Previews/listenbar-icon-default.png" width="160" alt="ListenBar App 图标">
</p>

<h1 align="center">ListenBar</h1>

<p align="center">一款原生 macOS 菜单栏工具，快速查看 Mac 上正在监听端口的进程。</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-0D96F6">
  <img alt="TCA" src="https://img.shields.io/badge/Architecture-TCA-7C3AED">
  <img alt="Xcode 26" src="https://img.shields.io/badge/Xcode-26-147EFB?logo=xcode&logoColor=white">
  <img alt="Universal Binary" src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-555555">
  <a href="https://github.com/ygsgdbd/ListenBar/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/ygsgdbd/ListenBar?display_name=tag&sort=semver&label=Latest%20Release"></a>
</p>

<p align="center">🇨🇳 <strong>简体中文</strong> · 🇺🇸 <a href="README.md">English</a></p>

## 🖼️ 界面截图

![ListenBar 浅色模式主菜单和进程操作](Documentation/Screenshots/zh-Hans-light.png#gh-light-mode-only)

![ListenBar 暗色模式主菜单和进程操作](Documentation/Screenshots/zh-Hans-dark.png#gh-dark-mode-only)

## ✨ 功能亮点

- 🔎 **快速发现监听端口。** 扫描 TCP `LISTEN` 端点和具有明确本地端口的 UDP socket，并在可获取时展示地址暴露范围、协议、端口、PID、进程或 App 名称、可执行文件路径、启动命令、推断来源和常驻内存。
- 🧩 **看懂端口归属于谁。** 将相关辅助进程归入其所属的 macOS App，命令行监听进程则按 PID 清晰区分；同时区分当前用户进程与系统或其他用户进程。
- 🔗 **打开服务，复制所需信息。** 使用 `http://localhost:<port>` 打开符合条件的本机 TCP 服务，或复制 URL、端口、PID、路径、`lsof` 命令、进程详情和完整监听报告。
- 🔒 **更安全地分享诊断信息。** 可选择复制完整或脱敏后的启动命令，在需要时省略敏感参数。
- 🛠️ **检查并管理进程。** 可在 Finder 中显示可执行文件、查看原生 App 或可执行文件图标、正常或强制退出 App，以及对单个进程发送 `SIGTERM` 或 `SIGKILL`；破坏性或高风险操作会先请求确认。
- 🔄 **让列表保持最新。** 默认在打开菜单时刷新，也可选择每 1、2、5 秒自动刷新、关闭自动刷新，或通过 Sparkle 手动检查更新。

## 🪶 原生与轻量

- 🍎 **真正原生。** ListenBar 的 App 业务代码 100% 使用 Swift 编写，并采用 SwiftUI 和 The Composable Architecture（TCA）架构。它基于 `MenuBarExtra` 与 `LSUIElement` 构建，不包含 Electron 运行时，也没有嵌入 WebView。
- 🪶 **为轻量而设计。** 一个专注的菜单栏工具无需附带完整的浏览器引擎。ListenBar 将运行时和界面集中在检查本机监听端口这一件事上。
- 🎨 **自然融入 macOS。** 界面会自动适配浅色与暗色模式。在 macOS 26 上，原生 SwiftUI 菜单控件会在适用位置呈现系统提供的 Liquid Glass 外观；macOS 14 与 macOS 15 则保持各自的原生系统样式。ListenBar 不使用自定义视觉效果模拟 Liquid Glass，发布版本使用 Xcode 26.2 构建。

## 📦 安装

### 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac（Universal Binary）

### Homebrew

```bash
brew install --cask ygsgdbd/tap/listenbar
```

Homebrew 要求显式信任来自第三方 tap 的软件包。使用上述完整 cask 名称只会信任 `listenbar`，而不会信任 `ygsgdbd/tap` 中当前及未来的全部软件包。

### GitHub Releases

1. 从[最新 GitHub Release](https://github.com/ygsgdbd/ListenBar/releases/latest) 下载 `ListenBar-macOS-universal.zip`。
2. 解压后将 `ListenBar.app` 移动到 `/Applications`。

### 首次启动与 Gatekeeper

当前发布构建**没有签名，也没有经过 notarization（公证）**。因此，即使 App 来自官方发布页，macOS 也可能阻止首次启动。

1. 在 Finder 中按住 Control 点击或右键点击 `ListenBar.app`，选择**打开**，然后再次确认**打开**。
2. 如果仍被阻止，请打开**系统设置 → 隐私与安全性**，找到 ListenBar 相关提示，点击**仍要打开**，然后确认**打开**。

仅当 App 来自本仓库的官方 GitHub Releases 且你信任该下载内容时，才应绕过 Gatekeeper。

## 🧪 开发与测试

项目当前包含 **121 个 XCTest 测试方法**，覆盖 reducer 行为、配置持久化、端口解析与分组、进程元数据、菜单呈现、截图 fixture 和 Sparkle 配置。

环境要求：Xcode 26 和 [Tuist](https://tuist.dev/)。

```bash
tuist generate
xcodebuild test \
  -project ListenBar.xcodeproj \
  -scheme ListenBar \
  -destination 'platform=macOS' \
  -testLanguage zh-Hans \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```
