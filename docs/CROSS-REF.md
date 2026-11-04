Cross-ref: shani-shell ↔ shani-desktop-plasma (shani-pkgbuilds)
- Glass palette (shell bar/card): #0b0d12 bg, #ff7f50 accent -> maps to
  plasma color-schemes/ + Kvantum theme under shani-desktop-plasma/usr/share/
- Wallpapers: shani-shell/assets/shani-{dark,light,night}.jpg — ShaniOS's own artwork (raven beneath a ringed planet, one composition in amber-dusk / day / night palettes), upscaled 3840x2160 from the masters in assets/masters/ by assets/make-wallpapers.py. Dark ships the amber dusk, light the day, and the night art is the picker wall; the Plasma look maps all three (images / images_twilight / images_dark), its twilight slot using the same dusk master
- Blur: shell uses ext-background-effect-v1 (protocol + layer-rule); plasma
  compositor uses its own blur (not this contract) — kept separate
- Agent contract (dev.shani.chronoa.Agent): not tied to plasma theme
