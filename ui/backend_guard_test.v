module ui2

import os

// The backend contract (backend.v) keeps the flags that select a backend out
// of shared code. This test reads the sources and enforces it.

const backend_flags = ['ui2_headless', 'ui2_embedder', 'ui2_document_library']

const backend_guards = {
	'document':       r'$if ui2_document_library ? {'
	'headless':       r'$if ui2_headless ? && !ui2_document_library ? {'
	'uikit':          r'$if ios && !ui2_headless ? && !ui2_document_library ? {'
	'custom':         r'$if (android || linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {'
	'custom desktop': r'$if (linux || macos || windows) && !ui2_headless ? && !ui2_document_library ? {'
	'custom android': r'$if android && !ui2_headless ? && !ui2_document_library ? {'
	'embedder':       r'$if macos && ui2_embedder ? && !ui2_headless ? && !ui2_document_library ? {'
}

// Branches a backend may take inside its own files, by file.
const backend_branch_exceptions = {
	'ui/backend_headless.v': [
		r'$if !(android || linux || macos || windows || ios) && !ui2_headless ? && !ui2_document_library ? {',
	]
	'ui/backend_custom.c.v': [
		r'pub const backend_embedder = $if ui2_embedder ? { true } $else { false }',
	]
	'ui/backend_document.v': [
		r'const document_host_custom = $if ui2_headless ? { false } $else { true }',
	]
	'ui/embedder_options.v': [
		r'$if ui2_embedder ? {',
		r'$if ui2_headless ? {',
	]
}

// The custom renderer selects its embedder host with this branch.
const embedder_surface_branch = r'$if macos && ui2_embedder ? {'

const backend_directories = {
	'uikit': 'uikit'
}

fn backend_source_files() []string {
	root := os.dir(@DIR)
	mut files := []string{}
	for dir in ['ui', 'uikit'] {
		for name in os.ls(os.join_path(root, dir)) or { panic(err) } {
			if name.ends_with('.v') && !name.ends_with('_test.v') {
				files << '${dir}/${name}'
			}
		}
	}
	files.sort()
	return files
}

fn backend_source_lines(path string) []string {
	lines := os.read_lines(os.join_path(os.dir(@DIR), path)) or { panic(err) }
	return lines.map(it.trim_right('\r'))
}

fn mentions_backend_flag(line string) bool {
	return (line.contains(r'$if') || line.contains(r'$else'))
		&& backend_flags.any(line.contains(it))
}

fn file_guard(lines []string) string {
	for name, guard in backend_guards {
		if guard in lines {
			return name
		}
	}
	return ''
}

fn test_backend_flags_appear_only_in_backend_guards() {
	mut offending := []string{}
	guards := backend_guards.values()
	for path in backend_source_files() {
		lines := backend_source_lines(path)
		guard := file_guard(lines)
		exceptions := backend_branch_exceptions[path] or { []string{} }
		for i, line in lines {
			if !mentions_backend_flag(line) || line.trim_space().starts_with('//') {
				continue
			}
			if line in guards || line.trim_space() in exceptions {
				continue
			}
			if guard in ['custom', 'custom desktop'] && line.trim_space() == embedder_surface_branch {
				continue
			}
			offending << '${path}:${i + 1}: ${line.trim_space()}'
		}
	}
	assert offending == [], 'shared code tests a backend flag; add a contract function or constant (ui/backend.v):\n' +
		offending.join('\n')
}

fn test_native_backend_directories_hold_only_their_backend() {
	for path in backend_source_files() {
		dir := path.all_before('/')
		backend := backend_directories[dir] or { continue }
		assert file_guard(backend_source_lines(path)) == backend, '${path} must open with the ${backend} guard from ui/backend.v'
	}
}

fn test_backend_contract_documents_every_guard() {
	contract := os.read_file(os.join_path(@DIR, 'backend.v')) or { panic(err) }
	for name, guard in backend_guards {
		assert contract.contains('`${guard}`'), 'ui/backend.v does not document the ${name} guard'
	}
}

fn test_every_backend_defines_its_name() {
	mut names := map[string]bool{}
	for path in backend_source_files() {
		for line in backend_source_lines(path) {
			if line.trim_space().starts_with('pub const backend_name = ') {
				names[line.all_after('= ').trim_space().trim("'")] = true
			}
		}
	}
	assert names.keys().sorted() == ['custom', 'document', 'headless', 'uikit']
}
