module main

import os
import time

// `ui2 dev <dir> [v flags] [-- program arguments]` runs a program while its
// files change, keeping its state:
//
// * a saved .vml file reloads in the running program (stage 1): the program
//   is built with `-d vml_interpreter -d ui2_dev`, so its generated builders
//   build their documents with the interpreter, which watches their files;
// * a saved .v file restarts it (stage 2): the new version is built while the
//   running one stays open; when it compiles, the running program saves its
//   component state and closes, and the new one starts from that state. A
//   build that fails leaves the running program alone.
//
// A document the interpreter cannot run is built compiled; while there is one,
// a saved .vml file restarts the program too.

const dev_poll = 300 * time.millisecond

struct DevSession {
	target       string
	flags        []string
	program_args []string
	dir          string
mut:
	builds  int
	process &os.Process = unsafe { nil }
	stamps  map[string]i64
}

fn dev(target string, flags []string, program_args []string) int {
	dir := os.join_path(os.vtmp_dir(), 'ui2-dev-${os.getpid()}')
	os.mkdir_all(dir) or {
		eprintln('ui2 dev: ${err}')
		return 1
	}
	defer {
		os.rmdir_all(dir) or {}
	}
	mut session := DevSession{
		target:       target
		flags:        flags
		program_args: program_args
		dir:          dir
	}
	session.stamps = session.scan()
	binary := session.build() or { return 1 }
	session.start(binary)
	for {
		time.sleep(dev_poll)
		if !session.process.is_alive() {
			session.process.wait()
			return session.process.code
		}
		stamps := session.scan()
		mut code := false
		mut documents := false
		for file, stamp in stamps {
			if session.stamps[file] or { -1 } == stamp {
				continue
			}
			if file.ends_with('.v') {
				code = true
			} else {
				documents = true
			}
		}
		if stamps.len != session.stamps.len {
			code = true
		}
		session.stamps = stamps.clone()
		if !code && !documents {
			continue
		}
		if code || (documents && session.has_compiled_documents()) {
			session.restart()
		} else {
			// The program reloads its documents; the builders follow them for
			// the next build.
			generate_paths([target]) or { eprintln('ui2 gen: ${err}') }
		}
	}
	return 0
}

// scan stamps the V and VML files under the target with their modification
// times. Generated builders are not sources.
fn (s &DevSession) scan() map[string]i64 {
	mut stamps := map[string]i64{}
	dev_scan(s.target, mut stamps)
	return stamps
}

fn dev_scan(path string, mut stamps map[string]i64) {
	if os.is_file(path) {
		if (path.ends_with('.v') && !is_generated(os.file_name(path))) || path.ends_with('.vml') {
			stamps[path] = os.file_last_mod_unix(path)
		}
		return
	}
	entries := os.ls(path) or { return }
	for entry in entries {
		if entry.starts_with('.') || entry in ['thirdparty', 'third_party', 'node_modules'] {
			continue
		}
		dev_scan(os.join_path(path, entry), mut stamps)
	}
}

// build generates the builders and builds a development binary. It returns
// none, after printing V's diagnostics, when the build fails.
fn (mut s DevSession) build() ?string {
	generate_paths([s.target]) or {
		eprintln('ui2 gen: ${err}')
		return none
	}
	s.builds++
	binary := os.join_path(s.dir, '${os.file_name(os.real_path(s.target))}-${s.builds}')
	mut flags := s.flags.clone()
	flags << ['-d', 'vml_interpreter', '-d', 'ui2_dev', '-o', binary]
	if compile(flags, s.target) != 0 {
		return none
	}
	return binary
}

// start runs a development binary with the files of a restart.
fn (mut s DevSession) start(binary string) {
	mut env := os.environ()
	env['UI2_DEV_STATE'] = os.join_path(s.dir, 'state')
	env['UI2_DEV_REQUEST'] = os.join_path(s.dir, 'request')
	env['UI2_DEV_COMPILED'] = os.join_path(s.dir, 'compiled')
	os.rm(env['UI2_DEV_COMPILED']) or {}
	mut process := os.new_process(binary)
	process.set_args(s.program_args)
	process.set_environment(env)
	process.run()
	s.process = process
}

// restart builds the new version, then asks the running program to save its
// state and close, and starts the new one.
fn (mut s DevSession) restart() {
	println('ui2 dev: rebuilding')
	binary := s.build() or {
		println('ui2 dev: the build failed; the running program stays open')
		return
	}
	request := os.join_path(s.dir, 'request')
	os.write_file(request, '') or {}
	// The program saves its state on its next frame; one that does not answer
	// is stopped, and the new version starts from its declared state.
	deadline := time.now().add(5 * time.second)
	for s.process.is_alive() && time.now() < deadline {
		time.sleep(50 * time.millisecond)
	}
	if s.process.is_alive() {
		s.process.signal_kill()
	}
	s.process.wait()
	os.rm(request) or {}
	previous := s.process.filename
	s.start(binary)
	if previous != binary {
		os.rm(previous) or {}
	}
}

fn (s &DevSession) has_compiled_documents() bool {
	text := os.read_file(os.join_path(s.dir, 'compiled')) or { return false }
	return text.trim_space().len > 0
}
