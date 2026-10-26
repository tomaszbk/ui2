// vtest vflags: -d vml_interpreter -d ui2_headless
// vtest build: vml_conformance?
module main

// vml: styles.vml
// vml: styles_local.vml
// vml: styles_custom_tokens.vml
// vml: motion.vml

import ui2

// Conformance of the interpreter with compiled VML (ui2.vml_conformance) for
// typed styles, theme tokens, local styles and motion: styles.vml,
// styles_local.vml, styles_custom_tokens.vml and motion.vml.

pub struct StylesContractApp {
pub mut:
	emphasized bool           = true
	patch      ui2.StylePatch = ui2.style_radius(3)
	progress   f64            = 0.25
	choice     string         = 'One'
	alpha      f64            = 0.8
	offset     f64            = 4
	hidden     bool
	config     ui2.MotionConfig = ui2.MotionConfig{
		reduced_motion: true
	}
}

fn styles_tree(mut app StylesContractApp, frame ui2.Rect) ui2.Element {
	return styles_vml_framed(mut app, frame)
}

fn local_styles_tree(mut app StylesContractApp, frame ui2.Rect) ui2.Element {
	return styles_local_vml_framed(mut app, frame)
}

fn custom_tokens_tree(mut app StylesContractApp, frame ui2.Rect) ui2.Element {
	return styles_custom_tokens_vml_framed(frame)
}

fn motion_tree(mut app StylesContractApp, frame ui2.Rect) ui2.Element {
	return motion_vml_framed(mut app, frame)
}

fn styles_reset(mut app StylesContractApp) {
	app = StylesContractApp{}
}

fn styles_check(file string, compiled fn (mut StylesContractApp, ui2.Rect) ui2.Element, theme ?ui2.Theme) {
	mut app := StylesContractApp{}
	report := ui2.vml_conformance[StylesContractApp](
		path:     @DIR + '/' + file
		frame:    ui2.rect(0, 0, 300, 240)
		model:    &app
		reset:    styles_reset
		compiled: compiled
		theme:    theme
	) or { panic(err) }
	println(report)
	assert report.equal(), report.str()
}

fn test_styles_interpreted_vml_matches_compiled() {
	styles_check('styles.vml', styles_tree, none)
}

fn test_local_styles_interpreted_vml_matches_compiled() {
	styles_check('styles_local.vml', local_styles_tree, ui2.Theme{
		colors: {
			'surface': u32(0x223344)
		}
	})
}

fn test_custom_tokens_interpreted_vml_matches_compiled() {
	styles_check('styles_custom_tokens.vml', custom_tokens_tree, ui2.Theme{
		colors:     {
			'brand': u32(0x445566)
		}
		spacing:    {
			'gutter': f64(7)
		}
		radii:      {
			'card': f64(5)
		}
		font_sizes: {
			'brand': f64(19)
		}
	})
}

fn test_motion_interpreted_vml_matches_compiled() {
	styles_check('motion.vml', motion_tree, none)
}
