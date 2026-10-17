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
	windows        []&Window
	reduced_motion bool
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

// str names a window without its contents. A window holds its backend's
// renderer and C library state, which has no printable form, and an event or
// a retained element tree reaches its window, so printing one prints this.
pub fn (w &Window) str() string {
	return 'Window{}'
}

// run runs the windows until the last one closes. Backends without an event
// loop return at once.
pub fn (mut app App) run() {
	app.run_backend()
}

// set_reduced_motion applies a reduced motion preference to every element of
// every window, as MotionConfig.reduced_motion does to one: transitions and
// layout changes show their end at once and timelines do not play, except
// that a held finite timeline shows its final values. Call it from the UI
// thread, for example when the platform's accessibility setting changes.
// Components draw their resting presentation only for the configurations
// that ask for it (their reduce_motion field).
pub fn (mut app App) set_reduced_motion(reduced bool) {
	if app.reduced_motion == reduced {
		return
	}
	app.reduced_motion = reduced
	for mut w in app.windows {
		w.backend_invalidate(.build)
	}
}

// reduced_motion reports the preference set_reduced_motion applies.
pub fn (app &App) reduced_motion() bool {
	return app.reduced_motion
}

// prefers_reduced_motion reports whether the app that runs w asks for less
// motion.
fn (w &Window) prefers_reduced_motion() bool {
	return w != unsafe { nil } && w.app != unsafe { nil } && w.app.reduced_motion
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
