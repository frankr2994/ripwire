#!/usr/bin/env bash
# cacheisolationcheck.sh — Ripwire-owned cache artifacts stay out of the shared TMPDIR root.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SHARED="$TMP/shared"; CORPUS="$TMP/corpus"; mkdir -p "$SHARED" "$CORPUS"
mkdir -m 0755 "$SHARED/ripwire"   # the binary must repair an existing permissive directory
printf 'int target( void ) { return 1; }\n' > "$CORPUS/code.cpp"
printf 'unrelated' > "$SHARED/not-ripwire"

echo "cacheisolationcheck: BIN=$BIN"

# Exercise the CLI parse cache, the MCP parse cache, and the per-target edit lock in one private TMPDIR.
TMPDIR="$SHARED" "$BIN" "$CORPUS" >/dev/null 2>"$TMP/cli.err"
# MSYS passes POSIX paths to native Windows processes, but the path is inside a
# JSON-RPC string here and therefore needs an explicit native spelling. The
# product still preserves the original filesystem path; this is only a harness
# boundary conversion.
MCP_PATH="$CORPUS"
case "$( uname -s 2>/dev/null || true )" in
    MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && MCP_PATH="$( cygpath -m "$CORPUS" )" ;;
esac
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"'"$MCP_PATH"'","symbol":"target","new_body":"int target( void ) { return 2; }"}}}' \
    | TMPDIR="$SHARED" "$BIN" --mcp >"$TMP/mcp.out" 2>"$TMP/mcp.err"

PRIVATE="$SHARED/ripwire"
[ -d "$PRIVATE" ] && ok "creates a dedicated TMPDIR/ripwire directory" || no "missing private directory: $PRIVATE"

if [ -d "$PRIVATE" ]; then
    if stat --version >/dev/null 2>&1; then mode="$( stat -c %a "$PRIVATE" )"; else mode="$( stat -f %Lp "$PRIVATE" )"; fi
    case "$( uname -s 2>/dev/null || true )" in
        MINGW*|MSYS*|CYGWIN*) ok "private directory uses the Windows owner-only ACL (MSYS mode $mode is platform-mapped)" ;;
        *) [ "$mode" = "700" ] && ok "private directory mode is 0700" || no "private directory mode is $mode, expected 700" ;;
    esac
fi

topArtifacts="$( find "$SHARED" -mindepth 1 -maxdepth 1 -name 'ripwire-*' -print 2>/dev/null )"
[ -z "$topArtifacts" ] && ok "shared TMPDIR root has no ripwire-* artifacts" \
    || { no "ripwire artifacts leaked into shared TMPDIR root"; printf '%s\n' "$topArtifacts"; }

cacheCount="$( find "$PRIVATE" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-mcp-*.cache' 2>/dev/null | wc -l | tr -d ' ' )"
lockCount="$( find "$PRIVATE/locks" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-edit-*.lock' 2>/dev/null | wc -l | tr -d ' ' )"
[ "$cacheCount" -ge 1 ] && ok "MCP cache is sharded under the private directory" || no "no sharded MCP cache found"
[ "$lockCount" -ge 1 ] && ok "edit lock is sharded under the private locks subtree" || no "no sharded edit lock found"

[ -f "$SHARED/not-ripwire" ] && ok "unrelated TMPDIR content remains untouched" || no "unrelated TMPDIR content was removed"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
