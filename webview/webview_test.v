module webview

fn test_config_defaults() {
	cfg := Config{}
	assert cfg.width == 1000
	assert cfg.height == 800
	assert cfg.persistent
}

fn test_platform_availability_is_explicit() {
	$if macos {
		assert supported()
	} $else {
		assert !supported()
	}
}
