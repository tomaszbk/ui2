module ui2

$if ( linux || ( ( macos || windows ) && ui2_custom_rendering ?) ) && !ui2_headless ? {
	// Retained drawing requests exclude position, transform, clip and selection.
	// The CPU layout/measurement engine stays independent of this window cache.
	struct TextPresentationRequest {
		text      string
		runs      []TextRun
		style     TextStyle
		width     f64
		lines     int
		ellipsize bool
		word_char bool
	}

	struct TextPresentationEntry {
		request TextPresentationRequest
		shaped  ShapedText
		frame   u64
	}

	fn (request TextPresentationRequest) snapshot() TextPresentationRequest {
		return TextPresentationRequest{
			...request
			text:  request.text.clone()
			style: TextStyle{ ...request.style, font_family: request.style.font_family.clone() }
			runs:  request.runs.map(TextRun{
				text:  it.text.clone()
				style: TextStyle{ ...it.style, font_family: it.style.font_family.clone() }
			})
		}
	}

	fn (ctx &DrawContext) presented_text(request TextPresentationRequest) !ShapedText {
		if ctx.destroyed || ctx.text == unsafe { nil } { return error('text context is closed') }
		g_text_font_mutex.lock()
		defer { g_text_font_mutex.unlock() }
		mut context := unsafe { ctx }
		if context.text_presentation_generation != g_text_font_generation {
			context.text_presentations.clear()
		}
		for index, entry in context.text_presentations {
			if entry.request == request {
				context.text_presentations[index] = TextPresentationEntry{
					...entry
					frame: context.text_presentation_frame
				}
				return entry.shaped
			}
		}
		// Editors replace/free their strings. Both queries and retained layouts
		// must borrow this cache's own snapshot, never the editor's allocation.
		owned := request.snapshot()
		mut engine := context.text
		shaped := engine.shape_runs_locked(owned.text, owned.runs, owned.style,
			owned.width, owned.lines, owned.ellipsize, owned.word_char)!
		if context.text_presentation_generation != engine.font_generation {
			context.text_presentations.clear()
			context.text_presentation_generation = engine.font_generation
		}
		context.text_layouts++
		context.text_presentations << TextPresentationEntry{
			request: owned
			shaped:  shaped
			frame:   context.text_presentation_frame
		}
		return shaped
	}
}
