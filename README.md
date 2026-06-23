# SwiftUninstall

轻量、原生、无常驻后台的 macOS 应用卸载工具。

## 核心原则

- 使用 Bundle ID、应用名称、可执行文件名、配置内容和安装收据进行关联归因。
- 将候选项分为“确定相关 / 高度相关 / 可能相关”，默认不选择低置信度项目。
- 普通文件移入废纸篓；系统级文件移入 `/Users/Shared/SwiftUninstall Recovery`。
- 系统级操作合并为一次管理员授权。
- 卸载前退出目标应用并卸载其用户级启动项。
- 保存卸载历史和恢复路径，不运行后台守护进程。

## 构建

```sh
xcodegen generate
xcodebuild -project SwiftUninstall.xcodeproj -scheme SwiftUninstall -configuration Debug build
```

项目当前聚焦卸载引擎，SwiftUI 界面保持简洁，便于后续独立美化。

部分其他应用的沙盒容器受 macOS 隐私保护。核心引擎不会递归枚举这些目录，而是使用 Bundle ID 精确定位并以带超时的 Spotlight 查询补全；如系统拒绝删除，需在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中授权。
