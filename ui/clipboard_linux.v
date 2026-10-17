// An X11 or Wayland clipboard belongs to a client that has to stay around to
// hand its contents over. The standard command-line clients — wl-copy, xclip and
// xsel — do exactly that from the background, so driving them gives custom-
// rendered Linux windows a real system clipboard without taking over the event
// loop sokol owns.
module ui2

import os

// The copy script reads the text from the file named by its first argument and
// sends the tool's output to /dev/null, so a client that stays in the background
// to serve the selection does not hold the pipe os.exec waits on. Paths travel
// as arguments, never inside the script.
struct LinuxClipboardTool {
	copy  string
	paste string
}

fn linux_has_executable(name string) bool {
	return (os.find_abs_path_of_executable(name) or { '' }).len > 0
}

fn linux_clipboard_tool() ?LinuxClipboardTool {
	if os.getenv('WAYLAND_DISPLAY').len > 0 && linux_has_executable('wl-copy')
		&& linux_has_executable('wl-paste') {
		return LinuxClipboardTool{
			copy:  'wl-copy < "$1" >/dev/null 2>&1'
			paste: 'wl-paste --no-newline --type text 2>/dev/null'
		}
	}
	if os.getenv('DISPLAY').len == 0 {
		return none
	}
	if linux_has_executable('xclip') {
		return LinuxClipboardTool{
			copy:  'xclip -selection clipboard -in < "$1" >/dev/null 2>&1'
			paste: 'xclip -selection clipboard -out 2>/dev/null'
		}
	}
	if linux_has_executable('xsel') {
		return LinuxClipboardTool{
			copy:  'xsel --clipboard --input < "$1" >/dev/null 2>&1'
			paste: 'xsel --clipboard --output 2>/dev/null'
		}
	}
	return none
}

fn host_clipboard_supported() bool {
	linux_clipboard_tool() or { return false }
	return true
}

fn host_set_clipboard_text(text string) bool {
	tool := linux_clipboard_tool() or { return false }
	path := os.join_path(os.temp_dir(), 'ui2-clipboard-${os.getpid()}.txt')
	os.write_file(path, text) or { return false }
	defer {
		os.rm(path) or {}
	}
	// The tool reads the file before it forks to keep serving the selection.
	return os.exec(['sh', '-c', tool.copy, 'sh', path]).exit_code == 0
}

fn host_clipboard_text() ?string {
	tool := linux_clipboard_tool() or { return none }
	result := os.exec(['sh', '-c', tool.paste])
	if result.exit_code != 0 {
		return none
	}
	return result.output
}
