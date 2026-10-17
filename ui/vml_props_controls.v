module ui2

// Text and images: Label, Run and Image. The kit's controls are in kit_*.v;
// the controls it replaces are in vml_props_legacy_*.v.

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
