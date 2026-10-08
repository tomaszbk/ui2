// vtest vflags: -d ui2_custom_rendering
@[has_globals]
module ui2

$if ( linux || macos || windows ) && !ui2_headless ?&& ( linux || ui2_custom_rendering ?) && !ui2_embedder ? {
	import os
	import time
	import sokol.gfx

	__global image_probe_stage = 0
	__global image_probe_started = false
	__global image_probe_passed = false
	__global image_probe_decodes = u64(0)

	fn image_probe_path() string {
		return os.join_path(@VMODROOT, 'examples', 'image_assets', 'assets', 'red.png')
	}

	fn image_probe_build() Element {
		if !image_probe_started {
			image_probe_started = true
			dispatcher := ui_dispatcher()
			spawn image_probe_worker(dispatcher)
		}
		mut children := [text_input(
			id:         'editor'
			text:       'ñ declarada'
			frame:      rect(10, 10, 200, 30)
			box:        BoxStyle{}
			text_style: TextStyle{}
			keyboard:   keyboard_default
			multiline:  false
		) or { panic(err) }]
		if image_probe_stage < 2 {
			children << image('one', image_probe_path(), rect(10.25, 70.5, 64, 64))
			if image_probe_stage == 0 {
				children << image('two', image_probe_path(), rect(100.25, 70.5, 64, 64))
			}
		}
		return screen(0xffffff, children)
	}

	fn image_probe_worker(dispatcher UiDispatcher) {
		for callback in [image_probe_shared, image_probe_one, image_probe_none] {
			mut waits := 0
			for dispatcher.stats().draws == 0 {
				time.sleep(20 * time.millisecond)
				waits++
				assert waits < 500
			}
			before := dispatcher.stats().draws
			assert dispatcher.post(callback)
			waits = 0
			for dispatcher.stats().draws == before && !dispatcher.stats().closed {
				time.sleep(20 * time.millisecond)
				waits++
				assert waits < 500
			}
		}
	}

	fn image_probe_shared() {
		image_probe_shared_checked() or { panic(err) }
	}

	fn image_probe_shared_checked() ! {
		stats := image_resource_stats()
		assert stats.entries == 1 && stats.pages == 1 && stats.decodes == 1
		assert stats.cache_hits > 0 && stats.uploads == 1
		image_probe_decodes = stats.decodes
		mut ctx := g_gg_app.ctx
		entry := ctx.images.entries[image_entry_key(image_probe_path(), 0)] or { panic('missing shared entry') }
		page := ctx.images.pages[entry.page] or { panic('missing shared page') }
		// A second owner on the active graphics device cannot share handles.
		mut isolated := &DrawContext{ inner: ctx.inner, scale: ctx.scale }
		isolated.images.begin_frame()
		other := isolated.images.acquire(image_probe_path(), 0)!
		other_page := isolated.images.pages[other.page] or { panic('missing isolated page') }
		assert other_page.image != page.image && other_page.sampler != page.sampler
		bad_consumer := Element{ ...image('bad', image_probe_path(), rect(0, 0, 32, 32)), image_asset: ImageAsset{ logical_size: LayoutSize{ width: 2, height: 2 } } }
		mut invalid_dimensions := false
		isolated.prepare_image(bad_consumer, 1) or { invalid_dimensions = true }
		assert invalid_dimensions
		assert image_entry_key(image_probe_path(), 0) in isolated.images.entries
		mut invalid_geometry := false
		isolated.image_geometry_for(bad_consumer, bad_consumer.frame) or { invalid_geometry = true }
		assert invalid_geometry
		// Replacement revisions and failed/removed files must invalidate entries,
		// while an unrelated shared page/consumer remains usable.
		temp_path := os.join_path(os.temp_dir(), 'ui2-image-replacement-${os.getpid()}.png')
		defer { os.rm(temp_path) or {} }
		os.write_file_array(temp_path, os.read_bytes(image_probe_path())!)!
		original := isolated.images.acquire(temp_path, 0)!
		os.write_file_array(temp_path, os.read_bytes(os.join_path(@VMODROOT, 'examples', 'image_assets', 'assets', 'green.png'))!)!
		replacement := isolated.images.acquire(temp_path, 1)!
		assert original.pixels != replacement.pixels
		replacement_page := isolated.images.pages[replacement.page] or { panic('replacement page missing') }
		offset := (int(replacement.pixels.y) * replacement_page.width + int(replacement.pixels.x)) * 4
		assert replacement_page.pixels[offset..offset + 4] == [u8(0), 255, 0, 255]
		os.write_file(temp_path, 'invalid image')!
		mut failed := false
		isolated.images.acquire(temp_path, 1) or { failed = true }
		assert failed
		assert image_entry_key(temp_path, 1) !in isolated.images.entries
		os.rm(temp_path)!
		isolated.images.acquire(temp_path, 0) or {}
		assert image_entry_key(temp_path, 0) !in isolated.images.entries
		assert gfx.query_image_state(other_page.image) == .valid
		isolated.destroy()
		assert gfx.query_image_state(other_page.image) != .valid
		assert gfx.query_sampler_state(other_page.sampler) != .valid
		assert gfx.query_image_state(page.image) == .valid
		set_text('editor', 'edición ñ áé')
		g_focused_field = 'editor'
		mut editor := g_text_editors['editor'] or { panic('missing editor') }
		editor.set_caret(2)
		replace_text_editor('editor', editor)
		image_probe_stage = 1
		refresh()
	}

	fn image_probe_one() {
		stats := image_resource_stats()
		assert stats.entries == 1 && stats.pages == 1 && stats.decodes == image_probe_decodes
		assert text('editor') == 'edición ñ áé'
		assert g_focused_field == 'editor'
		assert (g_text_editors['editor'] or { panic('editor lost') }).selection.caret == 2
		image_probe_stage = 2
		refresh()
	}

	fn image_probe_none() {
		stats := image_resource_stats()
		assert stats.entries == 0 && stats.pages == 0
		assert stats.textures == 0 && stats.samplers == 0
		assert stats.pages_created == stats.pages_destroyed
		assert text('editor') == 'edición ñ áé'
		assert g_focused_field == 'editor'
		image_probe_passed = true
		println('image runtime: reuse, owner isolation, shared release, UTF-8/focus/selection and normal close passed')
		quit()
	}
}

fn test_image_resources_submit_release_and_close_in_the_running_backend() {
	$if ( linux || macos || windows ) && !ui2_headless ?&& ( linux || ui2_custom_rendering ?) && !ui2_embedder ? {
		image_probe_stage = 0
		image_probe_started = false
		image_probe_passed = false
		run_window('UI2 image resource runtime', 320, 200, image_probe_build)
		assert image_probe_passed
		assert g_gg_app.ctx == unsafe { nil }
	}
}
