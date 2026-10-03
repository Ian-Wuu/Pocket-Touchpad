# 手势实现与验收边界

默认启用所有已实现手势，不再区分单手 / 平放。Mac 端每两秒只读系统触控板偏好，变更后同步到 iPhone，不写回或修改系统设置。

| 输入 | 行为 | 系统设置与限制 |
|---|---|---|
| 单指移动、轻点、双击 | 相对移动、点击 | 按显示器实际排列跨屏；读取轻点开关、跟踪速度；调用 Mac 已安装的原生 HID 加速曲线 |
| 拖移按钮 | 亮起后保持鼠标左键，抬手继续；再次点击放开 | 独立于触摸手势；离开应用、断线或停止心跳后释放 |
| 长按后拖动 | 按住左键，松手放开 | 手机便利操作，不等同力度按压 |
| 轻点后再次触摸拖动 | 拖移及拖移锁定 | 读取 Dragging / DragLock；锁定后轻点放开 |
| 三指拖移 | 三指移动时拖动 | 读取 TrackpadThreeFingerDrag；启用时优先于三指切换 |
| 双指轻点 / 双指双击 | 右键 / 智能缩放 | 读取对应开关；开启智能缩放后按 Mac 双击间隔延迟判定单次右键 |
| 双指移动 | 带阶段的连续滚动和惯性 | 读取自然方向、横向滚动、惯性开关；应用可据带阶段滚动处理页面导航 |
| 双指捏合 / 旋转 | 连续 magnify / rotate 事件 | 读取缩放 / 旋转开关；私有事件兼容路径，非 ⌘+ / ⌘− |
| 三指轻点 | 查询 | 读取查询开关及系统快捷键 |
| 三指 / 四指左右、上下滑动 | 桌面切换、调度中心、应用窗口 | 读取指头数量相关开关；连续发送原生 Dock HID 进度，反向、停住、松手速度及取消均独立处理 |
| 三指水平翻页 | swipe 事件 | 读取三指翻页设置，应用需支持 |
| 四指张开 / 捏合 | 显示桌面 / 应用入口 | 桌面使用系统快捷键；Launchpad 不存在时打开 Applications 文件夹，并非新版 Spotlight 应用网格 |
| 双指从右缘划入 | 通知中心 | 需要系统已配置通知中心键盘快捷键；当前未配置时不可用 |
| 横屏两拇指分居左右 | 同向移动光标、张合缩放 | 保留用户要求的双手平等操作；同一侧双指仍是普通触控板手势 |

## 不是硬件触控板

此版本没有注册成 Magic Trackpad / HID 触控板，也没有接入 Apple 私有硬件识别栈。Force Click、压力分级、防掌误触、所有应用内部的自定义 NSTouch 手势和辅助功能缩放，尚未等价实现。不能宣称“完整模拟全部 Apple 触控板设置”。

Apple 的 CoreHID 支持虚拟设备，但通用触摸板描述符并不保证接入 Apple 的手势识别器；虚拟设备权限、HID 报告和系统消费端都需要单独验证。本版不安装实验驱动，不修改系统安全策略。

私有事件格式位于 Mac/Gestures.swift 与 Mac/NativeInput.mm。启动时检查 AppKit 解码以及 HID 负载回读。macOS 27 通过 SLEventSetIOHIDEvent 附加系统 HIDEvent，使用进度、阶段、轴和离手速度；不写 CGEvent 内存偏移。接口不可用时，设置页不显示连续转场能力，并退回已配置的系统快捷键。断线、退出和触摸取消会终止未完成手势。

## 原生加速

Mac/Pointer.swift 只读本机触控板 HIDAccelCurves、HIDPointerResolution 和系统跟踪速度；Mac/NativeInput.mm 动态调用 Apple 签名的 IOHIDPointerScrollFilter 中 CreateWithParameters / multiplier，不复制或自行拟合 Apple 曲线。私有 ABI 仅对已检查的 macOS 26 / 27 启用，未来版本需重新验证。

手机的 UIKit 点以 160 点/英寸作为距离校准，再按真实 Mac 设备分辨率进入曲线；灵敏度只调整输入距离。每个样本保留原始时间间隔，按 Apple 67 Hz 基准计算速度，60 / 120 Hz 的同速移动保持相同增益。原始位移样本不在传输中合并，也不按网络到达时间计算加速。这复用了系统曲线计算，但不是注册硬件、压力识别或完全相同的传感器标定。若没有可读取的触控板曲线、系统关闭加速或接口不可用，使用线性位移，并在手机设置中显示实际状态。

## 当前验证

- scripts/GestureCheck.swift：轻点与滑动互斥、缩放排除点击、滚动阶段和惯性、分批抬手、停住后抬手、三指拖移、按钮拖移连续换位、系统拖移锁定、四指切换、左右拇指移动，以及 AppKit 对 magnify / rotate / smartMagnify 的解码。新增原生曲线速度响应、60 / 120 Hz 一致性、跨屏负坐标与边界、Dock HID 各阶段负载、反向离手和停住后松手的验证。
- scripts/TransportCheck.swift：TLS 正确配对、错误密钥拒绝、事件顺序与 Unicode；原始移动的 60 个独立采样及时间间隔保持完整。
- 此次 Mac 验收观察到调度中心的 Dock 转场窗口在开始后出现、停住期间保持、取消后退出；尚未完成手机真实滑动手感及所有桌面方向的现场验证。用户使用电脑期间不再执行桌面转场、光标移动或焦点切换测试。
- 模拟器与实际 Mac 连接后，已核对系统设置同步、拖移按钮开启高亮及再次点击释放、姿势切换移除、深色竖屏与浅色横竖屏排版。
- 编译、事件解码、模拟器画面检查不代表所有应用实际消费手势。Safari、Preview、Photos、设计软件中的缩放/旋转，以及手机真实多指触感，还需要逐项实机验证。

## 参考

- https://support.apple.com/en-gb/102482
- https://developer.apple.com/documentation/corehid/creatingvirtualdevices
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html
- https://github.com/scottlamb/macos-trackpad-companion
- https://github.com/WebKit/WebKit/blob/main/Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h
- https://github.com/HAOoool/mac-mouse-fix-macos27-fix

源码参考许可见 ThirdPartyNotices.txt。

- 原生加速源码依据：https://github.com/apple-oss-distributions/IOHIDFamily/tree/main/IOHIDEventSystemPlugIns
- macOS 27 HID 桥参考：https://github.com/timmyagentic/mac-mouse-fix-macos-27-fix
