#!/bin/zsh
# Builds eMotion and makes the separate test copy, build/eMotionTest.app, with
# its own bundle id (com.nidhin.emotion.selftest), so tests never touch the
# copy of the app in use. Usage: make-test-app.sh [debug|release]
cd "$(dirname "$0")/../.."
./make-app.sh ${1:-debug} 2>&1 | grep -E "error:|warning:|built" | tail -3
rm -rf build/eMotionTest.app && cp -R build/eMotion.app build/eMotionTest.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nidhin.emotion.selftest" -c "Set :CFBundleName eMotionTest" \
    -c "Set :CFBundleExecutable eMotionTest" build/eMotionTest.app/Contents/Info.plist
mv build/eMotionTest.app/Contents/MacOS/eMotion build/eMotionTest.app/Contents/MacOS/eMotionTest
codesign --force --deep --sign - build/eMotionTest.app 2>/dev/null
