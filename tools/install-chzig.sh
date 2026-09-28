#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  sh tools/install-chzig.sh [--prefix DIR]

Installs the `chzig` command. The default prefix is $HOME/.local, so the
command is installed as $HOME/.local/bin/chzig. The Zig WCH-LinkE writer is
built and copied into $prefix/libexec/chzig/wchlinke for `chzig flash`.
EOF
}

die() {
  printf 'install-chzig: %s\n' "$*" >&2
  exit 1
}

prefix="${HOME:-}/.local"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || die "--prefix requires a value"
      prefix=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$prefix" ] || die "prefix is empty"

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
src="$repo_root/tools/chzig"
dest_dir="$prefix/bin"
dest="$dest_dir/chzig"
libexec_dir="$prefix/libexec/chzig"
wchlinke_dest="$libexec_dir/wchlinke"

[ -f "$repo_root/build.zig.zon" ] || die "run this installer from the ch32fun_zig checkout"
[ -f "$src" ] || die "missing $src"

(cd "$repo_root" && zig build)
[ -x "$repo_root/zig-out/bin/wchlinke" ] || die "WCH-LinkE writer build failed"

mkdir -p "$dest_dir"
mkdir -p "$libexec_dir"
cp "$repo_root/zig-out/bin/wchlinke" "$wchlinke_dest"
chmod 755 "$wchlinke_dest"
awk -v repo_root="$repo_root" '
  /^EMBEDDED_CH32FUN_ZIG_HOME=/ {
    print "EMBEDDED_CH32FUN_ZIG_HOME=\"" repo_root "\""
    next
  }
  /^EMBEDDED_WCHLINKE=/ {
    print "EMBEDDED_WCHLINKE=\"@WCHLINKE_INSTALLED@\""
    next
  }
  { print }
' "$src" | sed "s|@WCHLINKE_INSTALLED@|$wchlinke_dest|g" > "$dest"
chmod 755 "$dest"

printf 'installed %s\n' "$dest"
printf 'installed %s\n' "$wchlinke_dest"
case ":${PATH:-}:" in
  *":$dest_dir:"*) ;;
  *) printf 'add %s to PATH to run `chzig` from any directory\n' "$dest_dir" ;;
esac
