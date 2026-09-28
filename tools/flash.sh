#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: tools/flash.sh <example>" >&2
  exit 2
fi

EXAMPLE="$1"
BIN="zig-out/firmware/${EXAMPLE}.bin"
WCHLINKE="zig-out/bin/wchlinke"

if [ ! -x "$WCHLINKE" ]; then
  echo "WCH-LinkE tool not found: $WCHLINKE" >&2
  echo "Build it first: zig build" >&2
  exit 1
fi

if [ ! -f "$BIN" ]; then
  echo "missing binary: $BIN" >&2
  echo "run: zig build -Dexample=$EXAMPLE" >&2
  exit 1
fi

exec "$WCHLINKE" "$BIN"
