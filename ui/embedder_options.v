module ui2

$if ui2_embedder ? {
	$if !macos {
		$compile_error('ui2_embedder is a macOS host; every other OS runs the renderer in its sokol window')
	}
	$if !ui2_custom_rendering ? {
		$compile_error('ui2_embedder hosts the custom renderer; build with -d ui2_custom_rendering')
	}
	$if darwin_sokol_glcore33 ? {
		$compile_error('ui2_embedder currently uses Metal; darwin_sokol_glcore33 is unsupported')
	}
	$if ui2_headless ? {
		$compile_error('ui2_embedder requires a platform surface; ui2_headless is unsupported')
	}
}
