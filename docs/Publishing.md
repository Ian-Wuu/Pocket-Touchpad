# Repository and packaging / 仓库与打包

## English

Repository: [Ian-Wuu/Pocket-Touchpad](https://github.com/Ian-Wuu/Pocket-Touchpad).

Run `python3 scripts/package-github.py` to create `dist/Pocket-Touchpad-GitHub.zip`. Extract it and put the contents of `Pocket-Touchpad/` at the repository root.

- Default GitHub homepage: `README.md` in English, linking to `README.zh-CN.md` in Chinese.
- Content: project overview, current features, actual screenshots, setup, limitations, and license.
- License: the project-specific Pocket Touchpad Source-Available License 1.0 in `LICENSE`, with `NOTICE` and the English-first bilingual explanation in `docs/OPEN_SOURCE.md`.
- Permission boundary: commercial work using the tool is allowed; commercializing its source code or modified versions as products or services is not.
- Screenshots: `docs/assets/screenshots/`, displayed directly in the README files.
- Includes the Xcode project and source. Excludes the website draft, promotional artwork, build caches, local signing configuration, private deployment history, and signed installation packages.

Product name: **Pocket Touchpad**. Repository name: `Pocket-Touchpad`.

Repository description:

> An iPhone trackpad and keyboard for Mac, with portrait and dual-hand landscape controls. Source available; commercial work with the tool is allowed.

Topics: `swift`, `swiftui`, `ios`, `macos`, `trackpad`, `remote-control`, `source-available`.

The repository contains source, documentation, and screenshots. No GitHub Pages site or signed binary release is provided.

## 简体中文

仓库：[Ian-Wuu/Pocket-Touchpad](https://github.com/Ian-Wuu/Pocket-Touchpad)。

运行 `python3 scripts/package-github.py`，生成 `dist/Pocket-Touchpad-GitHub.zip`。解压后，将 `Pocket-Touchpad/` 内的内容放到 GitHub 仓库根目录。

- 默认首页是英文 `README.md`，顶部链接到中文 `README.zh-CN.md`。
- 介绍由文字与实际截图组成，包含当前功能、安装方式、限制与许可。
- `LICENSE` 使用项目专用的 Pocket Touchpad Source-Available License 1.0，`NOTICE` 为版权与许可摘要，`docs/OPEN_SOURCE.md` 为英文在前的中英文声明。
- 允许用户用工具完成商业作品、收费工作和企业内部工作；禁止将本项目源码或修改版做成商业产品或服务。
- 包含 Xcode 项目和源码，不包含网页、宣传海报、构建缓存、个人签名配置、旧部署记录或已签名安装包。

产品名：**Pocket Touchpad（口袋触控板）**。仓库名：`Pocket-Touchpad`。

中文描述：iPhone 触控板与 Mac 接收端，支持横竖屏、多指手势和手机键盘。源码公开，允许用于商业工作。

仓库发布源码、文档和截图，不提供 GitHub Pages 网站或已签名二进制发行包。
