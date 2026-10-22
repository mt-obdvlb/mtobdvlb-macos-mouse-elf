# 鼠标精灵 · macOS 原生工程

## 回答和协作

- 默认中文，说明代码证据和实际验证结果。
- 修改前检查 Git 状态，保护用户已有改动。
- 用户已决定只支持 macOS；不要重新引入 WebView、Tauri 或跨平台框架。

## 技术栈与结构

- macOS 14+，Swift 6 工具链，SwiftPM，SwiftUI + 小范围 AppKit 桥接。
- `Sources/MouseElfCore/`：Codable 模型、验证和原子文件存储，不依赖 UI。
- `Sources/MouseElf/Services/`：Quartz 输入/录制、Carbon 全局热键、权限与执行状态机。
- `Sources/MouseElf/Views/`：任务、录制、脚本库、设置，保持实际功能分区。
- `AppStore.swift` 管理工作区和操作路由；UI 不实现第二套模拟执行。
- 不需要 Node.js、Rust 或第三方依赖。若有 Python 工具命令使用 `uv`。

## 开发与验收

```bash
./script/swift.sh build
./script/swift.sh test
./script/build_and_run.sh --verify
./script/build_app.sh release
```

- `./script/check.sh` 集中执行构建、单测和打包检查。
- `script/swift.sh` 通过原生 SwiftPM 构建，缓存放在 `~/Library/Caches/MouseElf/`，避免桌面同步目录的 Finder 元数据阻断测试签名。
- 修改输入引擎时，用可注入 driver 测试事件顺序、停止/取消、正常结束、暂停恢复和持有按键释放。
- UI 改动尽可能启动真实 `.app`，检查四分区、步骤编辑、最小窗口、权限入口、菜单与快捷键。
- 不把 mock 事件测试描述成真实系统输入成功。没有权限时保留明确错误，说明需要授权的应用。
- `.build/`、`dist/`、旧版本本地备份 `.legacy-backup/` 都不能提交。

## macOS 行为

- 全局热键必须使用系统注册，并显示注册失败。菜单快捷键不能代替全局快捷键。
- AX 辅助功能与输入监控分开检测；启动只检测，用户主动操作才请求权限。
- 录制、连点、回放互斥；倒计时/等待可取消；任务完成必须回到 idle。
- 不录自身合成事件，不录本应用窗口和控制热键，不静默忽略输入错误。
- 坐标统一使用 Quartz 全局坐标（左上为原点，负坐标支持多屏）。
- 本地数据原子写入；损坏数据保留，禁止默默覆盖。导入需要验证并重建标识。

## Git

- 验证通过后默认创建本地提交；推送需用户授权，本次重构用户已授权提交与推送。
- 不提交构建产物或权限数据库，不修改系统权限来伪造验证成功。
