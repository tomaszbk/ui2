module main

#include "@VMODROOT/tests/render_scheduler/cpu_linux.h"

fn C.ui2_acceptance_cpu_start()
fn C.ui2_acceptance_cpu_elapsed() f64

fn sample_cpu_start() { C.ui2_acceptance_cpu_start() }

fn print_sample_cpu(seconds int) {
	cpu := C.ui2_acceptance_cpu_elapsed()
	println('static CPU: user+system seconds=${cpu:.6f} percent_of_one_core=${cpu / seconds * 100:.4f}')
}
