<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/AppIcon/Previews/listenbar-icon-dark.png">
    <img src="Design/AppIcon/Previews/listenbar-icon-default.png" width="160" alt="ListenBar App 图标">
  </picture>
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
- 🙈 **忽略持续干扰项。** 可按稳定的 App 或可执行文件身份忽略监听项，并从菜单恢复单个或全部已忽略项目。
- 🔄 **让列表保持最新。** 默认在打开菜单时刷新，也可选择每 1、2、5 秒自动刷新、关闭自动刷新，或通过 Sparkle 手动检查更新。
- 🚀 **登录后自动启动。** 可让 ListenBar 在登录 macOS 后自动运行；需要用户批准时，可直接打开系统登录项设置。

## 🪶 原生与轻量

- 🍎 **真正原生。** ListenBar 的 App 业务代码 100% 使用 Swift 编写，并采用 SwiftUI 和 The Composable Architecture（TCA）架构。它基于 `MenuBarExtra` 与 `LSUIElement` 构建，不包含 Electron 运行时，也没有嵌入 WebView。
- 🪶 **超轻量软件。** ListenBar 专注于检查本机监听端口，无需附带完整的浏览器引擎。
- 🎨 **自然融入 macOS。** 界面会自动适配浅色与暗色模式。在 macOS 26 上，原生 SwiftUI 菜单控件会在适用位置呈现系统提供的 Liquid Glass 外观；macOS 14 与 macOS 15 则保持各自的原生系统样式。ListenBar 不使用自定义视觉效果模拟 Liquid Glass，发布版本使用 Xcode 26.2 构建。

## 📦 安装

### 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon 或 Intel Mac（Universal Binary）

### Homebrew

`brew trust` 命令首次随 Homebrew 5.1.15 于 2026 年 6 月 3 日发布。在 Homebrew 5.1.15–5.x 中，只有设置了 `HOMEBREW_REQUIRE_TAP_TRUST=1` 才会要求信任。从 2026 年 6 月 11 日发布的 Homebrew 6.0.0 开始，默认要求显式信任非官方 tap 中的 cask。

```bash
brew tap ygsgdbd/tap
brew trust --cask ygsgdbd/tap/listenbar
brew install --cask listenbar
```

这只会信任 `listenbar` cask，不会信任整个 tap。Homebrew 会保存信任记录，因此通常只需执行一次 trust 命令。详情请参阅 Homebrew 官方的 [Tap Trust 文档](https://docs.brew.sh/Tap-Trust)。

Homebrew 5.1.14 及更早版本没有 `brew trust`，也不需要执行该命令：

```bash
brew tap ygsgdbd/tap
brew install --cask listenbar
```

如果执行 `brew trust` 时出现 `Unknown command: trust`，请跳过该命令，或运行 `brew update` 升级 Homebrew。

Homebrew 安装版使用以下命令更新：

```bash
brew upgrade listenbar
```

#### Tap Trust 故障排查

- 如果 Homebrew 提示 `Refusing to load cask ... from untrusted tap`，请执行 `brew trust --cask ygsgdbd/tap/listenbar`，然后重新安装或升级。
- 如果 `brew doctor` 报告 `ygsgdbd/tap` 未受信任，只需使用上述命令信任 ListenBar cask，不需要信任整个 tap。
- 如果已有安装在 Homebrew 升级到 6.0.0 或更高版本后无法更新，请先信任该 cask，再重试 `brew upgrade listenbar`。
- 如果确实希望信任 tap 中所有当前及未来的 formula、cask 和 external command，可以使用 `brew trust ygsgdbd/tap`。该命令授权范围更大，不作为推荐方案。

### GitHub Releases

1. 从[最新 GitHub Release](https://github.com/ygsgdbd/ListenBar/releases/latest) 下载 `ListenBar-macOS-universal.zip`。
2. 解压后将 `ListenBar.app` 移动到 `/Applications`。

### 首次启动与 Gatekeeper

当前发布构建**没有签名，也没有经过 notarization（公证）**。因此，即使 App 来自官方发布页，macOS 也可能阻止首次启动。

1. 在 Finder 中按住 Control 点击或右键点击 `ListenBar.app`，选择**打开**，然后再次确认**打开**。
2. 如果仍被阻止，请打开**系统设置 → 隐私与安全性**，找到 ListenBar 相关提示，点击**仍要打开**，然后确认**打开**。

仅当 App 来自本仓库的官方 GitHub Releases 且你信任该下载内容时，才应绕过 Gatekeeper。

## 🧪 开发与测试

项目当前包含 **159 个 XCTest 测试方法**，覆盖 reducer 行为、配置持久化、监听项忽略身份与过滤、登录项管理、端口解析与分组、进程元数据、菜单呈现、截图 fixture 和 Sparkle 配置。

环境要求：Xcode 26、[Homebrew](https://brew.sh/)、[just](https://github.com/casey/just)、[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) 和 [Tuist](https://tuist.dev/)。

请手动安装开发工具，然后启用仓库管理的 Git hook：

```bash
brew install just swiftformat tuist
swiftformat --version # 必须为 0.62.1
just setup
just check
```

`just setup` 只检查已安装的工具并配置 `core.hooksPath`，不会安装或升级任何软件。如果 Homebrew 不再提供 SwiftFormat 0.62.1，请从[官方 Release](https://github.com/nicklockwood/SwiftFormat/releases/tag/0.62.1)手动安装该精确版本。

每次提交前，hook 会格式化已暂存的 Swift 文件。如果产生格式变化，本次提交会中止，便于你检查 diff、重新暂存并再次提交。对于部分暂存的 Swift 文件，hook 不会自动修改；请先暂存或 stash 其余改动，或手动运行 `just format`。运行 `just --list` 可以查看所有开发命令。

如需直接运行测试命令：

```bash
tuist generate --no-open
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
