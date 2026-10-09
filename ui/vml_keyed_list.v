module ui2

@[heap]
struct VmlKeyedEntry[T] {
	component &CompiledVmlComponent
	item      &Signal[T]
	node      &CompiledVmlNode
}

// A repeater owns a dedicated container and one child component scope per key.
// Its item signal changes when the same key receives new data; build is called
// only for inserted keys. Keys are validated before any mutation takes place.
@[heap]
pub struct VmlKeyedList[T] {
	owner  &CompiledVmlComponent
	parent &CompiledVmlNode
	key    fn (T) string = unsafe { nil }
	build  fn (mut CompiledVmlComponent, &Signal[T]) !&CompiledVmlNode = unsafe { nil }
mut:
	entries map[string]&VmlKeyedEntry[T]
	order   []string
}

pub fn new_vml_keyed_list[T](mut parent CompiledVmlNode, name string, key fn (T) string,
	build fn (mut CompiledVmlComponent, &Signal[T]) !&CompiledVmlNode) !&VmlKeyedList[T] {
	if key == unsafe { nil } || build == unsafe { nil } {
		return error('compiled VML keyed list requires key and build callbacks')
	}
	owner := parent.component.child('list:' + name)!
	return &VmlKeyedList[T]{ owner: owner, parent: &parent, key: key, build: build }
}

pub fn (list &VmlKeyedList[T]) nodes() []&CompiledVmlNode {
	mut result := []&CompiledVmlNode{cap: list.order.len}
	for key in list.order { result << list.entries[key].node }
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
		mut node := list.build(mut component, signal) or {
			component.dispose()!
			for inserted_key in inserted {
				list.entries[inserted_key].component.dispose()!
				list.entries.delete(inserted_key)
			}
			return err
		}
		// Key is structural identity; user ids remain scoped to this instance.
		node.declaration = Element{ ...node.declaration, key: key }
		list.entries[key] = &VmlKeyedEntry[T]{ component: component, item: signal, node: node }
		inserted << key
	}
	list.owner.runtime.batch(fn [mut list, items, keys] [T]() ! {
		for index, item in items { list.entries[keys[index]].item.set(item)! }
	})!
	mut children := []&CompiledVmlNode{cap: keys.len}
	for key in keys { children << list.entries[key].node }
	list.parent.set_children(children)!
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
	if !list.parent.component.is_disposed() { list.parent.set_children([]&CompiledVmlNode{})! }
	list.owner.dispose()!
	list.entries.clear()
	list.order.clear()
}
