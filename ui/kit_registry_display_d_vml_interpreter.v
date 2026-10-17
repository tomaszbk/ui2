module ui2

// The interpreter registry fragment of the kit's display, disclosure,
// navigation and feedback components, with the legacy tags they replace. A
// tag is one line here; the registry test checks the bindable fields and
// part-only tags listed below against the props types.

fn kit_display_widgets() map[string]VmlWidgetType {
	return {
		'Badge':           vml_widget[BadgeProps]()
		'Avatar':          vml_widget[AvatarProps]()
		'Tag':             vml_widget[TagProps]()
		'Separator':       vml_widget[SeparatorProps]()
		'Kbd':             vml_widget[KbdProps]()
		'Link':            vml_widget[LinkProps]()
		'Alert':           vml_widget[AlertProps]()
		'Empty':           vml_widget[EmptyProps]()
		'GroupBox':        vml_widget[GroupBoxProps]()
		'DescriptionList': vml_widget[DescriptionListProps]()
		'DescriptionItem': vml_widget[DescriptionItemProps]()
		'Progress':        vml_widget[ProgressProps]()
		'ProgressCircle':  vml_widget[ProgressCircleProps]()
		'Spinner':         vml_widget[SpinnerProps]()
		'Skeleton':        vml_widget[SkeletonProps]()
		'Shimmer':         vml_widget[ShimmerProps]()
		'Clipboard':       vml_widget[ClipboardProps]()
		'Collapsible':     vml_widget[CollapsibleProps]()
		'Accordion':       vml_widget[AccordionProps]()
		'AccordionItem':   vml_widget[AccordionItemProps]()
		'TabbedPanel':     vml_widget[TabbedPanelProps]()
		'Tab':             vml_widget[TabProps]()
		'Carousel':        vml_widget[CarouselProps]()
		'CarouselSlide':   vml_widget[CarouselSlideProps]()
		'TreeView':        vml_widget[TreeViewProps]()
		'TreeNode':        vml_widget[TreeNodeProps]()
	}
}

// kit_display_expected_bindables are the fragment's bindable properties,
// `Tag.field`, which the registry test checks.
fn kit_display_expected_bindables() []string {
	return ['Accordion.value', 'Accordion.values', 'Clipboard.copied', 'Collapsible.open']
}

// kit_display_expected_parts are the fragment's part-only tags, which take no
// common properties.
fn kit_display_expected_parts() []string {
	return []
}
