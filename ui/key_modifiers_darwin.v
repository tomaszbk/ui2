// The macOS host's key modifiers (platform.v), read from NSEvent.
module ui2

import macos

fn host_key_modifiers(_last_event KeyModifiers) KeyModifiers {
	flags := macos.msg_u64(macos.get_class('NSEvent'), 'modifierFlags')
	return KeyModifiers{
		shift: flags & (u64(1) << 17) != 0
		ctrl:  flags & (u64(1) << 18) != 0
		alt:   flags & (u64(1) << 19) != 0
		cmd:   flags & (u64(1) << 20) != 0
	}
}
