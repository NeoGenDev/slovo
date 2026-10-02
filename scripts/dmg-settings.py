# dmgbuild settings for the release disk image: large icons, the app on the left, Applications on
# the right, in a window without toolbars. No background picture: Finder on macOS 26 ignores the
# reference dmgbuild writes, and the plain window follows the light or dark appearance anyway.
# scripts/release.sh passes `app` and `icon` with -D.
import os.path

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]

format = "UDZO"
filesystem = "HFS+"

window_rect = ((200, 120), (560, 340))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (150, 160),
    "Applications": (410, 160),
}
