#!/usr/bin/env python3
"""Writes the projects Glass was checked with into a folder (the kit's
run.sh takes any .twine path):

    python3 Tools/SelfTest/make-glass-projects.py "$SCRATCH"

  Glass.twine  thin stripes; a 640 by 380 card (depth 60, refraction 100%),
               a star (depth 40) and a pill at Figma's new glass, frosted
  Mid.twine    a small card (120 by 80) and a 60 point star in the middle,
               to zoom in on (zoom 2;zoom 2;zoom 2)
  User.twine   the user's circle from 20 October 2026: 247.8 across,
               refraction 100%, depth 100, light 262 at 30%, dispersion 4%
  Edge.twine   that circle hanging off the composition's left edge

Each is built from the kit's Style project (format 2, read through every
migration), its stripes 20 wide every 40 in four colours.
"""
import copy
import json
import os
import sys
import uuid

KIT = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else "."

base = json.load(open(os.path.join(KIT, "Projects", "Style.twine", "document.json")))
bar = base["project"]["layers"][0]


def new_id():
    return str(uuid.uuid4()).upper()


def stripes():
    colours = [(0.9, 0.2, 0.2), (0.1, 0.3, 0.9), (1, 0.79, 0.3), (0.12, 0.12, 0.12)]
    layers = []
    for i in range(48):
        layer = copy.deepcopy(bar)
        layer["id"] = new_id()
        layer["name"] = f"Stripe {i + 1}"
        fill = layer["content"]["shape"]["fills"][0]
        fill["id"] = new_id()
        r, g, b = colours[i % 4]
        fill["paint"]["color"] = {"r": r, "g": g, "b": b, "a": 1}
        layer["size"] = {"width": 20, "height": 1080}
        layer["transform"]["anchor"] = {"x": 10, "y": 540}
        layer["transform"]["position"] = {"x": i * 40 + 10, "y": 540}
        layers.append(layer)
    return layers


def shape(name, geometry, w, h, x, y, glass, fill=None):
    layer = copy.deepcopy(bar)
    layer["id"] = new_id()
    layer["name"] = name
    layer["content"]["shape"]["geometry"] = geometry
    layer["content"]["shape"]["fills"] = [] if fill is None else [
        {"id": new_id(), "isEnabled": True, "paint": {"type": "solid", "color": fill}}]
    layer["size"] = {"width": w, "height": h}
    layer["transform"]["anchor"] = {"x": w / 2, "y": h / 2}
    layer["transform"]["position"] = {"x": x, "y": y}
    layer["effects"] = [{"id": new_id(), "isEnabled": True, "kind": {"type": "glass", "glass": glass}}]
    return layer


def rounded(r):
    return {"type": "rectangle", "cornerRadii": {"topLeft": r, "topRight": r, "bottomRight": r, "bottomLeft": r}}


STAR = {"type": "star", "points": 5, "innerRadius": 0.5, "cornerRadius": 0}
CIRCLE = {"type": "ellipse"}
FIGMA = {"lightAngle": -45, "lightIntensity": 0.8, "refraction": 0.8, "depth": 20, "dispersion": 0.5, "frost": 4, "splay": 0}
USER = {"lightAngle": 262, "lightIntensity": 0.3, "refraction": 1, "depth": 100, "dispersion": 0.04, "frost": 0, "splay": 0}


def write(name, layers):
    doc = copy.deepcopy(base)
    doc["project"]["layers"] = layers
    doc["project"]["actions"] = []
    folder = os.path.join(out, name + ".twine")
    os.makedirs(folder, exist_ok=True)
    json.dump(doc, open(os.path.join(folder, "document.json"), "w"), indent=1, sort_keys=True)
    print(folder)


write("Glass", stripes() + [
    shape("Card", rounded(60), 640, 380, 520, 330, dict(FIGMA, depth=60, refraction=1, frost=0)),
    shape("Star", STAR, 420, 400, 1400, 330, dict(FIGMA, depth=40, frost=0)),
    shape("Pill", rounded(100), 700, 200, 960, 820, FIGMA, fill={"r": 1, "g": 1, "b": 1, "a": 0.1}),
])
write("Mid", stripes() + [
    shape("Card", rounded(20), 120, 80, 960, 540, dict(FIGMA, depth=16)),
    shape("Star", STAR, 60, 60, 1060, 600, dict(FIGMA, depth=40, frost=0)),
])
write("User", stripes() + [shape("Ellipse", CIRCLE, 247.8, 247.8, 960, 543.2, USER)])
write("Edge", stripes() + [shape("Ellipse", CIRCLE, 247.8, 247.8, 140, 300, USER)])
