# 鼠标精灵 2

面向 macOS 的原生鼠标与键盘自动化工具。SwiftUI 工作台、系统级全局快捷键、Quartz 录制与回放，无 WebView、无前端服务、无第三方依赖。

需要 macOS 14 或更高版本及 Swift 6 工具链（Xcode 16+ / Command Line Tools）。本地构建默认生成当前 Mac 架构的应用。

## 开始使用

```bash
./script/build_and_run.sh
```

生成并打开 `dist/MouseElf.app`，Dock 显示“鼠标精灵”。该路径链接到缓存目录中已签名的应用，避免桌面同步附加元数据破坏签名。可将实际应用复制到“应用程序”目录后长期使用。首次使用需要在**设置**页分别检查辅助功能和输入监控；刚授权后若系统要求，退出并重新打开应用。

应用保持运行时，即使切换到其他应用或关闭主窗口，全局快捷键与菜单栏仍可控制任务。菜单栏可重新打开主窗口；退出应用会先停止任务、松开持有输入并保存工作区。

## 四个功能分区

- **任务**：鼠标左/右/中键，单击/双击，50 ms–1 小时点击间隔，有限次数或持续执行，当前鼠标或固定坐标，0–60 秒启动倒计时。
- **录制**：捕捉其他应用中的鼠标点击、路径、拖拽、滚轮和可选键盘输入；停止后创建独立脚本，不覆盖已打开的脚本。可手动编排移动、点击、按下/松开、滚动、等待、快捷键和 Unicode 文本。
- **脚本库**：本地自动保存，搜索、重命名、复制、删除确认，以及 JSON 导入导出。步骤可启用/禁用、编辑、复制、删除、上下移动；回放支持循环和 0.25–4 倍速。
- **设置**：分别检测系统权限，自定义全局热键并显示系统注册冲突，切换系统/浅色/深色外观，设置角落停止、录制内容和回放倒计时，查看运行日志。

录制、连点和回放互斥。等待与倒计时可取消，暂停不会消耗等待时间；结束或失败自动恢复就绪并释放持有的输入。鼠标移到任意屏幕的四个角（3 像素范围）会触发安全停止，可在设置中关闭。

## 默认快捷键

| 操作 | 全局快捷键 |
| --- | --- |
| 启动 / 暂停 / 继续 | `⌘⌥Return` |
| 开始 / 结束录制 | `⌘⌥R` |
| 立即停止 | `⌘⌥S` |
| 拾取当前鼠标坐标 | `⌘⌥P` |

启动键作用于最近打开的任务或脚本工作区；进入设置页不会改变目标。把鼠标移到目标位置后用拾取热键读取坐标；录制页选中带坐标的步骤时，拾取写入该步骤。

`Escape` 可在运行中停止，或在录制中结束录制；跨应用 Escape 监听受系统输入监听权限约束，专用全局停止热键独立注册。应用内还支持 `⌘.` 停止、`⌘N` 新建、`⌘O` 导入、`⌘S` 保存、`⌘⇧E` 导出和 `⌘1…4` 切换分区。自定义全局键须包含 Command、Control 或 Option，编辑后点击“应用快捷键”。

## 权限与坐标

- **辅助功能**：允许向其他应用发送鼠标和键盘事件。没有授权时执行直接报错，不显示模拟成功。
- **输入监控**：允许全局录制；键盘录制默认关闭，可按需打开。
- 系统授权对象是实际运行的 `MouseElf.app`。请尽量固定应用位置和签名身份；开发时重新构建的临时签名可能需要重新授权。构建脚本支持 `MOUSE_ELF_SIGNING_IDENTITY` 指定本机签名身份，默认临时签名；未执行公证或对外发布。
- 使用 Quartz 全局逻辑坐标，主屏左上为原点，多显示器可出现负坐标。更换分辨率或显示器布局后应重新拾取目标。
- 录制过滤自身合成事件、应用内控制操作和控制热键。键盘录制受 macOS Secure Input 约束，系统保护的输入区域可能无法捕捉。
- 滚轮按目标窗口投递，避免全局滚轮工具改写；每行换算为 10 个逻辑像素。窗口关联依赖 macOS 的窗口坐标接口（SPI），通过运行时检测和 Cocoa 事件转换测试保护；系统接口不可用时明确停止并报错，升级 macOS 后应复验此功能。

## 本地数据

工作区：`~/Library/Application Support/MouseElf/workspace.json`。设置页可打开数据目录。所有脚本、连点参数、偏好和选择状态均保存在本机，编辑后约 0.5 秒自动保存；临时无效参数不会打断输入，可在设置查看待保存原因。

写入采用原子替换。工作区损坏时保留原文件并暂停覆盖；可先导出当前脚本，然后备份/修复数据文件并重启。导入仅接受本应用 JSON 格式，校验版本、数字范围、步骤数量及标识，导入时重新分配脚本和步骤标识。单文件导入上限 5 MB，每脚本上限 10,000 步，脚本库上限 500 个。

旧版没有实现可靠脚本持久化，因此没有自动迁移浏览器演示数据。重构前的代码仍可在 Git 历史查看。

## 开发与验证

```bash
# 构建、测试、release .app 签名检查
./script/check.sh

# 单独运行 SwiftPM 命令
./script/swift.sh build
./script/swift.sh test

# debug 构建 + 启动 + 进程验证
./script/build_and_run.sh --verify

# release 构建（不启动）
./script/build_app.sh release

# 可选调试入口
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

`script/swift.sh` 使用系统 SwiftPM，将构建缓存放在 `~/Library/Caches/MouseElf/`，避免桌面/iCloud 文件同步附加 Finder 元数据导致测试包签名失败。可用 `MOUSE_ELF_BUILD_DIR` 覆盖缓存目录；源码不受此处理影响。

单元测试以注入的输入 driver 验证执行完成、双击状态、取消倒计时、暂停等待、互斥、异常清理、持有输入释放、多屏角落停止、零延迟循环和修饰键；同时验证脚本 CRUD、导入边界、损坏文件保护与保存重载。测试不发送真实系统输入，真实操作仍需在授权后的应用中验收。

`./script/input_probe.sh` 可打开独立的本地输入靶场，供人工或电脑控制验收真实点击、文本、拖拽和滚动。它只接收事件，不请求权限、不发送输入，统计和 Quartz 目标坐标写入 `/tmp/mouse-elf-probe.json`。应用支持 `open -n dist/MouseElf.app --args --workspace /tmp/mouse-elf-test-workspace.json` 隔离验收数据。

GitHub Actions 在 macOS 上运行构建、单测和打包检查。Codex 的 Run 按钮已绑定 `script/build_and_run.sh`。

本机已通过 31 项单元测试、Release 构建与签名校验，并在独立靶场完成真实连点、中文/emoji 输入、拖拽及三阶段滚动回放；物理全局快捷键已验证能生成并保存录制脚本。验收坐标取自靶场实时窗口位置，验收数据与日常工作区隔离。

## 代码结构

```text
Package.swift                        SwiftPM 入口，无外部依赖
Sources/MouseElfCore/                 模型、验证、JSON 文件存储
Sources/MouseElf/MouseElfApp.swift     场景、菜单、菜单栏与退出生命周期
Sources/MouseElf/AppStore.swift       工作区、互斥路由、自动保存
Sources/MouseElf/Services/            Quartz 引擎、录制、权限、Carbon 热键
Sources/MouseElf/Views/               四分区与步骤检查器
Tests/                               核心数据和引擎测试
Resources/Info.plist                  应用包信息
script/                              构建、签名、启动、验证
```

系统事件接口依据 Apple 的 [Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services) 和 [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)；应用仅处理本地事件与本地文件。
