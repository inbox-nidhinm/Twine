#!/bin/zsh
# Runs a script of steps in the test copy on a fresh copy of a test project.
#
#     run.sh PROJECT NAME "step;step;..."
#
# PROJECT is a folder in Projects (Actions, Blank, Mask, Style, Text) or a
# path to any .twine package, which is copied first so the original is never
# touched. Screenshots asked for with "shot X" land in $OUT/NAME/X.png and the
# log in $OUT/NAME.log, where OUT is $TWINE_TEST_OUT or a folder in $TMPDIR.
# Prints the state after every step.
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../../build/TwineTest.app"
OUTROOT=${TWINE_TEST_OUT:-${TMPDIR%/}/twine-selftest}
PROJECT=$1; NAME=$2
[[ -d $PROJECT ]] && SRC=$PROJECT || SRC=$HERE/Projects/$PROJECT.twine
FILE=$(basename $SRC)
OUT=$OUTROOT/$NAME; LOG=$OUTROOT/$NAME.log
N="Twine""Test"
# Asked to quit, so an open project saves first; forced only if it will not.
if pgrep -x "$N" >/dev/null; then
    osascript -e 'quit app id "com.nidhin.twine.selftest"' >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$N" >/dev/null || break; sleep 0.5; done
    pkill -x "$N"
fi
sleep 1
# Each run's copy of the project lives in the run's own folder, so no run
# can overwrite another's, which someone may have gone on working in (a
# run once wiped a project the user had been using in the test copy). An
# earlier run of the same name goes to the Bin, never deleted outright.
mkdir -p $OUTROOT
if [[ -e $OUT ]]; then mv $OUT ~/.Trash/"twine-selftest-$NAME-$(date +%Y%m%d-%H%M%S)"; fi
mkdir -p $OUT
cp -R $SRC $OUT/$FILE
# The test copy keeps its projects in a folder of its own, never the one in use.
CREATIONS=${TWINE_TEST_CREATIONS:-$OUTROOT/Creations}; mkdir -p "$CREATIONS"
(TWINE_CREATIONS="$CREATIONS" TWINE_SHOTS=$OUT TWINE_SELFTEST="$3" "$APP/Contents/MacOS/$N" > $LOG 2>&1 &)
sleep 1.5; open -g -a "$APP" $OUT/$FILE
W=""
for i in {1..900}; do
  if [[ -z $W ]]; then
    P=$(pgrep -x "$N")
    [[ -n $P ]] && W=$(swift -e "import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String:Any]]; for w in l where (w[\"kCGWindowOwnerPID\"] as? Int) == $P { if (w[\"kCGWindowName\"] as? String) == \"$FILE\" { print(w[\"kCGWindowNumber\"]!) } }" 2>/dev/null | head -1)
  fi
  for s in $(grep '^SHOT ' $LOG 2>/dev/null | awk '{print $2}'); do
    if [[ ! -f $OUT/$s.png && -n $W ]]; then screencapture -x -o -l $W $OUT/tmp.png && mv $OUT/tmp.png $OUT/$s.png; fi
  done
  grep -q '^done' $LOG && break
  sleep 0.1
done
grep -E "^(after|done|unknown)" $LOG | cut -c1-330
