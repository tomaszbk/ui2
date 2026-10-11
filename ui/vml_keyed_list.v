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
mut:
	leaving       bool
	exit_revision u64
}

// A typed wrapper retains the immutable key returned by the callback. Appending
// strings directly clones their bytes; keys only need to keep their GC owner.
struct VmlListKey {
	value string
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
	leaving []string
	key_buffer []VmlListKey
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
	owner.on_cleanup('@presence', fn [mut list] [T]() {
		// Scope cleanup also runs when an ancestor/window is disposed directly.
		// Node-owned cleanup cancels the timelines and their completion hooks.
		list.entries.clear()
		list.order.clear()
		list.leaving.clear()
	})!
	owner.values['@list'] = voidptr(list)
	owner.value_types['@list'] = 'VmlKeyedList[${T.name}]'
	return list
}

// The compiler supplies a typed array reader. Reads by the array reader and
// key callback can reconcile the list; item effects track their own sources.
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
	// The key reader still runs so captured key signals remain dependencies.
	// Keep its temporary storage across actions. Unchanged order already has
	// validated unique keys and needs neither a new map nor a new projection.
	list.key_buffer.clear()
	mut same_order := items.len == list.order.len
	for index, item in items {
		key := list.key(item)
		if key.len == 0 { return error('compiled VML list key cannot be empty') }
		list.key_buffer << VmlListKey{ value: key }
		if index >= list.order.len || key != list.order[index] { same_order = false }
	}
	if same_order {
		mut same_items := true
		for index, item in items {
			entry := list.entries[list.order[index]] or { return error('compiled VML list entry is missing') }
			if entry.item.peek()! != item { same_items = false; break }
		}
		if same_items { return }
		list.owner.runtime.untracked(fn [mut list, items] [T]() ! {
			list.update_items(items, list.order)!
		})!
		return
	}
	mut keys := []string{cap: list.key_buffer.len}
	for retained in list.key_buffer { keys << retained.value }
	mut active := map[string]bool{}
	for key in keys {
		if key in active { return error('duplicate compiled VML list key `${key}`') }
		active[key] = true
	}
	list.owner.runtime.untracked(fn [mut list, items, keys, active] [T]() ! {
		list.reconcile(items, keys, active)!
	})!
}

fn (mut list VmlKeyedList[T]) reconcile(items []T, keys []string, active map[string]bool) ! {
	mut inserted := []string{}
	for index, item in items {
		key := keys[index]
		if mut entry := list.entries[key] {
			if entry.leaving {
				entry.exit_revision++
				entry.leaving = false
				entry.component.leaving = false
				for mut node in entry.nodes { node.resume_presence_enter(entry.component)! }
			}
			continue
		}
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
			sibling_key := if nodes.len == 1 {
				key
			} else {
				vml_composed_key(key, if node.relative_key.len > 0 {
					node.relative_key
				} else {
					index.str()
				})
			}
			node.set_reconciliation_key(sibling_key)
		}
		list.entries[key] = &VmlKeyedEntry[T]{ component: component, item: signal, index: position, nodes: nodes }
		inserted << key
	}
	list.update_items(items, keys)!
	list.leaving = list.leaving.filter(it !in active)
	mut immediate := []string{}
	for old in list.order {
		if old !in active {
			mut entry := list.entries[old] or { continue }
			entry.exit_revision++
			revision := entry.exit_revision
			entry.leaving = true
			entry.component.leaving = true
			mut pending := &VmlPresenceExit{
				completion: fn [mut list, old, revision] [T]() {
					list.finish_presence_exit(old, revision) or {
						eprintln('ui2 presence removal failed: ${err}')
					}
				}
			}
			for mut node in entry.nodes { node.begin_presence_exit(mut pending)! }
			if pending.remaining > 0 {
				list.leaving << old
			} else {
				immediate << old
			}
		}
	}
	list.order = keys
	list.publish_presence_children()!
	for key in immediate {
		list.entries[key].component.dispose()!
		list.entries.delete(key)
	}
}

fn (mut list VmlKeyedList[T]) publish_presence_children() ! {
	mut children := []&CompiledVmlNode{cap: list.order.len + list.leaving.len}
	for key in list.order { children << list.entries[key].nodes }
	// Exits keep their old resolved frames, but do not take an active position
	// or prevent inserted/reordered items from using the current logical order.
	for key in list.leaving { children << list.entries[key].nodes }
	// Presence may change while the exact retained handles stay in place.
	list.parent.segments_current = false
	list.parent.set_segment(list.segment, children)!
}

fn (mut list VmlKeyedList[T]) finish_presence_exit(key string, revision u64) ! {
	if list.owner.is_disposed() { return }
	mut entry := list.entries[key] or { return }
	if !entry.leaving || entry.exit_revision != revision { return }
	list.leaving = list.leaving.filter(it != key)
	list.publish_presence_children()!
	entry.component.dispose()!
	list.entries.delete(key)
}

fn (mut list VmlKeyedList[T]) update_items(items []T, keys []string) ! {
	list.owner.runtime.batch(fn [mut list, items, keys] [T]() ! {
		for index, item in items {
			entry := list.entries[keys[index]] or { return error('compiled VML list entry is missing') }
			entry.item.set(item)!
			entry.index.set(index)!
		}
	})!
}

pub fn (mut list VmlKeyedList[T]) dispose() ! {
	if list.owner.is_disposed() { return }
	if !list.parent.component.is_disposed() {
		list.parent.set_segment(list.segment, []&CompiledVmlNode{})!
	}
	list.owner.dispose()!
	list.entries.clear()
	list.order.clear()
	list.leaving.clear()
}
