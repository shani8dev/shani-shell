# shani_link — vendored phone backends

This is `shani-link`'s `shani_link` Python package with its GTK `app/`
directory left out. The shell's Calls, Messages and Contacts apps use these
backends through `bridge/link.py`, so the shell works even when the separate
`shani-link` GTK app is not installed.

Re-sync from the sibling repo after upstream changes:

```sh
cd <shani-shell>/bridge
rm -rf shani_link
mkdir shani_link
cp ../shani-link/shani_link/*.py shani_link/
cp -r ../shani-link/shani_link/landline shani_link/ 2>/dev/null || true
rm -rf shani_link/app shani_link/__pycache__ shani_link/landline/__pycache__
```

The PKGBUILD packages this whole directory to `/usr/lib/shani-shell/shani_link`.
