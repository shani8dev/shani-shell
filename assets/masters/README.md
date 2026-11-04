# The wallpaper masters

`day.png`, `dusk.png`, `night.png` — ShaniOS's wallpaper masters, supplied by
the project. Same composition in three palettes:

| Master      | Look                          | Meta name      |
|-------------|-------------------------------|----------------|
| `day.png`   | blue sky, bright planet, calm | Shani day      |
| `dusk.png`  | amber dusk, the brand amber   | Shani twilight |
| `night.png` | deep indigo night, Milky Way  | Shani night    |

These are the sources of truth for `assets/shani-light.jpg` (day),
`assets/shani-dark.jpg` (dusk — the shell's dark default) and
`assets/shani-night.jpg` (the picker wallpaper) — do not edit the JPEGs by
hand. Rebuild with `make-wallpapers.py` (any directory; it writes next to
itself): Lanczos to 3840x2160, then a mild unsharp to recover the micro-contrast
the 2.3x upscale softens.

The Plasma look (`shani-desktop-plasma`) ships matching images converted with
the same script, in its day / twilight / night slots.
