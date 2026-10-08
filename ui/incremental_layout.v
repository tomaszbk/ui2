module ui2

import math

pub enum LayoutKind {
	none
	flex
	grid
	stack
	absolute
}

// LayoutSpec retains the algorithm and child constraints, never child Elements.
// Use the container constructors to create it.
pub struct LayoutSpec {
pub:
	kind  LayoutKind
	flex  FlexConfig
	grid  GridConfig
	stack StackConfig
}

fn flex_layout_spec(config FlexConfig) FlexConfig {
	return FlexConfig{ ...config, id: '', frame: Rect{}, box: BoxStyle{}, children: config.children.map(FlexChild{ ...it, element: Element{} }) }
}

fn grid_layout_spec(config GridConfig) GridConfig {
	return GridConfig{ ...config, id: '', frame: Rect{}, box: BoxStyle{}, children: [] }
}

fn stack_layout_spec(config StackConfig) StackConfig {
	return StackConfig{ ...config, id: '', frame: Rect{}, box: BoxStyle{}, children: config.children.map(StackChild{ ...it, element: Element{} }) }
}

fn layout_declared(element Element) Element {
	return Element{ ...element, layout_input: element.layout_input or { element.frame } }
}

// Environment versions are explicit because font/fallback availability can
// change without changing a declaration. Device DPI is a presentation concern.
pub struct LayoutEnvironment {
	backend_font_version    u64
	backend_context_version u64
pub:
	version      u64
	font_version u64
	scale        f64 = 1
}

pub struct LayoutStats {
pub mut:
	builds            u64
	reconciled        u64
	measure_visits    u64
	measure_hits      u64
	text_measurements u64
	text_hits         u64
	layout_visits     u64
	layout_hits       u64
}

pub struct LayoutIdentity {
pub:
	generation      u64
	content_version u64
}

@[heap]
struct RetainedLayoutNode {
mut:
	identity        string
	parent          string
	generation      u64
	version         u64
	subtree_version u64
	exterior_key    string
	own_key         string
	children        []string
	declaration     Element
	input           Rect
	measures        map[string]LayoutSize
	text_key        string
	text_measures   map[string]LayoutSize
	placed_frames   []Rect
	arrangement_key string
	placement_key   string
	frame           Rect
}

// LayoutTree is a UI-thread owner, isolated per window. Anonymous nodes receive
// a new generation on rebuild; supply id or sibling key for durable identity.
@[heap]
pub struct LayoutTree {
mut:
	nodes       map[string]&RetainedLayoutNode
	root        string
	serial      u64
	revision    u64
	environment LayoutEnvironment
	measurer    LayoutTextMeasureFn = unsafe { nil }
	counters    LayoutStats
}

pub fn (tree &LayoutTree) stats() LayoutStats { return tree.counters }

pub fn (mut tree LayoutTree) reset_stats() { tree.counters = LayoutStats{} }

pub fn (mut tree LayoutTree) clear() {
	tree.nodes.clear()
	tree.root = ''
	// Never reuse a retired generation, including after clear.
}

pub fn (tree &LayoutTree) identity(id string) ?LayoutIdentity {
	node := tree.find_id(id) or { return none }
	return LayoutIdentity{ generation: node.generation, content_version: node.version }
}

fn (tree &LayoutTree) find_id(id string) ?&RetainedLayoutNode {
	if id.len == 0 { return none }
	for _, node in tree.nodes { if node.declaration.id == id { return node } }
	return none
}

// replace validates before reconciling; duplicate ids/keys never partially
// mutate a mounted tree. Geometry is evaluated only by resolve.
pub fn (mut tree LayoutTree) replace(root Element) ! {
	validate_element_tree(root)!
	tree.counters.builds++
	mut active := map[string]bool{}
	tree.root = tree.reconcile(root, '', mut active)
	for identity in tree.nodes.keys() {
		if identity !in active { tree.nodes.delete(identity) }
	}
}

// patch replaces a mounted subtree without invoking the screen builder. The
// complete candidate is validated so ids cannot collide with outside nodes.
pub fn (mut tree LayoutTree) patch(id string, element Element) ! {
	if tree.root.len == 0 { return error('layout tree is empty') }
	target := tree.find_id(id) or { return error('no mounted element `${id}`') }
	if element.id != id { return error('subtree replacement must preserve id `${id}`') }
	mut found := []bool{len: 1}
	candidate := tree.patch_declaration(tree.root, id, element, mut found)
	validate_element_tree(candidate)!
	mut retired := []string{}
	tree.subtree_identities(target.identity, mut retired)
	previous_version := target.version
	previous_subtree := target.subtree_version
	parent := target.parent
	mut active := map[string]bool{}
	identity := tree.reconcile(element, parent, mut active)
	for old in retired { if old !in active { tree.nodes.delete(old) } }
	current := tree.nodes[identity] or { return error('missing patched subtree') }
	mut changed_size := previous_version != current.version
	changed_below := previous_subtree != current.subtree_version
	mut ancestor := parent
	for ancestor.len > 0 && changed_below {
		mut node := tree.nodes[ancestor] or { return error('missing layout ancestor') }
		tree.revision++
		node.subtree_version = tree.revision
		if changed_size && !(node.input.width > 0 && node.input.height > 0) {
			tree.revision++
			node.version = tree.revision
			node.measures.clear()
		} else {
			changed_size = false
		}
		ancestor = node.parent
	}
}

fn (tree &LayoutTree) subtree_identities(identity string, mut identities []string) {
	node := tree.nodes[identity] or { return }
	identities << identity
	for child in node.children { tree.subtree_identities(child, mut identities) }
}

fn (tree &LayoutTree) patch_declaration(identity string, id string, replacement Element, mut found []bool) Element {
	node := tree.nodes[identity] or { return Element{} }
	if node.declaration.id == id {
		found[0] = true
		return replacement
	}
	mut children := []Element{cap: node.children.len}
	for child in node.children {
		children << tree.patch_declaration(child, id, replacement, mut found)
	}
	return Element{ ...node.declaration, frame: node.input, children: children }
}

fn layout_metric_style(style TextStyle) TextStyle {
	return TextStyle{
		...style
		font_family:      style.font_family.bytes().hex()
		vertical_align:   style.vertical_align.bytes().hex()
		color:            0
		background_color: 0
		underline:        false
		strikethrough:    false
		shadow:           false
		outline:          false
		link:             ''
		align:            .left
		valign:           .middle
	}
}

fn layout_metric_key(element Element, input Rect) string {
	runs := element.text_runs.map(TextRun{ text: it.text.bytes().hex(), style: layout_metric_style(it.style) })
	// Hex-encode user strings so delimiters cannot alias key components.
	return '${element.kind}|${input}|${element.hidden}|${element.text.bytes().hex()}|${element.placeholder.bytes().hex()}|${layout_metric_style(element.text_style)}|${runs}|${element.layout}|${element.content_size}|${element.padding_left}|${element.disable_scroll}|${element.secure}|${element.image_path.bytes().hex()}'
}

fn (mut tree LayoutTree) reconcile(element Element, parent string, mut active map[string]bool) string {
	tree.counters.reconciled++
	identity := if parent.len == 0 {
		'root'
	} else if element.id.len > 0 {
		'id:' + element.id.bytes().hex()
	} else if element.key.len > 0 {
		parent + '/key:' + element.key.bytes().hex()
	} else {
		tree.serial++
		'anonymous:' + tree.serial.str()
	}
	input := element.layout_input or { element.frame }
	own := layout_metric_key(element, input)
	mut node := tree.nodes[identity] or {
		tree.serial++
		created := &RetainedLayoutNode{ identity: identity, generation: tree.serial }
		created
	}
	if node.declaration.kind != element.kind {
		tree.serial++
		node = &RetainedLayoutNode{ identity: identity, generation: tree.serial }
	}
	old_children := node.children.clone()
	mut children := []string{cap: element.children.len}
	mut changed_below := false
	mut changed_size := false
	for child in element.children {
		// Snapshot versions before the recursive call mutates retained nodes.
		child_id := if child.id.len > 0 {
			'id:' + child.id.bytes().hex()
		} else {
			identity + '/key:' + child.key.bytes().hex()
		}
		old := tree.nodes[child_id] or { &RetainedLayoutNode{} }
		previous_version := old.version
		previous_subtree := old.subtree_version
		resolved := tree.reconcile(child, identity, mut active)
		current := tree.nodes[resolved] or { panic('missing layout child') }
		children << resolved
		changed_size = changed_size || previous_version != current.version
		changed_below = changed_below || previous_subtree != current.subtree_version
	}
	own_changed := own != node.own_key || old_children != children
	exterior := if input.width > 0 && input.height > 0 { '${input}|${element.hidden}' } else { own }
	// Fixed leaves paint new content without changing any geometry dependency.
	geometry_changed := own_changed && !(input.width > 0 && input.height > 0 && children.len == 0 && exterior == node.exterior_key)
	if geometry_changed || changed_below {
		tree.revision++
		node.subtree_version = tree.revision
	}
	// A fixed exterior is a proven relayout boundary. Its descendants still
	// invalidate disposition, but cannot change the parent's preferred size.
	if exterior != node.exterior_key || (old_children != children && !(input.width > 0 && input.height > 0)) || (changed_size && !(input.width > 0 && input.height > 0)) {
		tree.revision++
		node.version = tree.revision
		node.measures.clear()
	}
	text_key := layout_metric_key(element, rect(0, 0, input.width, input.height))
	if text_key != node.text_key {
		node.text_measures.clear()
		node.text_key = text_key
	}
	node.exterior_key = exterior
	node.parent = parent
	node.own_key = own
	node.input = input
	node.children = children
	node.declaration = Element{ ...element, children: [], frame: input, layout_input: input }
	tree.nodes[identity] = node
	active[identity] = true
	return identity
}

// resolve preserves fractional logical coordinates. The backend rounds only
// when presenting. Measurer identity and environment participate in every key.
pub fn (mut tree LayoutTree) resolve(constraints LayoutConstraints, measure LayoutTextMeasureFn, environment LayoutEnvironment) !Element {
	constraints.validate()!
	if !math.is_finite(environment.scale) || environment.scale <= 0 {
		return error('layout environment scale must be positive and finite')
	}
	if tree.root.len == 0 { return error('layout tree is empty') }
	for _ in 0 .. 3 {
		effective := layout_effective_environment(environment, measure)
		if tree.environment != effective || voidptr(tree.measurer) != voidptr(measure) {
			for _, mut node in tree.nodes {
				node.measures.clear()
				node.text_measures.clear()
				node.placement_key = ''
				node.arrangement_key = ''
			}
		}
		tree.environment = effective
		tree.measurer = measure
		size := tree.measure_node(tree.root, constraints)!
		root := tree.nodes[tree.root] or { return error('missing root') }
		tree.place_node(tree.root, rect(root.input.x, root.input.y, size.width, size.height))!
		// A newly resolved font can advance the backend generation during a
		// cold pass. Stabilize once all fonts used by the tree are registered.
		if layout_effective_environment(environment, measure) == effective {
			return tree.output(tree.root)
		}
	}
	return error('measurement environment changed repeatedly during layout')
}

fn layout_effective_environment(environment LayoutEnvironment, measure LayoutTextMeasureFn) LayoutEnvironment {
	$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
		if voidptr(measure) == voidptr(measure_layout_text) {
			context_version := if g_gg_app.ctx != unsafe { nil } && g_gg_app.ctx.text != unsafe { nil } {
				g_gg_app.ctx.text.environment_version
			} else if g_cpu_text_engine != unsafe { nil } {
				g_cpu_text_engine.environment_version
			} else {
				u64(0)
			}
			return LayoutEnvironment{ ...environment, backend_font_version: u64(g_text_font_generation), backend_context_version: context_version }
		}
	}
	return environment
}

fn layout_measure_is_text(element Element) bool {
	return element.kind in [.label, .button, .toggle_button, .checkbox, .dropdown, .text_field,
		.text_area]
}

fn (mut tree LayoutTree) measure_node(identity string, constraints LayoutConstraints) !LayoutSize {
	mut node := tree.nodes[identity] or { return error('missing layout node') }
	key := '${node.generation}|${node.version}|${constraints}|${tree.environment}|${voidptr(tree.measurer)}'
	if size := node.measures[key] {
		tree.counters.measure_hits++
		return size
	}
	tree.counters.measure_visits++
	input := node.input
	mut preferred := LayoutSize{}
	if node.declaration.hidden {
		preferred = constraints.constrain(LayoutSize{})!
	} else if input.width > 0 && input.height > 0 {
		preferred = constraints.constrain(LayoutSize{ width: input.width, height: input.height })!
	} else if layout_measure_is_text(node.declaration) {
		text_key := '${node.text_key}|${constraints}|${tree.environment}|${voidptr(tree.measurer)}'
		if cached := node.text_measures[text_key] {
			tree.counters.text_hits++
			preferred = cached
		} else {
			tree.counters.text_measurements++
			preferred = measure_layout_element(node.declaration, constraints, tree.measurer)!
			if node.text_measures.len >= 16 { node.text_measures.clear() }
			node.text_measures[text_key] = preferred
		}
	} else {
		mut available := rect(0, 0, if input.width > 0 {
			input.width
		} else {
			math.max(0.0, constraints.max_width)
		},
			if input.height > 0 { input.height } else { math.max(0.0, constraints.max_height) })
		sizes := tree.child_sizes(node, LayoutConstraints{})!
		if input.width <= 0 && constraints.max_width < 0 {
			available = rect(0, 0, layout_natural_width(node, sizes)!, available.height)
		}
		frames, natural := tree.container_geometry(node, available, sizes, true)!
		_ = frames
		preferred = constraints.constrain(LayoutSize{
			width:  if input.width > 0 { input.width } else { natural.width }
			height: if input.height > 0 { input.height } else { natural.height }
		})!
	}
	// Bound memory during arbitrary resize; retired content drops all entries.
	if node.measures.len >= 16 { node.measures.clear() }
	node.measures[key] = preferred
	return preferred
}

fn (mut tree LayoutTree) child_sizes(node &RetainedLayoutNode, constraints LayoutConstraints) ![]Rect {
	mut sizes := []Rect{cap: node.children.len}
	for child in node.children {
		child_node := tree.nodes[child] or { return error('missing child') }
		if child_node.declaration.hidden {
			sizes << Rect{}
			continue
		}
		size := tree.measure_node(child, constraints)!
		sizes << rect(child_node.input.x, child_node.input.y, size.width, size.height)
	}
	return sizes
}

fn (mut tree LayoutTree) container_geometry(node &RetainedLayoutNode, available Rect, sizes []Rect, measuring bool) !([]Rect, Rect) {
	match node.declaration.layout.kind {
		.flex {
			mut items := []FlexChild{cap: sizes.len}
			for i, size in sizes {
				rule := if i < node.declaration.layout.flex.children.len {
					node.declaration.layout.flex.children[i]
				} else {
					FlexChild{}
				}
				items << FlexChild{ ...rule, element: Element{ frame: size } }
			}
			mut config := FlexConfig{ ...node.declaration.layout.flex, frame: available, children: items }
			// Natural height in an intrinsic column must not shrink its contents.
			initial := flex_preferred_size(config)!
			if measuring && node.input.height <= 0 {
				config = FlexConfig{ ...config, frame: rect(0, 0, available.width, initial.height) }
			}
			first := flex_frames(config)!
			for i, child in node.children {
				child_node := tree.nodes[child] or { return error('missing child') }
				if child_node.input.height > 0 { continue }
				// Assigned-width measurement is distinct from intrinsic measurement.
				measured := tree.measure_node(child, LayoutConstraints{ min_width: first[i].width, max_width: first[i].width })!
				items[i] = FlexChild{ ...items[i], element: Element{ frame: rect(0, 0, sizes[i].width, measured.height) } }
			}
			config = FlexConfig{ ...config, children: items }
			mut natural := flex_preferred_size(config)!
			if measuring && node.input.height <= 0 {
				config = FlexConfig{ ...config, frame: rect(0, 0, available.width, natural.height) }
			}
			frames := flex_frames(config)!
			if config.wrap {
				mut bottom := config.padding.top
				for frame in frames { bottom = math.max(bottom, frame.y + frame.height) }
				natural = rect(0, 0, natural.width, bottom + config.padding.bottom)
			}
			return frames, natural
		}
		.grid {
			mut config := GridConfig{ ...node.declaration.layout.grid, frame: available }
			initial := grid_preferred_size(config, sizes)!
			if measuring && node.input.height <= 0 {
				config = GridConfig{ ...config, frame: rect(0, 0, available.width, initial.height) }
			}
			first := grid_frames(config, sizes.len)!
			mut measured_sizes := sizes.clone()
			for i, child in node.children {
				child_node := tree.nodes[child] or { return error('missing child') }
				if child_node.input.height > 0 { continue }
				measured := tree.measure_node(child, LayoutConstraints{ min_width: first[i].width, max_width: first[i].width })!
				measured_sizes[i] = rect(0, 0, sizes[i].width, measured.height)
			}
			natural := grid_preferred_size(config, measured_sizes)!
			if measuring && node.input.height <= 0 {
				config = GridConfig{ ...config, frame: rect(0, 0, available.width, natural.height) }
			}
			return grid_frames(config, sizes.len)!, natural
		}
		.stack {
			mut children := []StackChild{cap: sizes.len}
			for i, size in sizes {
				rule := if i < node.declaration.layout.stack.children.len {
					node.declaration.layout.stack.children[i]
				} else {
					StackChild{}
				}
				children << StackChild{ ...rule, element: Element{ frame: size } }
			}
			mut config := StackConfig{ ...node.declaration.layout.stack, frame: available, children: children }
			first := stack_frames(config)!
			for i, child in node.children {
				child_node := tree.nodes[child] or { return error('missing child') }
				if child_node.input.height > 0 { continue }
				measured := tree.measure_node(child, LayoutConstraints{ min_width: first[i].width, max_width: first[i].width })!
				children[i] = StackChild{ ...children[i], element: Element{ frame: rect(0, 0, sizes[i].width, measured.height) } }
			}
			config = StackConfig{ ...config, children: children }
			return stack_frames(config)!, stack_preferred_size(config)!
		}
		else {
			mut width := 0.0
			mut height := 0.0
			for size in sizes {
				width = math.max(width, size.x + size.width)
				height = math.max(height, size.y + size.height)
			}
			return sizes, rect(0, 0, width, height)
		}
	}
}

fn (mut tree LayoutTree) place_node(identity string, frame Rect) ! {
	mut node := tree.nodes[identity] or { return error('missing layout node') }
	// Position-only changes do not require arranging the node's local children.
	key := '${node.generation}|${node.subtree_version}|${frame.width}|${frame.height}|${tree.environment}'
	node.frame = frame
	if node.declaration.hidden {
		node.placement_key = key
		return
	}
	if key == node.placement_key {
		tree.counters.layout_hits++
		return
	}
	mut dependencies := []string{cap: node.children.len}
	for child in node.children {
		child_node := tree.nodes[child] or { return error('missing layout child') }
		dependencies << '${child_node.generation}:${child_node.version}'
	}
	arrangement := '${node.own_key}|${dependencies}|${frame.width}|${frame.height}|${tree.environment}'
	mut frames := node.placed_frames.clone()
	if arrangement == node.arrangement_key {
		tree.counters.layout_hits++
	} else {
		tree.counters.layout_visits++

		sizes := tree.child_sizes(node, LayoutConstraints{})!
		available := if node.declaration.content_size.width > 0 {
			rect(0, 0, node.declaration.content_size.width, node.declaration.content_size.height)
		} else {
			rect(0, 0, frame.width, frame.height)
		}
		computed, _ := tree.container_geometry(node, available, sizes, false)!
		frames = computed.clone()
	}
	node.arrangement_key = arrangement
	node.placed_frames = frames
	node.placement_key = key
	for i, child in node.children { tree.place_node(child, frames[i])! }
}

fn (tree &LayoutTree) output(identity string) Element {
	node := tree.nodes[identity] or { return Element{} }
	mut children := []Element{cap: node.children.len}
	for child in node.children { children << tree.output(child) }
	return Element{ ...node.declaration, frame: node.frame, children: children }
}

struct LayoutPatch {
	id      string
	element Element
}

// declaration returns authored inputs, suitable for subsequent targeted patches.
pub fn (tree &LayoutTree) declaration() Element {
	return tree.authored(tree.root)
}

fn (tree &LayoutTree) authored(identity string) Element {
	node := tree.nodes[identity] or { return Element{} }
	mut children := []Element{cap: node.children.len}
	for child in node.children { children << tree.authored(child) }
	return Element{ ...node.declaration, children: children, frame: node.input }
}

fn layout_natural_width(node &RetainedLayoutNode, sizes []Rect) !f64 {
	match node.declaration.layout.kind {
		.flex {
			mut items := []FlexChild{}
			for i, size in sizes {
				rule := if i < node.declaration.layout.flex.children.len {
					node.declaration.layout.flex.children[i]
				} else {
					FlexChild{}
				}
				items << FlexChild{ ...rule, element: Element{ frame: size } }
			}
			return flex_preferred_size(FlexConfig{ ...node.declaration.layout.flex, children: items })!.width
		}
		.grid { return grid_preferred_size(node.declaration.layout.grid, sizes)!.width }
		.stack {
			mut children := []StackChild{}
			for size in sizes { children << StackChild{ element: Element{ frame: size } } }
			return stack_preferred_size(StackConfig{ ...node.declaration.layout.stack, children: children })!.width
		}
		else {
			mut width := 0.0
			for size in sizes { width = math.max(width, size.x + size.width) }
			return width
		}
	}
}

// with_layout_frame changes authored geometry even when called on a resolved
// Element. Changing only frame leaves the retained authored geometry unchanged.
pub fn (element Element) with_layout_frame(frame Rect) Element {
	return Element{ ...element, frame: frame, layout_input: frame }
}
