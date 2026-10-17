module ui2

import math
import math.easing

// MotionEasing names the easing curves motion offers: Robert Penner's set,
// the curves Kivy's AnimationTransition names. A custom curve can be supplied
// as a MotionEasingFn wherever an easing is accepted.
pub enum MotionEasing {
	linear
	in_sine
	out_sine
	in_out_sine
	in_quad
	out_quad
	in_out_quad
	in_cubic
	out_cubic
	in_out_cubic
	in_quart
	out_quart
	in_out_quart
	in_quint
	out_quint
	in_out_quint
	in_expo
	out_expo
	in_out_expo
	in_circ
	out_circ
	in_out_circ
	in_back
	out_back
	in_out_back
	in_elastic
	out_elastic
	in_out_elastic
	in_bounce
	out_bounce
	in_out_bounce
}

// MotionEasingFn maps linear progress 0...1 to eased progress. A curve may
// overshoot; opacity, scales and colors clamp the eased value.
pub type MotionEasingFn = fn (f64) f64

// ease applies the curve to linear progress 0...1.
pub fn (curve MotionEasing) ease(progress f64) f64 {
	return match curve {
		.linear { easing.linear(progress) }
		.in_sine { easing.in_sine(progress) }
		.out_sine { easing.out_sine(progress) }
		.in_out_sine { easing.in_out_sine(progress) }
		.in_quad { easing.in_quad(progress) }
		.out_quad { easing.out_quad(progress) }
		.in_out_quad { easing.in_out_quad(progress) }
		.in_cubic { easing.in_cubic(progress) }
		.out_cubic { easing.out_cubic(progress) }
		.in_out_cubic { easing.in_out_cubic(progress) }
		.in_quart { easing.in_quart(progress) }
		.out_quart { easing.out_quart(progress) }
		.in_out_quart { easing.in_out_quart(progress) }
		.in_quint { easing.in_quint(progress) }
		.out_quint { easing.out_quint(progress) }
		.in_out_quint { easing.in_out_quint(progress) }
		.in_expo { easing.in_expo(progress) }
		.out_expo { easing.out_expo(progress) }
		.in_out_expo { easing.in_out_expo(progress) }
		.in_circ { easing.in_circ(progress) }
		.out_circ { easing.out_circ(progress) }
		.in_out_circ { easing.in_out_circ(progress) }
		.in_back { easing.in_back(progress) }
		.out_back { easing.out_back(progress) }
		.in_out_back { easing.in_out_back(progress) }
		.in_elastic { easing.in_elastic(progress) }
		.out_elastic { easing.out_elastic(progress) }
		.in_out_elastic { easing.in_out_elastic(progress) }
		.in_bounce { easing.in_bounce(progress) }
		.out_bounce { easing.out_bounce(progress) }
		.in_out_bounce { easing.in_out_bounce(progress) }
	}
}

// motion_ease prefers a custom curve over a named one.
fn motion_ease(curve MotionEasing, custom MotionEasingFn, progress f64) f64 {
	if voidptr(custom) != unsafe { nil } {
		return custom(progress)
	}
	return curve.ease(progress)
}

fn motion_lerp(start f64, target f64, progress f64) f64 {
	return start * (1 - progress) + target * progress
}

fn motion_unit(value f64) f64 {
	return math.max(0.0, math.min(1.0, value))
}

// interpolate_color mixes two 0xRRGGBB colors channel by channel. Progress
// outside 0...1 is clamped, so an overshooting curve never wraps a channel.
fn interpolate_color(start u32, target u32, progress f64) u32 {
	if progress >= 1 || start == target {
		return target
	}
	if progress <= 0 {
		return start
	}
	r := motion_color_channel(start >> 16, target >> 16, progress)
	g := motion_color_channel(start >> 8, target >> 8, progress)
	b := motion_color_channel(start, target, progress)
	return (r << 16) | (g << 8) | b
}

fn motion_color_channel(start u32, target u32, progress f64) u32 {
	value := motion_lerp(f64(start & 0xff), f64(target & 0xff), progress)
	return u32(math.round(math.max(0.0, math.min(255.0, value))))
}

// MotionSpring is a damped spring, as an easing: progress follows a unit step
// response of a mass on a spring with zero initial velocity. Underdamped
// springs overshoot. motion_spring sets a transition's duration to the
// spring's settle time; with a shorter duration the motion snaps to its target
// when the duration ends.
pub struct MotionSpring {
pub:
	stiffness f64 = 170
	damping   f64 = 26
	mass      f64 = 1
}

pub fn (spring MotionSpring) validate() ! {
	if !finite_number(spring.stiffness) || spring.stiffness <= 0 || !finite_number(spring.damping)
		|| spring.damping <= 0 || !finite_number(spring.mass) || spring.mass <= 0 {
		return error('a motion spring needs positive finite stiffness, damping and mass')
	}
}

// position is how far the spring has moved toward its target after seconds.
pub fn (spring MotionSpring) position(seconds f64) f64 {
	if seconds <= 0 {
		return 0
	}
	omega := math.sqrt(spring.stiffness / spring.mass)
	zeta := spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass))
	t := seconds
	if zeta < 1 {
		damped := omega * math.sqrt(1 - zeta * zeta)
		decay := math.exp(-zeta * omega * t)
		return 1 - decay * (math.cos(damped * t) + zeta * omega / damped * math.sin(damped * t))
	}
	if zeta == 1 {
		return 1 - math.exp(-omega * t) * (1 + omega * t)
	}
	root := math.sqrt(zeta * zeta - 1)
	slow := -omega * (zeta - root)
	fast := -omega * (zeta + root)
	return 1 - (fast * math.exp(slow * t) - slow * math.exp(fast * t)) / (fast - slow)
}

// settle_time is the seconds until the spring stays within 0.1% of its
// target, at least 50 ms and at most 10 s.
pub fn (spring MotionSpring) settle_time() f64 {
	spring.validate() or { return 0 }
	omega := math.sqrt(spring.stiffness / spring.mass)
	zeta := spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass))
	epsilon := 0.001
	mut seconds := 0.0
	if zeta < 1 {
		damped := omega * math.sqrt(1 - zeta * zeta)
		amplitude := math.sqrt(1 + math.pow(zeta * omega / damped, 2))
		seconds = math.log(amplitude / epsilon) / (zeta * omega)
	} else {
		// The response is monotonic: bisect for the instant it is close enough.
		mut low := 0.0
		mut high := 1.0
		for spring.position(high) < 1 - epsilon && high < 10 {
			high *= 2
		}
		for _ in 0 .. 48 {
			middle := (low + high) / 2
			if spring.position(middle) < 1 - epsilon {
				low = middle
			} else {
				high = middle
			}
		}
		seconds = high
	}
	return math.max(0.05, math.min(10.0, seconds))
}
