# 鼠标脚本精灵

一个面向 macOS 的鼠标自动化桌面小工具，技术栈是 Tauri 2 + Next.js 16 + shadcn/ui。

当前版本已经具备：

- 定时自动点击：设置点击间隔、鼠标按键、重复次数。
- 鼠标脚本回放：按步骤执行移动、点击、等待、滚动。
- 鼠标行为录制：通过全局监听记录移动、点击、滚轮和等待动作。
- 脚本工作台 UI：时间线、脚本库、运行日志、右侧步骤检查器。
- macOS 打包：可生成 `.app` 和 `.dmg`。
- 应用内权限请求：可从右侧检查器主动触发 macOS 辅助功能授权弹窗。
- 自动化测试：提供 `pnpm test:ai` 给 Codex/CI 跑端到端工作流检查。

## 技术栈

- Tauri 2：桌面壳、Rust 后端命令、macOS 打包。
- Next.js 16 App Router：前端应用。
- shadcn/ui base-nova：基础 UI 组件。
- Tailwind CSS v4：样式系统。
- enigo：系统级鼠标输入模拟。
- rdev：系统级鼠标事件监听。

## 本地开发

安装依赖：

```bash
pnpm install
```

只跑前端：

```bash
pnpm dev
```

跑 Tauri 桌面应用：

```bash
pnpm desktop:dev
```

构建前端静态产物：

```bash
pnpm build
```

打包 macOS 应用：

```bash
pnpm desktop:build
```

自动化 agent 测试：

```bash
pnpm test:ai
```

打包产物会生成在：

```text
src-tauri/target/release/bundle/macos/
src-tauri/target/release/bundle/dmg/
```

## macOS 权限

真实鼠标点击和全局录制需要 macOS 辅助功能权限。

应用右侧检查器提供两个按钮：

- `请求授权`：在 Tauri 桌面模式下调用系统 API 发起 macOS 辅助功能授权请求。
- `重新检测`：重新读取当前进程是否已获得辅助功能权限。

开发模式下通常要给启动它的终端授权：

```text
系统设置 -> 隐私与安全性 -> 辅助功能 -> 允许 Terminal / iTerm / Codex 所在宿主
```

打包后运行 `.app`，则要给 `鼠标脚本精灵.app` 授权。

如果没有权限：

- `enigo` 可能无法真正移动或点击鼠标。
- `rdev` 在 macOS 上可能静默收不到全局事件。

## 代码结构

```text
src/app/page.tsx              主工作台界面和交互状态
src/app/globals.css           shadcn/Tailwind 主题
src/components/ui/            shadcn/ui 源码组件
src-tauri/src/lib.rs          Tauri 命令和鼠标自动化实现
src-tauri/tauri.conf.json     Tauri 窗口、构建、打包配置
```

## 当前命令

Rust 后端暴露的 Tauri 命令：

- `start_auto_click`
- `stop_auto_click`
- `start_recording`
- `stop_recording`
- `playback_script`
- `automation_status`
- `accessibility_permission_status`
- `request_accessibility_permission`

前端通过 `@tauri-apps/api/core` 的 `invoke` 调用这些命令；在普通浏览器预览时会退回到本地模拟状态，方便调 UI。

## 验证

常用检查：

```bash
pnpm lint
pnpm build
pnpm test:ai
cd src-tauri && cargo check
pnpm desktop:build
```

## 后续可做

- 脚本持久化：保存到 Tauri app data 目录。
- 热键：全局启动/停止快捷键。
- 权限检测：在 UI 中显示 macOS Accessibility 授权状态。
- 录制降噪：合并连续移动事件，给等待/滚动提供更准确的语义。
- 安全停止：鼠标移动到屏幕角落或按下 Escape 立即中断。
