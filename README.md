# 中英提示

macOS 输入法状态提示工具，支持中英文、Caps Lock 提示、全屏常驻提示、鼠标跟随提示、透明度设置和登录时自动启动。

- `app/`：软件工程，包括 Swift 包配置、源码、测试、构建脚本及开发说明。
- `dist/中英提示.app`：可双击运行的应用。

详细使用和开发说明见 [app/README.md](app/README.md)。

产品与设计文档：[PRD](app/docs/PRD.md) · [技术方案](app/docs/TECHNICAL_DESIGN.md)。

在当前目录构建与验证：

```sh
bash app/scripts/build-app.sh
bash app/scripts/test.sh
```

构建缓存保存在 `app/.build/`。整理前的缓存保留在 `app/.build-previous/`，不纳入版本管理。
