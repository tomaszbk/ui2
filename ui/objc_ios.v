module ui2

import dl
import macos

// Objective-C runtime helpers the iOS host services share (platform.v).
// Nothing here may be written in Objective-C: V compiles the generated
// sources with -fobjc-arc on iOS, and ARC rejects the manual retain and
// release calls the services are built on.

// UIKit and AVFoundation publish their constants as exported symbols
// instead of compile time values, so they are read from the running
// process. The literals are only a fallback for a symbol that cannot be
// resolved.
const rtld_default = voidptr(-2)

fn extern_symbol(name string) voidptr {
	return dl.sym(rtld_default, name)
}

fn extern_id(name string, fallback string) macos.Id {
	address := extern_symbol(name)
	if address != unsafe { nil } {
		value := unsafe { *(&voidptr(address)) }
		if value != unsafe { nil } {
			return value
		}
	}
	return macos.nsstring(fallback)
}

@[inline]
fn objc_nil() macos.Id {
	return unsafe { nil }
}

@[inline]
fn objc_is_nil(object macos.Id) bool {
	return object == unsafe { nil }
}

@[inline]
fn objc_is_kind_of(object macos.Id, class_name string) bool {
	return !objc_is_nil(object)
		&& macos.msg_bool_id(object, 'isKindOfClass:', macos.get_class(class_name))
}

fn objc_string(object macos.Id) string {
	if !objc_is_kind_of(object, 'NSString') {
		return ''
	}
	return macos.utf8_string(object)
}

// ios_root_view_controller is the root view controller of the key window:
// the one sokol_app installs over its Metal view.
fn ios_root_view_controller() macos.Id {
	app := macos.msg_id(macos.get_class('UIApplication'), 'sharedApplication')
	if objc_is_nil(app) {
		return objc_nil()
	}
	mut window := macos.msg_id(app, 'keyWindow')
	if objc_is_nil(window) {
		windows := macos.msg_id(app, 'windows')
		if !objc_is_nil(windows) && macos.msg_u64(windows, 'count') > 0 {
			window = macos.msg_id(windows, 'firstObject')
		}
	}
	if objc_is_nil(window) {
		return objc_nil()
	}
	return macos.msg_id(window, 'rootViewController')
}

// top_view_controller is the controller a new one has to be presented from:
// UIKit refuses to present over a controller that is already presenting.
fn top_view_controller(root macos.Id) macos.Id {
	if objc_is_nil(root) {
		return root
	}
	presented := macos.msg_id(root, 'presentedViewController')
	return if objc_is_nil(presented) { root } else { top_view_controller(presented) }
}

// ── Objective-C blocks ─────────────────────────────────────────────

// A few UIKit APIs report their result through a block and nothing else. A
// block is only a struct the ABI knows how to call, so V can lay one out: an
// isa marking it global — no captured state, so copying it is a no-op — the C
// function to run, and a descriptor holding its size and type encoding. State
// a real block would capture lives in globals instead.
const block_is_global = int(u32(1) << 28)

const block_has_signature = int(u32(1) << 30)

struct BlockDescriptor {
mut:
	reserved  u64
	size      u64
	signature voidptr // const char *
}

struct BlockLiteral {
mut:
	isa        voidptr
	flags      int
	reserved   int
	invoke     voidptr
	descriptor voidptr // struct BlockDescriptor *
}

// GlobalBlock owns the storage a block needs for as long as UIKit may call
// it, which is why it is only ever used through a global.
struct GlobalBlock {
mut:
	descriptor BlockDescriptor
	literal    BlockLiteral
}

// build returns a callable block for `invoke`, an ordinary C function whose
// first parameter is the block itself. `signature` is the Objective-C type
// encoding of that function and has to outlive the block, so it must be a
// literal or a const.
fn (mut block GlobalBlock) build(invoke voidptr, signature string) voidptr {
	if block.literal.invoke != unsafe { nil } {
		return voidptr(&block.literal)
	}
	isa := extern_symbol('_NSConcreteGlobalBlock')
	if isa == unsafe { nil } {
		return unsafe { nil }
	}
	block.descriptor = BlockDescriptor{
		reserved:  0
		size:      u64(sizeof(BlockLiteral))
		signature: voidptr(signature.str)
	}
	block.literal = BlockLiteral{
		isa:        isa
		flags:      block_is_global | block_has_signature
		reserved:   0
		invoke:     invoke
		descriptor: voidptr(&block.descriptor)
	}
	return voidptr(&block.literal)
}
