#ifndef UI2_MENU_HOST_WINDOWS_H
#define UI2_MENU_HOST_WINDOWS_H

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

#include <stdint.h>
#include <wchar.h>
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

// The window's menu bar, the notification area icon and the popup menus of the
// Windows host (ui/platform.v). The window is sokol's; a subclass routes the
// menu, tray and popup messages it would otherwise drop to the V side of
// menu_host_windows.c.v.

#define UI2_HOST_WM_TRAY (WM_APP + 78)
#define UI2_HOST_WM_POPUP (WM_APP + 79)
#define UI2_HOST_MENU_SUBCLASS_ID 0x7569326d

extern void ui2_host_menu_command(uint32_t command);
extern void ui2_host_tray_message(uint32_t mouse_message);
extern void ui2_host_popup_message(void);

static LRESULT CALLBACK ui2_host_menu_proc(HWND hwnd, UINT message, WPARAM wparam,
		LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
	(void)id;
	(void)data;
	// A menu row sends WM_COMMAND with a zero notification code and no control.
	if (message == WM_COMMAND && HIWORD(wparam) == 0 && lparam == 0) {
		ui2_host_menu_command((uint32_t)LOWORD(wparam));
		return 0;
	}
	if (message == UI2_HOST_WM_TRAY) {
		ui2_host_tray_message((uint32_t)LOWORD(lparam));
		return 0;
	}
	if (message == UI2_HOST_WM_POPUP) {
		ui2_host_popup_message();
		return 0;
	}
	return DefSubclassProc(hwnd, message, wparam, lparam);
}

static inline void ui2_host_menu_attach(void *hwnd) {
	if (hwnd != NULL) SetWindowSubclass((HWND)hwnd, ui2_host_menu_proc, UI2_HOST_MENU_SUBCLASS_ID, 0);
}

static inline void *ui2_host_menu_create(void) {
	return CreatePopupMenu();
}

static inline void *ui2_host_menubar_create(void) {
	return CreateMenu();
}

static inline void ui2_host_menu_destroy(void *menu) {
	if (menu != NULL) DestroyMenu((HMENU)menu);
}

static inline void ui2_host_menu_add_item(void *menu, unsigned int command,
		const wchar_t *title, int enabled, int checked) {
	if (menu == NULL) return;
	AppendMenuW((HMENU)menu, MF_STRING | (enabled ? MF_ENABLED : MF_GRAYED)
		| (checked ? MF_CHECKED : MF_UNCHECKED), command, title == NULL ? L"" : title);
}

static inline void ui2_host_menu_add_separator(void *menu) {
	if (menu != NULL) AppendMenuW((HMENU)menu, MF_SEPARATOR, 0, NULL);
}

// The parent menu takes ownership of the submenu, so only the outermost menu
// is ever destroyed by hand.
static inline void ui2_host_menu_add_submenu(void *menu, void *submenu, const wchar_t *title,
		int enabled) {
	if (menu == NULL || submenu == NULL) return;
	AppendMenuW((HMENU)menu, MF_POPUP | (enabled ? MF_ENABLED : MF_GRAYED),
		(UINT_PTR)(HMENU)submenu, title == NULL ? L"" : title);
}

static inline void ui2_host_set_menubar(void *hwnd, void *menu) {
	if (hwnd == NULL) return;
	HMENU previous = GetMenu((HWND)hwnd);
	SetMenu((HWND)hwnd, (HMENU)menu);
	if (previous != NULL) DestroyMenu(previous);
	DrawMenuBar((HWND)hwnd);
}

static NOTIFYICONDATAW ui2_host_tray_data;
static int ui2_host_tray_added = 0;
// Only an icon this layer loaded from a file is its to destroy; the stock
// application icon is shared.
static HICON ui2_host_tray_loaded_icon = NULL;

static inline void ui2_host_tray_set(void *hwnd, const wchar_t *tooltip,
		const wchar_t *icon_path) {
	if (hwnd == NULL) return;
	HICON icon = NULL;
	if (icon_path != NULL && icon_path[0] != L'\0') {
		icon = (HICON)LoadImageW(NULL, icon_path, IMAGE_ICON,
			GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE);
	}
	HICON previous = ui2_host_tray_loaded_icon;
	ui2_host_tray_loaded_icon = icon;
	if (icon == NULL) icon = LoadIconW(NULL, IDI_APPLICATION);

	ZeroMemory(&ui2_host_tray_data, sizeof(ui2_host_tray_data));
	ui2_host_tray_data.cbSize = sizeof(ui2_host_tray_data);
	ui2_host_tray_data.hWnd = (HWND)hwnd;
	ui2_host_tray_data.uID = 1;
	ui2_host_tray_data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
	ui2_host_tray_data.uCallbackMessage = UI2_HOST_WM_TRAY;
	ui2_host_tray_data.hIcon = icon;
	if (tooltip != NULL) {
		size_t capacity = sizeof(ui2_host_tray_data.szTip) / sizeof(wchar_t);
		wcsncpy(ui2_host_tray_data.szTip, tooltip, capacity - 1);
		ui2_host_tray_data.szTip[capacity - 1] = L'\0';
	}
	Shell_NotifyIconW(ui2_host_tray_added ? NIM_MODIFY : NIM_ADD, &ui2_host_tray_data);
	ui2_host_tray_added = 1;
	if (previous != NULL) DestroyIcon(previous);
}

static inline void ui2_host_tray_remove(void) {
	if (!ui2_host_tray_added) return;
	Shell_NotifyIconW(NIM_DELETE, &ui2_host_tray_data);
	ui2_host_tray_added = 0;
	if (ui2_host_tray_loaded_icon != NULL) {
		DestroyIcon(ui2_host_tray_loaded_icon);
		ui2_host_tray_loaded_icon = NULL;
	}
}

// A notification area menu only dismisses when its owner is foreground, and
// the trailing WM_NULL is the documented workaround for the first click after
// it closes being swallowed.
static inline unsigned int ui2_host_tray_popup(void *hwnd, void *menu) {
	if (hwnd == NULL || menu == NULL) return 0;
	POINT point;
	GetCursorPos(&point);
	SetForegroundWindow((HWND)hwnd);
	unsigned int command = (unsigned int)TrackPopupMenu((HMENU)menu,
		TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y, 0, (HWND)hwnd,
		NULL);
	PostMessageW((HWND)hwnd, WM_NULL, 0, 0);
	return command;
}

static inline int ui2_host_popup_post(void *hwnd) {
	if (hwnd == NULL) return 0;
	return PostMessageW((HWND)hwnd, UI2_HOST_WM_POPUP, 0, 0) ? 1 : 0;
}

// Opens a popup menu at the bottom-left corner of an anchor given in client
// pixels and returns the chosen command, or 0. A non-empty anchor (a select)
// is excluded from the menu's area, so the menu flips above it rather than
// covering it when there is no room below.
static inline unsigned int ui2_host_popup_track(void *hwnd, void *menu, int x, int y,
		int width, int height) {
	if (hwnd == NULL || menu == NULL) return 0;
	POINT origin;
	origin.x = x;
	origin.y = y;
	ClientToScreen((HWND)hwnd, &origin);
	TPMPARAMS params;
	ZeroMemory(&params, sizeof(params));
	params.cbSize = sizeof(params);
	params.rcExclude.left = origin.x;
	params.rcExclude.top = origin.y;
	params.rcExclude.right = origin.x + width;
	params.rcExclude.bottom = origin.y + height;
	int excluded = width > 0 || height > 0;
	return (unsigned int)TrackPopupMenuEx((HMENU)menu,
		TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_TOPALIGN | TPM_VERTICAL,
		origin.x, origin.y + height, (HWND)hwnd, excluded ? &params : NULL);
}

#endif
