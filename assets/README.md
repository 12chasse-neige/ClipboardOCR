# App icon

`AppIcon.png` is the generated master, copied into this repository. `AppIcon.icns` is the macOS icon built from it using `scripts/make-icon.command` (Apple `sips` and `iconutil`). The menu-bar glyph remains a monochrome SF Symbol so it adapts to light and dark menus.

Generated with the built-in image generation tool on 2026-09-16. Prompt:

> Use case: logo-brand. Create one finished macOS app icon for Clipboard OCR, a private local image-to-Markdown text and mathematics utility. Square 1024x1024 composition. A crisp rounded-square app tile with softly layered glass and porcelain depth, cool blue and teal accents, and a centered white clipboard sheet. On the sheet use two short dark text strokes and one beautifully clear mathematical x² glyph, framed by four subtle scan-corner brackets. Restrained, elegant, highly legible at small icon sizes, front-facing, balanced generous inset, precise simple silhouette, soft studio light. True transparent outer background outside the rounded square tile, no surrounding scene, no caption, no app name, no watermark, no mockup sheet, only one icon. The tile should occupy about 86 percent of the canvas with even transparent margins. Designed for Finder and Dock; polished but avoid intricate tiny details.

The returned master is 1254 × 1254 pixels. Build-time resizing preserves its alpha channel and generates all ten standard macOS icon representations through 1024 × 1024.
