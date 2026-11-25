#!/bin/zsh
# Builds the app and makes the separate test copy, build/TwineTest.app, with
# its own bundle id (com.nidhin.twine.selftest), so tests never touch the
# copy of the app in use. Usage: make-test-app.sh [debug|release]
cd "$(dirname "$0")/../.."
# The build's own word is kept: read through a filter alone, a failed build
# went unseen and the app from the build before was made into the test copy,
# so a test ran old code and looked like a pass.
out=$(TWINE_SELFTEST_BUILD=1 ./make-app.sh ${1:-debug} 2>&1)
built=$?
echo "$out" | grep -E "error:|warning:|built|driver|failed" | tail -5
if (( built != 0 )); then
    echo "The build failed, so the test copy was not made."
    exit 1
fi
rm -rf build/TwineTest.app && cp -R build/Twine.app build/TwineTest.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nidhin.twine.selftest" -c "Set :CFBundleName TwineTest" \
    -c "Set :CFBundleExecutable TwineTest" build/TwineTest.app/Contents/Info.plist
mv build/TwineTest.app/Contents/MacOS/Twine build/TwineTest.app/Contents/MacOS/TwineTest
# Signed with the hardened runtime, as the app is, and allowed to be
# inspected, so sample (profile.sh) can read it.
if ! codesign --force --deep --sign - --options runtime --entitlements Tools/SelfTest/TwineTest.entitlements build/TwineTest.app 2>/dev/null; then
    echo "Signing the test copy failed."
    exit 1
fi
