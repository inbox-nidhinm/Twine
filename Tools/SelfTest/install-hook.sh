#!/bin/zsh
# Puts the test driver into the app: copies SelfTest.swift in and adds the one
# line that starts it when a project window opens. Undo with remove-hook.sh
# before committing.
cd "$(dirname "$0")/../.."
cp Tools/SelfTest/SelfTest.swift eMotion/App/SelfTest.swift
grep -q "SelfTest.run" eMotion/Document/EditorWindowController.swift || python3 - <<'PY'
p='eMotion/Document/EditorWindowController.swift'
s=open(p).read()
s=s.replace("        HomeWindowController.shared.close()\n    }\n",
            "        HomeWindowController.shared.close()\n        if let window { SelfTest.run(window: window, controller: controller, menus: menus) }\n    }\n",1)
open(p,'w').write(s)
PY
grep -c "SelfTest.run" eMotion/Document/EditorWindowController.swift
