module main

import ui2

const carousel_width = 460
const carousel_height = 340

pub struct CarouselDemo {
pub mut:
	index int
}

pub fn (mut app CarouselDemo) previous() {
	app.index = ui2.carousel_previous(app.index, 3, true)
}

pub fn (mut app CarouselDemo) next() {
	app.index = ui2.carousel_next(app.index, 3, true)
}

fn main() {
	mut app := CarouselDemo{}
	ui2.run_compiled_vml[CarouselDemo](
		build:  build_carousel
		model:  &app
		title:  'Carousel'
		width:  carousel_width
		height: carousel_height
	) or { panic(err) }
}

fn build_carousel(mut app CarouselDemo) ui2.Element {
	return $vml('carousel.vml')
}

fn carousel_tree(mut app CarouselDemo, frame ui2.Rect) ui2.Element {
	return $vml('carousel.vml', frame)
}
