# Custom window

This example replaces the platform's title bar with an ordinary ui2 header:

```sh
v run examples/custom_window
```

`window.set_chrome(.hidden_titlebar)` gives the title bar to the drawn
content: macOS keeps its window buttons over the leading corner of a
transparent title bar, and Windows removes the caption while keeping the
resizable border. Linux and the mobile hosts keep their own frame, so the
header is only decoration there.

The header is a draggable ui2 `View`. Its pointer-down event calls
`event.window.start_move()`, so the operating system still performs the move.
The close button calls `event.window.quit()`. Everything else is declared in
[`custom_window.vml`](custom_window.vml).
