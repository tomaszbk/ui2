module main

import ui2

fn measure_interpreted(mut app Calculator, frame ui2.Rect, iterations int) {
	eprintln('the interpreted mode requires -d vml_interpreter')
	exit(1)
}
