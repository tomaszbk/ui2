// Permanent native-subclass regression support. Execution/typecheck is deferred
// while the human Linux/Windows verification hold is active.
static inline void ui2_win_focus_test_key(void *window, unsigned int message,
        unsigned int key, unsigned int scan, int repeated) {
    LPARAM provenance = 1 | ((LPARAM)(scan & 0x1ff) << 16);
    if (repeated) provenance |= (LPARAM)1 << 30;
    if (message == WM_KEYUP) provenance |= (LPARAM)3 << 30;
    SendMessageW((HWND)window, message, key, provenance);
}
static inline void ui2_win_focus_test_deactivate(void *window) {
    SendMessageW((HWND)window, WM_ACTIVATEAPP, FALSE, 0);
}
