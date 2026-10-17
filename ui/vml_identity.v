module ui2

// control_id gives an authored local id its canonical component namespace.
// Empty ids stay empty, and the document owner keeps its literal ids.
pub fn (component &CompiledVmlComponent) control_id(authored_id string) string {
	return if authored_id.len == 0 || component.namespace.len == 0 {
		authored_id
	} else {
		component.namespace + ':' + authored_id.bytes().hex()
	}
}

@[params]
pub struct VmlNodeConfig {
pub:
	identity string
	// A present VML dimension keeps zero; an omitted dimension measures content.
	authored_width  bool
	authored_height bool
	// Generic content follows its allocated parent's omitted dimensions.
	inherit_width  bool
	inherit_height bool
}

@[heap]
struct VmlOwnerIds {
mut:
	next u64
}

const vml_owner_ids = &VmlOwnerIds{}

fn next_vml_owner_id() string {
	mut ids := unsafe { vml_owner_ids }
	ids.next++
	return ids.next.str()
}

// Length-prefixed names compose unambiguously: a nested namespace grows by
// the name and its length, instead of re-encoding its parent at every level.
fn vml_identity_segment(name string) string {
	return '${name.len}:${name}'
}

// Private identity belongs to one retained owner lifetime. It is independent
// from authored ids and sibling keys, and never contains a memory address.
// It is composed once, when the node is created.
pub fn (node &CompiledVmlNode) identity() string {
	return node.identity_value
}

// identity_path is the identity encoded for reconciliation paths, whose
// segments must not contain the path separator. It is encoded once per node.
fn (node &CompiledVmlNode) identity_path() string {
	if node.identity_hex.len == 0 {
		unsafe {
			node.identity_hex = node.identity_value.bytes().hex()
		}
	}
	return node.identity_hex
}

fn (node &CompiledVmlNode) internal_identity(element Element, index int) string {
	suffix := if element.id.len > 0 {
		'id:' + element.id.bytes().hex()
	} else if element.key.len > 0 {
		'key:' + element.key.bytes().hex()
	} else {
		index.str()
	}
	return node.local_id + '/internal:' + suffix
}
