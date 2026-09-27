#!/bin/zsh
# Builds the app and makes the separate test copy, build/TwineTest.app, with
# its own bundle id (com.nidhin.emotion.selftest), so tests never touch the
# copy of the app in use. Usage: make-test-app.sh [debug|release]
cd "$(dirname "$0")/../.."
./make-app.sh ${1:-debug} 2>&1 | grep -E "error:|warning:|built" | tail -3
rm -rf build/TwineTest.app && cp -R build/Twine.app build/TwineTest.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nidhin.emotion.selftest" -c "Set :CFBundleName TwineTest" \
    -c "Set :CFBundleExecutable TwineTest" build/TwineTest.app/Contents/Info.plist
mv build/TwineTest.app/Contents/MacOS/Twine build/TwineTest.app/Contents/MacOS/TwineTest
codesign --force --deep --sign - build/TwineTest.app 2>/dev/null
