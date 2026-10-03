# Logo 与展示素材

Pocket Touchpad（口袋触控板）的标志使用白底、两段圆润的触摸面轮廓和一个触点，表达触摸、移动与双手协作。iPhone 与 Mac 应用图标共用这一套标志。

- 原图：`assets/touchpad-logo.png`（1254 × 1254）
- 项目图标：`assets/touchpad-icon.png`（512 × 512）
- 应用图标：`../Shared/Assets.xcassets/AppIcon.appiconset/`
- 实际界面截图：`assets/screenshots/`

## 制作方式

Logo 使用 OpenAI 内置 imagegen 工具生成（built-in 模式，非 CLI），随后只进行尺寸转换以适配图标目录。未使用生成工具伪造应用截图。仓库介绍使用 Markdown 文字与独立 iPhone 模拟器的实际截图。

最终 Logo 提示词：

```text
Use case: logo-brand. Create a single polished app icon for Touchpad, a minimalist iPhone-to-Mac touchpad. The user explicitly requests a WHITE background and a simple lively graceful design, rejecting a heavy dark block and a generic arrow icon. New direction: pure white square canvas edge to edge, only one small-to-medium charcoal-black fluid geometric mark in the center. The mark is an airy open rounded-square touch surface suggested by two separate elegant curved L-shaped strokes, offset diagonally, smoothly rounded ends; their tips almost meet but leave two clear gaps, conveying two fingertips cooperating and flowing in parallel. A tiny single circular dot at one gap can suggest a fingertip, integrated into the same rhythm. Think effortless movement, a clever quiet symbol, not a literal computer, not an external-link arrow. Consistent medium-light stroke weight, beautiful balanced negative space, slightly asymmetric lively rhythm inside an overall perfectly centered composition. Symbol occupies about 48 percent of the square. Flat precise vector-like black shapes only on pure white, no shadows, no texture, no gray background, no gradients, no dark surrounding block, no text, no letters, no border, no extra decoration, no 3D or mockup. Deliver ONLY the final white-square logo.
```

## 截图说明

截图使用 iPhone 17 Pro 模拟器、iOS 26.2，连接标题“我的 Mac”与已保存的 Mac 记录来自离线演示状态，不包含真实地址或配对凭据。12 张原始 PNG 保留实际 SwiftUI 布局，并展示拖移、键盘、布局编辑、设置与配对等状态。仓库首页直接展示原始截图，不添加手机外框或宣传海报。

离线模式仅在 `DEBUG && targetEnvironment(simulator)` 下可用，不创建网络连接、不读取配对密钥、不发送真实输入。它不能证明无线延迟、多指触感、震动或系统手势的实际运行表现。

文件名、尺寸及构建来源见 `assets/screenshots/manifest.json`。复现方式见 `../scripts/capture-screenshots.sh`。
