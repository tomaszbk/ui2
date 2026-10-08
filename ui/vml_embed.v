module ui2

// VmlApp owns a model and a parsed document without owning a window or loop.
// Build returns element callbacks that apply their captured declaration to this
// app. Hosts deliver the typed event payload directly to the hit element.
@[heap]
pub struct VmlApp[T] {
	template &VNode
mut:
	model T
}

pub fn new_vml_app[T](source string, model T) !&VmlApp[T] {
	template := parse_vml(source)!
	v_validate_template[T](template, model)!
	probe := rect(0, 0, 1024, 768)
	resolved, _ := v_evaluate_template(template, model, probe)!
	validate_element_tree(element_from_vnode(resolved, probe)!)!
	return &VmlApp[T]{ template: template, model: model }
}

pub fn (mut app VmlApp[T]) build(size Rect) !Element {
	frame := rect(0, 0, size.width, size.height)
	mut resolved, records := v_evaluate_template(app.template, app.model, frame)!
	v_attach_app_callbacks(mut app, mut resolved, records)
	return element_from_vnode(resolved, frame)!
}

fn v_attach_app_callbacks[T](mut app VmlApp[T], mut node VNode, records map[string]VmlEvent) {
	tag := node.tag
	for property in vml_event_properties {
		identifier := node.prop(property)
		record := records[identifier] or { continue }
		callback := fn [mut app, record, property, tag] [T](event ElementEvent) {
			if !vml_record_accepts(tag, property, record, event) { return }
			vml_apply_event[T](mut app.model, record, event) or {
				eprintln('ui2 VML event failed: ${err}')
				return
			}
			request_refresh()
		}
		node.callbacks[property] = VmlCallback{ on_event: callback }
	}
	for mut child in node.children { v_attach_app_callbacks(mut app, mut child, records) }
}

pub fn (app &VmlApp[T]) state() T { return app.model }
