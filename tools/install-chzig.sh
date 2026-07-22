#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  sh tools/install-chzig.sh [--prefix DIR] [--minichlink PATH]

Installs the `chzig` command. The default prefix is $HOME/.local, so the
command is installed as $HOME/.local/bin/chzig. A local minichlink binary is
copied into $prefix/libexec/chzig/minichlink and used by `chzig flash`.
EOF
}

die() {
  printf 'install-chzig: %s\n' "$*" >&2
  exit 1
}

prefix="${HOME:-}/.local"
minichlink=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || die "--prefix requires a value"
      prefix=$2
      shift 2
      ;;
    --minichlink)
      [ "$#" -ge 2 ] || die "--minichlink requires a value"
      minichlink=$2
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
minichlink_dest="$libexec_dir/minichlink"

[ -f "$repo_root/build.zig.zon" ] || die "run this installer from the ch32fun_zig checkout"
[ -f "$src" ] || die "missing $src"

if [ -z "$minichlink" ]; then
  if [ "${MINICHLINK:-}" ]; then
    minichlink=$MINICHLINK
  else
    minichlink="$repo_root/../ch32fun/minichlink/minichlink"
  fi
fi
[ -x "$minichlink" ] || die "minichlink not found or not executable: $minichlink"

mkdir -p "$dest_dir"
mkdir -p "$libexec_dir"
cp "$minichlink" "$minichlink_dest"
chmod 755 "$minichlink_dest"
awk -v repo_root="$repo_root" '
  /^EMBEDDED_CH32FUN_ZIG_HOME=/ {
    print "EMBEDDED_CH32FUN_ZIG_HOME=\"" repo_root "\""
    next
  }
  /^EMBEDDED_MINICHLINK=/ {
    print "EMBEDDED_MINICHLINK=\"@MINICHLINK_INSTALLED@\""
    next
  }
  { print }
' "$src" | sed "s|@MINICHLINK_INSTALLED@|$minichlink_dest|g" > "$dest"
chmod 755 "$dest"

printf 'installed %s\n' "$dest"
printf 'installed %s\n' "$minichlink_dest"
case ":${PATH:-}:" in
  *":$dest_dir:"*) ;;
  *) printf 'add %s to PATH to run `chzig` from any directory\n' "$dest_dir" ;;
esac
