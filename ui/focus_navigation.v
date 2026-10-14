module ui2

import math

pub enum FocusPolicy {
	automatic
	focusable
	unfocusable
}

pub enum FocusDirection {
	left
	right
	up
	down
}

// FocusNode geometry is in window logical coordinates, projected through the
// same ContentTransform as painting. It includes mounted, clipped controls.
struct FocusNode {
	el          Element
	path        string
	parent      string
	eligible    bool
	hidden      bool
	enabled     bool
	scopes      []string
	transform   ContentTransform
	parent_transform ContentTransform
	clip ClipRegion
	local_frame Rect
	scrolls     []string
	menu_options []string
	pointer_owner_identity string
mut:
	frame       Rect
	subtree_len int
}

struct FocusScopeEntry {
	id      string
	restore string
}

struct FocusReveal {
	// path also addresses anonymous Scroll ancestors.
	id   string
	path string
	rect Rect
}

// Pure navigation policy. Each backend owns one manager per existing window.
// Input/editor storage is deliberately independent of this registry.
struct FocusManager {
mut:
	root           Element
	// root_revision advances whenever a different root is published. In-flight
	// frames compare it instead of comparing whole Element trees per child.
	root_revision  u64
	geometry_revision u64
	geometry_serial u64
	presentation_serial u64
	motion_serial                u64
	geometry_motion_serial       u64
	refresh_motion_changed       bool
	refresh_presentation_changed bool
	refresh_offsets_changed bool
	geometry_frame Rect
	geometry_transform ContentTransform
	geometry_clip ClipRegion
	nodes          []FocusNode
	// Index the retained registry itself, including named non-focusable nodes
	// painted by custom backends and anonymous ancestors addressed by path.
	node_indices   map[string]int
	path_indices   map[string]int
	current        string
	scopes         []FocusScopeEntry
	scroll_offsets map[string]f64
	scroll_offsets_x map[string]f64
}

fn element_focusable(el Element) bool {
	if el.id.len == 0 || el.focus_policy == .unfocusable { return false }
	if el.focus_policy == .focusable { return true }
	return el.kind in [.button, .checkbox, .text_field, .text_area, .dropdown, .slider,
		.switch_control, .toggle_button] || (el.kind == .view && el.button_behavior)
}

// Mounted option arrays are immutable snapshots. Recompute only when the
// declaration changes, so paint and pointer geometry share the same options.
fn element_menu_options(el Element) []string {
	mut options := []string{cap: el.menu.len}
	for entry in el.menu { options << entry.title }
	return options
}

fn (node FocusNode) menu_options_snapshot() []string {
	// Geometry-only callers can construct a node without mounting a registry.
	if node.menu_options.len == node.el.menu.len { return node.menu_options }
	return element_menu_options(node.el)
}

fn (mut manager FocusManager) update(root Element, offsets map[string]f64) {
	manager.update_presented(root, offsets, ContentTransform{})
}

fn (mut manager FocusManager) update_presented(root Element, offsets map[string]f64, transform ContentTransform) {
	manager.update_geometry(root, offsets, transform, root.frame, ClipRegion{})
}

fn (mut manager FocusManager) update_mounted(root Element, offsets map[string]f64, viewport Rect, transform ContentTransform) {
	manager.update_geometry(root, offsets, transform, mounted_root_frame(root, viewport), paint_transformed_clip(viewport, transform))
}

fn (mut manager FocusManager) update_mounted_axes(root Element, offsets map[string]f64, offsets_x map[string]f64, viewport Rect, transform ContentTransform) {
	manager.update_geometry_axes(root, offsets, offsets_x, transform, mounted_root_frame(root, viewport), paint_transformed_clip(viewport, transform))
}

// set_root publishes a mounted tree. Republishing an equal tree keeps the
// revision, so nested refreshes do not cancel a frame painting that same tree.
fn (mut manager FocusManager) set_root(root Element) {
	if manager.root != root { manager.root_revision++ }
	manager.root = root
}

fn (mut manager FocusManager) update_geometry(root Element, offsets map[string]f64, transform ContentTransform, root_frame Rect, clip ClipRegion) {
	manager.update_geometry_axes(root, offsets, manager.scroll_offsets_x, transform, root_frame, clip)
}

fn (mut manager FocusManager) update_geometry_axes(root Element, offsets map[string]f64, offsets_x map[string]f64, transform ContentTransform, root_frame Rect, clip ClipRegion) {
	manager.set_root(root)
	if manager.geometry_serial > 0 && manager.geometry_revision == manager.root_revision
		&& manager.geometry_motion_serial == manager.motion_serial
		&& manager.geometry_frame == root_frame && manager.geometry_transform == transform
		&& manager.geometry_clip == clip && manager.scroll_offsets == offsets && manager.scroll_offsets_x == offsets_x { return }
	manager.refresh_presentation_changed = manager.geometry_serial == 0
	manager.refresh_motion_changed = manager.geometry_motion_serial != manager.motion_serial
	manager.geometry_motion_serial = manager.motion_serial
	manager.geometry_revision = manager.root_revision
	manager.geometry_serial++
	manager.geometry_frame = root_frame
	manager.geometry_transform = transform
	manager.geometry_clip = clip
	manager.refresh_offsets_changed = manager.scroll_offsets != offsets || manager.scroll_offsets_x != offsets_x
	if manager.scroll_offsets != offsets { manager.scroll_offsets = offsets.clone() }
	if manager.scroll_offsets_x != offsets_x { manager.scroll_offsets_x = offsets_x.clone() }
	// Keep the flat registry and its indexes when identity/order are stable.
	// A retained subtree with unchanged inherited geometry can be skipped whole.
	refreshed := manager.refresh_geometry(root, root_frame, 'root', '', 0, 0,
		transform, clip, false, true, []string{}, []string{}, 0, false)
	if refreshed != manager.nodes.len || refreshed < 0 {
		manager.refresh_presentation_changed = true
		manager.nodes.clear()
		manager.node_indices.clear()
		manager.path_indices.clear()
		manager.refresh_geometry(root, root_frame, 'root', '', 0, 0, transform, clip, false, true, []string{}, []string{}, 0, true)
	}
	if manager.refresh_presentation_changed { manager.presentation_serial++ }
	// Validate the complete active chain: a surviving inner scope may have
	// moved out of its parent, or that parent may have disappeared entirely.
	mut valid_scopes := 0
	for i, entry in manager.scopes {
		if node := manager.node(entry.id) {
			if node.el.focus_scope && !node.hidden && node.enabled
				&& (i == 0 || manager.scopes[i - 1].id in node.scopes) {
				valid_scopes++
				continue
			}
		}
		break
	}
	// Automatic unwinding shares explicit restoration, including its fallback
	// when the saved target was removed alongside the scope.
	for manager.scopes.len > valid_scopes {
		manager.leave_scope()
	}
	if manager.current.len > 0 && !manager.can_focus(manager.current) {
		manager.current = ''
		if manager.scopes.len > 0 { manager.current = manager.first(false) }
	}
}

// Returns the first index after this subtree, or -1 when a structural change
// needs a fresh registry. No callbacks run until the complete registry is ready.
fn (mut manager FocusManager) refresh_geometry(el Element, frame Rect, path string, parent string,
	off_x f64, off_y f64, outer ContentTransform, clip ClipRegion, ancestor_hidden bool,
	ancestor_enabled bool, scopes []string, scrolls []string, index int, rebuild bool) int {
	if !rebuild && index >= manager.nodes.len { return -1 }
	previous := if rebuild { FocusNode{} } else { manager.nodes[index] }
	if !rebuild && (previous.path != path || previous.parent != parent || previous.el.id != el.id
		|| previous.el.children.len != el.children.len) {
		return -1
	}
	hidden := ancestor_hidden || el.presented_hidden()
	enabled := ancestor_enabled && el.presented_enabled()
	local := rect(off_x + frame.x, off_y + frame.y, frame.width, frame.height)
	if !rebuild && !manager.refresh_offsets_changed && !manager.refresh_motion_changed && previous.el == el && previous.local_frame == local && previous.parent_transform == outer
		&& previous.clip == clip && previous.hidden == hidden && previous.enabled == enabled
		&& previous.scrolls == scrolls && !el.focus_scope && previous.scopes == scopes {
		return index + previous.subtree_len
	}
	visual := el.visual_transform().matrix(local) or { return if rebuild { index } else { -1 } }
	transform := outer.compose(visual)
	if previous.local_frame != local || previous.transform != transform || previous.parent_transform != outer
		|| previous.clip != clip || previous.hidden != hidden { manager.refresh_presentation_changed = true }
	// Ancestor chains are immutable; clone only when this node extends one.
	mut child_scopes := unsafe { scopes }
	if el.focus_scope {
		if previous.el.focus_scope && previous.scopes.len == scopes.len + 1
			&& previous.scopes[..scopes.len] == scopes && previous.scopes.last() == el.id {
			child_scopes = previous.scopes
		} else {
			child_scopes = scopes.clone()
			child_scopes << el.id
		}
	}
	mut menu_options := unsafe { previous.menu_options }
	if rebuild || previous.el.menu != el.menu { menu_options = element_menu_options(el) }
	if rebuild {
		if el.id.len > 0 { manager.node_indices[el.id] = index }
		manager.path_indices[path] = index
		// Append an empty slot first: moving a populated node into an array can
		// otherwise clone its retained Element subtree under array ownership.
		manager.nodes << FocusNode{}
	}
	manager.nodes[index] = FocusNode{
		el:               el
		path:             path
		parent:           parent
		eligible:         !hidden && enabled && element_focusable(el)
		hidden:           hidden
		enabled:          enabled
		scopes:           child_scopes
		frame:            transform.project(local)
		transform:        transform
		parent_transform: outer
		clip:             clip
		local_frame:      local
		scrolls:          scrolls
		menu_options:     menu_options
		pointer_owner_identity: if previous.pointer_owner_identity.len > 0 {
			previous.pointer_owner_identity
		} else if el.id.len > 0 { 'id:' + el.id } else { 'path:' + path }
		subtree_len:      previous.subtree_len
	}
	mut child_x := local.x
	mut child_y := local.y
	mut child_transform := transform
	mut child_clip := clip
	mut child_scrolls := unsafe { scrolls }
	if el.kind == .screen {
		child_clip = clip.intersect(paint_transformed_clip(local, transform))
		child_x = off_x
		child_y = off_y
	}
	if el.content_size.width > 0 && el.content_size.height > 0 {
		fit := contain_content(local, el.content_size.width, el.content_size.height) or {
			if !rebuild { return -1 }
			// A zero-size composition contributes this mounted owner only. Its
			// children cannot be projected, but later siblings must still register.
			manager.nodes[index].subtree_len = 1
			return index + 1
		}
		child_transform = transform.compose(fit)
		child_clip = clip.intersect(paint_transformed_clip(local, transform))
		child_x = 0
		child_y = 0
	}
	if el.kind == .scroll {
		child_clip = child_clip.intersect(paint_transformed_clip(local, transform))
		child_y -= manager.scroll_offsets[path] or { 0.0 }
		child_x -= manager.scroll_offsets_x[path] or { 0.0 }
		if previous.el.kind == .scroll && previous.scrolls == scrolls && previous.subtree_len > 1 {
			child_scrolls = manager.nodes[index + 1].scrolls
		} else {
			child_scrolls = scrolls.clone()
			child_scrolls << path
		}
	}
	mut next := index + 1
	for i, child in el.children {
		next = manager.refresh_geometry(child, child.frame, reconciliation_child_key(path, i, child), path,
			child_x, child_y, child_transform, child_clip, hidden, enabled, child_scopes, child_scrolls, next, rebuild)
		if next < 0 { return -1 }
	}
	manager.nodes[index].subtree_len = next - index
	return next
}

fn (manager &FocusManager) node(id string) ?FocusNode {
	index := manager.node_indices[id] or { return none }
	return manager.nodes[index]
}

fn (manager &FocusManager) path_node(path string) ?FocusNode {
	index := manager.path_indices[path] or { return none }
	return manager.nodes[index]
}

fn (manager &FocusManager) in_scope(node FocusNode) bool {
	return manager.scopes.len == 0 || manager.scopes.last().id in node.scopes
}

fn (manager &FocusManager) can_focus(id string) bool {
	node := manager.node(id) or { return false }
	return node.eligible && manager.in_scope(node)
}

fn (mut manager FocusManager) set_focus(id string) bool {
	if !manager.can_focus(id) { return false }
	manager.current = id
	return true
}

fn (manager &FocusManager) order() []string {
	mut candidates := []FocusNode{}
	for node in manager.nodes {
		if node.eligible && node.el.tab_index >= 0 && manager.in_scope(node) { candidates << node }
	}
	// Positive indices precede the normal (zero) tree order. Stable insertion
	// sorting preserves declaration order for ties, without map iteration.
	for i in 1 .. candidates.len {
		mut j := i
		for j > 0 && tab_index_before(candidates[j].el.tab_index, candidates[j - 1].el.tab_index) {
			previous := candidates[j - 1]
			candidates[j - 1] = candidates[j]
			candidates[j] = previous
			j--
		}
	}
	return candidates.map(it.el.id)
}

fn tab_index_before(a int, b int) bool {
	return a > 0 && (b == 0 || a < b)
}

fn (manager &FocusManager) first(backwards bool) string {
	order := manager.order()
	if order.len == 0 { return '' }
	return if backwards { order.last() } else { order[0] }
}

fn (mut manager FocusManager) traverse(backwards bool) bool {
	order := manager.order()
	if order.len == 0 { return false }
	index := order.index(manager.current)
	destination := if index < 0 {
		if backwards { order.len - 1 } else { 0 }
	} else {
		(index + if backwards { order.len - 1 } else { 1 }) % order.len
	}
	manager.current = order[destination]
	return true
}

fn (mut manager FocusManager) enter_scope(id string) bool {
	node := manager.node(id) or { return false }
	if !node.el.focus_scope || node.hidden || !node.enabled || !manager.in_scope(node) {
		return false
	}
	for entry in manager.scopes { if entry.id == id { return false } }
	manager.scopes << FocusScopeEntry{ id: id, restore: manager.current }
	destination := manager.first(false)
	if destination.len == 0 {
		manager.scopes.delete_last()
		return false
	}
	manager.current = destination
	return true
}

fn (mut manager FocusManager) leave_scope() bool {
	if manager.scopes.len == 0 { return false }
	entry := manager.scopes.pop()
	manager.current = if manager.can_focus(entry.restore) {
		entry.restore
	} else {
		manager.first(false)
	}
	return true
}

// This is the seam for transformed presentation geometry: no matrices or
// hit-test geometry are reimplemented here. Backends may project a control's
// final geometry with their common presentation helper before navigation.
fn (mut manager FocusManager) set_geometry(id string, frame Rect) {
	index := manager.node_indices[id] or { return }
	manager.nodes[index].frame = frame
}

fn (mut manager FocusManager) directional(direction FocusDirection) bool {
	from := manager.node(manager.current) or { return manager.traverse(false) }
	mut winner := ''
	mut best_beam := false
	mut best_score := math.inf(1)
	for id in manager.order() {
		if id == manager.current { continue }
		to := manager.node(id) or { continue }
		if to.frame.width <= 0 || to.frame.height <= 0 { continue }
		dx := to.frame.x + to.frame.width / 2 - from.frame.x - from.frame.width / 2
		dy := to.frame.y + to.frame.height / 2 - from.frame.y - from.frame.height / 2
		primary := match direction {
			.left { -dx }
			.right { dx }
			.up { -dy }
			.down { dy }
		}
		if primary <= 0.000001 { continue }
		vertical := direction in [.up, .down]
		cross := if vertical { math.abs(dx) } else { math.abs(dy) }
		beam := if vertical {
			to.frame.x < from.frame.x + from.frame.width && to.frame.x + to.frame.width > from.frame.x
		} else {
			to.frame.y < from.frame.y + from.frame.height && to.frame.y + to.frame.height > from.frame.y
		}
		score := primary + cross * cross / primary
		if winner.len == 0 || (beam && !best_beam) || (beam == best_beam && score < best_score) {
			winner = id
			best_beam = beam
			best_score = score
		}
	}
	if winner.len == 0 { return false }
	manager.current = winner
	return true
}

fn (manager &FocusManager) reveals(id string) []FocusReveal {
	node := manager.node(id) or { return []FocusReveal{} }
	mut result := []FocusReveal{}
	// Carry exact window corners inside out. Only the local Rect scrolling
	// API needs a bound; the ancestor receives the shifted/clipped polygon.
	mut target := transformed_clip(node.local_frame, node.transform)
	for i := node.scrolls.len - 1; i >= 0; i-- {
		path := node.scrolls[i]
		pane := manager.path_node(path) or { continue }
		inverse := pane.transform.inverted() or { continue }
		local_points := target.points.map(inverse.point(it.x, it.y))
		if local_points.len == 0 { break }
		local := point_bounds(local_points)
		offset := manager.scroll_offsets[path] or { 0.0 }
		offset_x := manager.scroll_offsets_x[path] or { 0.0 }
		request := rect(local.x - pane.local_frame.x + offset_x, local.y - pane.local_frame.y + offset, local.width, local.height)
		result << FocusReveal{ id: pane.el.id, path: path, rect: request }
		next := math.min(focus_scroll_maximum(pane.el), focus_reveal_offset(offset, pane.el.frame.height, request))
		next_x := math.min(math.max(0, if pane.el.scroll_mode != .vertical_only { scroll_content_width(pane.el.children) - pane.el.frame.width } else { 0.0 }), focus_reveal_offset(offset_x, pane.el.frame.width, rect(request.y, request.x, request.height, request.width)))
		shifted := local_points.map(pane.transform.point(it.x + offset_x - next_x, it.y + offset - next))
		target = ClipRegion{ bounded: true, points: shifted }.intersect(transformed_clip(pane.local_frame, pane.transform))
	}
	return result
}

fn focus_reveal_offset(offset f64, viewport_height f64, target Rect) f64 {
	if target.y < offset { return math.max(0, target.y) }
	if target.y + target.height > offset + viewport_height {
		return math.max(0, if target.height > viewport_height {
			target.y
		} else {
			target.y + target.height - viewport_height
		})
	}
	return offset
}

fn scroll_content_height(el Element) f64 {
	if el.scroll_mode == .horizontal_only { return 0.0 }
	mut bottom := 0.0
	for child in el.children {
		if !child.layout_excluded() { bottom = math.max(bottom, child.frame.y + child.frame.height) }
	}
	return if bottom > 0 { bottom + 16 } else { 0.0 }
}

fn focus_scroll_maximum(el Element) f64 {
	return math.max(0, scroll_content_height(el) - el.frame.height)
}

// Windows character messages retain their originating key's scan code. A
// consumed navigation key may remain held while another key enters text.
// Scan-less synthesized/IME text does not belong to a consumed physical key.
// Only the Windows backend calls it; it stays shared so its tests run everywhere.
@[markused]
fn consumed_key_character(scan_code u32, suppressed map[u32]u32) bool {
	if scan_code == 0 { return false }
	for _, consumed_scan in suppressed {
		if consumed_scan == scan_code { return true }
	}
	return false
}
