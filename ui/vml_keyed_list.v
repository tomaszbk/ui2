module ui2

// VmlSourceLocation identifies authored VML for errors from reactive execution.
@[params]
pub struct VmlSourceLocation {
pub:
	source string
	line   int
	column int
}

fn (location VmlSourceLocation) wrap_error(cause IError) IError {
	if location.source.len == 0 { return cause }
	return error_with_code('${location.source}:${location.line}:${location.column}: ${cause.msg()}', cause.code())
}

@[heap]
struct VmlKeyedEntry[T] {
	component &CompiledVmlComponent
	item      &Signal[T]
	index     &Signal[int]
	nodes     []&CompiledVmlNode
}

// A repeater owns one child component scope per key and flattens its roots into
// a named segment of the receiving parent, without a presentation container.
// Its item signal changes when the same key receives new data; build is called
// only for inserted keys. Keys are validated before any mutation takes place.
@[heap]
pub struct VmlKeyedList[T] {
	owner   &CompiledVmlComponent
	parent  &CompiledVmlNode
	key     fn (T) string = unsafe { nil }
	build   fn (mut CompiledVmlComponent, &Signal[T]) ![]&CompiledVmlNode = unsafe { nil }
	segment string
mut:
	entries map[string]&VmlKeyedEntry[T]
	order   []string
	effect  &SignalEffect = unsafe { nil }
}

pub fn new_vml_keyed_list[T](mut parent CompiledVmlNode, name string, key fn (T) string,
	build fn (mut CompiledVmlComponent, &Signal[T]) ![]&CompiledVmlNode) !&VmlKeyedList[T] {
	if key == unsafe { nil } || build == unsafe { nil } {
		return error('compiled VML keyed list requires key and build callbacks')
	}
	owner := parent.component.child('list:' + parent.local_id.bytes().hex() + ':' + name)!
	if value := owner.values['@list'] {
		if owner.value_types['@list'] != 'VmlKeyedList[${T.name}]' {
			return error('compiled VML list `${name}` changed item type')
		}
		return unsafe { &VmlKeyedList[T](value) }
	}
	parent.set_segment('list:' + name, []&CompiledVmlNode{})!
	list := &VmlKeyedList[T]{ owner: owner, parent: &parent, key: key, build: build, segment: 'list:' + name }
	owner.values['@list'] = voidptr(list)
	owner.value_types['@list'] = 'VmlKeyedList[${T.name}]'
	return list
}

// The compiler supplies a typed array reader. Only sources read by this effect
// can reconcile the list; property effects inside existing items stay intact.
// Source locations qualify errors from the initial read and later updates.
pub fn (mut list VmlKeyedList[T]) bind(source fn () ![]T, location VmlSourceLocation) ! {
	list.owner.require_alive()!
	if list.effect != unsafe { nil } { return }
	if source == unsafe { nil } { return error('compiled VML list source is nil') }
	list.effect = list.owner.scope.effect('@items', fn [mut list, source, location] [T]() ! {
		items := source() or { return location.wrap_error(err) }
		list.update(items) or { return location.wrap_error(err) }
	})!
}

pub fn (list &VmlKeyedList[T]) nodes() []&CompiledVmlNode {
	mut result := []&CompiledVmlNode{cap: list.order.len}
	for key in list.order { result << list.entries[key].nodes }
	return result
}

pub fn (mut list VmlKeyedList[T]) update(items []T) ! {
	list.owner.require_alive()!
	mut keys := []string{cap: items.len}
	mut active := map[string]bool{}
	for item in items {
		key := list.key(item)
		if key.len == 0 { return error('compiled VML list key cannot be empty') }
		if key in active { return error('duplicate compiled VML list key `${key}`') }
		active[key] = true
		keys << key
	}
	mut inserted := []string{}
	for index, item in items {
		key := keys[index]
		if key in list.entries { continue }
		mut component := list.owner.child(key)!
		signal := component.state('item', item)!
		position := component.state('@index', index)!
		mut nodes := list.build(mut component, signal) or {
			component.dispose()!
			for inserted_key in inserted {
				list.entries[inserted_key].component.dispose()!
				list.entries.delete(inserted_key)
			}
			return err
		}
		// Key is structural identity; user ids remain scoped to this instance.
		for index, mut node in nodes {
			sibling_key := if nodes.len == 1 { key } else {
				vml_composed_key(key, if node.relative_key.len > 0 { node.relative_key } else { index.str() })
			}
			node.set_reconciliation_key(sibling_key)
		}
		list.entries[key] = &VmlKeyedEntry[T]{ component: component, item: signal, index: position, nodes: nodes }
		inserted << key
	}
	list.owner.runtime.batch(fn [mut list, items, keys] [T]() ! {
		for index, item in items {
			list.entries[keys[index]].item.set(item)!
			list.entries[keys[index]].index.set(index)!
		}
	})!
	mut children := []&CompiledVmlNode{cap: keys.len}
	for key in keys { children << list.entries[key].nodes }
	list.parent.set_segment(list.segment, children)!
	for old in list.order {
		if old !in active {
			list.entries[old].component.dispose()!
			list.entries.delete(old)
		}
	}
	list.order = keys
}

pub fn (mut list VmlKeyedList[T]) dispose() ! {
	if list.owner.is_disposed() { return }
	if !list.parent.component.is_disposed() {
		list.parent.set_segment(list.segment, []&CompiledVmlNode{})!
	}
	list.owner.dispose()!
	list.entries.clear()
	list.order.clear()
}
