# Changelog

## v0.4.0

### 中文

#### 功能

- 新增忽略应用和命令行进程的功能，并可从菜单中恢复单个或全部已忽略项目。
- 启动时静默检查 Sparkle 更新；发现新版本后通过菜单提示，不会主动弹出更新窗口。
- 新增完整的繁体中文本地化支持。

#### 优化

- 重新整理菜单分区、进程和端口计数以及进程终止相关文案。
- 完善非官方 Homebrew tap 的信任、安装、升级和故障排查说明。

### English

#### Features

- Added persistent controls for ignoring applications and command-line processes, with options to restore individual or all ignored items from the menu.
- Added a silent Sparkle update check at launch; the menu indicates when a new version is available without presenting an update window automatically.
- Added complete Traditional Chinese localization.

#### Improvements

- Refined menu grouping, process and port counts, and process termination copy.
- Expanded guidance for trusting, installing, upgrading, and troubleshooting the third-party Homebrew tap.

## v0.3.0

### 中文

#### 功能

- 新增登录后自动启动设置，可在菜单中直接启用或关闭。
- 当 macOS 需要用户批准登录项时，可直接打开系统登录项设置。
- 新增 GitHub 仓库入口，方便从菜单访问项目主页。

#### 优化

- 更新应用截图和下载体积说明。
- 改进发布工作流，支持重试已有标签，并升级 macOS 与 Xcode 构建环境。

### English

#### Features

- Added a launch-at-login setting that can be enabled or disabled directly from the menu.
- Added a direct link to macOS Login Items settings when user approval is required.
- Added a GitHub repository link for opening the project page from the menu.

#### Improvements

- Updated app screenshots and download size documentation.
- Improved the release workflow with existing-tag retries and updated macOS and Xcode build environments.

## v0.2.0

### 中文

#### 功能

- 新增自动刷新设置，支持关闭或选择 1、2、5 秒刷新间隔，并持久保存用户选择。
- 新增退出和强制退出应用的操作，可直接处理占用多个监听端口的应用。
- 新增进程内存占用、来源应用、可执行文件路径等详细信息。
- 新增在 Finder 中显示文件、复制文件路径等快捷操作。

#### 优化

- 打开菜单时自动刷新端口列表，减少过期状态。
- 改进进程复制、终止操作的反馈、菜单标签和 PID 展示。
- 优化技术信息排版、相对时间显示、应用图标和菜单栏图标。
- 完善中英文 README、安装指引和明暗主题截图。

#### 修复

- 修复自动刷新期间可能发生的菜单崩溃。
- 修复 Apple 系统进程路径分类不正确的问题。
- 修复快速刷新时可能出现的陈旧操作和复制内容问题。

### English

#### Features

- Added configurable automatic refresh intervals: Off, 1, 2, or 5 seconds, with persistent preferences.
- Added Quit and Force Quit actions for applications that own listening ports.
- Added process memory usage, source application, executable path, and other process details.
- Added Finder reveal and file path copy actions.

#### Improvements

- Refresh the port list whenever the menu opens to reduce stale results.
- Improved feedback, menu labels, PID visibility, and process copy and termination actions.
- Refined technical text styling, relative date formatting, app icon, and menu bar icon.
- Improved English and Chinese documentation, installation guidance, and theme-aware screenshots.

#### Fixes

- Fixed a menu crash that could occur during automatic refresh.
- Fixed incorrect classification of Apple system process paths.
- Fixed stale actions and copied values during rapid port refreshes.

## v0.1.0

### 中文

- 首个 ListenBar 发布版本。
- 支持在菜单栏查看本机监听端口，并按 macOS 应用或进程分组。
- 支持打开 localhost、复制 URL/PID/lsof 命令。
- 支持安全终止或强制终止占用端口的进程，并对高风险目标显示确认。
- 新增 Sparkle 更新检查和 GitHub Release 发布链路。

### English

- Initial ListenBar release.
- View local listening ports from the menu bar, grouped by macOS app or process.
- Open localhost, copy URLs, copy PIDs, and copy lsof commands.
- Quit or force kill processes that own ports, with confirmations for risky targets.
- Added Sparkle update checking and GitHub Release automation.
