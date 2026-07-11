# Changelog

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
