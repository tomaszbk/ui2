module main

import ui2

const accordion_width = 620
const accordion_height = 460

pub struct AccordionSection {
pub:
	id          int
	title       string
	description string
	detail      string
	color       u32
}

pub struct AccordionDemo {
pub:
	sections []AccordionSection
pub mut:
	open_id int    = 1
	status  string = 'Rectangle is open.'
}

fn initial_accordion() AccordionDemo {
	return AccordionDemo{
		sections: [
			AccordionSection{ id: 1, title: 'Rectangle', description: 'A responsive colored surface.', detail: 'The original page contains a simple red rectangle.', color: u32(0xfee2e2) },
			AccordionSection{ id: 2, title: 'Radio', description: 'A compact exclusive-choice group.', detail: 'This port uses ui2 portable selection controls.', color: u32(0xdcfce7) },
			AccordionSection{ id: 3, title: 'Slider', description: 'A compact value-control overview.', detail: 'The source accordion includes horizontal and vertical sliders.', color: u32(0xdbeafe) },
			AccordionSection{ id: 4, title: 'Group', description: 'Related controls presented together.', detail: 'See the dedicated group example for editable fields.', color: u32(0xf3e8ff) },
			AccordionSection{ id: 5, title: 'Dropdown', description: 'Choose one item from a menu.', detail: 'See the dedicated dropdown example for live feedback.', color: u32(0xfef3c7) },
		]
	}
}

pub fn (mut app AccordionDemo) toggle_section(id int) {
	if app.open_id == id {
		app.open_id = -1
		app.status = 'All sections are collapsed.'
		return
	}
	for section in app.sections {
		if section.id == id {
			app.open_id = id
			app.status = '${section.title} is open.'
			return
		}
	}
}

fn main() {
	mut app := initial_accordion()
	ui2.run_compiled_vml[AccordionDemo](
		build:  build_accordion
		model:  &app
		title:  'Accordion'
		width:  accordion_width
		height: accordion_height
	) or { panic(err) }
}

fn build_accordion(mut app AccordionDemo) ui2.Element {
	return $vml('accordion.vml')
}

fn accordion_tree(mut app AccordionDemo, frame ui2.Rect) ui2.Element {
	return $vml('accordion.vml', frame)
}
