module ui2

fn test_vml_display_text_preserves_strings_and_formats_numeric_scalars() {
	caption := 'Español: niño, café'
	assert vml_display_text(caption) == caption
	assert vml_display_text(caption).str == caption.str
	assert vml_display_text('') == ''
	assert vml_display_text(0) == '0'
	assert vml_display_text(-42) == '-42'
	assert vml_display_text(u64(18446744073709551615)) == '18446744073709551615'
	assert vml_display_text(f32(12.5)) == '12.5'
	assert vml_display_text(f64(-0.25)) == '-0.25'
}
