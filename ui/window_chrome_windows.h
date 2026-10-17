#ifndef UI2_WINDOW_CHROME_WINDOWS_H
#define UI2_WINDOW_CHROME_WINDOWS_H

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#ifndef WINVER
#define WINVER _WIN32_WINNT
#endif

#include <windows.h>
#include <commctrl.h>

#define UI2_CHROME_SUBCLASS_ID 0x75693263

// With the caption removed, the frame above the client area is given to the client
// too, so content reaches the top edge, while the left, right and bottom frames
// stay as resize borders. A maximized window keeps its whole frame off screen.
static LRESULT CALLBACK ui2_chrome_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
		UINT_PTR id, DWORD_PTR data) {
	(void)id;
	(void)data;
	if (message == WM_NCCALCSIZE && wparam == TRUE) {
		NCCALCSIZE_PARAMS *params = (NCCALCSIZE_PARAMS *)lparam;
		LONG top = params->rgrc[0].top;
		LRESULT result = DefSubclassProc(hwnd, message, wparam, lparam);
		params->rgrc[0].top = top;
		if (IsZoomed(hwnd)) {
			params->rgrc[0].top += GetSystemMetrics(SM_CYFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
		}
		return result;
	}
	return DefSubclassProc(hwnd, message, wparam, lparam);
}

static int ui2_chrome_set(void *native, int hidden) {
	HWND window = (HWND)native;
	if (window == NULL) return 0;
	LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
	if (hidden) {
		SetWindowSubclass(window, ui2_chrome_proc, UI2_CHROME_SUBCLASS_ID, 0);
		style &= ~(LONG_PTR)WS_CAPTION;
		style |= WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
	} else {
		RemoveWindowSubclass(window, ui2_chrome_proc, UI2_CHROME_SUBCLASS_ID);
		style |= WS_CAPTION;
	}
	SetWindowLongPtrW(window, GWL_STYLE, style);
	SetWindowPos(window, NULL, 0, 0, 0, 0,
		SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
	return 1;
}

// Handing the press to the title-bar hit test makes Windows run the move loop.
static int ui2_chrome_start_drag(void *native) {
	HWND window = (HWND)native;
	if (window == NULL) return 0;
	ReleaseCapture();
	SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
	return 1;
}

static int ui2_chrome_minimize(void *native) {
	HWND window = (HWND)native;
	if (window == NULL) return 0;
	ShowWindow(window, SW_MINIMIZE);
	return 1;
}

static int ui2_chrome_toggle_maximize(void *native) {
	HWND window = (HWND)native;
	if (window == NULL) return 0;
	ShowWindow(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
	return 1;
}

static int ui2_chrome_is_maximized(void *native) {
	HWND window = (HWND)native;
	return window != NULL && IsZoomed(window);
}

#endif
