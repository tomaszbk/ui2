#!/usr/bin/env bash
# Runs the VML conformance tests: every example document and the
# tests/compiled_vml fixtures, built compiled and interpreted (see
# ui/vml_conformance_d_vml_interpreter.v). Each test compiles a whole example
# twice over, so they only run when asked for with `-d vml_conformance`; this
# script passes it. Run from anywhere; the repository must live in a
# directory named `ui2`.
# Usage: scripts/vml-conformance.sh [shard shards]
# With a shard, runs every shards-th test starting at the shard-th (0-based).
set -eu
cd "$(dirname "$0")/../.."
V=${V:-v}
F=${VFLAGS:-"-b c -cc gcc"}
shard=${1:-0}
shards=${2:-1}
files=()
index=0
for file in ui2/tests/compiled_vml/vml_conformance_*_test.v ui2/examples/*/*_vml_conformance_test.v; do
	if ((index % shards == shard)); then files+=("$file"); fi
	index=$((index + 1))
done
echo "VML conformance shard $shard of $shards: ${#files[@]} of $index tests"
$V $F -d vml_conformance test "${files[@]}"
