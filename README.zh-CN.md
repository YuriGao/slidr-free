# Slidr Free

[English](README.md) | 简体中文

Slidr Free 是一款开源 macOS 实用工具，提供物理触控板边缘手势功能。

本项目是独立开源项目，与任何同名商业产品或供应商无关。

## 系统要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本

## 功能

- **左右边缘滑动** — 沿物理触控板左侧或右侧边缘上下滑动，用于调节亮度和音量。默认左侧调节亮度，右侧调节音量。
- **左右互换** — 可在设置面板中交换左右边缘对应的动作。
- **上边缘浏览器标签页滑动** — 沿物理触控板上边缘左右滑动，在 Safari、Google Chrome 和 Microsoft Edge 中切换标签页，并在每次切换时提供触感反馈。

## 实验性物理触控板支持

物理触控板边缘手势是实验性功能。由于 macOS 没有提供获取每根手指物理触控板坐标的公开 API，Slidr Free 通过 Apple 私有 `MultitouchSupport` 框架读取物理触摸帧。

- 目前**没有公开 API 回退方案**，也不会回退为屏幕边缘光标手势。如果 `MultitouchSupport` 不可用、被阻止，或在未来 macOS 版本中发生变化，物理触控板边缘手势会被禁用，而不是根据指针位置猜测。
- 可通过菜单栏 **调试…** 面板查看物理触控板监视器是否运行、最后一次物理触摸帧、动作结果和失败信息。
- 可能的失败模式包括私有符号缺失或变更、不支持的硬件、权限或沙盒限制、没有触摸帧上报，以及 macOS 更新改变私有 API 行为。这些失败应显示在调试面板中，且不应导致应用崩溃。

## 设置

应用提供音量边缘手势、亮度边缘手势和上边缘浏览器标签页切换的独立开关。也可以交换左右边缘动作，并调整物理边缘宽度。

## 权限

Slidr Free 需要以下权限：

- **辅助功能（Accessibility）** — 用于监听触控板边缘手势所需的全局输入事件。首次启动时 macOS 会提示授予此权限。请在 **系统设置 → 隐私与安全性 → 辅助功能** 中授予。

如果缺少此权限，应用将在首次启动时显示权限引导。

## 安装

Slidr-Free 仅以源代码形式发布。在本地构建：

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free
swift build -c release
bash scripts/package-release.sh
```

然后将 `release/Slidr-Free.app` 拖到「应用程序」文件夹。

## 构建、测试和打包

```bash
# 构建
swift build

# 运行核心检查
swift run SlidrFreeCoreChecks

# 创建发布包
bash scripts/package-release.sh
```

打包脚本会生成 `release/Slidr-Free.app`，其中包含一个独立的 `.app` 包，设置了 `LSUIElement=true`（不显示 Dock 图标和应用菜单栏）。

## 已知限制

- **私有 MultitouchSupport API** — 物理触控板边缘手势依赖未公开的 Apple 框架，可能在部分设备或 macOS 版本上停止工作。请查看 **调试…** 获取诊断信息。
- **浏览器标签页切换范围** — 上边缘标签页切换只会在 Safari、Google Chrome 或 Microsoft Edge 位于前台时执行。

## 支持项目

Slidr Free 是开源免费项目。如果它对你有帮助，欢迎通过支付宝支持项目维护：

<img src="docs/assets/alipay-qr.jpg" alt="支付宝收款二维码" width="220">

## 许可证

本项目基于 MIT 许可证开源。详见 [LICENSE](LICENSE) 文件。
