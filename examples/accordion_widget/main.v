module main

import ui2

const accordion_width = 440
const accordion_height = 320

pub struct AccordionDemo {
pub mut:
	section string = 'profile'
}

fn main() {
	mut app := AccordionDemo{}
	ui2.run_compiled_vml[AccordionDemo](
		build:  build_accordion_widget
		model:  &app
		title:  'Accordion'
		width:  accordion_width
		height: accordion_height
	) or { panic(err) }
}

fn build_accordion_widget(mut app AccordionDemo) ui2.Element {
	return $vml('accordion_widget.vml')
}

fn accordion_widget_tree(mut app AccordionDemo, frame ui2.Rect) ui2.Element {
	return $vml('accordion_widget.vml', frame)
}
