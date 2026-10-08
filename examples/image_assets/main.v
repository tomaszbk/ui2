module main

import os
import ui2

fn asset_path(name string) string {
	return os.join_path(os.dir(@FILE), 'assets', name)
}

fn caption(text string, x f64, y f64, w f64) ui2.Element {
	return ui2.label('', text, ui2.rect(x, y, w, 24), ui2.TextStyle{ size: 13, color: 0x334155 })
}

fn tile(id string, path string, frame ui2.Rect, style ui2.ImageStyle, rotation f64) ui2.Element {
	return ui2.Element{ ...ui2.image(id, path, frame), image_style: style, rotation: rotation }
}

fn build() ui2.Element {
	mut children := [caption('Image fits · logical frames 100 × 100 · source 96 × 48', 24, 16, 720)]
	for i, fit in [ui2.ImageFit.contain, .cover, .fill, .none, .scale_down] {
		x := 24.25 + f64(i) * 140
		children << ui2.view('', ui2.rect(x, 54.5, 100, 100), ui2.BoxStyle{ bg: 0xdbe4ef }, [])
		children << tile('fit${i}', asset_path('pattern.png'), ui2.rect(x, 54.5, 100, 100), ui2.ImageStyle{ fit: fit }, 0)
		children << caption(fit.str(), x, 162, 120)
	}
	children << caption('Source crop · clockwise rotation · alpha × tint · adjacent atlas entries', 24, 205, 720)
	children << tile('crop', asset_path('pattern.png'), ui2.rect(24.25, 245.5, 100, 100),
		ui2.ImageStyle{ source: ui2.rect(0.5, 0, 0.5, 1) }, 0)
	children << tile('rotate', asset_path('pattern.png'), ui2.rect(164.25, 245.5, 100, 100), ui2.ImageStyle{}, 45)
	children << ui2.view('', ui2.rect(304.25, 245.5, 100, 100), ui2.BoxStyle{ bg: 0x204060 }, [])
	children << tile('tint', asset_path('alpha.png'), ui2.rect(304.25, 245.5, 100, 100),
		ui2.ImageStyle{ tint: ui2.ImageTint{ r: 128, g: 192, b: 255, a: 128 } }, 0)
	children << tile('neighbor_red', asset_path('red.png'), ui2.rect(452.25, 254.5, 64, 64), ui2.ImageStyle{}, 23)
	children << tile('neighbor_green', asset_path('green.png'), ui2.rect(556.25, 254.5, 64, 64), ui2.ImageStyle{}, -23)
	children << caption('right half', 24, 362, 120)
	children << caption('45°', 164, 362, 120)
	children << caption('50% tint alpha', 304, 362, 140)
	children << caption('red / green, no bleed', 450, 362, 240)
	children << caption('DPI variants · 1x red / 2x green / 3x blue · content scales 0.5, 1, 1.5, 3', 24, 410, 730)
	asset := ui2.ImageAsset{
		logical_size: ui2.LayoutSize{ width: 32, height: 16 }
		variants:     [
			ui2.ImageVariant{ path: asset_path('variant2.png'), density: 2 },
			ui2.ImageVariant{ path: asset_path('variant3.png'), density: 3 },
		]
	}
	for i, scale in [0.5, 1.0, 1.5, 3.0] {
		x := 24.25 + f64(i) * 180
		el := ui2.Element{ ...ui2.image('dpi${i}', asset_path('variant1.png'), ui2.rect(0, 0, 32, 16)), image_asset: asset }
		children << ui2.scaled_content('', ui2.rect(x, 460.5, 32 * scale, 16 * scale), 32, 16,
			ui2.BoxStyle{ transparent: true }, [el])
		children << caption('scale ${scale}', x, 520, 160)
	}
	return ui2.screen(0xf8fafc, children)
}

fn main() {
	$if !( linux || android || ( ( macos || windows ) && ui2_custom_rendering ?) ) {
		eprintln('Run image_assets with -d ui2_custom_rendering (see docs/images-assets.md).')
		return
	}
	ui2.run_window('UI2 image assets', 760, 570, build)
}
