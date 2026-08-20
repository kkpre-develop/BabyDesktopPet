# BabyDesktopPet 🍼

macOS 桌面悬浮宝宝宠物 —— 基于 AI 生成的宝宝形象，悬浮在桌面上会爬行、散步、说话、举相框展示照片。

## 下载

直接下载最新版应用（免编译）：

👉 **[下载 BabyDesktopPet_v4_ditto.zip](https://github.com/kkpre-develop/BabyDesktopPet/releases/latest)**（Releases 页面附件）

> **如果双击提示「已损坏，应该移到废纸篓」**：这是 macOS 对网上下载的未签名 App 的隔离提示，**文件本身没有坏**。在终端执行即可解决：
>
> ```bash
> xattr -cr /Applications/BabyDesktopPet.app
> ```
>
> （没放进「应用程序」就换成实际路径；完整图文说明见 Releases 附件 `INSTALL_FIX.txt`）

解压后拖入「应用程序」或双击运行即可。详细使用说明见 `安装说明.txt`。

## 功能

- 宝宝悬浮在桌面，可拖拽移动
- 待机呼吸/漂浮动画，自动随机切换动作（爬行、散步）
- 偶尔冒出气泡说话：「爸爸妈妈在干啥～」「我要睡觉啦」「我要出去玩」
- 右键菜单：切换动作、变大/变小、躲起来（只露眼睛以上）
- 举相框：宝宝举起相框，展示指定文件夹中随机 3 张照片，每 3 秒切换

## 源码结构

| 文件 | 说明 |
|------|------|
| `main.m` | 应用主程序（Objective-C + AppKit） |
| `extract_frames.py` | 从动作视频提取透明 PNG 帧序列 |
| `remove_bg.py` | 背景去除处理脚本 |

## 编译

```bash
clang -fobjc-arc -framework AppKit -framework QuartzCore main.m -o BabyDesktopPet
```

需要将 `baby.png`、`frames_crawl/`、`frames_stroll/` 等资源放入 app bundle 的 `Contents/Resources/`（结构参考 Releases 中的完整包）。
