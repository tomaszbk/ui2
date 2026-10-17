#!/usr/bin/env bash
# Builds the V compiler pinned in scripts/v-pin.env, the same way CI does.
# Usage: scripts/setup-v.sh [install-dir]   (default: ~/.local/share/ui2-v)
# Then add the printed directory to PATH. Needs git and a C compiler (CC, or cc).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=v-pin.env
. "$here/v-pin.env"
dir=${1:-"$HOME/.local/share/ui2-v"}
cc=${CC:-cc}
case "$(uname -s)" in
	Darwin) tcc_revision=$TCC_REVISION_MACOS ;;
	Linux) tcc_revision=$TCC_REVISION_LINUX ;;
	*) echo "use the CI setup action on this platform" >&2; exit 1 ;;
esac

fetch() { # fetch <repo> <revision> <dir>
	mkdir -p "$3"
	git -C "$3" init -q
	git -C "$3" remote remove origin 2>/dev/null || true
	git -C "$3" remote add origin "https://github.com/$1"
	git -C "$3" fetch -q --depth 1 origin "$2"
	git -C "$3" checkout -q --force FETCH_HEAD
}

fetch "$V_REPOSITORY" "$V_REVISION" "$dir"
fetch vlang/vc "$VC_REVISION" "$dir/vc"
fetch vlang/tccbin "$tcc_revision" "$dir/thirdparty/tcc"

cd "$dir"
"$cc" -DCUSTOM_DEFINE_v1_fallback -std=c99 -w -o v1 vc/v.c -lm -lpthread
./v1 -b c -no-parallel -cc "$cc" -o v2 -gc none cmd/v
./v2 -b c -nocache -cc "$cc" -o v -gc none cmd/v
rm -f v1 v2
./v version
echo "Add $dir to PATH"
