// ui2 is the command line tool of the ui2 library. It generates the V builders
// of VML documents and runs or builds programs after generating them.
//
//   ui2 gen [paths...]          generate the builders the V files under paths declare
//   ui2 run <dir> [v flags] [-- args]   generate, build and run
//   ui2 build <dir> [v flags]           generate, then build with `v`
//
// run and build print V's diagnostics in VML documents in VML terms:
// `element \`Slider\` has no property named \`maxx\`` rather than the props type
// and field the generated builder uses.
//
// A V file declares each document it builds with a directive comment:
//
//   // vml: app.vml
//   // vml: fixtures/row.vml as fixture_row
//
// The path is relative to the V file. The builder, `<name>_vml`, is written to
// `<name>_vml.v` in that V file's directory and module. A document used by a
// test of a library module is written to `<name>_vml_d_vml_fixtures.v`, which
// V compiles only with `-d vml_fixtures`, so test fixtures never reach the
// library.
module main

import os
import ui2.vml

const usage = 'usage: ui2 gen [paths...] | ui2 run <dir> [v flags] | ui2 build <dir> [v flags]'

fn main() {
	if os.args.len < 2 {
		eprintln(usage)
		exit(1)
	}
	command := os.args[1]
	rest := os.args[2..]
	match command {
		'gen' {
			paths := if rest.len > 0 { rest } else { ['.'] }
			count := generate_paths(paths) or {
				eprintln('ui2 gen: ${err}')
				exit(1)
			}
			println('ui2 gen: ${count} builder(s) up to date')
		}
		'run', 'build' {
			if rest.len == 0 {
				eprintln(usage)
				exit(1)
			}
			target := rest[0]
			generate_paths([target]) or {
				eprintln('ui2 gen: ${err}')
				exit(1)
			}
			mut flags := rest[1..].clone()
			if command == 'build' {
				exit(compile(flags, target))
			}
			// `ui2 run <dir> [v flags] [-- program arguments]`
			mut program_args := []string{}
			separator := flags.index('--')
			if separator >= 0 {
				program_args = flags[separator + 1..].clone()
				flags = flags[..separator].clone()
			}
			binary := os.join_path(os.vtmp_dir(), 'ui2-run-${os.getpid()}', os.file_name(os.real_path(target)))
			os.mkdir_all(os.dir(binary)) or {}
			flags << ['-o', binary]
			code := compile(flags, target)
			if code != 0 {
				exit(code)
			}
			mut program := os.new_process(binary)
			program.set_args(program_args)
			program.run()
			program.wait()
			os.rmdir_all(os.dir(binary)) or {}
			exit(program.code)
		}
		'-h', '--help', 'help' {
			println(usage)
		}
		else {
			eprintln(usage)
			exit(1)
		}
	}
}

// compile runs the V compiler that runs this tool, so both use one toolchain,
// and prints its output with diagnostics in VML documents worded in VML terms.
fn compile(flags []string, target string) int {
	vexe := os.getenv_opt('VEXE') or { @VEXE }
	mut process := os.new_process(vexe)
	mut args := flags.clone()
	args << target
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp() + process.stderr_slurp()
	process.wait()
	if output.len > 0 {
		println(rewrite_vml_diagnostics(output))
	}
	return process.code
}

// Directive is one `// vml:` declaration of a V file.
struct Directive {
	source   string // the .vml file
	name     string // the builder name, without `_vml`
	dir      string // the directory of the declaring V file
	module   string // its module
	fixtures bool   // declared by a test of a library module
}

// generate_paths generates the builders declared under paths and returns how
// many are up to date. A builder is rewritten only when its text changes, so
// unchanged builders keep their modification time and V's caches.
fn generate_paths(paths []string) !int {
	mut directives := map[string]Directive{}
	for path in paths {
		for file in v_files(path)! {
			for directive in file_directives(file)! {
				key := os.join_path(directive.dir, output_name(directive))
				if existing := directives[key] {
					if os.real_path(existing.source) != os.real_path(directive.source) {
						return error('${key}: `${directive.name}` names both ${existing.source} and ${directive.source}; use `as <name>`')
					}
					continue
				}
				directives[key] = directive
			}
		}
	}
	for output, directive in directives {
		code := vml.generate_file(directive.source,
			module: directive.module
			name:   directive.name
			dir:    directive.dir
		)!
		current := os.read_file(output) or { '' }
		if current != code {
			os.write_file(output, code)!
		}
	}
	return directives.len
}

fn output_name(directive Directive) string {
	return if directive.fixtures {
		'${directive.name}_vml_d_vml_fixtures.v'
	} else {
		'${directive.name}_vml.v'
	}
}

// v_files lists the V files under path (or path itself), skipping generated
// builders and directories that hold no sources of ours.
fn v_files(path string) ![]string {
	if os.is_file(path) {
		return if path.ends_with('.v') { [path] } else { []string{} }
	}
	if !os.is_dir(path) {
		return error('`${path}` does not exist')
	}
	mut files := []string{}
	for entry in os.ls(path)! {
		if entry.starts_with('.') || entry in ['thirdparty', 'third_party', 'node_modules'] {
			continue
		}
		full := os.join_path(path, entry)
		if os.is_dir(full) {
			files << v_files(full)!
		} else if entry.ends_with('.v') && !is_generated(entry) {
			files << full
		}
	}
	return files
}

fn is_generated(name string) bool {
	return name.ends_with('_vml.v') || name.ends_with('_vml_d_vml_fixtures.v')
}

// file_directives reads the `// vml:` directives of a V file.
fn file_directives(file string) ![]Directive {
	text := os.read_file(file)!
	if !text.contains('// vml:') {
		return []Directive{}
	}
	dir := os.dir(file)
	module := file_module(text)
	fixtures := file.ends_with('_test.v') && module != 'main'
	mut out := []Directive{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('// vml:') {
			continue
		}
		spec := line.all_after('// vml:').trim_space()
		relative := spec.all_before(' as ').trim_space()
		if !relative.ends_with('.vml') {
			return error('${file}: `// vml:` names a .vml file, not `${relative}`')
		}
		source := os.real_path(os.join_path(dir, relative))
		if !os.is_file(source) {
			return error('${file}: ${source} does not exist')
		}
		name := if spec.contains(' as ') {
			spec.all_after(' as ').trim_space()
		} else {
			vml.builder_base_name(source)
		}
		out << Directive{
			source:   source
			name:     name
			dir:      dir
			module:   module
			fixtures: fixtures
		}
	}
	return out
}

fn file_module(text string) string {
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('module ') {
			return line.all_after('module ').trim_space()
		}
	}
	return 'main'
}
