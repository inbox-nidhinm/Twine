#!/bin/zsh
# Puts the test driver into the app: copies SelfTest.swift in and adds the one
# line that starts it when a project window opens. Undo with remove-hook.sh
# before committing.
cd "$(dirname "$0")/../.."
cp Tools/SelfTest/SelfTest.swift Twine/App/SelfTest.swift
grep -q "SelfTest.run" Twine/Document/EditorWindowController.swift || python3 - <<'PY'
p='Twine/Document/EditorWindowController.swift'
s=open(p).read()
s=s.replace("        if let window { TrafficLights.retry(in: window) }\n    }\n",
            "        if let window { TrafficLights.retry(in: window) }\n        if let window { SelfTest.run(window: window, controller: controller, menus: menus) }\n    }\n",1)
open(p,'w').write(s)
PY
grep -c "SelfTest.run" Twine/Document/EditorWindowController.swift
