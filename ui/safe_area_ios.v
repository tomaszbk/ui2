module ui2

import macos

// host_safe_area_top is how far the status bar and the sensor housing reach
// into the top of the renderer's full-screen view, in points.
fn host_safe_area_top() f64 {
	root := ios_root_view_controller()
	if objc_is_nil(root) {
		return 0
	}
	content := macos.msg_id(root, 'view')
	if objc_is_nil(content) {
		return 0
	}
	// UIEdgeInsets lands in a rect as top, left, bottom, right.
	return macos.msg_rect(content, 'safeAreaInsets').x
}
