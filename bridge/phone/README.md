# phone — the shell's device backends

This package is part of shani-shell. Calls, Messages, Contacts, Health and the
Devices window use these engines through the bridges in `bridge/`, so the
shell works with no separate phone app installed.

Nothing here is re-synced from another repository. `landline/media.py`,
`landline/ua.py` and `landline/video.py` are the media engine: move or rename
their imports only, never their internals.

State lives in the shell's own homes (`~/.config/shani-shell/`,
`~/.local/share/shani-shell/`, `~/.local/state/shani-shell/`). On first start
the shell quietly moves earlier phone data into those homes.
