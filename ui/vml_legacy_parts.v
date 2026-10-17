module ui2

// The records of the legacy composite parts. VmlPart names them, so they stay
// here while their widgets are replaced: TreeViewNode by the kit's Tree,
// MessageBoxAction by its dialogs. Each goes with its VmlPart variant.

pub struct TreeViewNode {
pub:
	id        string
	text      string
	on_event  ElementCallback = unsafe { nil }
	on_toggle ElementCallback = unsafe { nil }
	expanded  bool
	selected  bool
	enabled   bool = true
	children  []TreeViewNode
}

// MessageBoxAction is one button of a custom_message_box.
pub struct MessageBoxAction {
pub:
	id       string // lookup identity; callbacks choose behavior
	on_event ElementCallback = unsafe { nil }
	title    string
}
