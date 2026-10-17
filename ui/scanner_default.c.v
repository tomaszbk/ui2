// Only iOS has a camera scanner this layer can drive.
module ui2

fn host_start_barcode_scan(on_result ScanCallback) {
	if on_result != unsafe { nil } {
		on_result(ScanResult{
			kind: .error
			text: 'barcode scanner unavailable'
		})
	}
}
