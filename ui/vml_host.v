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
	component.command_handler(command)!
}

fn compiled_vml_host_command(command VmlHostCommand) ! {
	if backend_needs_host {
		return error('compiled VML ref command requires an attached host command handler')
	}
	match command.kind {
		.focus { focus(command.id) }
		.set_text { set_text(command.id, command.text) }
	}
}

fn compiled_vml_request_refresh() {
	if backend_needs_host {
		panic('compiled VML document library refresh requires a host publisher')
	}
	request_refresh()
}
