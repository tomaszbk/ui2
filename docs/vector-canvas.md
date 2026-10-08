# Vector canvas

`VectorPath` describes local logical coordinates. Prepare it once with
`prepare_vector_shape`, then retain the returned immutable `VectorShape` in your
model. `vector_canvas` draws prepared shapes, in array order, through the custom
renderer's existing `DrawContext`. It is a transparent `View`, participates in
normal identity/reconciliation and has no dedicated textures or GPU resources.
Native tree validation reports `vector canvas requires the custom renderer`.

```v
mut path := ui2.VectorPath{}
path.move_to(10, 80)
path.quadratic_to(80, -20, 150, 80)
path.line_to(150, 100)
path.close()
shape := ui2.prepare_vector_shape(path, ui2.VectorStyle{
    fill: 0x99f6e4
    stroke: 0x0f766e
    stroke_width: 4
    cap: .round
    join: .round
})!
canvas := ui2.vector_canvas(
    id: 'curve'
    frame: ui2.rect(20, 20, 170, 120)
    shapes: [shape]
    hit_mode: .paint
    button_behavior: true
    on_event: on_curve
)!
```

`move_to` starts a contour; `line_to`, `quadratic_to` and `cubic_to` append
segments. Quadratic curves have one control point; cubic curves have two.
`close` joins the endpoint to the start. Start the next contour with `move_to`,
including after `close`. `vector_polygon([]VectorPoint)` is the same path API
with a closed sequence of lines. There is no string path language or implicit
conversion. Construct these declarations in V, alongside the application's
business logic; this feature does not introduce new VML grammar.

Fill closes every contour implicitly, including open contours. Stroke closes
only explicitly closed contours. Contours with fewer than three points do not
fill. Multiple contours, concave polygons, overlapping contours and self
intersections are supported. The default `.nonzero` fill uses signed winding:
opposite contour directions produce holes, equal directions remain filled.
`.even_odd` toggles membership at each crossing, so nested contours form holes
regardless of direction. A painted boundary belongs to the shape.

`fill` and `stroke` are optional opaque RGB colors; omission disables that paint.
Strokes are centered on their segments, with logical `stroke_width` (default 1).
The offered caps are `.butt` (default), `.round` and `.square`; joins are `.miter`
(default), `.bevel` and `.round`. A miter longer than `miter_limit` times half the
width falls back to bevel (default limit 4). Round caps are outward semicircles
oriented by the first and last nondegenerate flattened segments, including when
those segments are shorter than half the stroke width. Closed contours have joins at the
seam and no caps. Consecutive equal points collapse. A zero-length open contour
paints a disk only with a round cap; butt/square have no defined tangent and
paint nothing. Zero stroke width paints nothing.

The default hit mode `.paint` tests the union of enabled fill and stroke geometry.
`.fill` and `.stroke` test just that enabled paint. `.bounds` explicitly tests
each shape's painted geometry bounds; it can accept a hole or an empty corner.
An unpainted shape has no hits. Use `shape.contains(x, y, mode)` to query geometry
directly. Canvas hits, hover styling and tooltips use the same local membership,
after the existing shared window-to-content inverse conversion. Reverse paint
order determines the winning element. Use separate canvas elements with ids and
callbacks when individual shapes need independent event ownership. Pointer event
`x`/`y` keep the existing composition-space contract, rather than becoming
shape-relative. Capture/drag behavior uses the existing pointer capture loop.
An empty canvas keeps its identity and has no paint, hits, hover or tooltip
region, including in `.bounds` mode; adding shapes restores their membership.

Both painting and hits are clipped to the canvas frame and effective ancestor
clip. ScaledContent and scrolling share the existing coordinate conversion;
put a vector canvas *inside* ScaledContent rather than applying `content_size`
to the canvas itself. The pinned base supports uniform scale and translation.
Rotation/nonuniform affine transforms and exact rotated ancestor clipping belong
to the shared visual-transform feature and need integration verification there.
Arbitrary path clipping, gradients, shadows, blur, dashes and translucent paint
are outside this API.

Curves and round strokes flatten adaptively with `tolerance` measured in local
logical units (default 0.25, allowed 0.001–10). Round strokes use inscribed chord
segments. Hit boundaries follow the retained approximation used for paint,
with numerical epsilon 1e-9 in cross products. Device DPI and content scale do
not change the source geometry or accumulate rounding; their projection is
applied only when drawing. For very large zoom, explicitly prepare a smaller
tolerance for the desired quality. Fill tessellation splits horizontal slabs at
vertices and intersections, so holes use ordinary triangles and need no stencil
buffer. Preparation may allocate; redraw and resize reuse these triangles.

Inputs must be finite, points within ±10,000,000, width in 0–10,000,000 and miter
limit in 1–1000. Preparation diagnoses paths exceeding 4096 commands/flattened
points, 20 curve subdivision levels, 32768 sweep levels, 4096 circle segments or
131072 triangles per paint. Geometry preparation has quadratic intersection
cost and is intended for retained UI artwork. The existing Sokol command/vertex
capacity also limits an entire frame; overflowing it produces a diagnostic.
This is not an unbounded drawing or streaming API.

`flattened_contours`, `fill_mesh`, `stroke_mesh`, `paint_bounds` and `paint_style`
expose independent snapshots for geometry tools and fixtures. Editing a builder
or a snapshot cannot change an already prepared shape. To update artwork,
prepare a replacement and refresh the normal retained element declaration.
Removing a canvas releases its CPU geometry when no model/declaration/target
references remain; there is no additional GPU cleanup path. Existing renderer
teardown and on-demand policy remain authoritative (Linux GL still presents
retained frames).

Run `examples/vector_canvas` with `-d ui2_custom_rendering` on macOS/Windows
(Linux uses custom by default). Its nine panels cover polygon segments,
fill rules and holes, both Bézier types, every cap/join, a closed curved contour,
frame clipping and ScaledContent. Click paint and empty corners to compare hits.
The editable UTF-8 field can be used while resizing and interacting with shapes.
Public independent fixtures are in `tests/vector_geometry_test.v`; runtime
coordinate/clip fixtures are in `ui/vector_canvas_immediate_test.v`.
