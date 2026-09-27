#!/bin/zsh
# Takes the test driver back out of the app. Always run before committing.
cd "$(dirname "$0")/../.."
rm -f Twine/App/SelfTest.swift
python3 - <<'PY'
p='Twine/Document/EditorWindowController.swift'
s=open(p).read()
s=s.replace("        if let window { SelfTest.run(window: window, controller: controller, menus: menus) }\n","")
open(p,'w').write(s)
PY
git status --short Twine
