module ui2

import os

fn test_draw_commands_declaration_only_client_imports_the_owner_symbol() {
	$if macos {
		temporary := os.join_path(os.temp_dir(), 'ui2-draw-command-client-${os.getpid()}')
		os.mkdir(temporary)!
		defer { os.rmdir_all(temporary) or {} }
		object := os.join_path(temporary, 'client.o')
		fixture := os.join_path(@VMODROOT, 'tests', 'render_scheduler', 'draw_commands_client.c')
		includes := os.join_path(@VEXEROOT, 'thirdparty', 'sokol')
		command := 'clang -std=c11 -Werror -I ${os.quoted_path(includes)} -c ${os.quoted_path(fixture)} -o ${os.quoted_path(object)}'
		result := os.execute(command)
		assert result.exit_code == 0, result.output
		symbols := os.execute('nm ${os.quoted_path(object)}')
		assert symbols.exit_code == 0, symbols.output
		assert symbols.output.contains('U _ui2_sgl_discard_commands')
		assert !symbols.output.contains('T _ui2_sgl_discard_commands')
		eprintln('draw command declaration-only client imports owner passed')
	}
}
