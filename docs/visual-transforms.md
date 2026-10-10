# Visual transforms

Desktop custom rendering supports translation, nonuniform scale, reflection and
clockwise rotation on every `Element` and its subtree. Layout frames, wrapping
constraints, ids and editor state remain logical and unchanged. Native profiles
reject visual presentation with a diagnostic. Android also rejects it because
its Fontstash text path does not support full affine glyphs. No new host port or
animation/presence lifecycle is part of this API.

```v
panel := ui2.with_transform(
    ui2.view('panel', ui2.rect(20, 30, 200, 100), ui2.BoxStyle{ bg: 0xdbeafe }, children),
    ui2.VisualTransform{
        translate_x: 12
        translate_y: -4
        rotation: 15
        scale_x: 1.2
        scale_y: 0.8
        origin_x: 100
        origin_y: 50
    })
```

`Element` exposes the same canonical fields (`translate_x/y`, `scale_x/y`,
`rotation`, `origin_x/y`). `with_transform` writes those fields;
`el.visual_transform()` reads them. There is no image-only rotation path or
`transformed_image` constructor. Use `image` with the common transform.

Origin is in logical units from the element's top-left; the default is `(0,0)`.
For center rotation, explicitly use half the frame width/height. Angles are
**degrees, clockwise** in the y-down UI coordinate system. Order is translation,
pivot, rotation, scale, inverse pivot (`T * P * R * S * -P`). All values must be
finite. Matrices whose determinant magnitude is at most `1e-12` reject; zero
scale is an error, rather than a hidden but interactive surface.

Compiled VML uses the same numeric properties and rejects quoted numbers, bools
and string-valued model bindings:

```vml
View(rotation: 15, origin_x: 100, origin_y: 50, scale_x: 1.2, scale_y: 0.8, translate_x: 12)
```

Compiled VML lowers these properties to the canonical `Element` fields. A bound
transform updates its retained node through a property effect.

## Presentation updates and coordinates

On the UI thread, `set_visual_transform(id, transform)!` patches the retained
declaration and requests a paint. It does not rebuild layout, change declared
text, reset selection/IME, or start a frame loop. The drawing context owns one
`TextEngine`; its shape cache retains source text and logical glyph/line geometry.
Text, metric styles, constraints, scale, font generation and environment version
participate in shape keys. Paint colors reuse canonical rich-run geometry. CPU
measurement, retained layout caches and the renderer glyph atlas have separate owners. Invalid values and unknown ids
return errors without mutating the tree. A subsequent declarative rebuild
replaces the patch: retain your camera/transform in your application model too.

A typed element callback that calls this setter is a presentation-only action
and skips automatic rebuilding. If that callback also changes layout/model
content, call `refresh()` explicitly. Ordinary callbacks retain automatic
refresh behavior. Existing widget animation APIs remain separate.

`visual_geometry(id)!` describes an element traversed in the **last presented**
frame. Canceled frames preserve that snapshot. Hidden and culled elements have no entry; a transformed element outside
its clip can retain geometry with empty visible bounds, preserving capture.

- `frame`: logical frame in the active composition, including accumulated layout
  offsets and current scroll translation;
- `transform`: composition-to-window affine;
- `parent_transform`: the same mapping before this element's visual transform;
- `clip`: exact effective window-logical ancestor clip;
- `bounds()` / `contains(x,y)`: visible bounds and exact membership.

`mounted_geometry(id)!` reads the current resolved mounted registry, including
offscreen controls. A transform setter updates this geometry before directional
focus, semantics, reveal and capture queries, without resolving layout. Navigation
eligibility follows hidden, enabled and scope state. Nested Scroll reveal carries
exact corners inside out and bounds them only for each local Rect scrolling API.

`ContentTransform` is the single common affine helper. `outer.compose(inner)`
means `outer * inner`. `point(x,y)` includes translation; `vector(x,y)` does not.
`inverted()!`, `inverse(x,y)` and `inverse_vector(x,y)` reverse those mappings.
Invalid inverse mappings return noninteractive NaN coordinates; authored/runtime
setters reject them earlier. `project(Rect)` and `inverse_rect(Rect)` return
**AABB bounds**, suitable for culling, semantic frames and the OS IME rectangle.
They must not be used to draw a rotated rectangle or recover a clip.

Existing `ElementEvent.x/y` remain active-composition logical coordinates,
including accumulated frame offsets. To obtain window coordinates, project them
with the current `mounted_geometry(id).transform`; to obtain coordinates relative
to the control's top-left, subtract its `frame.x/y`. Capture retains event identity
while using the current mounted transform if the owner moves, including before paint; removal falls
back to the captured mapping for the terminal pointer event.

## ScaledContent, clipping, scroll and DPI

`ScaledContent` fits fixed child geometry first, composes with all ancestor and
local transforms exactly once, and preserves letterboxing. Scroll translations
remain local logical offsets. Device DPI is outside the affine: vertices reach
the rasterizer at device scale once, while caret/IME receive window-logical AABBs.
Axis-aligned rectangles may snap shared physical edges; rotated/sheared geometry
preserves vertices instead of deforming an AABB back into local space.

`ClipRegion` retains convex window polygons. `transformed_clip(frame, matrix)`
constructs a rectangular clip; `intersect` produces exact nested intersections.
Bounded regions with zero area (including edge/corner tangency), nonfinite
coordinates, unrepresentable bounds or nonconvex point sequences are empty.
Publicly constructed snapshots follow the same rule in `contains`, `bounds`,
`intersect` and `clip_polygon`; intersections normalize exact duplicate and
redundant collinear clip vertices. There is no minimum-area cutoff for valid
small or fractional regions. `contains` includes boundaries with a relative
floating-point roundoff allowance; painting clips to the inclusive halfplanes
without enlarging them.
Broad bounds and inverse rectangle tests include boundaries with a `1e-8` logical
coordinate tolerance for projection/inverse roundoff; they retain the exact clip
narrow phase. Filled/stroked
primitives, image UVs, glyph quads and decorations, selection and caret all use
`clip_polygon`, with interpolated UV/color at intersections. Build regions with `transformed_clip`
and `intersect`; `clip_polygon` accepts convex primitives (triangulate complex
local geometry before submission). Scissor is only a
conservative optimization. Pointer, hover, tooltips and scroll use the same
polygon and inverse local membership. Rectangle boundaries are inclusive for
pointer, tooltip and scroll membership; shared boundaries resolve in reverse
paint order. Rounded controls retain rectangular hit
frames; their corner radius is presentation, not shape hit testing.

Wheel and drag input are **window vectors**. Each Scroll consumes its inverse
local vertical component and forwards the unconsumed window vector to ancestors.
A pane rotated 90° scrolls with horizontal wheel motion; vertical wheel motion
has no local vertical component there. Scrollbar capture projects pointer points
into the pane's local axis, including outside bounds during capture. A captured
draggable surface owns its drag instead of simultaneously scrolling ancestors.
Dropdown/menu/tooltip overlays remain in window space and anchor to projected
bounds; they do not inherit the owner's transform again.

## Pan and zoom

`PanZoom` is a camera value, not another pointer loop:

```v
camera = camera.pan(parent_delta.x, parent_delta.y)!
camera = camera.zoom_at(next_zoom, parent_pointer)!
ui2.set_visual_transform('camera', camera.transform())!
```

`pan` takes a parent-logical vector. `zoom_at` takes the next positive zoom and a
parent-logical anchor, keeping the same content point at that anchor. For a camera
at a nonzero layout position, subtract the camera frame's top-left from the
parent pointer before zooming. Convert window input with `parent_transform`'s
inverse; do not divide by device DPI or a scalar content scale. The application
chooses zoom limits and gestures using existing typed callbacks/capture.

Run the maintained example with:

```sh
v -d ui2_custom_rendering run examples/visual_transforms
make screenshot EXAMPLE=visual_transforms
```

It combines rotated ScaledContent descendants, scroll, UTF-8 editors, image,
nonuniform nested transforms and a draggable pan/zoom camera. macOS's existing
owned embedder (`-d ui2_embedder`) supplies its IME bridge. GL/D3D still repaint
the retained tree for their existing presentation requirement; macOS Metal
returns to idle after transform interaction.

Independent geometry/input fixtures live in `visual_transform*_test.v`. The
macOS GPU fixture records submitted clipped geometry at DPI 1/1.25/1.5/2 and
checks full glyph affine vertices, editor state, caret projection, sibling clip
restoration and paint-only/idle counters, including stable actual shape-build and layout-visit counters
for paint-only updates. Cross-backend checks are typechecks,
not runtime acceptance on other platforms. The PR11/15/20 combination has focused mounted geometry, text ownership and
callback fixtures. Integration with PR22/23/24 remains a later stack.

For a pinned compiler wrapper, Make accepts `V` and explicit compiler `VFLAGS`,
which also propagate to example/screenshot child builds, for example
`make V=/path/to/wrapper VFLAGS='-cc clang' examples-custom`.
