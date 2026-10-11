# VML build benchmark

Measures construction and disposal of the retained `ui2.Element` tree emitted
by `$vml` for `form.vml`. Warmup runs before timing. The checksum consumes each built tree;
results report elapsed time, microseconds and allocated bytes per build/dispose
cycle, and actual GC collections. The first build is sampled separately from
the warmed loop. Allocation totals come from Boehm's cumulative counters, so
short-lived garbage is included even when a collection reclaims it.

From the UI2 repository root, with the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -b c -gc boehm -d no_gc_thread_local_alloc -nocache -prod -d ui2_custom_rendering \
    -path "$(dirname "$PWD")|@vlib|@vmodules" \
    -o /tmp/ui2-vml-build-bench benchmarks/vml_build/main.v
/tmp/ui2-vml-build-bench
# Optional: override the default 1,000 build/dispose cycles and five rows.
/tmp/ui2-vml-build-bench 10 5
# 75 rows reproduce the 300-key first-build workload.
/tmp/ui2-vml-build-bench 1 75
```

This measures a cold component lifecycle. See `../steady_state/README.md` for
idle, hover and retained property-effect allocation acceptance. Measurement
rejects builds without Boehm instead of treating unavailable counters as zero.

With precise sampling on the same macOS host and compiler `4c58652`, revision
`7857c36` and the optimized implementation produced these allocations for the
calculator fixtures:

| Keys | Scope | Before | After |
| ---: | --- | ---: | ---: |
| 20 | First build/dispose | 9,097,152 bytes / 4 GC | 4,217,712 bytes / 3 GC |
| 20 | Warm build/dispose, mean of 10 | 9,215,525 bytes | 4,336,110 bytes |
| 20 | GC collections over the 10 warm builds | 4 | 3 |
| 300 | First build/dispose | 1,340,560,016 bytes / 31 GC | 419,457,456 bytes / 15 GC |
| 300 | One warm build/dispose | 1,340,943,872 bytes / 14 GC | 419,841,888 bytes / 5 GC |

The first-build regression tests enforce a 5 MiB budget for 20 keys and a
512 MiB budget for 300 keys. Collection
counts and elapsed time depend on collector and host state; the test bounds
allocation traffic rather than imposing a machine-specific timing threshold.
