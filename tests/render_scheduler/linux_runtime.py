#!/usr/bin/env python3
"""Bounded X11 runtime acceptance; run in Xvfb with an already compiled fixture.

Usage: python3 tests/render_scheduler/linux_runtime.py /outputs/acceptance /outputs
No dependencies beyond Python stdlib, libX11, xdotool and the runner's PNG helper.
The fixture's UI thread exports state after F1; no worker mutates UI. Screenshots
are taken while the app continues, then WM_DELETE_WINDOW verifies idle teardown.
"""
import ctypes as c
import json
import pathlib
import subprocess
import sys
import time
import struct
import zlib

binary, output = sys.argv[1], pathlib.Path(sys.argv[2])
state_file = output / 'platform-state.json'
log = (output / 'platform.log').open('w')
# Keep one connection alive: Xvfb otherwise resets the keyboard map when the
# xmodmap client exits before the application opens its own connection.
keyboard_x = c.CDLL('libX11.so.6')
keyboard_x.XOpenDisplay.argtypes = [c.c_char_p]
keyboard_x.XOpenDisplay.restype = c.c_void_p
keyboard_x.XCloseDisplay.argtypes = [c.c_void_p]
keyboard_x.XInternAtom.argtypes = [c.c_void_p, c.c_char_p, c.c_int]
keyboard_x.XInternAtom.restype = c.c_ulong
keyboard_x.XSendEvent.argtypes = [c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.c_void_p]
keyboard_x.XSendEvent.restype = c.c_int
keyboard_x.XSync.argtypes = [c.c_void_p, c.c_int]
keyboard_display = keyboard_x.XOpenDisplay(None)
assert keyboard_display, 'missing X11 display'
# Install persistent Spanish keysyms before Sokol constructs its key table.
# xdotool's temporary Unicode remaps can be removed before XLookupString reads
# a queued event; that would test the remapper rather than a real keyboard.
subprocess.run(['xmodmap', '-e', 'keycode 51 = ntilde Ntilde', '-e', 'keycode 94 = eacute Eacute'], check=True)
app = subprocess.Popen([binary, '--state-file', str(state_file), '--reopen'], stdout=log, stderr=log)


def xd(*args):
    return subprocess.check_output(['xdotool', *map(str, args)], text=True).strip()


class ClientMessageData(c.Union):
    _fields_ = [('b', c.c_char * 20), ('s', c.c_short * 10), ('l', c.c_long * 5)]


class ClientMessage(c.Structure):
    _fields_ = [('type', c.c_int), ('serial', c.c_ulong), ('send_event', c.c_int),
               ('display', c.c_void_p), ('window', c.c_ulong),
               ('message_type', c.c_ulong), ('format', c.c_int), ('data', ClientMessageData)]


class XEvent(c.Union):
    _fields_ = [('client', ClientMessage), ('pad', c.c_long * 24)]


def request_window_close(window):
    # Send the same ICCCM message as a window manager. No F4/ui2.quit, extra
    # input or scheduler invalidation may rescue a blocked idle frame.
    event = XEvent()
    event.client.type = 33  # ClientMessage
    event.client.display = keyboard_display
    event.client.window = window
    event.client.message_type = keyboard_x.XInternAtom(keyboard_display, b'WM_PROTOCOLS', 0)
    event.client.format = 32
    event.client.data.l[0] = keyboard_x.XInternAtom(keyboard_display, b'WM_DELETE_WINDOW', 0)
    event.client.data.l[1] = 0  # CurrentTime
    assert keyboard_x.XSendEvent(keyboard_display, window, 0, 0, c.byref(event)), 'close send failed'
    keyboard_x.XSync(keyboard_display, 0)


def snapshot():
    before = json.loads(state_file.read_text())['serial'] if state_file.exists() else 0
    xd('key', 'F1')
    for _ in range(1000):
        time.sleep(.03)
        try:
            value = json.loads(state_file.read_text())
            if value['serial'] > before:
                return value
        except (FileNotFoundError, json.JSONDecodeError):
            pass
    raise RuntimeError('UI state snapshot timed out')


def capture(name, width=640, height=480):
    path = output / (name + '.png')
    subprocess.run(['python3', '/runner/x11_capture.py', str(path)], check=True)
    # Independent pixel check: these scenes use light opaque backgrounds and
    # navy text, so no pure black pixel belongs inside the undecorated window.
    # The black Xvfb desktop outside its rectangle is deliberately excluded.
    png = path.read_bytes()
    at, data, screen_width = 8, bytearray(), None
    while at < len(png):
        size = struct.unpack('>I', png[at:at + 4])[0]
        tag, body = png[at + 4:at + 8], png[at + 8:at + 8 + size]
        if tag == b'IHDR':
            screen_width = struct.unpack('>I', body[:4])[0]
            assert body[8:10] == bytes([8, 2]), 'expected RGB PNG'
        elif tag == b'IDAT':
            data.extend(body)
        at += 12 + size
    rows = zlib.decompress(data)
    stride = 1 + screen_width * 3
    for y in range(height):
        assert rows[y * stride] == 0, 'runner encoder uses unfiltered rows'
        line = rows[y * stride + 1:y * stride + 1 + width * 3]
        assert all(line[x:x + 3] != b'\0\0\0' for x in range(0, len(line), 3)), (name, 'black pixels inside window', y)
    # The four known texture quadrants must survive restore and a new GL
    # context. An empty image on an intact background would evade a black check.
    for x, y, expected in [(560, 156, (239, 68, 68)), (576, 156, (16, 185, 129)),
                            (560, 172, (59, 130, 246)), (576, 172, (245, 158, 11))]:
        actual = rows[y * stride + 1 + x * 3:y * stride + 1 + x * 3 + 3]
        assert all(abs(a - b) <= 3 for a, b in zip(actual, expected)), (name, 'missing/stale texture', tuple(actual), expected)
    print('PASS complete image', name, width, height, flush=True)


def idle_after(phase):
    time.sleep(1.2)
    snapshot()
    # F1 itself invalidates; settle its frame before comparing observations.
    time.sleep(1.2)
    first_log = (output / 'platform.log').read_text()
    time.sleep(2.1)
    last_log = (output / 'platform.log').read_text()[len(first_log):]
    lines = [line for line in last_log.splitlines() if line.startswith('interactive')]
    assert lines, (phase, 'missing synchronized observation')
    for line in lines:
        values = dict(item.split('=') for item in line.split() if '=' in item)
        for key in ['loop_callbacks', 'callbacks', 'builds', 'draws', 'event_wakeups', 'worker_wakeups', 'deadline_wakeups']:
            assert int(values[key]) == 0, (phase, line)
    print('PASS idle after', phase, flush=True)


def await_presentation(log_start, phase):
    """Observe completed painting and two settled samples without injecting input.

    Software GL under contention can take longer than a fixed screenshot delay.
    A blocked callback with unfinished work must not qualify as settled.
    """
    deadline = time.monotonic() + 30
    seen_draw, settled = False, 0
    processed = 0
    while time.monotonic() < deadline:
        lines = (output / 'platform.log').read_text()[log_start:].splitlines()
        for line in lines[processed:]:
            if not line.startswith('interactive'):
                continue
            values = dict(item.split('=') for item in line.split() if '=' in item)
            seen_draw |= int(values['draws']) > 0
            quiet = all(int(values[key]) == 0 for key in ['loop_callbacks', 'callbacks', 'builds', 'draws'])
            quiet &= values['pending'] == 'false' and values['in_flight'] == 'false'
            settled = settled + 1 if seen_draw and quiet else 0
            if settled >= 2:
                print('PASS completed presentation and idle', phase, flush=True)
                return
        processed = len(lines)
        if app.poll() is not None:
            raise RuntimeError('fixture exited during ' + phase)
        time.sleep(.1)
    raise RuntimeError('presentation did not settle after ' + phase)


try:
    window = None
    for _ in range(150):
        found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^UI2 renderer scheduler acceptance$'], capture_output=True, text=True)
        if found.returncode == 0:
            window = int(found.stdout.splitlines()[0])
            break
        if app.poll() is not None:
            raise RuntimeError('fixture exited before mounting')
        time.sleep(.1)
    assert window, 'missing visible fixture window'
    xd('windowfocus', window)
    ready = snapshot()
    assert ready['stats']['draws'] > 0, 'wait for the first complete presentation'
    time.sleep(.2)
    capture('initial')

    # One pointer movement, then wait without further input for the tooltip.
    xd('mousemove', '--window', window, 80, 64)
    time.sleep(.2)
    capture('before-tooltip')
    time.sleep(.7)
    capture('tooltip')
    tooltip = snapshot()
    assert tooltip['stats']['deadline_wakeups'] > 0
    idle_after('stationary tooltip')

    xd('mousemove', '--window', window, 80, 110)
    xd('click', 1)
    xd('type', '--clearmodifiers', '--delay', 35, 'Hello / Hola, año, café')
    xd('key', 'shift+Left', 'shift+Left', 'shift+Left', 'shift+Left')
    edited = snapshot()
    assert edited['editor'] == 'Hello / Hola, año, café', edited
    assert edited['selection'] == 4 and edited['focused'] == 'editor', edited
    xd('key', 'BackSpace')
    xd('type', '--clearmodifiers', '--delay', 35, 'café')
    xd('key', 'shift+Left', 'shift+Left', 'shift+Left', 'shift+Left')
    assert snapshot()['editor'] == edited['editor'], 'selection replacement lost UTF-8 text'
    xd('key', 'F2')
    time.sleep(1.2)  # worker posts without moving pointer or sending more keys
    delivered = snapshot()
    assert delivered['message'] == 'Worker delivered on UI thread'
    for key in ['editor', 'selection', 'caret', 'focused']:
        assert delivered[key] == edited[key], (key, edited, delivered)
    capture('worker-edit-preserved')
    idle_after('worker and Spanish edit/selection')

    xd('mousemove', '--window', window, 90, 300)
    xd('click', '--repeat', 4, '--delay', 80, 5)
    scrolled = snapshot()
    assert scrolled['scroll'] > 0, scrolled
    xd('key', 'F2')
    time.sleep(1.2)
    assert snapshot()['scroll'] == scrolled['scroll']
    idle_after('scroll')

    xd('mousemove', '--window', window, 175, 165)
    xd('mousedown', 1)
    xd('mousemove', '--window', window, 550, 195)
    time.sleep(.15)
    xd('mouseup', 1)
    dragged = snapshot()
    assert dragged['drags'] > 0 and dragged['releases'] > 0, dragged
    idle_after('pointer capture outside original bounds')

    xd('key', 'F3')
    time.sleep(1.5)
    assert snapshot()['animation_completed']
    capture('animation-complete')
    idle_after('animation')

    before_resize = snapshot()
    time.sleep(.2)
    resize_log_start = len((output / 'platform.log').read_text())
    xd('windowsize', window, 780, 560)
    await_presentation(resize_log_start, 'resize')
    capture('resized', 780, 560)
    resized = snapshot()
    for key in ['editor', 'selection', 'caret', 'focused', 'scroll']:
        assert resized[key] == before_resize[key], ('resize', key, before_resize, resized)
    idle_after('resize')

    # Xvfb has no window manager. Set ICCCM WM_STATE and actually unmap/map the
    # window to exercise Sokol's PropertyNotify iconify/restore path. This is
    # not compositor or GPU context-loss acceptance.
    x = c.CDLL('libX11.so.6')
    x.XOpenDisplay.argtypes = [c.c_char_p]; x.XOpenDisplay.restype = c.c_void_p
    x.XInternAtom.argtypes = [c.c_void_p, c.c_char_p, c.c_int]; x.XInternAtom.restype = c.c_ulong
    x.XChangeProperty.argtypes = [c.c_void_p, c.c_ulong, c.c_ulong, c.c_ulong, c.c_int, c.c_int, c.c_void_p, c.c_int]
    for name in ['XUnmapWindow', 'XMapWindow']:
        getattr(x, name).argtypes = [c.c_void_p, c.c_ulong]
    x.XSync.argtypes = [c.c_void_p, c.c_int]; x.XCloseDisplay.argtypes = [c.c_void_p]
    display = x.XOpenDisplay(None)
    atom = x.XInternAtom(display, b'WM_STATE', 0)
    def window_state(state):
        value = (c.c_ulong * 2)(state, 0)
        x.XChangeProperty(display, window, atom, atom, 32, 0, value, 2)
        (x.XUnmapWindow if state == 3 else x.XMapWindow)(display, window)
        x.XSync(display, 0)
    before_hide = snapshot()
    xd('key', 'F2')  # business callback must still be delivered while hidden
    hidden_log_start = len((output / 'platform.log').read_text())
    window_state(3)
    time.sleep(2.2)
    hidden_lines = (output / 'platform.log').read_text()[hidden_log_start:].splitlines()
    assert any(line.startswith('interactive suspended=true:') and 'builds=0 draws=0' in line for line in hidden_lines), hidden_lines
    restore_log_start = len((output / 'platform.log').read_text())
    window_state(1)
    await_presentation(restore_log_start, 'restoration')
    xd('windowfocus', window)
    capture('restored', 780, 560)
    x.XCloseDisplay(display)
    restored = snapshot()
    assert restored['message'] == 'Worker delivered on UI thread'
    for key in ['editor', 'selection', 'caret', 'focused', 'scroll']:
        assert restored[key] == before_hide[key], ('restoration', key, before_hide, restored)
    assert not restored['stats']['suspended']
    idle_after('unmap/map restoration')
    request_window_close(window)
    # Reopened window has a genuinely new GL context, not just an exposed
    # backbuffer. Find it and inspect its first complete retained presentation.
    window = None
    for _ in range(300):
        found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--name', '^UI2 renderer scheduler acceptance recreated$'], capture_output=True, text=True)
        if found.returncode == 0:
            window = int(found.stdout.splitlines()[0])
            break
        if app.poll() is not None:
            raise RuntimeError('fixture exited before context recreation')
        time.sleep(.1)
    assert window, 'missing recreated context window'
    xd('windowfocus', window)
    recreated = snapshot()
    assert recreated['message'] == 'New GL context after normal close'
    assert recreated['stats']['draws'] > 0, 'new context must finish its first paint'
    capture('context-recreated')
    idle_after('GL context recreation')
    request_window_close(window)
    assert app.wait(timeout=10) == 0
    print('PASS X11 input, stationary deadline, worker, identity/edit/selection/scroll, capture, animation, resize/restore, idle WM_DELETE_WINDOW recreation and exit')
finally:
    if app.poll() is None:
        app.kill()
        app.wait()
    log.close()
    keyboard_x.XCloseDisplay(keyboard_display)
