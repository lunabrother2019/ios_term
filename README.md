# ios_term

一个 iOS SSH 终端应用，用于远程连接 AWS EC2 等 Linux 服务器执行命令行操作。

## 架构

```
┌──────────────────┐       SSH (port 22)       ┌──────────────┐
│    iOS App       │◄─────────────────────────►│  Linux Server │
│   (SwiftUI)      │    NIO SSH + SwiftTerm     │  (AWS EC2等)  │
│                  │                            │              │
│  TerminalView    │   密码 / 密钥认证           │   bash/zsh   │
│  Extra Keys Bar  │   PTY + Shell Channel      │              │
└──────────────────┘                            └──────────────┘
```

## 技术栈

### SSH 连接层

- **[SwiftNIO SSH](https://github.com/apple/swift-nio-ssh)** — Apple 官方纯 Swift SSH2 实现，无 C 依赖
  - `NIOSSHHandler` — SSH 协议处理
  - `SSHShellChannelHandler` — Shell 通道，管理 PTY 请求、环境变量、数据收发
  - `NIOSSHClientUserAuthenticationDelegate` — 密码认证
  - 支持 `WindowChangeRequest` 终端窗口大小同步

### 终端模拟

- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** — VT100/xterm-256color 终端模拟器
  - `TerminalView` (UIView) — 终端渲染、文本选择、滚动
  - `TerminalViewDelegate` — 键盘输入转发、窗口大小变化、剪贴板

### UI 层

- **SwiftUI** — 连接表单、导航
- **UIViewControllerRepresentable** — SwiftTerm UIKit 桥接到 SwiftUI
- **UIInputView** — 自定义辅助按键栏

### 数据安全

- **iOS Keychain** (Security.framework) — 密码安全存储
- **@AppStorage** — 主机名/端口/用户名持久化

## 功能

### 已实现

- ✅ SSH 密码认证连接
- ✅ 全功能终端（VT100/xterm-256color），支持 vim、top、htop 等
- ✅ 辅助按键栏：Esc、Tab、Ctrl、PgUp/PgDn、方向键、|、/、~、-
- ✅ Ctrl 组合键（Ctrl+C 中断、Ctrl+D 退出、Ctrl+Z 挂起等）
- ✅ 终端窗口大小自适应 + 键盘避让
- ✅ 记住连接信息（IP/端口/用户名自动填充）
- ✅ 密码 Keychain 安全存储，可选"记住密码"开关
- ✅ 剪贴板复制支持
- ✅ 链接点击打开（OSC 8）

### 待实现

- SSH 密钥认证（.pem 文件导入）
- 多主机管理列表
- 多会话 + 应用内分屏
- Host key 指纹验证
- 断线重连
- 主题配色 / 字体缩放

## 运行

1. Xcode 打开 `ios_term.xcodeproj`
2. SPM 自动拉取依赖（SwiftTerm + SwiftNIO SSH）
3. 选择模拟器或真机，Run
4. 输入服务器地址、用户名、密码，点击 Connect

## 项目结构

```
ios_term/
├── ios_term.xcodeproj/
├── ios_term/
│   ├── ios_termApp.swift              # App 入口
│   ├── ContentView.swift              # 连接表单 + 终端视图切换
│   ├── Services/
│   │   ├── SSHConnection.swift        # NIO SSH 连接核心
│   │   └── KeychainManager.swift      # Keychain 密码存取
│   ├── Terminal/
│   │   ├── SshTerminalView.swift      # TerminalView 子类 + Delegate
│   │   └── TerminalViewController.swift # UIKit 控制器，键盘适配
│   └── Views/
│       ├── ExtraKeysView.swift        # 辅助按键栏 (Esc/Tab/Ctrl/方向键)
│       └── TerminalRepresentable.swift # SwiftUI ↔ UIKit 桥接
└── PLAN.md                            # 开发计划
```

## 数据流

```
键盘输入 → TerminalViewDelegate.send()
       → SSHConnection.send(Data)
       → SSHShellChannelHandler.write()
       → SSH Channel → 远程服务器

远程输出 → SSH Channel
       → SSHShellChannelHandler.channelRead()
       → TerminalView.feed(byteArray:)
       → 屏幕渲染
```

## 依赖

| 包 | 版本 | 用途 |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.13+ | 终端模拟器 |
| [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) | 0.13+ | SSH 协议 |
| SwiftNIO | (自动) | 异步网络 I/O |
| SwiftCrypto | (自动) | 加密 |

## tmux 使用

在远程服务器上使用 tmux 时，建议在 `~/.tmux.conf` 中添加：

```bash
set -g mouse on
bind-key -T root PPage copy-mode -u
```

- `set -g mouse on` — 启用鼠标模式
- `bind-key -T root PPage copy-mode -u` — 按 PgUp 直接进入滚动模式

滚动操作：
- **PgUp** — 进入 copy mode 并向上翻页
- **PgDn** — 向下翻页
- **↑↓** — 逐行滚动
- **q** 或 **Esc** — 退出 copy mode，恢复正常键盘输入

## 已知问题

- **服务器兼容性**：SwiftNIO SSH 0.13.0 与 OpenSSH 8.7 的旧版 strict KEX 补丁（如 Rocky Linux 9 的 openssh-8.7p1-38）存在兼容性问题，密码认证会失败。需升级 OpenSSH 至 8.7p1-48+ 或 9.x
- **Ctrl + 软键盘**：Ctrl 修饰键仅对辅助栏上的按钮生效，不能配合系统软键盘使用
- **tmux 滚动**：SwiftTerm 的触摸滑动不会转换为鼠标滚轮事件，需通过 PgUp/PgDn 按钮翻页
