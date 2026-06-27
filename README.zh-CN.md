# Slidr Free

[English](README.md) | 简体中文

Slidr Free 是一款开源 macOS 实用工具，提供边缘手势、中键点击、精细控制、打字智能检测和光标冻结等功能。

本项目是独立开源项目，与任何同名商业产品或供应商无关。

## 系统要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本

## 功能

- **音量边缘手势** — 在屏幕边缘滑动调节音量。
- **亮度边缘手势** — 在屏幕边缘滑动调节亮度。
- **中键点击** — 通过手势或键盘快捷键触发中键点击。
- **精细控制** — 按住修饰键进行更慢、更精确的调节。
- **左右互换** — 交换左右边缘手势区域。
- **底部四分之一模式** — 仅在屏幕边缘底部四分之一区域激活边缘手势。
- **打字智能检测** — 打字时自动抑制手势，避免干扰。
- **光标冻结** — 手势输入期间按住修饰键冻结光标。

## 开关

所有功能均可在菜单栏设置面板中单独启用或禁用。

## 权限

Slidr Free 需要以下权限：

- **辅助功能（Accessibility）** — 用于监听全局输入事件（边缘手势、中键点击、光标冻结）。首次启动时 macOS 会提示授予此权限。请在 **系统设置 → 隐私与安全性 → 辅助功能** 中授予。
- **输入监控（Input Monitoring）** — macOS 14+ 需要此权限来捕获键盘和鼠标事件。请在 **系统设置 → 隐私与安全性 → 输入监控** 中授予。

如果缺少任一权限，应用将在首次启动时显示权限引导。

## 安装说明（下载版）

本应用**未签名**。从 GitHub 下载 zip 解压后，macOS 会因隔离属性（quarantine）将应用标记为"已损坏"。请在终端运行以下命令修复：

```bash
xattr -cr /path/to/Slidr-Free.app
```

将 `/path/to/` 替换为实际路径。例如解压到"下载"文件夹：

```bash
xattr -cr ~/Downloads/Slidr-Free.app
```

移除隔离属性后，双击应用即可启动。首次启动时，请在 **系统设置 → 隐私与安全性** 中授予 **辅助功能** 和 **输入监控** 权限。

也可以从源码构建以完全避免 Gatekeeper 限制：

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free
swift build -c release
bash scripts/package-release.sh
open release/Slidr-Free.app
```

## 构建、测试和打包

```bash
# 构建
swift build

# 运行核心检查
swift run SlidrFreeCoreChecks

# 创建发布包
bash scripts/package-release.sh
```

打包脚本会生成 `release/Slidr-Free.app.zip`，其中包含一个独立的 `.app` 包，设置了 `LSUIElement=true`（不显示 Dock 图标和应用菜单栏）。

## 路线图

- [ ] 外接显示器亮度控制
- [ ] 按应用配置手势方案
- [ ] 自定义手势区域和动作
- [ ] 高级偏好设置窗口

## 已知限制

- **外接显示器亮度** — v0.1.0 仅控制内置显示器亮度。外接显示器亮度支持计划在未来版本中实现。

## 许可证

本项目基于 MIT 许可证开源。详见 [LICENSE](LICENSE) 文件。
