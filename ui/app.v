module ui2

// Desktop windows open at 800x600 logical units, phone-sized ones at 400x800.
const default_window_width = $if android || ios { 400 } $else { 800 }
const default_window_height = $if android || ios { 800 } $else { 600 }

// WindowConfig describes a window that App.new_window opens.
@[params]
pub struct WindowConfig {
pub:
	title      string = 'App'
	width      int    = default_window_width
	height     int    = default_window_height
	min_width  int
	min_height int
	build      BuildFn = unsafe { nil }
}

// App is the application process: the windows it runs, and the services the
// operating system and the C libraries keep once per process. Everything that
// belongs to one window is that Window's own.
@[heap]
pub struct App {
mut:
	windows []&Window
}

pub fn new_app() &App {
	return &App{}
}

// new_window opens a window that builds its tree with config.build. Configure
// it, for example its key handlers and menu bar, before App.run.
pub fn (mut app App) new_window(config WindowConfig) !&Window {
	if config.build == unsafe { nil } {
		return error('a window needs a build function')
	}
	if config.width <= 0 || config.height <= 0 {
		return error('window dimensions must be positive')
	}
	w := app.open_backend_window(config)!
	app.windows << w
	return w
}

// windows lists the windows the app opened that are still open.
pub fn (app &App) windows() []&Window {
	return app.windows.clone()
}

// run runs the windows until the last one closes. Backends without an event
// loop return at once.
pub fn (mut app App) run() {
	app.run_backend()
}

fn (mut app App) forget_window(w &Window) {
	for index, open in app.windows {
		if open == w {
			app.windows.delete(index)
			return
		}
	}
}

// run_window opens one window and runs it until it closes.
pub fn run_window(title string, width int, height int, build BuildFn) {
	mut app := new_app()
	app.new_window(title: title, width: width, height: height, build: build) or {
		panic('ui2: ${err}')
	}
	app.run()
}

// run opens one window of the default size and runs it until it closes.
pub fn run(build BuildFn) {
	run_window('App', default_window_width, default_window_height, build)
}
