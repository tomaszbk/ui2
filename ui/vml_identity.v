module ui2

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

// Private identity belongs to one retained owner lifetime. It is independent
// from authored ids and sibling keys, and never contains a memory address.
pub fn (node &CompiledVmlNode) identity() string {
	return '/compiled:' + node.component.identity_namespace + '/' + node.local_id.bytes().hex()
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
