#include <sys/resource.h>
static double ui2_acceptance_cpu_before;
static double ui2_acceptance_cpu(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6
         + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}
static void ui2_acceptance_cpu_start(void) { ui2_acceptance_cpu_before = ui2_acceptance_cpu(); }
static double ui2_acceptance_cpu_elapsed(void) { return ui2_acceptance_cpu() - ui2_acceptance_cpu_before; }
