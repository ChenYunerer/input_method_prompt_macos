# 应用图标

- 源图：`AppIcon.png`，内置 image_gen 工具生成，保留透明背景。
- 设计：浅薄荷圆角底、青绿色「中」与柔和珊瑚色「a」，小清新扁平化风格，圆润字形与充足留白。
- 构建：`bash app/scripts/build-icon.sh`，生成缓存位于 `app/.build/`。
- `build-app.sh` 自动生成各尺寸图标并打包到 `Contents/Resources/AppIcon.icns`。

## 原始生成提示词

```text
Use case: logo-brand.
Asset type: production macOS app icon, Chinese/English input indicator.
Design a fresh, airy, youthful and friendly minimalist FLAT app icon. 1024x1024 square RGBA image, genuine alpha transparency outside a macOS continuous rounded-square silhouette. Rounded-square tile inset about 70 pixels from each canvas edge.
Use an almost-white very pale mint solid tile (#EDF8F3). Central motif: exactly the Chinese character “中” in clean seafoam teal (#36AFA0) and a lowercase Latin “a” in soft warm coral (#EF9F91). Arrange the two glyphs as a compact, optically balanced typographic pair across the middle, 中 slightly higher on the left and a slightly lower on the right, with ample clear space between them. Both glyphs fully visible. Overall symbol group should occupy only about 60% of the tile width, with generous breathing room all around. Use medium-weight rounded contemporary sans-serif letterforms: friendly, crisp and light, not huge or heavy, not calligraphic. The lowercase a should be single-storey for a softer contemporary character. No decorations or other symbols. Clear silhouette and readable at 32 pixels.
Pure flat vector-like color shapes, perfectly smooth clean edges. No gradients, no glow, no texture, no shiny glass, no bevel, no 3D, no shadows, no keyboard buttons, no stacked cards, no thick borders. Absolutely no navy, black or dark background. Think fresh spring air, quiet mint stationery and modern independent macOS utility, not corporate branding or retro skeuomorphism.
No mockup, no surrounding scene, no text except exactly 中 and a, no logo, no watermark, no fake checkerboard. Transparent pixels outside the light mint rounded-square tile.
```
