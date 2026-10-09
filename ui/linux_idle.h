#ifndef UI2_LINUX_IDLE_H
#define UI2_LINUX_IDLE_H
#ifndef SOKOL_APP_IMPL_INCLUDED
#error "ui2 Linux idle wait requires the pinned Sokol app implementation first"
#endif
#include <X11/Xlib.h>
#include <sys/eventfd.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <stdint.h>
#include <limits.h>

/* UI thread only. sokol.sapp's transitive sokol.c import includes the pinned
   implementation before this header, so its static _sapp state is visible.
   Do not change these flags: Sokol owns quit-request dispatch/cancel/cleanup. */
static bool ui2_linux_host_close_pending(void) {
    return _sapp.quit_requested || _sapp.quit_ordered;
}

static int ui2_linux_signal_create(void) {
    return eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
}
static void ui2_linux_signal_send(int fd) {
    uint64_t value = 1;
    while (write(fd, &value, sizeof(value)) < 0 && errno == EINTR) {}
    /* EAGAIN already represents a pending wake. No UI/Xlib calls on workers. */
}
static void ui2_linux_signal_drain(int fd) {
    uint64_t value;
    while (read(fd, &value, sizeof(value)) < 0 && errno == EINTR) {}
}
/* Does not consume X events: Sokol remains the sole input/lifecycle owner.
   XPending also checks Xlib's buffered events before blocking on its socket. */
static int ui2_linux_poll(int event_fd, int signal_fd, int64_t delay_ms) {
    if (signal_fd < 0) return -1;
    struct pollfd fds[2] = {
        {event_fd, POLLIN, 0}, {signal_fd, POLLIN, 0}
    };
    int timeout = delay_ms < 0 ? -1 : delay_ms > INT_MAX ? INT_MAX : (int)delay_ms;
    int result = poll(fds, 2, timeout);
    if (result < 0) return errno == EINTR ? -2 : -1;
    if (!result) return 0;
    if ((fds[0].revents | fds[1].revents) & (POLLERR | POLLHUP | POLLNVAL)) return -1;
    return ((fds[0].revents & POLLIN) ? 1 : 0) | ((fds[1].revents & POLLIN) ? 2 : 0);
}
static int ui2_linux_wait(void *display, int signal_fd, int64_t delay_ms) {
    Display *dpy = (Display *)display;
    if (!dpy) return -1;
    if (XPending(dpy)) return 1;
    return ui2_linux_poll(ConnectionNumber(dpy), signal_fd, delay_ms);
}
#endif
