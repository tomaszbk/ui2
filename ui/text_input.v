module ui2

pub struct TextInputConfig {
pub:
	id           string
	on_event     ElementCallback = unsafe { nil }
	frame        Rect
	text         string
	placeholder  string
	password     bool
	readonly     bool
	enabled      bool = true
	autocorrect  bool = true
	keyboard     int
	padding_left f64 = 12.0
	box          BoxStyle
	text_style   TextStyle
}

// TextInput creates a single-line editable field, including secure entry.
pub fn text_input(config TextInputConfig) !Element {
	return Element{
		kind:         .text_field
		id:           config.id
		on_event:     config.on_event
		text:         config.text
		placeholder:  config.placeholder
		frame:        config.frame
		box:          config.box
		text_style:   config.text_style
		secure:       config.password
		readonly:     config.readonly
		enabled:      config.enabled
		autocorrect:  config.autocorrect
		keyboard:     config.keyboard
		padding_left: config.padding_left
	}
}

pub struct TextAreaConfig {
pub:
	id             string
	on_event       ElementCallback = unsafe { nil }
	frame          Rect
	text           string
	placeholder    string
	text_runs      []TextRun
	readonly       bool
	disable_scroll bool
	enabled        bool = true
	autocorrect    bool = true
	keyboard       int
	padding_left   f64 = 12.0
	box            BoxStyle
	text_style     TextStyle
}

// TextArea creates a multiline editor with optional rich text and scrolling.
pub fn text_area(config TextAreaConfig) !Element {
	return Element{
		kind:           .text_area
		id:             config.id
		on_event:       config.on_event
		text:           config.text
		text_runs:      config.text_runs
		placeholder:    config.placeholder
		frame:          config.frame
		box:            config.box
		text_style:     config.text_style
		readonly:       config.readonly
		disable_scroll: config.disable_scroll
		enabled:        config.enabled
		autocorrect:    config.autocorrect
		keyboard:       config.keyboard
		padding_left:   config.padding_left
	}
}

// text_field_content_rect is the immediate renderer's single-line viewport.
// Keep a small vertical inset for the focus border and clamp narrow controls
// rather than passing negative sizes to the graphics backend.
fn text_field_content_rect(frame Rect, padding_left f64) Rect {
	left := if padding_left > 0 { padding_left } else { 0.0 }
	return rect(frame.x + left, frame.y + 2, if frame.width > left + 8 {
		frame.width - left - 8
	} else {
		0.0
	}, if frame.height > 4 { frame.height - 4 } else { 0.0 })
}
