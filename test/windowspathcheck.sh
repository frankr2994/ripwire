#!/usr/bin/env bash
# windowspathcheck.sh — Windows-native path spelling must behave like Git paths.
#
# The crawler and selector resolver receive a mixture of Git's forward-slash
# paths and native Windows paths. This gate keeps the two spellings equivalent
# for ignore accounting, changed-file discovery, and qualified symbol expansion.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "windowspathcheck: no git on PATH — SKIP"; exit 0; }

REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/ignored"
printf 'ignored/\n' >"$REPO/.gitignore"
printf 'export function rwWindowsPathSymbol(value: number) { return value + 1; }\n' >"$REPO/src/demo.ts"
printf 'export function rwIgnoredWindowsSymbol(value: number) { return value + 9; }\n' >"$REPO/ignored/demo.ts"
(
    cd "$REPO" || exit 1
    git init -q .
    git config user.email gate@example.invalid
    git config user.name gate
    git add .gitignore src/demo.ts
    git commit -qm fixture
)
printf 'export function rwWindowsPathSymbol(value: number) { return value + 2; }\n' >"$REPO/src/demo.ts"

run_repo(){ ( cd "$REPO" && "$BIN" . "$@" ); }

SITU="$(run_repo --situ --no-cache 2>"$TMP/situ.err")"
printf '%s' "$SITU" | grep -q '1 changed file(s)' \
    && ok "Git diff detects the changed tracked file" \
    || no "Git diff missed the changed tracked file (stderr: $(cat "$TMP/situ.err"))"

GATE="$(run_repo '--test-gate=.\src\demo.ts' --no-cache 2>/dev/null)"
printf '%s' "$GATE" | grep -q 'changed="1"' \
    && ok "native Windows changed-file selector reaches the test gate" \
    || no "native Windows changed-file selector was not resolved by the test gate"

SKIPPED="$(run_repo --skipped --no-cache 2>/dev/null)"
printf '%s' "$SKIPPED" | grep -q 'ignored_dirs="1"' \
    && ok "Git-ignore accounting recognizes the ignored directory" \
    || no "Git-ignore accounting did not recognize the ignored directory"

FORWARD="$(run_repo '--expand=src/demo.ts:rwWindowsPathSymbol' --top-k=0 --no-cache 2>/dev/null)"
printf '%s' "$FORWARD" | grep -q 'value + 2' \
    && ok "forward-slash qualified selector expands the changed body" \
    || no "forward-slash qualified selector failed"

NATIVE="$(run_repo '--expand=.\src\demo.ts:rwWindowsPathSymbol' --top-k=0 --no-cache 2>/dev/null)"
printf '%s' "$NATIVE" | grep -q 'value + 2' \
    && ok "native Windows qualified selector expands the changed body" \
    || no "native Windows qualified selector failed"

[ "$fail" -eq 0 ] && { echo "windowspathcheck: PASS"; exit 0; }
echo "windowspathcheck: FAIL"; exit 1
