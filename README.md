# 🗑️ RunningTrash

> 一个会逃跑、会顶嘴、会吞东西的 macOS 废纸篓。两只废纸篓：一只老实待在菜单栏干活，一只在桌面上到处乱跑。
>
> A macOS trash can that runs from your cursor, talks back when caught, and actually eats your files. Two cans — one works in the menu bar, one causes trouble on your desktop.

[![Website](https://img.shields.io/badge/🌐_网站-Live-5eead4?style=for-the-badge)](https://wintlin776.github.io/running-trash/)
[![Download](https://img.shields.io/badge/⬇_下载_DMG-393_KB-46e0a8?style=for-the-badge)](https://wintlin776.github.io/running-trash/downloads/RunningTrash.dmg)

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/arch-arm64-blue)
![Swift](https://img.shields.io/badge/Swift-AppKit-orange?logo=swift)
![License](https://img.shields.io/badge/made_with-Swift_+_AppKit-orange)

---

## ✨ 特性 / Features

- 🏃 **会逃跑** — 鼠标靠近就开溜，越近跑越快，还会躲屏幕边缘、偶尔"跑累"。
- 💬 **会顶嘴** — 抓住它头顶弹出随机垃圾话，每次都不一样。
- 😋 **真能吞文件** — 拖文件进去会播放挤压拉伸的吞咽动画，文件真的进系统废纸篓。
- 🔄 **和系统实时同步** — 跟随系统废纸篓的空 / 满状态；清空时轻松一蹦，外部塞满时惊讶一抖。
- 🎯 **一键聚焦** — 菜单里「聚焦废纸篓」(快捷键 `F`)，它闪现到右下角定住 6 秒方便扔东西。
- 🪶 **轻量** — 不占程序坞、点击穿透、原生 Swift + AppKit，几乎不吃资源。

## 📦 下载 / Download

直接下载打包好的 DMG：[`docs/downloads/RunningTrash.dmg`](docs/downloads/RunningTrash.dmg)（约 393 KB，含使用说明）。

拖进「应用程序」即可。首次打开：右键 App →「打开」放行（自签名、非恶意软件）。

## 🔨 从源码编译 / Build from source

```bash
./build.sh          # 用命令行工具编译，无需完整 Xcode
open build/RunningTrash.app
```

然后到「系统设置 → 隐私与安全性 → 辅助功能」勾选 RunningTrash —— 桌面那只才会逃跑。

> 要求：macOS 13+ · Apple Silicon（arm64）。

## 🗂 项目结构 / Layout

```
Sources/        Swift 源码
  AppDelegate.swift        入口、接线
  MenuBarTrash.swift       菜单栏废纸篓（真正干活）
  RunningTrashWindow.swift 桌面逃跑废纸篓（逃跑/吞咽/聚焦/反应动画）
  TrashMonitor.swift       监控系统废纸篓空/满
  TrashIcon.swift          图标加载
Resources/      Info.plist / 图标
build.sh        一键编译打包
docs/           炫酷介绍网页（中英双语）+ DMG 下载（GitHub Pages 根目录）
```

## 🌐 网页 / Landing page

`docs/index.html` 是一个自包含的单页介绍站（中英切换、滚动驱动动画、可交互的逃跑废纸篓）。本地直接双击即可打开，线上版由 GitHub Pages 从 `main` 分支的 `/docs` 目录发布。

---

图标取自 macOS 系统原装 · 用 Swift + AppKit 手搓 · 玩得开心 :)
