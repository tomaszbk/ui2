module ui2

// Legacy value controls: TextInput, TextArea, Checkbox, Slider, Switch and
// ToggleButton, until the kit's actions replace them. Each updates its own
// value in apply_event.

// TextInputProps is a single-line editor; `password` also makes it secure.
pub struct TextInputProps {
	CommonProps
pub mut:
	text        DisplayText = ''
	placeholder string
	password    bool
	readonly    bool
	keyboard    TextKeyboard
}

pub fn (p TextInputProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(text_input(TextInputConfig{
		id:          ctx.id
		on_event:    p.element_callback()
		frame:       ctx.frame
		text:        p.text.str()
		placeholder: p.placeholder
		password:    p.password
		readonly:    p.readonly
		enabled:     p.enabled or { true }
		autocorrect: p.autocorrect or { true }
		keyboard:    int(p.keyboard)
	})!, ctx)
}

pub fn (p TextInputProps) project(el Element, ctx VmlBuildContext) !Element {
	projected := p.CommonProps.project_common(el, ctx)
	return Element{
		...projected
		secure: projected.secure || p.password
	}
}

pub fn (mut p TextInputProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.text = event.text }
}

// TextAreaProps is a multiline editor; Run children give it rich text.
pub struct TextAreaProps {
	CommonProps
pub mut:
	text           DisplayText = ''
	placeholder    string
	readonly       bool
	disable_scroll bool
	keyboard       TextKeyboard
}

pub fn (p TextAreaProps) build(ctx VmlBuildContext) !Element {
	runs := ctx.text_runs(p.style)!
	return vml_keyed(text_area(TextAreaConfig{
		id:             ctx.id
		on_event:       p.element_callback()
		frame:          ctx.frame
		text:           if runs.len > 0 { text_runs_content(runs) } else { p.text.str() }
		text_runs:      runs
		placeholder:    p.placeholder
		readonly:       p.readonly
		disable_scroll: p.disable_scroll
		enabled:        p.enabled or { true }
		autocorrect:    p.autocorrect or { true }
		keyboard:       int(p.keyboard)
	})!, ctx)
}

pub fn (mut p TextAreaProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.text = event.text }
}

pub struct CheckboxProps {
	CommonProps
pub mut:
	text    DisplayText = ''
	checked bool
}

pub fn (p CheckboxProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(checkbox(ctx.id, p.text.str(), p.checked, ctx.frame, TextStyle{}), ctx,
		p.element_callback())
}

pub fn (mut p CheckboxProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.checked = event.checked }
}

pub struct SliderProps {
	CommonProps
pub mut:
	value             f64
	min               f64
	max               f64 = 100
	step              f64
	orientation       Orientation
	track_inset       f64 = 16
	value_track       bool
	value_track_color u32 = 0x93c5fd
	thumb_color       u32 = 0x2563eb
	track_width       f64 = 4
	thumb_size        f64 = 20
}

pub fn (p SliderProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(slider(SliderConfig{
		id:          ctx.id
		on_event:    p.element_callback()
		frame:       ctx.frame
		min:         p.min
		max:         p.max
		value:       p.value
		step:        p.step
		orientation: p.orientation
		padding:     p.track_inset
		value_track: p.value_track
		style:       SliderStyle{
			value_track_color: p.value_track_color
			thumb_color:       p.thumb_color
			track_width:       p.track_width
			thumb_size:        p.thumb_size
		}
	}), ctx)
}

pub fn (mut p SliderProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.value = event.value }
}

// SwitchProps runs on_active before on_change for the same change.
pub struct SwitchProps {
	CommonProps
pub mut:
	active               bool
	inactive_color       u32             = 0xcbd5e1
	active_color         u32             = 0x22c55e
	thumb_color          u32             = 0xffffff
	disabled_track_color u32             = 0xe2e8f0
	disabled_thumb_color u32             = 0xf8fafc
	on_active            ElementCallback = unsafe { nil }
}

pub fn (p SwitchProps) build(ctx VmlBuildContext) !Element {
	handlers := p.event_handlers()
	return vml_keyed(switch_control(SwitchConfig{
		id:       ctx.id
		on_event: VmlEventHandlers{
			...handlers
			on_active: p.on_active
		}.callback()
		frame:    ctx.frame
		active:   p.active
		style:    SwitchStyle{
			inactive_track_color: p.inactive_color
			active_track_color:   p.active_color
			thumb_color:          p.thumb_color
			disabled_track_color: p.disabled_track_color
			disabled_thumb_color: p.disabled_thumb_color
		}
	}), ctx)
}

pub fn (mut p SwitchProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.active = event.checked }
}

// ToggleButtonProps keeps a pressed state; buttons sharing a group are
// exclusive. The pressed face uses down_* and the authored typography.
pub struct ToggleButtonProps {
	CommonProps
pub mut:
	text               DisplayText = ''
	pressed            bool
	group              string
	allow_no_selection bool = true
	down_background    u32  = 0x2563eb
	down_color         u32  = 0xffffff
	down_corner_radius f64  = 6
}

pub fn (p ToggleButtonProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p ToggleButtonProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(toggle_button(ToggleButtonConfig{
		id:                 ctx.id
		frame:              ctx.frame
		on_event:           p.element_callback()
		title:              p.text.str()
		pressed:            p.pressed
		group:              p.group
		allow_no_selection: p.allow_no_selection
		down_box:           BoxStyle{
			bg:     p.down_background
			radius: p.down_corner_radius
		}
		text_style:         TextStyle{}
		down_text_style:    TextStyle{
			...apply_text_style(TextStyle{}, p.style)!
			color: p.down_color
		}
		native_style:       p.native or { false }
	}), ctx)
}

pub fn (mut p ToggleButtonProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.pressed = event.checked }
}
