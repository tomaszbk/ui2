# Native browser windows

`ui2.webview` supplies standalone macOS `WKWebView` windows without importing the
legacy `ui` module. It uses the host AppKit application and main run loop, leaving
its application delegate intact. Call `supported()` before using it on another
platform; `new_window` explicitly fails on platforms without an implementation.

```v
import ui2.webview

view := webview.new_window(
	url: 'https://example.com'
	title: 'Sign in'
	persistent: false
	js_on_init: 'window.webkit.messageHandlers.vui.postMessage(document.title)'
)
view.eval_js('document.title')
// Poll from a worker while the host UI keeps running:
println(view.js_value())
println(view.cookie('session', 'example.com'))
view.close()
```

Initialization scripts run at document start. JavaScript values, cookie caches,
navigation generations, and closed status belong to each window. Navigation and
closing clear previous JavaScript results. Late evaluation and cookie callbacks
from an earlier navigation cannot repopulate their results.

`persistent: false` gives a fresh in-memory WebKit data store, including isolated
cookies and local storage. The default, `true`, uses WebKit's shared persistent
store to support sign-in renewal. `delete_all_cookies()` matches the legacy
behavior by asynchronously removing all website data from the window's store.
Prefer a nonpersistent window when a clean sign-in is needed immediately.

Window creation marshals synchronously to the main thread; worker creation
requires an active host UI run loop. Load, evaluate, clear, and close operations
marshal asynchronously from workers. Cookie reads on workers wait at most three
seconds, including HttpOnly cookies. Main-thread cookie reads return the cached
value immediately and request a fresh asynchronous read. Cookie domains match
exactly, ignoring case and an optional leading dot; they do not match subdomains.

`obj` exposes the actual `WKWebView` for additional native APIs; access WebKit on
the main thread. Close releases the window, stops loading, and removes delegates
and script handlers. The state handle and detached native view remain available
so racing native readers and polling workers can safely observe the closed state.

The module's tests use blank pages and isolated data stores. They verify
document-start injection, per-window results, navigation resets, HttpOnly cookie
reads, store isolation, worker calls and timeouts, late native readers, and both
programmatic and user close. From the `ui2` repository:

```sh
v test webview
```

Tests briefly create native windows and require a macOS graphical session. No
external login or network access is needed.
