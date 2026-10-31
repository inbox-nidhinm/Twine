#!/usr/bin/env python3
"""Writes ui.html from ui.src.html with AA Bridge Slab embedded, since a
Figma plugin's panel must be a single file. Run it after editing the panel:

    python3 build.py

When the AA-Bridge submodule (Vendor/AA-Bridge) is checked out, the web font
is first refreshed from it by Tools/update-fonts.sh; otherwise the committed
AABridgeSlab.woff2 here is used.
"""
import base64
import os
import pathlib
import subprocess

here = pathlib.Path(__file__).resolve().parent
update = here.parent / "Tools" / "update-fonts.sh"
if not os.environ.get("TWINE_FONTS_COPIED") and update.exists():
    subprocess.run([str(update)], check=True)
font = here / "AABridgeSlab.woff2"
source = (here / "ui.src.html").read_text()
page = source.replace("{{AA_BRIDGE_SLAB}}", base64.b64encode(font.read_bytes()).decode())
doctype, rest = page.split("\n", 1)
(here / "ui.html").write_text(doctype + "\n<!-- Made by build.py from ui.src.html: edit that, not this. -->\n" + rest)
print("wrote ui.html")
