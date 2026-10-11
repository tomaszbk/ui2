module ui2

// Scratch text is borrowed until the next call on this buffer. Shape caches
// own their source text; immediate text submission consumes it synchronously.
struct FrameTextBuffer {
mut:
	bytes []u8
}

fn (mut buffer FrameTextBuffer) field_text(text string, secure bool) string {
	if !secure { return text }
	return buffer.field_prefix(text, rune_len(text), true)
}

fn (mut buffer FrameTextBuffer) field_prefix(text string, runes int, secure bool) string {
	// Malformed bytes become the same replacement runes as V's rune APIs.
	// UTF-8 output needs at most three bytes per source byte, plus termination.
	buffer.bytes.ensure_cap(text.len * 3 + 1)
	mut count := 0
	mut length := 0
	for value in text.runes_iterator() {
		if count >= runes { break }
		mut destination := unsafe { &u8(buffer.bytes.data) + length }
		encoded := unsafe { utf32_to_str_no_malloc(u32(if secure { `•` } else { value }), mut destination) }
		length += encoded.len
		count++
	}
	unsafe { buffer.bytes.len = length + 1 }
	buffer.bytes[length] = 0
	return unsafe { string{str: buffer.bytes.data, len: length, is_lit: 1} }
}
