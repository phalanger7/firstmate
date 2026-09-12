#!/usr/bin/env bash
# Field reproduction of the knotkin failure, driven against the real scripts.
set -u
ROOT=/home/phloid/.no-mistakes/worktrees/86f59197aae3/01M2AAKYAZM4V5GQC2E0ZE6QAM
. "$ROOT/tests/fixtures.sh"
G() { git -c user.name='Captain' -c user.email='cap@example.invalid' "$@"; }

CASE=$(mktemp -d /tmp/knotkin-e2e.XXXXXX)
home=$CASE/home; project=$CASE/project; origin=$CASE/origin.git; pool=$CASE/pool
fakebin=$(fm_test_make_spawn_fakebin "$CASE/fake")
id1=knotkin-feature-r1
id2=knotkin-next-r1
mkdir -p "$home/data" "$home/projects" "$home/state" "$home/config"
printf 'codex\n' > "$home/config/crew-harness"
fm_test_spawn_brief "$home" "$id2"
touch "$home/state/.last-watcher-beat"
printf -- '- project [local-only] - knotkin-like project\n' > "$home/data/projects.md"

echo "== 1. captain's local-only project, origin exists but is never pushed to =="
G init --quiet -b main "$project"
printf 'v1\n' > "$project/app.txt"; G -C "$project" add app.txt; G -C "$project" commit -qm "initial"
G clone --quiet --bare "$project" "$origin"
G -C "$project" remote add origin "file://$origin"
G -C "$project" fetch --quiet origin
G -C "$project" branch --quiet --set-upstream-to=origin/main main 2>/dev/null

echo "== 2. first task ships an approved feature; fm-merge-local lands it on LOCAL main =="
G -C "$project" branch "fm/$id1" main
G -C "$project" worktree add --quiet "$CASE/wt1" "fm/$id1"
printf 'v1\nAPPROVED FEATURE the captain just accepted\n' > "$CASE/wt1/app.txt"
G -C "$CASE/wt1" add app.txt; G -C "$CASE/wt1" commit -qm "feat: the approved feature"
G -C "$CASE/wt1" checkout --quiet --detach HEAD
fm_write_meta "$home/state/$id1.meta" "window=fm-$id1" "worktree=$CASE/wt1" "project=$project" "mode=local-only"
FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
  "$ROOT/bin/fm-merge-local.sh" "$id1" 2>&1 | sed 's/^/   merge-local: /'
echo "   local main:  $(G -C "$project" log --oneline -1 main)"
echo "   origin/main: $(G -C "$project" log --oneline -1 origin/main)   <- feature was never pushed"

echo
echo "== 3. pooled slot allocated before the merge; next local-only task spawns into it =="
G -C "$project" worktree add --quiet --detach "$pool" "$(G -C "$project" rev-parse origin/main)"
out=$(fm_test_run_spawn "$home" "$pool" "$fakebin" "$id2" "$project" --mode local-only --yolo off)
echo "$out" | sed 's/^/   spawn: /'
echo "   pooled HEAD app.txt:"
sed 's/^/     | /' "$pool/app.txt"

echo
echo "== 4. the worker commits its own change on fm/$id2 and the review diff is taken =="
G -C "$pool" checkout --quiet -b "fm/$id2"
# The worker edits the file it was handed - it appends to ITS base, whatever that is.
printf 'new work from this task\n' >> "$pool/app.txt"
G -C "$pool" add app.txt; G -C "$pool" commit -qm "feat: this task's own change"
fm_write_meta "$home/state/$id2.meta" "window=fm-$id2" "worktree=$pool" "project=$project" "mode=local-only"
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
  "$ROOT/bin/fm-review-diff.sh" "$id2" 2>&1 | sed 's/^/   /'

echo
echo "== verdict =="
echo "   what landing this branch would do to local main:"
G -C "$project" diff main.."fm/$id2" -- app.txt | sed 's/^/     | /'
if G -C "$project" diff main.."fm/$id2" -- app.txt | grep -q '^-.*APPROVED FEATURE'; then
  echo "   FAIL: the branch REVERTS the approved feature the captain just accepted."
else
  echo "   PASS: the branch adds its own work and leaves the approved feature intact."
fi
