#!/usr/bin/env -S v

// v run c/build.vsh [library|example|test|smoke] [V compiler flags...]
import os

const root = @VMODROOT
const build_dir = os.join_path(root, 'build', 'c')

fn checked_execute(command []string) {
	result := os.exec(command)
	if result.exit_code != 0 {
		eprintln(result.output)
		exit(1)
	}
	if result.output.len > 0 { print(result.output) }
}

mode := if args.len > 1 { args[1] } else { 'library' }
if mode !in ['library', 'example', 'test', 'smoke'] {
	eprintln('usage: v run c/build.vsh [library|example|test|smoke] [V compiler flags...]')
	exit(1)
}
os.mkdir_all(build_dir)!
cc := os.getenv_opt('CC') or {
	$if windows {
		'clang'
	} $else {
		'cc'
	}
}
library_name := $if macos { 'libui2.dylib' } $else $if windows { 'ui2.dll' } $else { 'libui2.so' }
library := os.join_path(build_dir, library_name)
module_path := os.dir(root) + '|@vlib|@vmodules'
mut command := [@VEXE, '-b', 'c', '-enable-globals', '-cc', cc, '-gc', 'boehm', '-shared']
command << args#[2..]
$if linux {
	command << ['-cflags', '-Wl,-soname,libui2.so']
}
command << ['-path', module_path, '-o', library, os.join_path(root, 'c')]
checked_execute(command)
$if macos {
	// Give the library a relocatable install name that ordinary C
	// executables can resolve through rpath.
	checked_execute(['install_name_tool', '-id', '@rpath/libui2.dylib', library])
}
println('Built ${library}')
if mode == 'library' { exit(0) }

mut link_library := library
mut runtime_flags := []string{}
$if windows {
	// LLVM's import library lets a normal C compiler link to V's DLL. The
	// export list comes from the bridge, avoiding a separately maintained list.
	mut exports := ['LIBRARY ui2.dll', 'EXPORTS']
	for line in os.read_lines(os.join_path(root, 'c', 'api.v'))! {
		if line.starts_with("@[export: '") { exports << line.all_after("'").all_before("'") }
	}
	def_path := os.join_path(build_dir, 'ui2.def')
	os.write_file(def_path, exports.join('\n') + '\n')!
	link_library = os.join_path(build_dir, 'ui2.lib')
	checked_execute(['llvm-dlltool', '-m', 'i386:x86-64', '-d', def_path, '-l', link_library])
} $else {
	runtime_flags << '-Wl,-rpath,${build_dir}'
}
source := if mode == 'test' {
	os.join_path(root, 'c', 'tests', 'api_test.c')
} else if mode == 'smoke' {
	os.join_path(root, 'c', 'tests', 'window_test.c')
} else {
	os.join_path(root, 'examples', 'counter_c', 'main.c')
}
output := os.join_path(build_dir, match mode {
	'test' { 'api_test' }
	'smoke' { 'window_test' }
	else { 'counter' }
}) + $if windows { '.exe' } $else { '' }
mut compile := [cc, '-std=c99', '-Wall', '-Wextra', '-Werror', '-I', os.join_path(root, 'c'), source,
	link_library]
compile << runtime_flags
compile << ['-o', output]
checked_execute(compile)
println('Built ${output}')
if mode in ['test', 'smoke'] { checked_execute([output]) }
