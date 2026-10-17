module main

import ui2

// The designer's palette comes from the VML widget registry (the
// descriptors the interpreter builds documents with): an entry exists only
// for a registered tag, and the properties it edits are checked against that
// tag's descriptor. A preset adds what the registry cannot know: the
// palette name and size, default content, and which declared property holds
// the control's text and its callback.
struct DesignerPreset {
	kind         string
	tag          string
	width        f64
	height       f64
	background   u32
	palette_size f64 = 68
	// The property the inspector's text field edits; empty for none.
	text_prop    string
	default_text string
	// The event the inspector's callback is declared on.
	event string = 'on_click'
	// Plain views receive clicks only when declared clickable.
	clickable bool
}

const designer_presets = [
	DesignerPreset{
		kind:         'label'
		tag:          'Label'
		width:        120
		height:       26
		background:   0xffffff
		text_prop:    'text'
		default_text: 'Label {n}'
		clickable:    true
	},
	DesignerPreset{
		kind:         'button'
		tag:          'Button'
		width:        112
		height:       36
		background:   0x2563eb
		text_prop:    'text'
		default_text: 'Button {n}'
	},
	DesignerPreset{
		kind:         'text_field'
		tag:          'TextInput'
		width:        190
		height:       36
		background:   0xffffff
		palette_size: 82
		text_prop:    'placeholder'
		default_text: 'Text field {n}'
		event:        'on_change'
	},
	DesignerPreset{
		kind:         'text_area'
		tag:          'TextArea'
		width:        240
		height:       108
		background:   0xffffff
		palette_size: 82
		text_prop:    'text'
		default_text: 'Text area {n}'
		event:        'on_change'
	},
	DesignerPreset{
		kind:         'checkbox'
		tag:          'Checkbox'
		width:        150
		height:       30
		background:   0xffffff
		palette_size: 82
		text_prop:    'text'
		default_text: 'Checkbox {n}'
	},
	DesignerPreset{
		kind:         'dropdown'
		tag:          'Dropdown'
		width:        170
		height:       36
		background:   0xffffff
		palette_size: 82
		text_prop:    'text'
		default_text: 'Option 1'
		event:        'on_change'
	},
	DesignerPreset{
		kind:         'view'
		tag:          'View'
		width:        160
		height:       100
		background:   0xdbeafe
		palette_size: 82
		clickable:    true
	},
	DesignerPreset{
		kind:       'image'
		tag:        'Image'
		width:      120
		height:     100
		background: 0xe2e8f0
		text_prop:  'source'
		clickable:  true
	},
]

// DesignerKind is a palette entry: a preset with its tag's descriptor.
struct DesignerKind {
	DesignerPreset
	title  string
	widget ui2.VmlWidgetType
}

// has reports whether the control declares `name`.
fn (k DesignerKind) has(name string) bool {
	k.widget.prop(name) or { return false }
	return true
}

// text_title is the inspector's label for the text property.
fn (k DesignerKind) text_title() string {
	return if k.text_prop.len == 0 { 'Text' } else { k.text_prop.capitalize() }
}

const designer_kinds = designer_palette()

// designer_palette lists the presets whose tag is registered and declares
// the preset's text property, its event and, for clickable views, the
// `clickable` flag.
fn designer_palette() []DesignerKind {
	mut kinds := []DesignerKind{}
	for preset in designer_presets {
		widget := ui2.vml_widget_type(preset.tag) or { continue }
		if preset.text_prop.len > 0 {
			info := widget.prop(preset.text_prop) or { continue }
			if info.kind !in [.string, .display_text] { continue }
		}
		event := widget.prop(preset.event) or { continue }
		if !event.is_event { continue }
		if preset.clickable {
			widget.prop('clickable') or { continue }
		}
		kinds << DesignerKind{
			DesignerPreset: preset
			title:          preset.kind.replace('_', ' ').capitalize()
			widget:         widget
		}
	}
	return kinds
}

fn designer_kind(kind string) ?DesignerKind {
	for entry in designer_kinds {
		if entry.kind == kind { return entry }
	}
	return none
}

fn designer_kind_for_tag(tag string) ?DesignerKind {
	for entry in designer_kinds {
		if entry.tag == tag { return entry }
	}
	return none
}

fn component_title(kind string) string {
	entry := designer_kind(kind) or { return kind }
	return entry.title
}

fn component_tag(kind string) string {
	entry := designer_kind(kind) or { return '' }
	return entry.tag
}

fn tag_component_kind(tag string) string {
	entry := designer_kind_for_tag(tag) or { return '' }
	return entry.kind
}

fn component_default_size(kind string) (f64, f64) {
	entry := designer_kind(kind) or { return 120.0, 36.0 }
	return entry.width, entry.height
}

fn component_default_background(kind string) u32 {
	entry := designer_kind(kind) or { return u32(0xffffff) }
	return entry.background
}

fn component_default_text(kind string, ordinal int) string {
	entry := designer_kind(kind) or { return kind }
	return entry.default_text.replace('{n}', ordinal.str())
}

fn component_event_property(component DesignerComponent) string {
	entry := designer_kind(component.kind) or { return 'on_click' }
	return entry.event
}
