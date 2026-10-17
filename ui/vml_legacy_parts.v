module ui2

// The record of the legacy MessageBox part. VmlPart names it, so it stays
// here until the kit's dialogs replace it, with its VmlPart variant.

// MessageBoxAction is one button of a custom_message_box.
pub struct MessageBoxAction {
pub:
	id       string // lookup identity; callbacks choose behavior
	on_event ElementCallback = unsafe { nil }
	title    string
}
