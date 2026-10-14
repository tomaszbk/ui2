"""A ui2 app using only Python's standard library and the C ABI.

Build the library with `make c-api`, then run this file. Pass --validate to
exercise the Python callbacks and foreign handles without opening a window.
"""

import ctypes as C
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
name = {"darwin": "libui2.dylib", "win32": "ui2.dll"}.get(sys.platform, "libui2.so")
ui2 = C.CDLL(str(root / "build" / "c" / name))

Build = C.CFUNCTYPE(C.c_void_p, C.c_void_p)
class ElementEvent(C.Structure):
    _fields_ = [
        ("kind", C.c_int), ("id", C.c_char_p), ("x", C.c_double), ("y", C.c_double),
        ("text", C.c_char_p), ("value", C.c_double), ("checked", C.c_int),
        ("target", C.c_char_p),
    ]


Event = C.CFUNCTYPE(None, C.c_void_p, C.POINTER(ElementEvent))
Key = C.CFUNCTYPE(None, C.c_void_p, C.c_char_p)


class Config(C.Structure):
    _fields_ = [
        ("title", C.c_char_p), ("width", C.c_int), ("height", C.c_int),
        ("build", Build), ("user_data", C.c_void_p), ("key", Key),
    ]


ui2.ui2_create.argtypes = [C.c_int, C.c_char_p] + [C.c_double] * 4
ui2.ui2_create.restype = C.c_void_p
ui2.ui2_add.argtypes = [C.c_void_p, C.c_void_p]
ui2.ui2_add.restype = None
ui2.ui2_set_text.argtypes = [C.c_void_p, C.c_char_p]
ui2.ui2_set_text.restype = None
ui2.ui2_set_flags.argtypes = [C.c_void_p, C.c_uint32]
ui2.ui2_set_flags.restype = None
ui2.ui2_set_events.argtypes = [C.c_void_p, Event, C.c_void_p]
ui2.ui2_set_events.restype = None
ui2.ui2_run.argtypes = [C.POINTER(Config)]
ui2.ui2_run.restype = C.c_int
ui2.ui2_validate.argtypes = [C.POINTER(Config)]
ui2.ui2_validate.restype = C.c_int
ui2.ui2_last_error.argtypes = []
ui2.ui2_last_error.restype = C.c_char_p

count = 0


@Build
def build(_user_data):
    screen = ui2.ui2_create(0, None, 0, 0, 0, 0)
    label = ui2.ui2_create(2, b"count", 20, 16, 240, 30)
    ui2.ui2_set_text(label, f"Count: {count}".encode("utf-8"))
    button = ui2.ui2_create(4, b"increment", 20, 56, 240, 40)
    ui2.ui2_set_text(button, b"Increment")
    ui2.ui2_set_flags(button, 1)  # UI2_NATIVE
    ui2.ui2_set_events(button, increment, None)
    ui2.ui2_add(screen, label)
    ui2.ui2_add(screen, button)
    return screen


@Event
def increment(_user_data, event):
    global count
    if event.contents.kind == 0:  # UI2_EVENT_CLICK
        count += 1


# Keep the callbacks and config alive for the entire ui2_run call.
config = Config(title=b"Counter from Python", width=280, height=120,
                build=build)
entry = ui2.ui2_validate if "--validate" in sys.argv else ui2.ui2_run
if entry(C.byref(config)) != 0:
    raise RuntimeError(ui2.ui2_last_error().decode("utf-8"))
