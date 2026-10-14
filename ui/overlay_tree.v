module ui2

struct OverlayLayer {
mut:
	element      Element
	config       OverlayConfig
	path         string
	parent       string
	dependencies []string
	scopes       []string
	available    bool
	active       bool
	frame        Rect
	layout       &LayoutTree = &LayoutTree{}
	surface      Element
	backdrop     Element
}

// One window owns its portal projections. The authored/layout tree retains
// component lifetime; this tree only owns placement and presentation snapshots.
@[heap]
struct OverlayTree {
mut:
	geometry           &FocusManager       = &FocusManager{}
	placement_geometry &FocusManager       = &FocusManager{}
	measure            LayoutTextMeasureFn = unsafe { nil }
	environment        LayoutEnvironment
	source             Element
	output             Element
	viewport           Rect
	initialized        bool
	has_overlays       bool
	geometry_serial    u64
	source_revision    u64
	offsets_x          map[string]f64
	layers             []OverlayLayer
	modal              string
	candidate          Element
	candidate_buffer   []Element
	output_buffer      []Element
}

fn element_has_overlays(element Element) bool {
	if element.overlay != none { return true }
	for child in element.children { if element_has_overlays(child) { return true } }
	return false
}

const overlay_host_path = 'overlay_host'

fn presentation_root_path(element Element) string {
	return if element.overlay_host { overlay_host_path } else { 'root' }
}

fn strip_overlay_children(element Element, path string, parent string) Element {
	mut children := []Element{cap: element.children.len}
	mut changed := false
	for i, child in element.children {
		if child.overlay != none {
			changed = true
			continue
		}
		clean := strip_overlay_children(child, reconciliation_child_key(path, i, child), path)
		children << clean
		changed = changed || clean != child
	}
	return if changed || element.mounted_path.len == 0 {
		Element{ ...element, children: children, mounted_path: path, mounted_parent_path: parent }
	} else {
		element
	}
}

// Reflow may change frames, never editor/scroll/tooltip identity. In particular
// two portals containing anonymous controls must keep their distinct raw keys.
fn restore_portal_identity(element Element, source Element) Element {
	mut children := []Element{cap: element.children.len}
	for i, child in element.children {
		children << if i < source.children.len {
			restore_portal_identity(child, source.children[i])
		} else {
			child
		}
	}
	return Element{
		...element
		mounted_generation:  source.mounted_generation
		mounted_path:        source.mounted_path
		mounted_parent_path: source.mounted_parent_path
		mounted_scroll_id:   source.mounted_scroll_id
		mounted_tooltip_key: source.mounted_tooltip_key
		children:            children
	}
}

// Anchors and owners may appear later in the declaration, including inside a
// different portal. Resolve those portals first, then use their presented frame.
fn (tree &OverlayTree) declaration_owner(id string) string {
	mut node := tree.geometry.node(id) or { return '' }
	for _ in 0 .. tree.geometry.nodes.len {
		if node.el.overlay != none { return node.el.id }
		node = tree.geometry.path_node(node.parent) or { return '' }
	}
	return ''
}

fn (mut tree OverlayTree) order_layers() ! {
	mut ordered := []OverlayLayer{cap: tree.layers.len}
	mut added := map[string]bool{}
	for ordered.len < tree.layers.len {
		mut progress := false
		for layer in tree.layers {
			if added[layer.element.id] or { false } { continue }
			mut ready := true
			for dependency in layer.dependencies {
				if tree.layer_index(dependency) >= 0 && !(added[dependency] or { false }) {
					ready = false
					break
				}
			}
			if !ready { continue }
			ordered << layer
			added[layer.element.id] = true
			progress = true
		}
		if !progress { return error('overlay anchor/owner relationships contain a cycle') }
	}
	tree.layers = ordered
}

fn (mut tree OverlayTree) collect(element Element, path string, parent string, old map[string]&LayoutTree) ! {
	mut next_parent := parent
	if config := element.overlay {
		next_parent = element.id
		raw := tree.geometry.path_node(path) or { FocusNode{} }
		mut logical_parent := parent
		mut dependencies := []string{}
		if parent.len > 0 { dependencies << parent }
		if config.anchor.len > 0 {
			anchor_owner := tree.declaration_owner(config.anchor)
			if anchor_owner.len > 0 {
				logical_parent = anchor_owner
				if anchor_owner !in dependencies { dependencies << anchor_owner }
			}
		}
		if config.owner.len > 0 {
			owner := tree.declaration_owner(config.owner)
			if owner.len > 0 {
				logical_parent = owner
				if owner !in dependencies { dependencies << owner }
			}
		}
		backdrop := view(element.id + '__backdrop', tree.viewport, config.backdrop, [])
		tree.layers << OverlayLayer{
			element:      strip_overlay_children(element, path, raw.parent)
			config:       config
			path:         path
			parent:       logical_parent
			dependencies: dependencies
			frame:        element.frame
			layout:       old[element.id] or { &LayoutTree{} }
			backdrop:     Element{ ...backdrop, mounted_path: overlay_host_path + '/backdrop:' + element.id.bytes().hex(), mounted_parent_path: overlay_host_path, clickable: true, focus_policy: .unfocusable, accessibility_role: 'presentation' }
		}
	}
	for i, child in element.children {
		tree.collect(child, reconciliation_child_key(path, i, child), next_parent, old)!
	}
}

fn (tree &OverlayTree) layer_index(id string) int {
	for i, layer in tree.layers { if layer.element.id == id { return i } }
	return -1
}

fn (tree &OverlayTree) logical_scopes(id string) []string {
	mut result := []string{}
	mut current := id
	for _ in 0 .. tree.layers.len {
		index := tree.layer_index(current)
		if index < 0 { break }
		layer := tree.layers[index]
		if layer.element.focus_scope { result.insert(0, current) }
		current = layer.parent
	}
	return result
}

fn (mut layer OverlayLayer) resolve_surface(measure LayoutTextMeasureFn, environment LayoutEnvironment) !Element {
	local_frame := rect(0, 0, layer.frame.width, layer.frame.height)
	local := layer.element.with_layout_frame(local_frame)
	layer.layout.geometry_readonly = true
	layer.layout.replace(Element{ ...local, overlay: none })!
	for _ in 0 .. 64 {
		resolved := layer.layout.resolve(LayoutConstraints{}, measure, environment)!
		updates := compiled_vml_sync_geometry(Element{ ...resolved, frame: layer.frame, overlay: none })!
		if updates.len == 0 { return restore_portal_identity(resolved, layer.element) }
		for update in updates {
			projection := if update.compiled_node == layer.element.compiled_node {
				Element{ ...update.with_layout_frame(local_frame), overlay: none }
			} else {
				update
			}
			layer.layout.patch_compiled(update.compiled_node, projection)!
		}
	}
	return error('overlay geometry changed repeatedly during surface layout')
}

fn (mut tree OverlayTree) resolve(root Element, offsets map[string]f64, viewport Rect, motion_serial u64) !Element {
	changed := !tree.initialized || tree.source != root
	if changed {
		tree.has_overlays = element_has_overlays(root)
		tree.source_revision++
	}
	if !tree.has_overlays {
		tree.layers.clear()
		tree.modal = ''
		tree.source = root
		tree.output = root
		tree.initialized = true
		return root
	}
	tree.geometry.motion_serial = motion_serial
	tree.geometry.update_mounted_axes(root, offsets, tree.offsets_x, viewport, ContentTransform{})
	if !changed && tree.viewport == viewport && tree.geometry_serial == tree.geometry.geometry_serial {
		return tree.output
	}
	if !changed && tree.reproject(offsets, viewport)! {
		tree.viewport = viewport
		tree.geometry_serial = tree.geometry.geometry_serial
		return tree.output
	}
	tree.source = root
	tree.viewport = viewport
	tree.initialized = true
	tree.geometry_serial = tree.geometry.geometry_serial
	mut old := map[string]&LayoutTree{}
	for layer in tree.layers { old[layer.element.id] = layer.layout }
	tree.layers.clear()
	tree.collect(root, 'root', '', old)!
	tree.order_layers()!
	for layer in tree.layers {
		if layer.config.kind == .dialog && tree.geometry.node(layer.element.id + '__backdrop') != none {
			return error('overlay backdrop id `${layer.element.id}__backdrop` collides with a declared element')
		}
	}
	tree.modal = ''
	mut children := []Element{}
	base := if root.overlay == none {
		strip_overlay_children(root, 'root', '')
	} else {
		view('', viewport, BoxStyle{ transparent: true }, [])
	}
	children << Element{ ...base, frame: mounted_root_frame(root, viewport), mounted_path: 'root', mounted_parent_path: overlay_host_path }
	for index in 0 .. tree.layers.len {
		mut layer := &tree.layers[index]
		layer.scopes = tree.logical_scopes(layer.parent)
		tree.place_layer(index, Element{ ...view('', viewport, BoxStyle{ transparent: true }, children), overlay_host: true }, offsets, viewport)!
		// The surface has its own constraints; shrinking at a viewport edge must
		// reflow its children rather than merely clipping their old layout.
		surface := layer.resolve_surface(tree.measure, tree.environment)!
		layer.surface = surface
		children << Element{
			...surface
			frame:               layer.frame
			overlay:             layer.config
			overlay_scopes:      layer.scopes
			mounted_path:        layer.path
			mounted_parent_path: overlay_host_path
			hidden:              surface.hidden || !layer.config.open || !layer.available
			motion_state:        if layer.available && (layer.config.open || layer.element.hidden) {
				layer.element.motion_state
			} else {
				unsafe { nil }
			}
			enabled:             surface.enabled && layer.active
			overlay_inert:       layer.config.kind == .tooltip
		}
	}
	mut presented := []Element{cap: 1 + tree.layers.len * 2}
	tree.fill_presentation(children, mut presented, viewport)
	tree.candidate = Element{ ...view('', viewport, BoxStyle{ transparent: true }, children), overlay_host: true }
	tree.candidate_buffer = []Element{cap: children.len}
	for child in children { tree.candidate_buffer << unsafe { child } }
	tree.output = Element{ ...view('', viewport, BoxStyle{ transparent: true }, presented), overlay_host: true }
	tree.output_buffer = []Element{cap: 1 + tree.layers.len * 2}
	return tree.output
}

fn (mut tree OverlayTree) fill_presentation(candidates []Element, mut presented []Element, viewport Rect) {
	tree.modal = ''
	for layer in tree.layers {
		if layer.active && layer.config.kind == .dialog { tree.modal = layer.element.id }
	}
	presented.trim(0)
	presented << Element{ ...candidates[0], overlay_inert: tree.modal.len > 0 }
	for index, layer in tree.layers {
		allowed := tree.modal.len == 0 || layer.element.id == tree.modal || tree.modal in layer.scopes
		if layer.config.kind == .dialog {
			// Keep a stable hidden slot when its anchor is clipped or presence ends.
			// Geometry refreshes can then reuse both presentation and focus buffers.
			presented << Element{
				...layer.backdrop
				frame:   viewport
				hidden:  !(layer.config.open || layer.element.presence_leaving()) || layer.element.presented_hidden() || !layer.available
				opacity: layer.config.backdrop_opacity * layer.element.presented_opacity()
				enabled: layer.active && allowed
			}
		}
		presented << Element{ ...candidates[index + 1], overlay_inert: !allowed || layer.config.kind == .tooltip }
	}
}

// Both cold layout and retained projection resolve the same dependency and
// projected owner/anchor availability before choosing a modal input gate.
fn (mut tree OverlayTree) place_layer(index int, candidate Element, offsets map[string]f64, viewport Rect) ! {
	mut layer := &tree.layers[index]
	raw := tree.geometry.path_node(layer.path) or { FocusNode{} }
	mut available := true
	if owner := tree.geometry.path_node(raw.parent) { available = !owner.hidden && owner.enabled }
	if layer.config.owner.len > 0 {
		owner := tree.geometry.node(layer.config.owner) or { FocusNode{ hidden: true } }
		available = available && !owner.hidden && owner.enabled
	}
	mut anchor_frame := Rect{}
	if layer.config.anchor.len > 0 {
		anchor := tree.geometry.node(layer.config.anchor) or { FocusNode{ hidden: true } }
		available = available && !anchor.hidden && anchor.enabled
		anchor_frame = anchor.frame
	}
	for dependency in layer.dependencies {
		owner := tree.layer_index(dependency)
		if owner >= 0 { available = available && tree.layers[owner].active }
	}
	if layer.config.anchor.len > 0 || layer.config.owner.len > 0 {
		// The private candidate buffer may change earlier slots during this pass.
		// Force the registry to read current scalar frames without publishing it.
		tree.placement_geometry.motion_serial++
		tree.placement_geometry.update_mounted_axes(candidate, offsets, tree.offsets_x, viewport, ContentTransform{})
		if layer.config.owner.len > 0 {
			owner := tree.placement_geometry.node(layer.config.owner) or { FocusNode{ hidden: true } }
			available = available && !owner.hidden && owner.enabled
		}
		if layer.config.anchor.len > 0 {
			if anchor := tree.placement_geometry.node(layer.config.anchor) {
				visible := anchor.clip.intersect(paint_transformed_clip(anchor.local_frame, anchor.transform)).bounds()
				available = available && !anchor.hidden && anchor.enabled && visible.width > 0 && visible.height > 0
				anchor_frame = anchor.frame
			} else {
				available = false
			}
		}
	}
	layer.frame = overlay_frame(layer.config, LayoutSize{ width: layer.element.frame.width, height: layer.element.frame.height }, anchor_frame, viewport)!
	layer.available = available
	layer.active = available && layer.config.open && !layer.element.hidden && layer.element.presented_enabled()
}

// A geometry-dependent effect can change layout or structure. Let the normal
// resolve/sync loop publish those changes before reflowing; firing it in the
// projection cache first would consume its update against an older source.
fn overlay_geometry_needs_reflow(element Element) bool {
	if element.overlay != none || element.hidden { return false }
	if element.compiled_node != unsafe { nil } && !element.compiled_node.component.is_disposed() {
		value := element.compiled_node.frame_value
		if value.value != element.frame && value.node.subscribers.len > 0 { return true }
	}
	for child in element.children { if overlay_geometry_needs_reflow(child) { return true } }
	return false
}

// Geometry-only frames keep the authored surfaces and their layout snapshots.
// Working candidates are private; published presentation slots alternate buffers
// so the current FocusManager/paint snapshot is never mutated in place.
fn (mut tree OverlayTree) reproject(offsets map[string]f64, viewport Rect) !bool {
	mut candidates := unsafe { tree.candidate_buffer }
	candidates[0] = Element{ ...candidates[0], frame: mounted_root_frame(tree.source, viewport) }
	for index in 0 .. tree.layers.len {
		mut layer := &tree.layers[index]
		tree.place_layer(index, Element{ ...tree.candidate, frame: viewport, children: candidates }, offsets, viewport)!
		frame := layer.frame
		if frame.width != layer.surface.frame.width || frame.height != layer.surface.frame.height {
			return false
		}
		if layer.surface.compiled_node != unsafe { nil } {
			projection := Element{ ...layer.surface, frame: frame, overlay: none }
			if overlay_geometry_needs_reflow(projection) { return false }
			updates := compiled_vml_sync_geometry(projection)!
			if updates.len > 0 { return false }
		}
		candidates[index + 1] = Element{
			...layer.surface
			frame:               frame
			overlay:             layer.config
			overlay_scopes:      layer.scopes
			mounted_path:        layer.path
			mounted_parent_path: overlay_host_path
			hidden:              layer.surface.hidden || !layer.config.open || !layer.available
			motion_state:        if layer.available && (layer.config.open || layer.element.hidden) {
				layer.element.motion_state
			} else {
				unsafe { nil }
			}
			enabled:             layer.surface.enabled && layer.active
			overlay_inert:       layer.config.kind == .tooltip
		}
	}
	mut presented := unsafe { tree.output_buffer }
	tree.fill_presentation(candidates, mut presented, viewport)
	previous_candidates := unsafe { tree.candidate.children }
	tree.candidate = Element{ ...tree.candidate, frame: viewport, children: candidates }
	tree.candidate_buffer = previous_candidates
	previous_output := unsafe { tree.output.children }
	tree.output = Element{ ...tree.output, frame: viewport, children: presented }
	tree.output_buffer = previous_output
	return true
}

fn (tree &OverlayTree) top_active() ?OverlayLayer {
	for i := tree.layers.len - 1; i >= 0; i-- {
		layer := tree.layers[i]
		if layer.active && layer.config.kind != .tooltip
			&& (tree.modal.len == 0 || layer.element.id == tree.modal || tree.modal in layer.scopes) {
			return layer
		}
	}
	return none
}
