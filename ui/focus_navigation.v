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
	frame       Rect
	transform   ContentTransform
	local_frame Rect
	scrolls     []string
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
	nodes          []FocusNode
	current        string
	scopes         []FocusScopeEntry
	scroll_offsets map[string]f64
}

fn element_focusable(el Element) bool {
	if el.id.len == 0 || el.focus_policy == .unfocusable { return false }
	if el.focus_policy == .focusable { return true }
	return el.kind in [.button, .checkbox, .text_field, .text_area, .dropdown, .slider,
		.switch_control, .toggle_button] || (el.kind == .view && el.button_behavior)
}

// Native disabled containers do not necessarily disable their children. Use
// effective enabled state in every backend, including pointer/action routing.
fn effective_element_state(el Element, parent_enabled bool) Element {
	enabled := parent_enabled && el.enabled
	mut children := []Element{cap: el.children.len}
	for child in el.children { children << effective_element_state(child, enabled) }
	return Element{ ...el, enabled: enabled, children: children }
}

fn (mut manager FocusManager) update(root Element, offsets map[string]f64) {
	manager.update_presented(root, offsets, ContentTransform{})
}

fn (mut manager FocusManager) update_presented(root Element, offsets map[string]f64, transform ContentTransform) {
	manager.root = root
	manager.scroll_offsets = offsets.clone()
	manager.nodes.clear()
	manager.collect(root, 'root', '', 0, 0, transform, false, true, []string{}, []string{})
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

fn (mut manager FocusManager) collect(el Element, path string, parent string,
	off_x f64, off_y f64, transform ContentTransform, ancestor_hidden bool,
	ancestor_enabled bool, scopes []string, scrolls []string) {
	hidden := ancestor_hidden || el.hidden
	enabled := ancestor_enabled && el.enabled
	local := rect(off_x + el.frame.x, off_y + el.frame.y, el.frame.width, el.frame.height)
	mut child_scopes := scopes.clone()
	if el.focus_scope { child_scopes << el.id }
	manager.nodes << FocusNode{
		el:          el
		path:        path
		parent:      parent
		eligible:    !hidden && enabled && element_focusable(el)
		hidden:      hidden
		enabled:     enabled
		scopes:      child_scopes
		frame:       transform.project(local)
		transform:   transform
		local_frame: local
		scrolls:     scrolls
	}
	mut child_x := local.x
	mut child_y := local.y
	mut child_transform := transform
	mut child_scrolls := scrolls.clone()
	if el.kind == .screen {
		child_x = off_x
		child_y = off_y
	}
	if el.content_size.width > 0 && el.content_size.height > 0 {
		fit := contain_content(local, el.content_size.width, el.content_size.height) or { return }
		child_transform = transform.compose(fit)
		child_x = 0
		child_y = 0
	}
	if el.kind == .scroll {
		child_y -= manager.scroll_offsets[path] or { 0.0 }
		child_scrolls << path
	}
	for i, child in el.children {
		manager.collect(child, reconciliation_child_key(path, i, child), path,
			child_x, child_y, child_transform, hidden, enabled, child_scopes, child_scrolls)
	}
}

fn (manager &FocusManager) node(id string) ?FocusNode {
	for node in manager.nodes { if node.el.id == id && id.len > 0 { return node } }
	return none
}

fn (manager &FocusManager) path_node(path string) ?FocusNode {
	for node in manager.nodes { if node.path == path { return node } }
	return none
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
	for i, node in manager.nodes {
		if node.el.id == id {
			manager.nodes[i] = FocusNode{ ...node, frame: frame }
			return
		}
	}
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
	// Reveal inside out, carrying the control's visible rect after each planned
	// scroll. Revealing the whole inner viewport would lose targets when that
	// viewport is taller than its outer ancestor.
	mut target := node.frame
	for i := node.scrolls.len - 1; i >= 0; i-- {
		path := node.scrolls[i]
		pane := manager.path_node(path) or { continue }
		local := pane.transform.inverse_rect(target)
		offset := manager.scroll_offsets[path] or { 0.0 }
		request := rect(local.x - pane.local_frame.x, local.y - pane.local_frame.y + offset, local.width, local.height)
		result << FocusReveal{
			id:   pane.el.id
			path: path
			rect: request
		}
		next := math.min(focus_scroll_maximum(pane.el), focus_reveal_offset(offset, pane.el.frame.height, request))
		target = intersect_rect(pane.transform.project(rect(local.x, local.y + offset - next, local.width, local.height)), pane.frame)
	}
	return result
}

fn replace_focus_element(el Element, id string, replacement Element) Element {
	if el.id == id { return replacement }
	mut children := []Element{cap: el.children.len}
	for child in el.children { children << replace_focus_element(child, id, replacement) }
	return Element{ ...el, children: children }
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

fn focus_scroll_maximum(el Element) f64 {
	mut bottom := 0.0
	for child in el.children {
		if !child.hidden { bottom = math.max(bottom, child.frame.y + child.frame.height) }
	}
	return math.max(0, bottom + 16 - el.frame.height)
}

// Windows character messages retain their originating key's scan code. A
// consumed navigation key may remain held while another key enters text.
// Scan-less synthesized/IME text does not belong to a consumed physical key.
fn consumed_key_character(scan_code u32, suppressed map[u32]u32) bool {
	if scan_code == 0 { return false }
	for _, consumed_scan in suppressed {
		if consumed_scan == scan_code { return true }
	}
	return false
}
