module ui2

// vml_display_text formats numbers for a VML text declaration and preserves strings.
// The accepted type is checked at compile time; this does not convert binding writes.
@[inline]
pub fn vml_display_text[T](value T) string {
	$if T is string {
		return value
	} $else $if T is $int || T is $float {
		return value.str()
	} $else {
		$compile_error('VML text requires a string or number')
	}
}
