Cross-ref: shani-shell ↔ shani-desktop-plasma (shani-pkgbuilds)
- Glass palette (shell bar/card): #0b0d12 bg, #7fd1c1 accent -> maps to
  plasma color-schemes/ + Kvantum theme under shani-desktop-plasma/usr/share/
- Wallpapers: shani-shell/assets/shani-dark.jpg and shani-light.jpg (rendered by assets/make-wallpapers.py); the earlier assets/wallpaper.png, which a plasma wallpaper copy was made from, is gone
- Blur: shell uses ext-background-effect-v1 (protocol + layer-rule); plasma
  compositor uses its own blur (not this contract) — kept separate
- Agent contract (dev.shani.chronoa.Agent): not tied to plasma theme
