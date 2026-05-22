# AGENTS.md

## 回答和协作

- 默认用中文回答。
- 站在程序员视角说清楚原因、证据、命令和取舍。
- 不确定时先读代码和运行命令，不要凭印象改。

## 包管理

- Node.js 相关命令使用 `pnpm`。
- Python 相关命令使用 `uv`。
- 不要引入 npm/yarn/bun lockfile。

## 项目栈

- 桌面端：Tauri 2。
- 前端：Next.js 16 App Router。
- UI：shadcn/ui + Tailwind CSS v4。
- 鼠标输入模拟：`enigo`。
- 全局鼠标事件监听：`rdev`。

## 开发命令

```bash
pnpm dev
pnpm desktop:dev
pnpm lint
pnpm build
pnpm test:ai
cd src-tauri && cargo check
pnpm desktop:build
```

## 代码约定

- 前端交互组件需要 `"use client"`。
- 左侧导航是实际功能分区，不是装饰栏；`任务`、`录制`、`脚本库`、`设置` 的内容不要重新混回一个首页。
- shadcn/ui 组件源码在 `src/components/ui/`，新增组件用 `pnpm dlx shadcn@latest add ...`。
- Tauri 命令集中放在 `src-tauri/src/lib.rs`，前端通过 `invoke` 调用。
- Next 需要静态导出给 Tauri 使用，保留 `next.config.ts` 里的 `output: "export"`。
- 不要提交构建产物：`.next/`、`out/`、`src-tauri/target/`。

## macOS 权限注意

真实点击和全局录制依赖系统辅助功能权限。开发模式下要给启动进程的终端授权，打包后要给 `.app` 授权。应用内 `请求授权` 按钮会调用 macOS `AXIsProcessTrustedWithOptions` 发起系统请求；没有权限时不要误判为代码逻辑失败。

## 验收要求

提交前至少跑：

```bash
pnpm lint
pnpm build
pnpm test:ai
cd src-tauri && cargo check
```

`pnpm test:ai` 是给 Codex/CI 使用的 Playwright 端到端检查，覆盖定时点击、左侧分区导航、录制按钮、步骤增删改查、权限入口和最小窗口布局。测试失败时先看 UI 可访问性、按钮可定位性、信息架构是否被重新混杂，以及代理绕过配置，不要只改断言。

改动 Tauri/Rust 侧时优先再跑：

```bash
pnpm desktop:build
```
