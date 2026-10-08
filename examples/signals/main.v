module main

import ui2

// Business state is explicit V code. The effect is the current integration
// seam: request the existing UI rebuild after a coherent transaction.
@[heap]
struct SignalsDemo {
mut:
	runtime      &ui2.SignalRuntime
	count        &ui2.Signal[int]
	bonus        &ui2.Signal[int]
	use_bonus    &ui2.Signal[bool]
	total        &ui2.Memo[int]
	observations int
	last_total   int
}

fn new_demo() !&SignalsDemo {
	mut runtime := ui2.new_signal_runtime()
	mut scope := runtime.scope()!
	mut count := ui2.new_signal(mut scope, 2, name: 'count')!
	mut bonus := ui2.new_signal(mut scope, 10, name: 'bonus')!
	mut use_bonus := ui2.new_signal(mut scope, true, name: 'use bonus')!
	mut total := ui2.new_memo(mut scope, fn [mut count, mut bonus, mut use_bonus] () !int {
		return count.get()! * 2 + if use_bonus.get()! { bonus.get()! } else { 0 }
	},
		name: 'total'
	)!
	mut demo := &SignalsDemo{
		runtime:   runtime
		count:     count
		bonus:     bonus
		use_bonus: use_bonus
		total:     total
	}
	scope.effect('observe total', fn [mut demo] () ! {
		demo.last_total = demo.total.get()!
		demo.observations++
		ui2.request_refresh()
	})!
	return demo
}

fn (mut demo SignalsDemo) change(action string) ! {
	demo.runtime.batch(fn [mut demo, action] () ! {
		match action {
			'increment' { demo.count.set(demo.count.peek()! + 1)! }
			'batch' {
				demo.count.set(demo.count.peek()! + 1)!
				demo.count.set(demo.count.peek()! + 1)!
				demo.bonus.set(demo.bonus.peek()! + 5)!
				// A dirty memo read here already sees all three committed writes.
				assert demo.total.get()! == demo.count.peek()! * 2 + if demo.use_bonus.peek()! {
					demo.bonus.peek()!
				} else {
					0
				}
			}
			'toggle' { demo.use_bonus.set(!demo.use_bonus.peek()!)! }
			else { return error('unknown action: ${action}') }
		}
	})!
	ui2.request_refresh()
}

fn (mut demo SignalsDemo) build() ui2.Element {
	style := ui2.TextStyle{ color: 0x243449, size: 17 }
	mut children := [
		ui2.label('title', 'Signals: lazy memo + batch', ui2.rect(24, 20, 580, 42), ui2.TextStyle{ size: 25, weight: 700 }),
		ui2.label('inputs', 'Count ${demo.count.peek() or { panic(err) }} / bonus ${demo.bonus.peek() or { panic(err) }}', ui2.rect(24, 72, 580, 34), style),
		ui2.label('total', 'Total = ${demo.last_total}', ui2.rect(24, 112, 580, 42), ui2.TextStyle{ size: 28, color: 0x176d55 }),
		ui2.label('observations', 'Effect observations: ${demo.observations}', ui2.rect(24, 160, 580, 32), style),
	]
	for index, action in ['increment', 'batch', 'toggle'] {
		caption := ['Count +1', 'Batch: +2 / +5', 'Toggle bonus'][index]
		children << ui2.with_event(ui2.button(action, caption,
			ui2.rect(24 + index * 194, 208, 180, 42), ui2.BoxStyle{ bg: 0xdbe9e4, radius: 6 }, style),
			fn [mut demo, action] (event ui2.ElementEvent) {
				if event.kind == .tap { demo.change(action) or { eprintln(err) } }
			})
	}
	children << ui2.label('branch', 'Bonus subscription: ${if demo.use_bonus.peek() or { panic(err) } {
		'active'
	} else {
		'removed'
	}}', ui2.rect(24, 266, 580, 32), style)
	children << ui2.label('edit hint', 'Edit here; state changes preserve the same declared text:', ui2.rect(24, 310, 580, 26), ui2.TextStyle{ size: 14 })
	children << ui2.text_input(
		id:    'notes'
		text:  'Español: niño, acción'
		frame: ui2.rect(24, 346, 580, 38)
	) or { panic(err) }
	return ui2.view('root', ui2.rect(0, 0, 640, 410), ui2.BoxStyle{ bg: 0xf4f7f6 }, children)
}

fn main() {
	mut demo := new_demo() or { panic(err) }
	defer { demo.runtime.dispose() or { eprintln(err) } }
	ui2.run_window('Signals core', 640, 410, fn [mut demo] () ui2.Element { return demo.build() })
}
