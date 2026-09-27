#!/usr/bin/env python3
"""Writes ui.html from ui.src.html with PP Kyoto Light embedded, since a
Figma plugin's panel must be a single file. Run it after editing the panel:

    python3 build.py
"""
import base64
import pathlib

here = pathlib.Path(__file__).resolve().parent
font = here.parent / "Packages/MotionKit/Sources/Theme/Resources/Fonts/PPKyoto-Light.otf"
source = (here / "ui.src.html").read_text()
page = source.replace("{{KYOTO}}", base64.b64encode(font.read_bytes()).decode())
doctype, rest = page.split("\n", 1)
(here / "ui.html").write_text(doctype + "\n<!-- Made by build.py from ui.src.html: edit that, not this. -->\n" + rest)
print("wrote ui.html")
