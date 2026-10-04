#!/bin/bash
# Builds Twine and puts a double-clickable copy at
# build/Twine.app.
#
#     ./make-app.sh            Release build
#     ./make-app.sh debug      Debug build
#
# The version is the number of builds listed in Twine/VersionHistory.swift,
# counted here and handed to Xcode, so the About box, the home screen and the
# bundle can never disagree.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-release}" in
    debug|Debug) CONFIG=Debug ;;
    *) CONFIG=Release ;;
esac

VERSION=$(grep -c '^        \.init(date:' Twine/VersionHistory.swift)

# The test driver (Tools/SelfTest) is compiled only into the test copy,
# which make-test-app.sh builds with TWINE_SELFTEST_BUILD=1. Any other build
# refuses while it is installed, so it can never ship by being forgotten.
EXTRA=()
if [[ -n "${TWINE_SELFTEST_BUILD:-}" ]]; then
    EXTRA=('OTHER_SWIFT_FLAGS=$(inherited) -D SELFTEST')
elif [[ -e Twine/App/SelfTest.swift ]] || grep -q "SelfTest.run" Twine/Document/EditorWindowController.swift; then
    echo "The test driver is installed. Run Tools/SelfTest/remove-hook.sh first."
    exit 1
fi

LOG=build/xcodebuild.log
mkdir -p build
if ! xcodebuild -project Twine.xcodeproj -scheme Twine -configuration "$CONFIG" \
        -derivedDataPath build/DerivedData \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" ${EXTRA[@]+"${EXTRA[@]}"} \
        build > "$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u || true
    echo "build failed, full log in $LOG"
    exit 1
fi

# Warnings are treated as failures of the milestone, so they are always shown.
grep -E "warning:" "$LOG" | grep -v "appintentsmetadataprocessor" | sort -u || true

rm -rf build/Twine.app
cp -R "build/DerivedData/Build/Products/$CONFIG/Twine.app" build/Twine.app
echo "built build/Twine.app (build $VERSION, $CONFIG)"
