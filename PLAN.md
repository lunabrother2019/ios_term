# iOS SSH Terminal App (ios_term) 实现计划

## Context

构建一个 iOS SSH 终端应用，用于远程连接 AWS EC2 实例执行命令行操作，支持应用内分屏。

## 方案选择：从零构建（SwiftTerm + SwiftNIO SSH）

**不选 Blink Shell fork**：代码量巨大，自定义渲染管线，改造成本高于从零写。
**不选 SwiftTermApp fork**：已停止维护，SSH I/O 有数据丢失 bug。

**选择从零构建**：SwiftTerm 的示例代码已提供完整的 SSH 终端实现（~350行），我们在此基础上扩展即可。

## 依赖

| 包 | 用途 |
|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | VT100/xterm 终端模拟器，提供 `TerminalView` (UIView) |
| [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) | Apple 官方纯 Swift SSH2 实现，支持密码和密钥认证 |

## 文件结构

```
ios_term/
├── ios_termApp.swift                   # App 入口
├── ContentView.swift                   # 根导航（连接表单 + 终端）
├── Models/
│   ├── HostModel.swift                 # 主机配置 (Codable)
│   └── SessionModel.swift              # 活跃会话状态
├── Services/
│   ├── SSHConnection.swift             # NIO SSH 客户端核心
│   ├── KeychainManager.swift           # Keychain 存取密码/私钥
│   └── HostStore.swift                 # 主机列表持久化 (JSON)
├── Terminal/
│   ├── SshTerminalView.swift           # TerminalView 子类 + Delegate
│   └── TerminalViewController.swift    # UIViewController 包装
├── Views/
│   ├── HostListView.swift              # 主机列表
│   ├── HostFormView.swift              # 添加/编辑主机表单
│   ├── TerminalContainerView.swift     # 会话容器（分屏布局）
│   ├── TerminalRepresentable.swift     # UIViewControllerRepresentable 桥接
│   └── ExtraKeysView.swift             # 辅助按键栏 (Esc/Tab/Ctrl/方向键)
```

## 分阶段实现

### Phase 1：单终端连接（核心）✅ 已完成

1. ✅ SPM 依赖：SwiftTerm + SwiftNIO SSH
2. ✅ SSH 连接层 (`SSHConnection.swift`) — 密码认证、数据收发、窗口大小调整
3. ✅ 终端视图 (`SshTerminalView.swift`) — TerminalViewDelegate 完整实现
4. ✅ UIKit 桥接 (`TerminalViewController.swift` + `TerminalRepresentable.swift`)
5. ✅ 连接 UI (`ContentView.swift`) — 表单 + @AppStorage 记住 IP/用户名 + Keychain 存密码
6. ✅ 辅助按键栏 (`ExtraKeysView.swift`) — Esc, Tab, Ctrl, 方向键等

### Phase 2：主机管理与持久化

1. **HostModel** — name, hostname, port, username, authMethod (password/privateKey)
2. **KeychainManager** ✅ 已完成 — 用 Security framework 存取密码和 SSH 私钥
3. **HostStore** — JSON 文件持久化主机列表
4. **HostListView** — 主机列表，滑动删除，点击连接
5. **HostFormView** — 添加/编辑表单，含 "选择密钥文件" 按钮（UIDocumentPicker 导入 .pem）

### Phase 3：应用内分屏 + 多会话

1. **SessionModel** — 管理多个活跃 SSH 会话
2. **TerminalContainerView** — 分屏布局
   - 默认单屏，工具栏按钮切换为左右分屏（两个终端并排）
   - 用 `HStack` + 可拖拽分隔条
   - 用 ZStack + opacity 保持所有会话存活（避免 TabView 销毁 view 导致 SSH 断连）
3. **新建会话** — 分屏中可从主机列表选择不同主机打开第二个连接

### Phase 4：完善

1. **Host key 验证** — 首次连接显示指纹确认，存储后续验证
2. **断线重连** — 检测断开，显示 overlay，支持手动重连
3. **主题** — 2-3 个内置配色（暗色/亮色/Solarized）
4. **字体缩放** — 捏合手势调整字体大小

## 注意事项

- **RSA 密钥**：SwiftNIO SSH 原生支持 Ed25519/ECDSA，RSA .pem 可能需要 SwiftCrypto 辅助解析
- **后台连接**：iOS 后台 ~30 秒会挂起 app，SSH 会断，需要重连机制
- **内存**：多会话时每个 TerminalView 有 scrollback buffer，建议限制 10000 行
- **服务器兼容性**：SwiftNIO SSH 0.13.0 与 OpenSSH 8.7 的旧版 strict KEX 补丁（如 Rocky Linux 9 的 openssh-8.7p1-38）存在兼容性问题，密码认证会失败。升级 OpenSSH 到 8.7p1-48+ 或使用 OpenSSH 9.x 可解决。认证代理需加 `tried` 标记防止密码重试导致服务器封禁 IP

## 验证方式

1. Phase 1：输入 AWS 主机信息 → 连接 → 能执行 `ls`, `top`, `vim` 等命令
2. Phase 2：保存主机 → 杀掉 app 重启 → 主机列表还在 → 点击直接连接
3. Phase 3：同时打开两个终端 → 左右分屏显示 → 各自独立操作
4. 辅助按键栏：Tab 补全，Ctrl+C 中断，方向键移动光标
