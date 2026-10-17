module ui2

// An Element is a declaration. What the retained runtime learns about an
// element it has mounted lives in records that the runtime owns: the layout
// and overlay trees own mounts, compiled nodes and the motion tree own
// presentation state. Elements the runtime hands out borrow those records
// through two private links, `mount` and `runtime`. Authored declarations
// leave both nil, so copying an Element never copies runtime state, and the
// records are immutable once linked: a change links a new record.
//
// A side table keyed by path would make every render, focus and hit-test walk
// hash the path of every node to find the strings it needs, and the path
// itself is one of them. The links cost two words and no lookup.

// ElementMount is where a layout or overlay tree mounted an output element.
// The identity strings are formatted once per mount, not on every frame.
@[heap]
struct ElementMount {
	generation  u64
	path        string
	parent_path string
	scroll_id   string
	tooltip_key string
	// Portals keep their logical focus ancestry while presented in the
	// window layer; an inert layer paints but takes no input.
	overlay_scopes []string
	overlay_inert  bool
	overlay_host   bool
}

// ElementRuntime is presentation state attached by the retained runtime.
@[heap]
struct ElementRuntime {
	motion_state &ElementMotionState = unsafe { nil }
	// The element stays painted while its exit runs, outside layout and input.
	exiting bool
	// Constructor projections compare against the snapshot they received,
	// even when effects have since updated the retained declaration.
	source &VmlSourceSnapshot = unsafe { nil }
}

fn (el &Element) mounted_generation() u64 {
	return if el.mount == unsafe { nil } { 0 } else { el.mount.generation }
}

fn (el &Element) mounted_path() string {
	return if el.mount == unsafe { nil } { '' } else { el.mount.path }
}

fn (el &Element) mounted_parent_path() string {
	return if el.mount == unsafe { nil } { '' } else { el.mount.parent_path }
}

fn (el &Element) mounted_scroll_id() string {
	return if el.mount == unsafe { nil } { '' } else { el.mount.scroll_id }
}

fn (el &Element) mounted_tooltip_key() string {
	return if el.mount == unsafe { nil } { '' } else { el.mount.tooltip_key }
}

fn (el &Element) overlay_scopes() []string {
	return if el.mount == unsafe { nil } { []string{} } else { el.mount.overlay_scopes }
}

fn (el &Element) overlay_inert() bool {
	return el.mount != unsafe { nil } && el.mount.overlay_inert
}

fn (el &Element) overlay_host() bool {
	return el.mount != unsafe { nil } && el.mount.overlay_host
}

fn (el &Element) motion_state() &ElementMotionState {
	return if el.runtime == unsafe { nil } { unsafe { nil } } else { el.runtime.motion_state }
}

fn (el &Element) presence_exiting() bool {
	return el.runtime != unsafe { nil } && el.runtime.exiting
}

fn (el &Element) compiled_source() &VmlSourceSnapshot {
	return if el.runtime == unsafe { nil } { unsafe { nil } } else { el.runtime.source }
}

// Mount record updates return the receiver when nothing changes, so retained
// projections keep comparing equal and allocate nothing.
fn (mount &ElementMount) with_path(path string, parent_path string) &ElementMount {
	if mount == unsafe { nil } {
		return &ElementMount{ path: path, parent_path: parent_path }
	}
	if mount.path == path && mount.parent_path == parent_path { return mount }
	return &ElementMount{ ...*mount, path: path, parent_path: parent_path }
}

// with_identity takes the identity of `source` and keeps the receiver's
// overlay presentation.
fn (mount &ElementMount) with_identity(source &ElementMount) &ElementMount {
	if mount == source { return mount }
	if source == unsafe { nil } {
		if mount == unsafe { nil } || (mount.overlay_scopes.len == 0 && !mount.overlay_inert && !mount.overlay_host) {
			return unsafe { nil }
		}
		return &ElementMount{ overlay_scopes: mount.overlay_scopes, overlay_inert: mount.overlay_inert, overlay_host: mount.overlay_host }
	}
	if mount == unsafe { nil } || (mount.overlay_scopes.len == 0 && !mount.overlay_inert && !mount.overlay_host) {
		if source.overlay_scopes.len == 0 && !source.overlay_inert && !source.overlay_host {
			return source
		}
		return &ElementMount{ ...*source, overlay_scopes: []string{}, overlay_inert: false, overlay_host: false }
	}
	return &ElementMount{ ...*source, overlay_scopes: mount.overlay_scopes, overlay_inert: mount.overlay_inert, overlay_host: mount.overlay_host }
}

fn (mount &ElementMount) with_inert(inert bool) &ElementMount {
	if mount == unsafe { nil } {
		return if inert { &ElementMount{ overlay_inert: true } } else { unsafe { nil } }
	}
	if mount.overlay_inert == inert { return mount }
	return &ElementMount{ ...*mount, overlay_inert: inert }
}

// same_overlay reports whether both records present the same overlay state;
// nil presents none.
fn (mount &ElementMount) same_overlay(other &ElementMount) bool {
	if mount == unsafe { nil } || other == unsafe { nil } {
		present := if mount == unsafe { nil } { other } else { mount }
		return present == unsafe { nil } || (present.overlay_scopes.len == 0
			&& !present.overlay_inert && !present.overlay_host)
	}
	return mount.overlay_scopes == other.overlay_scopes && mount.overlay_inert == other.overlay_inert
		&& mount.overlay_host == other.overlay_host
}

fn overlay_host_mount() &ElementMount {
	return &ElementMount{ overlay_host: true }
}

fn (runtime &ElementRuntime) is_empty() bool {
	return runtime == unsafe { nil }
		|| (runtime.motion_state == unsafe { nil } && !runtime.exiting && runtime.source == unsafe { nil })
}

fn (runtime &ElementRuntime) with_motion_state(state &ElementMotionState) &ElementRuntime {
	if runtime == unsafe { nil } {
		return if state == unsafe { nil } {
			unsafe { nil }
		} else {
			&ElementRuntime{ motion_state: state }
		}
	}
	if runtime.motion_state == state { return runtime }
	updated := &ElementRuntime{ ...*runtime, motion_state: state }
	return if updated.is_empty() { unsafe { nil } } else { updated }
}

fn (runtime &ElementRuntime) with_exiting(exiting bool) &ElementRuntime {
	if runtime == unsafe { nil } {
		return if exiting { &ElementRuntime{ exiting: true } } else { unsafe { nil } }
	}
	if runtime.exiting == exiting { return runtime }
	updated := &ElementRuntime{ ...*runtime, exiting: exiting }
	return if updated.is_empty() { unsafe { nil } } else { updated }
}
