# 构建与安装

[English](Setup.md) | 简体中文

要求：iOS 26+、macOS 26+、包含对应 SDK 的 Xcode。当前代码使用 Xcode-beta 开发，两个应用均无第三方包依赖。

## 签名与运行

1. 打开 `Touchpad.xcodeproj`。
2. 在 Touchpad 和 TouchpadMac 两个 Target 的 Signing & Capabilities 中选择自己的开发团队。需要时将 Bundle Identifier 改为你自己的唯一标识。
3. 也可新建 `Config/Local.xcconfig`，内容为 `DEVELOPMENT_TEAM = 你的团队ID`。此文件已被 Git 忽略；仓库内 `Signing.xcconfig` 仅包含可选引用。
4. 选择 TouchpadMac Scheme，运行在 My Mac，点击“允许控制此 Mac”，在系统提示的辅助功能控制权限入口开启应用。
5. 连接 iPhone，按系统提示启用开发者模式。选择 Touchpad Scheme 与手机，点击 Run。
6. 两端加入同一局域网；在 iPhone 允许本地网络、扫码时允许相机权限，扫描 Mac 窗口的二维码。也可粘贴 Mac 提供的配对链接。
7. 将 Mac 焦点放到目标应用。接收端不需要留在前台。

配对二维码和链接包含凭据，不要公开截图或提交到仓库。

## 只编译，不控制电脑

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Touchpad.xcodeproj -scheme Touchpad \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/touchpad-sim CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Touchpad.xcodeproj -scheme TouchpadMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/touchpad-mac CODE_SIGNING_ALLOWED=NO build
```

若使用正式版 Xcode，将 `DEVELOPER_DIR` 改为它的实际路径。`CODE_SIGNING_ALLOWED=NO` 仅适合构建检查；真机安装和稳定的 Mac 权限需要正确签名。

`python3 scripts/create-project.py` 可重新生成项目，会覆盖手动改动的项目配置；日常打开与编译不需要运行它。本机团队设置保存在忽略的 `Config/Local.xcconfig`，不会写入生成器或共享项目文件。

## 截图

`scripts/capture-screenshots.sh` 创建独立模拟器，启动 Debug 专用离线场景，生成 12 张浅色、深色、横屏、拖移、键盘、布局编辑、设置与配对截图。不会连接接收端，也不向 Mac 注入输入。首次创建模拟器可能需要较长时间，脚本完成后会关闭并移除本次创建的专用设备。

仓库首页直接通过 README 展示文字与截图，无需部署网页。默认截图环境是 iPhone 17 Pro / iOS 26.2 模拟器，可通过 `SIM_TYPE` 与 `SIM_RUNTIME` 环境变量选择本机安装的其他模拟器。

## 权限与连接排查

- **手机仍提示需要允许控制：** 确认运行中的接收端与系统权限列表里的应用是同一份。频繁改变路径或签名会影响系统对应用身份的判断。保持签名和安装路径稳定；必要时移除旧权限条目，再添加实际使用的版本。系统可能要求密码或 Touch ID。
- **找不到 Mac：** 两端需在互通的局域网，访客网络或客户端隔离可能阻止设备通信。检查本地网络权限。
- **锁屏后需要恢复：** iOS 可能暂停后台网络。应用回到前台会探测连接，并用保存的配对自动重连；不保证永久后台在线。
- **高级手势不一致：** 在手机设置查看同步与能力状态，并查阅 [Gestures.md](Gestures.md)。不同应用、macOS 版本的事件消费方式可能不同。

不会为控制输入安装内核扩展，也无需关闭系统安全策略。
