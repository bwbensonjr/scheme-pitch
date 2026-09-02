#!/bin/sh
# Size-graded formatting benchmark. See tests/bench/README.md for what the
# corpus is and, just as importantly, for what this measurement does not cover.
#
# Not part of the correctness suite: timings vary with machine load, and a
# flaky timing in a correctness suite trains people to ignore failures. It is
# reached only through `make bench`.
#
# Reports, per member, its line count, wall time, cost per thousand lines and
# peak resident set, then the two ratios the formatting-performance
# requirements are stated in terms of.

set -e

PITCH=${PITCH:-build/pitch}
BENCH_DIR=${BENCH_DIR:-tests/bench}
BENCH_REPEATS=${BENCH_REPEATS:-3}

CODE_MEMBERS="code-small code-medium code-large"
DATA_MEMBER=data-large
# The hand-written member the data-dense one is compared against. The two are
# of comparable size, which is what makes their ratio a statement about shape
# rather than about size.
COMPARABLE=code-large

if [ ! -x "$PITCH" ]; then
  echo "bench: no formatter at $PITCH; run make pitch-build" >&2
  exit 2
fi

# Peak resident set needs a non-portable flag: `-lp` on BSD and macOS, `-f` on
# GNU. Probe once, so a host with neither says so here rather than producing a
# table of blanks.
if /usr/bin/time -lp true 2> /dev/null; then
  TIME_KIND=bsd
elif /usr/bin/time -f '%e %M' true 2> /dev/null; then
  TIME_KIND=gnu
else
  echo "bench: /usr/bin/time supports neither BSD -lp nor GNU -f" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

# `--stdout` runs the whole pipeline -- tokenize, parse, translate, layout,
# both output checks -- and writes the result, so it measures formatting rather
# than the decision not to rewrite a file. Unlike `--check` its exit status
# does not depend on whether the member is already a fixed point, so a corpus
# member does not have to be pre-formatted to be timed.
run_once() {
  case $TIME_KIND in
    bsd)
      /usr/bin/time -lp "$PITCH" --stdout --dialect r7rs \
        < "$1" > /dev/null 2> "$work/time"
      awk '/^real/ { s = $2 }
           /maximum resident set size/ { m = $1 / 1024 }
           END { printf "%s %d\n", s, m }' "$work/time"
      ;;
    gnu)
      /usr/bin/time -f '%e %M' "$PITCH" --stdout --dialect r7rs \
        < "$1" > /dev/null 2> "$work/time"
      tail -1 "$work/time"
      ;;
  esac
}

# Best of BENCH_REPEATS. The minimum is the least contaminated sample: load
# from elsewhere on the machine can only add time, never remove it.
measure() {
  member=$1
  input="$BENCH_DIR/$member.scm"
  best=
  i=0
  while [ "$i" -lt "$BENCH_REPEATS" ]; do
    if ! sample=$(run_once "$input"); then
      echo "bench: $PITCH refused $input" >&2
      exit 1
    fi
    if [ -z "$best" ]; then
      best=$sample
    else
      best=$(awk -v a="$best" -v b="$sample" \
        'BEGIN { split(a, x, " "); split(b, y, " ");
                 print (y[1] < x[1]) ? b : a }')
    fi
    i=$((i + 1))
  done
  lines=$(wc -l < "$input" | tr -d ' ')
  printf '%s %s %s\n' "$member" "$lines" "$best" >> "$work/results"
}

: > "$work/results"

echo "host:    $(uname -smr)"
if [ -r /proc/cpuinfo ]; then
  echo "cpu:     $(awk -F: '/model name/ { print $2; exit }' /proc/cpuinfo | sed 's/^ *//')"
elif command -v sysctl > /dev/null 2>&1; then
  echo "cpu:     $(sysctl -n machdep.cpu.brand_string 2> /dev/null)"
fi
echo "pitch:   $("$PITCH" --version 2>&1 | head -1)"
echo "scheme:  Emit, ahead-of-time build at $PITCH"
echo "repeats: $BENCH_REPEATS, best of"
echo

for member in $CODE_MEMBERS $DATA_MEMBER; do
  measure "$member"
done

printf '%-14s %7s %10s %14s %10s\n' member lines seconds s/1000lines peakMiB
awk '{ printf "%-14s %7d %10.2f %14.2f %10.1f\n",
         $1, $2, $3, $3 * 1000 / $2, $4 / 1024 }' "$work/results"
echo

# The ratios are reported rather than left to be computed: they are what the
# requirements are stated in, and a reader recomputing them from a table is a
# reader who can get them wrong.
awk -v code="$CODE_MEMBERS" -v data="$DATA_MEMBER" -v cmp="$COMPARABLE" '
  { per[$1] = $3 * 1000 / $2; lines[$1] = $2 }
  END {
    n = split(code, members, " ")
    for (i = 1; i <= n; i++) {
      m = members[i]
      if (smallest == "" || lines[m] < lines[smallest]) smallest = m
      if (largest  == "" || lines[m] > lines[largest])  largest  = m
      if (worst    == "" || per[m]   > per[worst])      worst    = m
    }
    size = per[largest] / per[smallest]
    printf "size ratio   %s / %s   %.2f  (bound 1.50)  %s\n",
      largest, smallest, size, (size <= 1.5 ? "ok" : "OVER")
    inter = per[worst] / per[smallest]
    printf "  worst member %-13s          %.2f  (bound 1.50)  %s\n",
      worst, inter, (inter <= 1.5 ? "ok" : "OVER")
    shape = per[data] / per[cmp]
    printf "shape ratio  %s / %s   %.2f  (bound 1.50)  %s\n",
      data, cmp, shape, (shape <= 1.5 ? "ok" : "OVER")
  }' "$work/results"
