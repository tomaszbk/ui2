# VML build benchmark

Measures construction and disposal of the retained `ui2.Element` tree emitted
by `$vml` for `form.vml`, or built by `generic.v`: the same document written by
hand in the shape of the generic lowering (`ui2.vml_document`, `vml_root`,
`vml_child`, `vml_repeat`, `prop`). Warmup runs before timing. The checksum consumes each built tree;
results report elapsed time, microseconds and allocated bytes per build/dispose
cycle, and actual GC collections. The first build is sampled separately from
the warmed loop. Allocation totals come from Boehm's cumulative counters, so
short-lived garbage is included even when a collection reclaims it.

From the UI2 repository root, with the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -b c -gc boehm -d no_gc_thread_local_alloc -nocache -prod -d ui2_custom_rendering \
    -path "$(dirname "$PWD")|@vlib|@vmodules" \
    -o /tmp/ui2-vml-build-bench benchmarks/vml_build
/tmp/ui2-vml-build-bench
# Optional: override the default 1,000 build/dispose cycles and five rows.
/tmp/ui2-vml-build-bench 10 5
# 75 rows reproduce the 300-key first-build workload.
/tmp/ui2-vml-build-bench 1 75
# A third argument selects the lowering: compiled (default), generic or both.
/tmp/ui2-vml-build-bench 10 5 generic
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

Retained projections later settled once per batch instead of re-projecting
every sibling up to the root after each child change. With the command above on
a Linux x86-64 host (gcc, `-prod -d ui2_custom_rendering`), revision `90495a5`
and that change produced:

| Keys | Scope | Before | After |
| ---: | --- | ---: | ---: |
| 20 | First build/dispose | 7,566,320 bytes / 5 GC | 2,289,008 bytes / 4 GC |
| 20 | Warm build/dispose, mean of 10 | 7,679,078 bytes, 13.5 ms | 2,401,914 bytes, 2.9 ms |
| 300 | First build/dispose | 962,341,840 bytes / 33 GC | 31,039,072 bytes / 8 GC |
| 300 | One warm build/dispose | 962,701,456 bytes / 16 GC, 1.30 s | 31,398,480 bytes / 3 GC, 0.10 s |

Runtime state then moved out of `Element` into records owned by the runtime,
sparse properties moved behind shared references, and Flex and Stack layouts
kept compact child rules instead of full child Elements. `sizeof(Element)` went
from 5,976 to 4,096 bytes. On a Linux x86-64 host with the command above,
revision `dcce5ab` and those changes produced:

| Keys | Scope | Before | After |
| ---: | --- | ---: | ---: |
| 20 | First build/dispose | 2,554,688 bytes / 4 GC | 2,038,224 bytes / 4 GC |
| 20 | Warm build/dispose, mean of 1,000 | 2,686,004 bytes | 2,169,524 bytes |
| 300 | First build/dispose | 34,440,832 bytes / 8 GC | 27,818,032 bytes / 8 GC |
| 300 | One warm build/dispose | 34,800,208 bytes / 3 GC | 28,177,520 bytes / 3 GC |

The first-build regression tests enforce a 4 MiB budget for 20 keys and a
56 MiB budget for 300 keys, about twice the Linux measurements. Collection
counts and elapsed time depend on collector and host state; the test bounds
allocation traffic rather than imposing a machine-specific timing threshold.

The generic node runtime builds the same documents with less allocation. With
the command above on a Linux x86-64 host (gcc, `-prod -d ui2_custom_rendering`),
revision `f244aff` plus the generic runtime, with each figure from its own
process:

| Keys | Scope | Compiled | Generic |
| ---: | --- | ---: | ---: |
| 20 | First build/dispose | 2,555,472 bytes / 4 GC | 1,581,760 bytes / 3 GC |
| 20 | Warm build/dispose, mean of 10 | 2,668,083 bytes, 3.2 ms | 1,614,845 bytes, 2.0 ms |
| 300 | First build/dispose | 34,445,696 bytes / 8 GC | 20,049,248 bytes / 7 GC |
| 300 | One warm build/dispose | 34,805,104 bytes / 3 GC, 78 ms | 20,086,672 bytes / 2 GC, 37 ms |

The generic first builds have the same budgets as the compiled ones, and a test
checks that both lowerings build the same tree.
