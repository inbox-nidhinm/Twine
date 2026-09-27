#!/bin/zsh
# Samples the test copy's threads while a run.sh script plays, then ranks the
# app's own functions on the main thread by time.
#
#     profile.sh PROJECT NAME "steps" DELAY SECONDS
#
# Starts sampling DELAY seconds after launch, for SECONDS. Writes
# $OUT/NAME.sample.txt and prints the ranking.
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTROOT=${EMOTION_TEST_OUT:-${TMPDIR%/}/emotion-selftest}
N="Twine""Test"
pkill -x "$N"; sleep 2
$HERE/run.sh $1 $2 "$3" >/dev/null 2>&1 &
sleep 4
for i in {1..60}; do P=$(pgrep -x "$N"); [[ -n $P ]] && break; sleep 0.5; done
sleep $4
sample $P $5 -mayDie -file $OUTROOT/$2.sample.txt >/dev/null 2>&1
wait
grep PERF $OUTROOT/$2.log
python3 $HERE/hot.py $OUTROOT/$2.sample.txt TwineTest | head -40
