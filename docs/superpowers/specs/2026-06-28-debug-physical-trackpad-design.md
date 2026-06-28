# Debug 面板与物理触控板边缘检测设计规格

日期：2026-06-28

## 1. 背景

当前版本通过 `CGEventTap` 监听滚轮事件，并使用鼠标指针在屏幕上的位置判断是否位于左/右边缘。该方案可以在“鼠标指针靠近屏幕边缘时双指滚动”场景下触发识别，但不能检测“手指在触控板物理边缘滑动”。

目标功能必须以触控板物理边缘为准。因此后续不再把公开 API 的屏幕边缘滚动方案作为正式功能路径。

## 2. 范围

本阶段实现：

- Debug 面板
- 动作执行诊断
- 实验性物理触控板边缘检测
- 移除或停用屏幕边缘滚动触发逻辑
- README 风险说明

不实现：

- 外接显示器亮度控制
- App Store / notarization 支持
- 公共 API 屏幕边缘滚动 fallback 作为正式手势路径

## 3. Debug 面板

菜单栏新增 `Debug…`。

Debug 面板展示：

- 权限状态：Accessibility / Input Monitoring
- MultitouchSupport 状态：loaded / unavailable / failed
- 触控板设备状态：detected / not detected
- 物理触控板监听状态：running / stopped
- 最近触摸帧：触点数量、时间戳
- 最近触摸点：normalized x/y、pressure、state（如可用）
- 命中区域：left edge / right edge / none
- 识别手势：volume + / volume - / brightness + / brightness - / none
- 执行动作：adjust volume / adjust brightness / middle click / none
- 执行结果：success / failed / unsupported
- 最近 50 条日志

Debug 面板只读，不改变设置。刷新由运行时事件驱动，必要时可提供 `Clear Logs`。

## 4. 物理触控板监听模块

新增 `PhysicalTrackpadMonitor`，职责：

- 使用 `dlopen` 动态加载 `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`
- 使用 `dlsym` 查找：
  - `MTDeviceCreateList`
  - `MTDeviceCreateDefault`
  - `MTRegisterContactFrameCallback`
  - `MTDeviceStart`
  - `MTDeviceStop`
- 枚举或获取默认触控板设备
- 注册触摸帧回调
- 将 `MTTouch.normalizedPosition.position.x/y` 转换为内部事件
- 在停止或退出时注销/停止设备监听

模块必须隔离私有 API 结构体定义和函数指针，不能让私有 API 类型泄漏到核心识别层。

## 5. 输入事件与识别

新增核心事件类型或扩展现有 `NormalizedInputEvent`：

- physicalTouchFrame
  - touches: `[PhysicalTouch]`
  - timestamp

`PhysicalTouch` 至少包含：

- id（如可用）
- x：0...1 normalized coordinate
- y：0...1 normalized coordinate
- pressure（如可用）
- state（如可用）

识别规则：

- 左物理边缘：`x <= edgeWidthPercent`
- 右物理边缘：`x >= 1 - edgeWidthPercent`
- 垂直方向：根据连续帧中同一触点或主触点的 `y` 差值判断
- 向上：增加
- 向下：降低
- 左右互换按现有设置生效
- 底部四分之一区域模式按 `y` 判断
- 打字冷却仍然生效

屏幕坐标和鼠标指针位置不参与物理边缘手势识别。

## 6. 动作执行诊断

`SystemControl` 的动作方法改为返回结果：

- success
- failed(reason)
- unsupported(reason)

覆盖：

- 音量调节
- 内置屏幕亮度调节
- 中键点击
- 光标冻结
- 反馈显示

Debug 面板必须记录每次动作的执行结果，避免只看到 `vol+` / `bright+` 但不知道系统调用是否实际生效。

## 7. 权限和失败模式

如果 MultitouchSupport 加载失败：

- Debug 面板显示失败原因
- 菜单栏和设置仍可使用
- 物理边缘手势不可用
- 不自动回退到屏幕边缘滚动触发

如果没有触控板设备：

- Debug 面板显示 `No trackpad device detected`
- 手势不可用

如果系统更新导致结构体不兼容或回调异常：

- 捕获可捕获错误
- 停止监听
- 记录日志
- 不崩溃主应用

## 8. UI 设置变化

设置界面保留现有功能开关，但文案应明确这是“触控板物理边缘”。

新增或调整：

- Physical trackpad edge gestures：总开关
- Debug…：菜单栏入口
- 实验性提示：私有 API，可能随 macOS 更新失效

移除或停用：

- 屏幕边缘滚动触发路径

## 9. README 更新

README 与中文 README 均需说明：

- 物理触控板边缘检测依赖 macOS 私有 MultitouchSupport API
- 该功能为 experimental
- macOS 更新后可能失效
- 非 App Store 友好
- 如果 Debug 面板显示 MultitouchSupport unavailable，则物理边缘手势不可用

## 10. 测试计划

自动检查：

- 物理触摸事件到手势识别的纯逻辑
- 左/右边缘判断
- 上/下方向判断
- 左右互换
- 底部四分之一区域过滤
- 动作结果模型

手动测试：

- Debug 面板打开
- MultitouchSupport 加载状态显示
- 触控板设备检测
- 物理左边缘滑动调亮度
- 物理右边缘滑动调音量
- 左右互换
- 关闭功能后不触发
- 动作失败时 Debug 日志有明确原因

## 11. 风险

- MultitouchSupport 是私有 API，不保证未来 macOS 兼容。
- 结构体布局可能变化。
- arm64e / PAC / 调用约定可能导致崩溃风险。
- 该功能不适合 Mac App Store 分发。
- 当前项目是未公证开源工具，仍需用户自行处理 Gatekeeper。

## 12. 自检

- 范围明确：本阶段只做 Debug、动作诊断、物理触控板边缘检测。
- 明确不再使用公开 API 屏幕边缘滚动方案作为正式功能路径。
- 私有 API 风险、失败模式和 Debug 可观测性均已覆盖。
- 自动测试和手动测试边界明确。
