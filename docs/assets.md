# 资源来源

- App 图标由 `scripts/make_icon.swift` 使用 AppKit 路径绘制。仓库包含各尺寸生成结果，可以重新运行脚本生成。
- 界面中的标记由 `Design/DaylineDesign.swift` 的 `DaylineMark` 绘制。
- 纸纹为本项目使用图像生成工具生成的静态素材，路径为 `Design/Assets.xcassets/PaperTexture.imageset/paper.png`。它仅作装饰，没有文字、第三方商标或运行时网络依赖，可以替换或在设置中关闭。
- 界面使用系统字体与 SF Symbols；系统字体和符号字体不随仓库重新分发。

图标生成：

```sh
swift scripts/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
```

原纸纹提示词：

```text
Square seamless static background texture for a premium minimalist task app. Pure white paper filling every edge, sparse shallow softly wrinkled creases and nearly invisible fibers. Neutral monochrome, extremely high-key diffuse light, whisper-soft shadows. No beige, blue, purple, dirty speckles, hard folds, vignette, borders, objects, text or logos. Calm writing surface suitable beneath small black UI text.
```

仓库中的项目自有代码、图标绘制与文档按 MIT 提供；纸纹作为项目素材一同提供。
