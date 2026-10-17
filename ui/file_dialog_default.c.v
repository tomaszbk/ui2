// Fallback for targets whose platform dialog needs a UI callback this layer
// cannot install, including Android and iOS.
module ui2

fn host_file_dialog_supported() bool {
	return false
}

fn host_file_dialog(cfg FileDialogConfig) []string {
	eprintln('ui2: native file dialogs are unavailable on this target')
	return []string{}
}
