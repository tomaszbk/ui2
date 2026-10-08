# Fixed composition scaling

The custom renderer supports `scaled_content(id, viewport, content_width,
content_height, box, children)`. Children retain their fixed logical coordinates.
The view centers and scales the composition to fit its viewport, preserving its
aspect ratio. It clips drawing and pointer targets to the visible content. Device
DPI and the composition scale are separate; native backends report unsupported
scaled content instead of silently changing its meaning.

```vml
Screen {
    Absolute {
        transparent: true
        ScaledContent {
            id: "slide"
            content_width: 1280
            content_height: 720
            Column {
                Label { text: "A fixed composition" font_size: 36 height: 60 }
            }
        }
        Button { id: "next" text: "Next" x: 12 y: 12 width: 44 height: 64 }
    }
}
```

The slide lays out at 1280 by 720 before fitting into its declared frame (the
parent's available size when unspecified). The sibling button keeps its ordinary
window size. At a 640 by 480 viewport, the slide scales by 0.5 and has 60 units of
vertical letterboxing. Resizing does not change its logical wrapping or frames.
Nested scaled views compose their transforms.

Shapes, images, shaped text, clipping and editor caret geometry use the same
transform. Controls hit test in window coordinates; slider, scroll and pointer
callback coordinates map back into the fixed composition. The existing IME bridge
receives the projected window caret. Text fields keep their existing caret-on-click
behavior; this feature does not add grapheme-aware editing or a new IME bridge.
Floating dropdowns anchor to the projected control and fit the window; tooltips
and menus remain window overlays. State, ids, bindings and the scheduler are retained.
