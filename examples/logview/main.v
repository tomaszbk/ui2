module main

import ui2

const logview_width = 640
const logview_height = 420

pub struct LogviewDemo {
pub mut:
	log       string
	next_task int    = 1
	status    string = 'Ready to scan.'
}

pub fn (mut app LogviewDemo) start_scan() {
	mut entries := []string{cap: 8}
	for _ in 0 .. 8 {
		entries << 'processing ... task ${app.next_task} complete'
		app.next_task++
	}
	separator := if app.log.len == 0 { '' } else { '\n' }
	app.log += separator + entries.join('\n')
	app.status = '${app.next_task - 1} tasks complete'
}

pub fn (mut app LogviewDemo) clear() {
	app.log = ''
	app.next_task = 1
	app.status = 'Log cleared.'
}

fn main() {
	mut app := LogviewDemo{}
	ui2.run_compiled_vml[LogviewDemo](
		build:  build_logview
		model:  &app
		title:  'Log View'
		width:  logview_width
		height: logview_height
	) or { panic(err) }
}

fn build_logview(mut app LogviewDemo) ui2.Element {
	return $vml('logview.vml')
}

fn logview_tree(mut app LogviewDemo, frame ui2.Rect) ui2.Element {
	return $vml('logview.vml', frame)
}
