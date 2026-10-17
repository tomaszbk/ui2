// vtest vflags: -d ui2_custom_rendering
module main

import os

fn test_compiled_visual_dynamic_types_and_inactive_arms_report_vml_locations() {
	root := os.join_path(os.real_path(os.vtmp_dir()), 'vml_visual_types_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	module_path := [os.dir(@VMODROOT), '@vlib', '@vmodules'].join(os.path_delimiter)
	os.write_file(source, 'import ui2\nstruct Wrong { weight string align string count int flag bool color f64 }
	fn build(mut app Wrong) ui2.Element { return $vml("view.vml") }
	fn main() { mut app := Wrong{}; _ = build(mut app) }')!
	for entry in [
		['Label(\n    style: [weight(app.weight)],\n)', '2:5'],
		['component Typed(valid bool = app.count) { Label(text: "value") }', '1:17'],
		['component Typed(caption string = app.count) { Label(text: caption) }', '1:17'],
		['component Typed(ratio f32 = app.flag) { Label(text: ratio) }', '1:17'],
		['Label(\n    width: app.flag\n)', '2:5'],
		['Label(\n    style: [font_size(app.count > 0)],\n)', '2:5'],
		['Label(\n    style: [foreground(app.flag)],\n)', '2:5'],
		['Grid(\n    columns: app.color\n)', '2:5'],
		['Label(\n    style: [font_size(true ? 18 : app.flag)],\n)', '2:5'],
		['Label(\n    style: [weight(app.flag)],\n)', '2:5'],
		['Label(\n    style: [weight(app.color)],\n)', '2:5'],
		['Label(\n    style: [weight(app.count > 0)],\n)', '2:5'],
		['Label(\n    style: [foreground(app.color)],\n)', '2:5'],
		['Label(\n    style: [text_align(app.align)],\n)', '2:5'],
		['Label(\n    text: app.flag\n)', '2:5'],
		['Label(\n    text: app.flag && app.flag\n)', '2:5'],
		['Label(\n    text: app.count > 0\n)', '2:5'],
		['Label(\n    text: !app.flag\n)', '2:5'],
		['Label(\n    text: app.count ? "yes" : "no"\n)', '2:5'],
		['Label(\n    style: [weight(true ? 400 : app.weight)],\n)', '2:5'],
		['Label(\n    text: true ? "valid" : app.flag\n)', '2:5'],
		['Label(\n    style: [italic(false ? app.count : true)],\n)', '2:5'],
		['Label() {
    Run(
        style: [weight(true ? 400 : app.weight)],
    )
}', '3:9'],
		['Label() {
    Run(
        style: [weight(app.weight)],
    )
}', '3:9'],
		['Label() {
    Run(
        text: app.flag
    )
}', '3:9'],
	] {
		os.write_file(view, entry[0])!
		result := os.exec([@VEXE, '-b', 'c', '-path', module_path, '-d', 'ui2_custom_rendering',
			'-check', source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:${entry[1]}:'), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}
