module ui2

// Repeaters of the generic node runtime (vml_widget_node.v). A repeater is a
// keyed list (vml_keyed_list.v) whose items are declared through a
// VmlSegment: the item builder declares its roots with
// `vml_child(mut segment, mut item_owner, ...)`, and the segment builds them
// as children of the widget that lays them out.

// VmlSegment is the parent handle of one repeater item: its roots are laid out
// by the host widget, but declared, owned and reconciled per key.
@[heap]
pub struct VmlSegment {
	VmlChildList
mut:
	host  &VmlNodeCore          = unsafe { nil }
	owner &CompiledVmlComponent = unsafe { nil }
	name  string
}

// vml_parent is the parent protocol of vml_child and vml_repeat.
pub fn (mut s VmlSegment) vml_parent() VmlParent {
	return VmlParent{
		host: s.host
		list: &s.VmlChildList
	}
}

// VmlRepeater attaches a declared repeater to the retained node that holds its
// items (the host element, or the fragment of an enclosing item).
interface VmlRepeater {
mut:
	attach(mut target CompiledVmlNode) !
}

@[heap]
struct VmlRepeat[T] {
	name  string
	items fn () ![]T    = unsafe { nil }
	key   fn (T) string = unsafe { nil }
	build fn (mut CompiledVmlComponent, mut VmlSegment, &Signal[T]) ! = unsafe { nil }
	src   VmlSourceLocation
	host  &VmlNodeCore = unsafe { nil }
}

// vml_repeat declares a keyed repeater among the children of a widget node or
// of an enclosing repeater item. `name` is unique among the parent's
// repeaters (the compiled lowering uses the declaration path). `items` is
// tracked; `build` runs once per inserted key with that key's owner, segment
// and item signal.
pub fn vml_repeat[T, N](mut parent N, name string, items fn () ![]T, key fn (T) string, build fn (mut CompiledVmlComponent, mut VmlSegment, &Signal[T]) !, src VmlSourceLocation) ! {
	if items == unsafe { nil } || key == unsafe { nil } || build == unsafe { nil } {
		return src.wrap_error(error('VML repeater requires items, key and build callbacks'))
	}
	handle := parent.vml_parent()
	repeat := &VmlRepeat[T]{
		name:  name
		items: items
		key:   key
		build: build
		src:   src
		host:  handle.host
	}
	mut list := handle.list
	list.repeats << VmlRepeatSlot{
		position: list.children.len
		repeat:   repeat
	}
}

fn (mut r VmlRepeat[T]) attach(mut target CompiledVmlNode) ! {
	repeat := &r
	mut list := new_vml_keyed_list[T](mut target, r.name, r.key, fn [repeat] [T](mut owner CompiledVmlComponent, item &Signal[T]) ![]&CompiledVmlNode {
		mut segment := &VmlSegment{
			host:  repeat.host
			owner: &owner
			name:  repeat.name
		}
		repeat.build(mut owner, mut segment, item)!
		return segment.realize()!
	}) or { return r.src.wrap_error(err) }
	list.bind(r.items, r.src)!
}

// realize builds the item's declared roots as children of the host, with the
// input and placement the host offers a repeated child. An item that holds a
// nested repeater returns one fragment carrying its segments.
fn (mut s VmlSegment) realize() ![]&CompiledVmlNode {
	mut host := s.host
	mut host_node := host.node
	if host_node == unsafe { nil } {
		return error('VML repeater host is not built')
	}
	typed := host.typed()
	frame := host_node.frame_value.peek()!
	input := typed.vml_child_input(frame, host.children.len)!
	placement := typed.vml_child_placement(.normal)
	kind := host_node.declaration.layout.kind
	mut nodes := []&CompiledVmlNode{cap: s.children.len}
	for mut child in s.children {
		if !child.typed().vml_facts().element {
			return child.src.wrap_error(error('a repeater item must be an element'))
		}
		mut node := child.build_element(input, placement) or { return child.src.wrap_error(err) }
		if rule := vml_child_rule_for(kind, child.typed().vml_layout_item()) {
			node.set_child_layout(rule)!
		}
		nodes << node
	}
	if s.repeats.len == 0 {
		return nodes
	}
	mut fragment := s.owner.fragment('body:' + s.name)!
	vml_attach_segments(mut fragment, s.VmlChildList, nodes)!
	return [fragment]
}

// vml_attach_segments registers static children and repeaters as named
// segments of target in declaration order, like the compiled lowering: a
// static child is the segment `static:<declaration index>`.
fn vml_attach_segments(mut target CompiledVmlNode, list VmlChildList, nodes []&CompiledVmlNode) ! {
	mut declaration := 0
	mut repeat := 0
	mut built := 0
	for child in list.children {
		for repeat < list.repeats.len && list.repeats[repeat].position == declaration - repeat {
			mut slot := list.repeats[repeat]
			slot.repeat.attach(mut target)!
			repeat++
			declaration++
		}
		if child.node != unsafe { nil } && built < nodes.len {
			target.set_segment('static:' + declaration.str(), [nodes[built]])!
			built++
		}
		declaration++
	}
	for repeat < list.repeats.len {
		mut slot := list.repeats[repeat]
		slot.repeat.attach(mut target)!
		repeat++
	}
}
