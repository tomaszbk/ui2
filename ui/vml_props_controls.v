module ui2

// Controls: Label, Run, TextInput, TextArea, Image, Button, Checkbox,
// Dropdown, Option, ProgressBar, Slider, Switch, Spinner, MessageBox and
// ToggleButton. Value controls update their own value in apply_event.

// LabelProps shows `text`, or the concatenation of its Run children.
pub struct LabelProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p LabelProps) build(ctx VmlBuildContext) !Element {
	runs := ctx.text_runs(p.style)!
	if runs.len > 0 {
		return vml_handled(rich_label(ctx.id, runs, ctx.frame, TextStyle{}), ctx, p.element_callback())
	}
	return vml_handled(label(ctx.id, p.text.str(), ctx.frame, TextStyle{}), ctx, p.element_callback())
}

// RunProps is one rich-text run of a Label or TextArea.
pub struct RunProps {
pub mut:
	text  DisplayText = ''
	style StylePatch
}

pub fn (p RunProps) vml_custom_renderer() {}

pub fn (p RunProps) part(ctx VmlBuildContext) !VmlPart {
	return VmlRun{
		text:  p.text.str()
		style: p.style
	}
}

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

// ImageProps shows the image at `source` (or its older spelling `path`).
pub struct ImageProps {
	CommonProps
pub mut:
	source ?string
	path   ?string
}

pub fn (p ImageProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(image(ctx.id, p.source or { p.path or { '' } }, ctx.frame), ctx,
		p.element_callback())
}

// ButtonProps is a push button. It may contain element children, and inside a
// MessageBox it is one of the box's actions.
pub struct ButtonProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p ButtonProps) vml_container() {}

pub fn (p ButtonProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(Element{
		...button(ctx.id, p.text.str(), ctx.frame, BoxStyle{}, TextStyle{})
		children: ctx.children
	}, ctx, p.element_callback())
}

pub fn (p ButtonProps) part(ctx VmlBuildContext) !VmlPart {
	return MessageBoxAction{
		id:       ctx.id
		on_event: p.on_click
		title:    p.text.str()
	}
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

// DropdownProps selects `text` among its Option children.
pub struct DropdownProps {
	CommonProps
pub mut:
	text DisplayText = ''
}

pub fn (p DropdownProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(dropdown(ctx.id, p.text.str(), ctx.options().map(it.title), ctx.frame,
		BoxStyle{}, TextStyle{}), ctx, p.element_callback())
}

pub fn (mut p DropdownProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.text = event.text }
}

// OptionProps is one choice of a Dropdown or Spinner.
pub struct OptionProps {
pub mut:
	text DisplayText = ''
}

pub fn (p OptionProps) part(ctx VmlBuildContext) !VmlPart {
	title := p.text.str()
	return MenuEntry{
		id:    title
		title: title
	}
}

// ProgressBarProps styles itself: background, foreground and radius refine
// its track and fill.
pub struct ProgressBarProps {
	CommonProps
pub mut:
	value f64
	max   f64 = 100
}

pub fn (p ProgressBarProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p ProgressBarProps) build(ctx VmlBuildContext) !Element {
	config := ProgressBarConfig{
		id:    ctx.id
		frame: ctx.frame
		value: p.value
		max:   p.max
	}
	styled := if p.style != StylePatch{} { style_progress_bar(config, p.style)! } else { config }
	return vml_handled(progress_bar(styled), ctx, p.element_callback())
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

// SpinnerProps cycles through its Option children.
pub struct SpinnerProps {
	CommonProps
pub mut:
	text            DisplayText = ''
	text_autoupdate bool
}

pub fn (p SpinnerProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p SpinnerProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(spinner(SpinnerConfig{
		id:              ctx.id
		on_event:        p.element_callback()
		frame:           ctx.frame
		text:            p.text.str()
		values:          ctx.options().map(it.title)
		text_autoupdate: p.text_autoupdate
	}), ctx)
}

pub fn (mut p SpinnerProps) apply_event(event ElementEvent) {
	if event.kind == .change { p.text = event.text }
}

// MessageBoxProps is the in-window dialog; its Button children are actions.
// The accessibility fields of the overlay stay empty unless authored.
pub struct MessageBoxProps {
	CommonProps
pub mut:
	title         string
	text          DisplayText = ''
	dialog_width  f64         = 300
	dialog_height f64         = 150
}

pub fn (p MessageBoxProps) vml_structure() VmlStructure {
	return .generated
}

pub fn (p MessageBoxProps) build(ctx VmlBuildContext) !Element {
	return vml_handled(custom_message_box(CustomMessageBoxConfig{
		id:      ctx.id
		frame:   ctx.frame
		title:   p.title
		text:    p.text.str()
		hidden:  p.hidden or { false }
		width:   p.dialog_width
		height:  p.dialog_height
		actions: ctx.message_actions()
	}), ctx, p.element_callback())
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
