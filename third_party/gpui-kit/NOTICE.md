# GPUI Kit attribution

Source: https://github.com/longbridge/gpui-kit
Revisions: `1b6059c13315dc5c304759ad3aa666e0b6e301d8` (batch 1) and
`f8cf0bd964f9ef2e5b7be79f3a8fc391371feb4a` (later batches)
Copyright 2024 - 2026 Longbridge <https://longbridge.com>

These files adapt GPUI Kit logic or tests and are distributed under
Apache-2.0; the complete license is in `LICENSE-APACHE` alongside this notice.
Each carries an SPDX header naming it.

| File | Adapted from |
| --- | --- |
| `ui/kit_logic_actions.v` | The rating click rule of `crates/component/src/rating.rs` (clicking a filled star sets the value to the star before it) and the stepping rules of `step_value` in `crates/base/src/number_input.rs`. |
| `ui/kit_logic_actions_test.v` | Rating click-rule and number-input stepping cases from the same files, beside new tests. |
| `ui/kit_logic_display.v` | The controlled pagination state and page-window algorithm of `crates/base/src/pagination.rs`; the size presets, stroke formula and both loading curves of `crates/component/src/progress/progress.rs` and `progress_circle.rs`; and the spread clamping, band center and padding of `crates/component/src/shimmer.rs`. The V version changes types and error handling and caps visible-page allocation. |
| `ui/kit_logic_display_test.v` | Pagination behavior and shimmer spread and band cases from the same files, beside new tests. |
| `ui/component_popovers_position.v` | The side choice (preferred, else opposite, else roomier), alignment and clamping of `crates/base/src/positioner.rs`, and the arrow's corner clearance of `crates/component/src/popover.rs`. |
| `ui/component_popovers.v` | The hover-card timing rules of `crates/base/src/hover_card.rs`. |
| `ui/component_popovers_menu.v` | The keyboard navigation rules of `crates/component/src/menu/popup_menu.rs`. |
| `ui/component_popovers_test.v` | Placement cases from upstream's positioner tests, beside new tests. |

Every other kit implementation is new V code following the GPUI Kit
catalog's documented concepts, not copied Rust. It, the examples and the
documentation use UI2's existing MIT license. No GPUI Kit assets or runtime are
included, and this does not change the license of existing UI2 files.
