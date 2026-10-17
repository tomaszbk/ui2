module ui2

// Declaration-only records connect VML's typed child declarations to existing
// composite control APIs. They are not an AST, model or runtime evaluator.
@[heap]
pub struct CompiledVmlMetadata {
pub:
	tab    ?TabbedPanelTab
	tree   ?TreeViewNode
	screen ?ManagedScreen
	// A MenuBar or Menu document carries its application menus; see menus().
	menu_document bool
	menus         []Menu
	// records describe a child declaration to its parent (a Tab its value and
	// title); see with_record and VmlBuildContext.child_record.
	records []VmlPartRecord
}

// with_record attaches record to el's compiled metadata, keeping what the
// metadata already holds. A child declaration describes itself to its parent
// this way; the parent reads the record with ctx.child_record[T](index).
pub fn with_record(el Element, record VmlPartRecord) Element {
	base := if el.compiled_metadata == unsafe { nil } {
		CompiledVmlMetadata{}
	} else {
		*el.compiled_metadata
	}
	mut records := base.records.clone()
	records << record
	return Element{
		...el
		compiled_metadata: &CompiledVmlMetadata{
			...base
			records: records
		}
	}
}

// vml_record_text is a record on one line, for the props harness and the
// conformance dumps. Callbacks print as their type only.
fn vml_record_text(record VmlPartRecord) string {
	return '${record}'.split_into_lines().map(it.trim_space()).join(' ')
}

// element_record is the record of type T attached to el, or none.
pub fn element_record[T](el Element) ?T {
	metadata := el.compiled_metadata
	if metadata == unsafe { nil } {
		return none
	}
	for record in metadata.records {
		if record is T {
			return record
		}
	}
	return none
}
