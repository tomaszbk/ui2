module ui2

pub enum VmlHostCommandKind {
	focus
	set_text
}

pub struct VmlHostCommand {
pub:
	kind VmlHostCommandKind
	id   string
	text string
}

// Compiled document libraries own declarations and signals. Commands that
// touch a mounted control are delivered to the window that hosts the document.
pub fn (mut component CompiledVmlComponent) set_command_handler(handler fn (VmlHostCommand) !) ! {
	component.require_alive()!
	if handler == unsafe { nil } { return error('compiled VML host command handler is nil') }
	component.command_handler = handler
	for _, mut child in component.children {
		if !child.is_disposed() { child.set_command_handler(handler)! }
	}
}

fn (component &CompiledVmlComponent) dispatch_command(command VmlHostCommand) ! {
	component.require_alive()!
	if component.command_handler != unsafe { nil } {
		component.command_handler(command)!
		return
	}
	if backend_needs_host {
		return error('compiled VML ref command requires an attached host command handler')
	}
	mut w := component.host_window()
	if w == unsafe { nil } {
		return error('compiled VML ref command requires a mounted document')
	}
	match command.kind {
		.focus { w.focus(command.id) }
		.set_text { w.set_text(command.id, command.text) }
	}
}

// compiled_vml_request_refresh rebuilds the window a compiled callback's
// event happened in.
fn compiled_vml_request_refresh(event ElementEvent) {
	if backend_needs_host {
		panic('compiled VML document library refresh requires a host publisher')
	}
	mut w := event.window
	if w != unsafe { nil } {
		w.request_refresh()
	}
}
