# VML build benchmark

Measures construction and disposal of the retained `ui2.Element` tree emitted
by `$vml` for `form.vml`. Warmup runs before timing. The checksum consumes each built tree;
results report elapsed time and microseconds per build/dispose cycle.

From the UI2 repository root, with the pinned V compiler:

```sh
/path/to/v -b c -nocache -prod -d ui2_custom_rendering \
    -path "$(dirname "$PWD")|@vlib|@vmodules" \
    -o /tmp/ui2-vml-build-bench benchmarks/vml_build/main.v
/tmp/ui2-vml-build-bench
# Optional: override the default 1,000 build/dispose cycles.
/tmp/ui2-vml-build-bench 10000
```

This measures a cold component lifecycle. Steady-state property effects and retained
layout require their own benchmarks.
