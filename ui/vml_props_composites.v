module ui2

// The ScreenManager composite, with the page declarations it reads
// (ManagedScreen/ScreenView). A page declaration is an element carrying its
// record in compiled_metadata, so a parent rebuild sees the same records. Like
// the existing constructors, ScreenManager keeps the root element its
// constructor returns: element events are not attached.

fn vml_managed_screen(ctx VmlBuildContext, name string) Element {
	return Element{
		...vml_keyed(view(ctx.id, ctx.frame, BoxStyle{}, ctx.children), ctx)
		compiled_metadata: &CompiledVmlMetadata{
			screen: ManagedScreen{
				name: name
			}
		}
	}
}

fn vml_managed_screens(children []Element) ![]ManagedScreen {
	mut screens := []ManagedScreen{cap: children.len}
	for child in children {
		metadata := child.compiled_metadata
		if metadata == unsafe { nil } { return error('ScreenManager requires Screen children') }
		record := metadata.screen or { return error('ScreenManager requires Screen children') }
		screens << ManagedScreen{
			...record
			content: child
		}
	}
	return screens
}

// ScreenManagerProps shows the page named `current` (the first when empty).
pub struct ScreenManagerProps {
	CommonProps
pub mut:
	current string
}

pub fn (p ScreenManagerProps) vml_container() {}

pub fn (p ScreenManagerProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p ScreenManagerProps) build(ctx VmlBuildContext) !Element {
	return vml_keyed(screen_manager(ScreenManagerConfig{
		id:      ctx.id
		frame:   ctx.frame
		current: p.current
		screens: vml_managed_screens(ctx.children)!
	})!, ctx)
}

// ManagedScreenProps is a ScreenManager page named `name` (default: its id).
pub struct ManagedScreenProps {
	CommonProps
pub mut:
	name ?string
}

pub fn (p ManagedScreenProps) vml_container() {}

pub fn (p ManagedScreenProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p ManagedScreenProps) build(ctx VmlBuildContext) !Element {
	return vml_managed_screen(ctx, p.name or { ctx.id })
}

pub fn (p ManagedScreenProps) part(ctx VmlBuildContext) !VmlPart {
	return ManagedScreen{
		name: p.name or { ctx.id }
	}
}

// ScreenViewProps is the same page declaration as ManagedScreen.
pub struct ScreenViewProps {
	CommonProps
pub mut:
	name ?string
}

pub fn (p ScreenViewProps) vml_container() {}

pub fn (p ScreenViewProps) vml_structure() VmlStructure {
	return .sourced
}

pub fn (p ScreenViewProps) build(ctx VmlBuildContext) !Element {
	return vml_managed_screen(ctx, p.name or { ctx.id })
}

pub fn (p ScreenViewProps) part(ctx VmlBuildContext) !VmlPart {
	return ManagedScreen{
		name: p.name or { ctx.id }
	}
}
