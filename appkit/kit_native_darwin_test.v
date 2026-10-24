// vtest build: macos && !ui2_custom_rendering?
// vfmt off
@[has_globals]
module ui2

$if !ui2_custom_rendering ? {
import macos

__global appkit_kit_clicks = []string{}

fn appkit_kit_click(event ElementEvent) {
	assert event.window != unsafe { nil }
	appkit_kit_clicks << event.id
}

// The kit's Button is AppKit's push button in native mode: the declaration
// lays out and reconciles into an NSButton, and its click reaches the
// handler with the window that delivered it.
fn test_appkit_kit_button_is_an_nsbutton_that_delivers_clicks() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := appkit_fixture_window('Kit button fixture', 320, 120)
	defer { st.close_fixture() }
	button := kit_native_button(kit_tokens(Theme{}), 'save', rect(10, 10, 120, 32), ButtonProps{
		text: 'Save'
		on_click: appkit_kit_click
	}, []) or { panic(err) }
	st.render_root(screen(0xffffff, [button]))
	native := st.views['save'] or { panic('missing native button') }
	assert macos.msg_bool_id(native, 'isKindOfClass:', macos.get_class('NSButton'))
	assert macos.utf8_string(macos.msg_id(native, 'title')) == 'Save'
	appkit_kit_clicks = []string{}
	macos.msg_void1(native, 'performClick:', native_nil_view())
	assert appkit_kit_clicks == ['save']
}

// A presentation the native profile cannot show is rejected before it
// reaches a view: the window keeps what it showed.
fn test_appkit_rejects_a_declaration_outside_the_native_profile() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut st := appkit_fixture_window('Native profile fixture', 320, 120)
	defer { st.close_fixture() }
	st.render_root(screen(0xffffff, [label('caption', 'Shown', rect(10, 10, 120, 20), TextStyle{})]))
	assert st.text('caption') == 'Shown'
	outlined := view('outlined', rect(10, 40, 80, 30), BoxStyle{ outline_width: 2 }, [])
	if _ := st.layout_tree.replace(screen(0xffffff, [outlined])) {
		assert false, 'an outline is outside the native profile'
	}
	assert 'outlined' !in st.views
	assert st.text('caption') == 'Shown'
}

__global appkit_closed_windows = 0

// Closing a window runs its close hooks and takes it out of its app and the
// host's registry, which AppKit's callbacks look windows up in.
fn test_appkit_window_close_runs_hooks_and_leaves_the_app() {
	pool := macos.autorelease_pool_new()
	defer { macos.release(pool) }
	mut app := new_app()
	mut first := app.new_window(title: 'First', width: 200, height: 100, build: fn (mut w Window) Element {
		return screen(0xffffff, [])
	}) or { panic(err) }
	mut second := app.new_window(title: 'Second', width: 200, height: 100, build: fn (mut w Window) Element {
		return screen(0xffffff, [])
	}) or { panic(err) }
	assert app.windows().len == 2
	assert appkit_window_open(first) && appkit_window_open(second)
	appkit_closed_windows = 0
	first.on_close(fn () { appkit_closed_windows++ })
	first.quit()
	assert appkit_closed_windows == 1
	assert app.windows().len == 1
	assert !appkit_window_open(first) && appkit_window_open(second)
	window := appkit_window_for(voidptr(second.window)) or { panic('second window must stay registered') }
	assert window == second
	second.quit()
	assert app.windows().len == 0
}
}
