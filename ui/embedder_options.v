module ui2

$if ui2_embedder ? {
	$if !macos {
		$compile_error('ui2_embedder currently requires macOS; use the existing custom backend on this platform')
	}
	$if !ui2_custom_rendering ? {
		$compile_error('ui2_embedder requires -d ui2_custom_rendering')
	}
	$if darwin_sokol_glcore33 ? {
		$compile_error('ui2_embedder currently uses Metal; darwin_sokol_glcore33 is unsupported')
	}
	$if ui2_headless ? {
		$compile_error('ui2_embedder requires a platform surface; ui2_headless is unsupported')
	}
}
