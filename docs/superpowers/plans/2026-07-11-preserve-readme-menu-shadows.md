# Preserve README Menu Shadows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Regenerate ListenBar README screenshots with complete native menu shadows and equal 12pt outer spacing, without capturing the macOS menu bar.

**Architecture:** Replace rectangular screen capture with per-window `screencapture -l<windowID>` capture. The Swift helper returns each new menu window ID, its pixel-space content bounds, and back-to-front order; the shell script composites the transparent window captures at their real offsets on the controlled light or dark background.

**Tech Stack:** zsh, Swift/CoreGraphics, macOS `screencapture`, ImageMagick.

## Global Constraints

- Preserve the native window shadow; do not synthesize or blur a replacement.
- Add 12pt spacing outside the complete shadow on all four sides.
- Do not include the macOS menu bar, desktop, usernames, paths, or live process data.
- Keep the existing highest-physical-resolution display selection.
- Do not add dependencies or change Release behavior.

---

### Task 1: Add screenshot spacing regression validation

**Files:**
- Create: `script/validate_readme_screenshots.sh`

**Interfaces:**
- Consumes: the 8 PNG files in `Documentation/Screenshots/raw/`.
- Produces: exit status 0 only when the detected content/shadow bounds have equal outer margins.

- [ ] **Step 1: Add a validation script**

Use ImageMagick with each screenshot's known controlled background color, trim that background with a small fuzz tolerance, and compare the remaining top, left, right, and bottom margins. Fail when their difference exceeds two pixels.

- [ ] **Step 2: Run the validator against the current screenshots**

Run: `./script/validate_readme_screenshots.sh`

Expected: FAIL because the current top shadow is clipped and the top margin differs from the other sides.

### Task 2: Capture and compose native menu windows

**Files:**
- Modify: `script/readme_menu_windows.swift`
- Modify: `script/generate_readme_screenshots.sh`

**Interfaces:**
- `readme_menu_windows windows <snapshot-file> <display-id>` prints `windowID,x,y,width,height`, one window per line, in back-to-front order and in target-display pixel coordinates.
- `capture_visible_menus <output-path> <background-color>` captures each returned window with `screencapture -l`, preserves alpha and native shadow, composites real relative positions, and adds the final equal margin.

- [ ] **Step 1: Extend the Swift helper**

Add the `windows` command, reuse the existing window filtering, convert CoreGraphics point bounds to target-display pixels using `CGDisplayMode.pixelWidth/pixelHeight`, and print the filtered windows in back-to-front order.

- [ ] **Step 2: Replace rectangular capture**

Capture every returned window ID separately without `screencapture -o`. Derive each capture's shadow inset from the PNG size minus its content bounds, calculate the union of complete shadow images, and composite them on the controlled background with 12pt scaled padding.

- [ ] **Step 3: Regenerate all screenshots**

Run: `./script/generate_readme_screenshots.sh`

Expected: 8 raw screenshots and 4 README composites; log confirms use of the 3840x2160 display.

### Task 3: Verify behavior and project health

**Files:**
- Verify: `Documentation/Screenshots/raw/*.png`
- Verify: `Documentation/Screenshots/*.png`

**Interfaces:**
- Produces: validated screenshots and unchanged application behavior outside Debug README mode.

- [ ] **Step 1: Run screenshot validation**

Run: `./script/validate_readme_screenshots.sh`

Expected: PASS for all 8 raw screenshots.

- [ ] **Step 2: Visually inspect all four composites**

Confirm complete top/side/bottom shadows, equal spacing, correct theme and localization, correct submenu layering, and no menu bar or private desktop content.

- [ ] **Step 3: Run project verification**

Run the complete test suite, Release build, `git diff --check`, README image-link validation, and final worktree status inspection.

Expected: 109 or more tests pass, Release build exits 0, all README image links exist, and no whitespace errors are reported.
