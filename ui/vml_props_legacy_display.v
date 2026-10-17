module ui2

// Legacy display controls: ProgressBar and the option-cycling Spinner, until
// the kit's feedback components replace them.

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
