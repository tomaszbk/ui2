// Times compiled VML build/dispose and typed tree builders that measure intrinsic Flex/Grid sizes:
// the responsive example, a flat wrapping Flex, and nested Flex containers.
// From the repository root:
//   v -prod -path "$(dirname "$PWD")|@vlib|@vmodules" -o /tmp/ui2-flex-bench benchmarks/flex_measure/main.v
//   /tmp/ui2-flex-bench [name-filter]
module main

import os
import time
import ui2

const runs = 7

pub struct Project {
pub:
	id          int
	title       string
	description string
}

pub struct BenchApp {
pub mut:
	created  int
	projects []Project
}

pub fn (mut app BenchApp) create_project() {
	app.created++
}

enum CaseKind {
	responsive
	flat
	nested
}

struct Case {
	name  string
	kind  CaseKind
	frame ui2.Rect
	depth int
}

fn responsive(mut app BenchApp, frame ui2.Rect) ui2.Element {
	return $vml('../../examples/responsive_layout/responsive_layout.vml', frame)
}

fn nested(depth int, frame ui2.Rect) ui2.Element {
	mut child := ui2.label('', 'content that can wrap at a narrow width', ui2.Rect{},
		ui2.TextStyle{ lines: 3 })
	for level in 0 .. depth {
		child = ui2.flex(ui2.FlexConfig{
			frame:       frame
			orientation: if level % 2 == 0 { .horizontal } else { .vertical }
			gap:         4
			children:    [
				ui2.FlexChild{ element: ui2.label('', 'level ${level}', ui2.Rect{}, ui2.TextStyle{}) },
				ui2.FlexChild{ element: child },
			]
		}) or { panic(err) }
	}
	return ui2.screen(0xffffff, [child])
}

fn flat(count int, frame ui2.Rect) ui2.Element {
	mut labels := []ui2.FlexChild{cap: count}
	for index in 0 .. count {
		labels << ui2.FlexChild{ element: ui2.label('', 'item ${index}', ui2.Rect{}, ui2.TextStyle{}) }
	}
	return ui2.screen(0xffffff, [ui2.flex(ui2.FlexConfig{
		frame:    frame
		wrap:     true
		gap:      6
		children: labels
	}) or { panic(err) }])
}

fn model() BenchApp {
	mut projects := []Project{cap: 12}
	for id in 1 .. 13 {
		projects << Project{
			id:          id
			title:       'Project ${id}'
			description: 'A description that is long enough to wrap in narrow cards'
		}
	}
	return BenchApp{
		projects: projects
	}
}

fn build(case Case, mut app BenchApp) int {
	root := match case.kind {
		.responsive { responsive(mut app, case.frame) }
		.flat { flat(200, case.frame) }
		.nested { nested(case.depth, case.frame) }
	}
	checksum := root.children.len
	if root.compiled_node != unsafe { nil } {
		root.compiled_node.dispose_document() or { panic(err) }
	}
	return checksum
}

fn median(values []f64) f64 {
	mut sorted := values.clone()
	sorted.sort(a < b)
	return sorted[sorted.len / 2]
}

fn main() {
	wide := ui2.rect(0, 0, 1000, 780)
	compact := ui2.rect(0, 0, 390, 780)
	cases := [
		Case{ name: 'responsive wide (compiled)', kind: .responsive, frame: wide },
		Case{ name: 'responsive compact (compiled)', kind: .responsive, frame: compact },
		Case{ name: 'flat wrap 200 (typed)', kind: .flat, frame: wide },
		Case{ name: 'nested 4 (typed)', kind: .nested, frame: wide, depth: 4 },
		Case{ name: 'nested 8 (typed)', kind: .nested, frame: wide, depth: 8 },
		Case{ name: 'nested 10 (typed)', kind: .nested, frame: wide, depth: 10 },
	]
	filter := if os.args.len > 1 { os.args[1] } else { '' }
	mut checksum := 0
	for case in cases {
		if filter.len > 0 && !case.name.contains(filter) {
			continue
		}
		mut app := model()
		checksum += build(case, mut app) // warm fonts and caches outside timing
		mut iterations := 1
		for {
			mut watch := time.new_stopwatch()
			for _ in 0 .. iterations {
				checksum += build(case, mut app)
			}
			if watch.elapsed().milliseconds() >= 100 || iterations >= 100_000 {
				break
			}
			iterations *= 2
		}
		mut samples := []f64{cap: runs}
		for _ in 0 .. runs {
			mut watch := time.new_stopwatch()
			for _ in 0 .. iterations {
				checksum += build(case, mut app)
			}
			samples << f64(watch.elapsed().microseconds()) / f64(iterations)
		}
		println('${case.name:-28} ${median(samples):12.1f} us/build')
	}
	println('checksum ${checksum}')
}
