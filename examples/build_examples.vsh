#!/usr/bin/env -S v

// Compiles every example under examples/ and reports all failures at once.
// Extra arguments are passed through to the compiler, e.g.
//   v -b c run examples/build_examples.vsh -d ui2_custom_rendering

import os
import rand

const vexe = @VEXE

fn println_one_of_many(msg string, entry_idx int, entries_len int) {
	eprintln('${entry_idx + 1:2}/${entries_len:-2} ${msg}')
}

println('v executable: ${vexe}')
print('v version: ${os.exec([vexe, 'version']).output}')

extra_flags := os.args[1..]
custom_profile := os.args.any(it in ['ui2_custom_rendering', '-d=ui2_custom_rendering', 'ui2_headless',
	'-d=ui2_headless'] || it.ends_with(':ui2_custom_rendering') || it.ends_with(':ui2_headless'))
mut skipped := 0

examples_dir := join_path(@VMODROOT, 'examples')

build_dir := join_path(temp_dir(), 'ui2-examples-build-${rand.ulid()}')

mkdir(build_dir)!

defer {
	rmdir_all(build_dir) or {}
}

mut entries := []string{}

for entry in ls(examples_dir)! {
	example_dir := join_path(examples_dir, entry)
	if !is_dir(example_dir) {
		continue
	}
	if !exists(join_path(example_dir, 'main.v')) {
		eprintln('skipping ${example_dir}, it has no main.v')
		continue
	}
	// Profile declarations only exclude presentation features native controls
	// explicitly reject. Every selected example still compiles with -W.
	profile := read_lines(join_path(example_dir, 'main.v'))!.filter(it.starts_with('// ui2 profiles:'))
	if !custom_profile && profile.any(it.starts_with('// ui2 profiles: custom')) {
		println('skipping ${entry} in native profile: ${profile[0].all_after('// ui2 profiles: ')}')
		skipped++
		continue
	}
	entries << example_dir
}

entries.sort()

if entries.len == 0 {
	eprintln('no examples found in ${examples_dir}')
	exit(1)
}

mut failures := []string{}

for entry_idx, entry in entries {
	out := join_path(build_dir, file_name(entry) + $if windows { '.exe' } $else { '' })
	// Reject warnings; compiler notices also cover pre-existing unused private
	// helpers shared across backends and are not compilation failures.
	mut argv := [vexe, '-b', 'c', '-W']
	argv << extra_flags
	argv << ['-o', out, entry]
	cmd := argv.map(quoted_path(it)).join(' ')
	println_one_of_many('compile with: ${cmd}', entry_idx, entries.len)
	ret := os.exec(argv)
	if ret.exit_code != 0 {
		failures << cmd
		eprintln('>>> FAILURE')
		eprintln('----------------------------------------------------------------------------------')
		eprintln(ret.output)
		eprintln('----------------------------------------------------------------------------------')
	}
}

if failures.len > 0 {
	for failure in failures {
		eprintln('> failed compilation cmd: ${failure}')
	}
	err_count := if failures.len == 1 { '1 error' } else { '${failures.len} errors' }
	eprintln('\nFailed with ${err_count}.')
	exit(1)
}

println('\nAll ${entries.len} compatible examples compiled successfully; ${skipped} custom-profile examples skipped.')
