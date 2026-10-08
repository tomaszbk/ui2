module main

import ui2

fn test_signals_demo_observes_one_result_per_batch_and_keeps_edit_declaration() ! {
	mut demo := new_demo()!
	assert demo.last_total == 14 && demo.observations == 1
	before := demo.build()
	demo.change('batch')!
	assert demo.last_total == 23 && demo.observations == 2
	demo.change('toggle')!
	assert demo.last_total == 8 && demo.observations == 3
	demo.bonus.set(99)!
	assert demo.last_total == 8 && demo.observations == 3
	after := demo.build()
	ui2.validate_element_tree(after)!
	assert before.children.last().id == after.children.last().id
	assert before.children.last().text == after.children.last().text
	assert after.children.last().text == 'Español: niño, acción'
	demo.runtime.dispose()!
	assert demo.runtime.stats() == ui2.SignalStats{}
}
