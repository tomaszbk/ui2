// vfmt off
@[has_globals]
module ui2

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
 __global scaled_callback_events = []ElementEvent{}
 fn capture_scaled_callback_event(event ElementEvent) { scaled_callback_events << event }
 fn test_scaled_hit_clipping_and_inverse_slider() {
 	mut w := &Window{}
  previous := w.ctx
  w.ctx = &DrawContext{content_transform:ContentTransform{xx: 0.5, yy: 0.5,y:60}}
  defer { w.ctx = previous; w.hit_targets = []HitTarget{} }
  w.hit_targets = []HitTarget{}
  w.add_hit_target(HitTarget{id:'inside',x:-20,y:100,w:120,h:40},rect(0,0,1280,720))
  assert w.hit_test(20,115).id == 'inside'
  assert w.hit_test(20,30).id == ''
  target := HitTarget{slider:true,slider_frame:rect(100,100,200,40),slider_spec:SliderSpec{min:0,max:100},content_transform:ContentTransform{xx: 0.5, yy: 0.5,y:60}}
  assert w.slider_target_value(target,100,120) == 50
  scaled_callback_events = []ElementEvent{}
  w.fire_pointer_event(.pointer_drag,HitTarget{id:'move',on_event:capture_scaled_callback_event,content_transform:ContentTransform{xx: 0.5, yy: 0.5,y:60}},36,92)
  assert scaled_callback_events == [ElementEvent{window:w,kind:.pointer_drag,id:'move',x:72,y:64}]
 }

 fn test_scaled_scroll_keeps_logical_offsets() {
 	mut w := &Window{}
  previous := w.ctx
  w.ctx = &DrawContext{content_transform:ContentTransform{xx: 0.5, yy: 0.5,y:60}}
  defer { w.ctx = previous; w.reset_scroll_frame(); w.scroll_offsets.clear() }
  w.reset_scroll_frame()
  w.scroll_offsets.clear()
  w.register_scroll_view_in_parent(named_scroll_state_id('pane'), '',rect(0,0,200,100),rect(0,0,1280,720),300,true,true,false,HitTarget{})
  assert w.scroll_hit_test(40,80) == named_scroll_state_id('pane')
  assert w.scroll_hit_test(40,20) == ''
  w.apply_scroll_vector([named_scroll_state_id('pane')],0,25)
  assert w.scroll_offset('pane') == 50
  assert w.scroll_maximum(named_scroll_state_id('pane')) == 200
 }
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
 struct ScaledFixtureModel {
pub:
 title string = 'Fixed title'
 }
 fn test_model_vml_fixed_composition_does_not_reflow() {

  mut fixture_model_2 := ScaledFixtureModel{}
  a := compiled_scaled_content_immediate_1(mut fixture_model_2, rect(0,0,640,360))
  mut fixture_model_1 := ScaledFixtureModel{}
  b := compiled_scaled_content_immediate_0(mut fixture_model_1, rect(0,0,1440,900))
  assert a.children[0].children[0].frame == b.children[0].children[0].frame
  assert a.children[0].children[0].frame.width == 1280
  assert a.children[0].children[0].children[0].text == 'Fixed title'
 }
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
 fn test_scroll_transform_snapshots_do_not_cross_windows() {
  mut first := &Window{ctx: &DrawContext{content_transform:ContentTransform{xx: 0.5, yy: 0.5}}}
  mut second := &Window{ctx: &DrawContext{content_transform:ContentTransform{xx: 2, yy: 2}}}
  first.register_scroll_view_in_parent(named_scroll_state_id('pane'), '',rect(0,0,200,100),rect(0,0,200,100),300,true,true,false,HitTarget{})
  second.register_scroll_view_in_parent(named_scroll_state_id('pane'), '',rect(0,0,200,100),rect(0,0,200,100),300,true,true,false,HitTarget{})
  second.apply_scroll_vector([named_scroll_state_id('pane')],0,20)
  assert second.scroll_offset('pane') == 10
  first.apply_scroll_vector([named_scroll_state_id('pane')],0,20)
  assert first.scroll_offset('pane') == 40
  assert first.scroll_transforms[named_scroll_state_id('pane')].xx == 0.5
  assert second.scroll_offset('pane') == 10
  assert second.scroll_transforms[named_scroll_state_id('pane')].xx == 2
 }

}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {
 fn test_scaled_visual_states_use_inverse_pointer_and_keep_hit_bounds() {
 	mut w := &Window{}
  previous_tooltip := w.tooltip
  previous_touch := w.touch
  previous_focus := w.focused_field
  defer { w.tooltip = previous_tooltip; w.touch = previous_touch; w.focused_field = previous_focus }
  transform := ContentTransform{xx: 0.5, yy: 0.5,y:60}
  frame := rect(100,100,200,40)
  el := with_interaction_style(button('next','Next',frame,BoxStyle{},TextStyle{}),InteractionStyle{
   hover:BoxStylePatch{bg:u32(0x00ff00)}
   focus:BoxStylePatch{outline_width:f64(3),outline_offset:f64(3)}
   pressed:BoxStylePatch{bg:u32(0xff0000)}
   hover_text:TextStylePatch{color:u32(0)}
  })
  w.tooltip = TooltipState{pointer_in:true,pointer_x:100,pointer_y:120}
  w.touch = TouchState{}
  w.focused_field = ''
  hover := w.resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform)
  assert hover.box.bg == 0x00ff00 && hover.text_style.color == 0
  assert hover.frame == frame && hover.text_style.size == 15
  // Letterbox and a parent clip exclude the same inverse pointer.
  assert w.resolve_custom_visual_style(el,frame,rect(0,0,80,720),transform).box.bg == el.box.bg
  w.tooltip.pointer_y = 30
  assert w.resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform).box.bg == el.box.bg
  // A touch press need not have generated a mouse hover event.
  w.touch = TouchState{down:true,current_x:100,current_y:120,pressed_id:'next'}
  w.tooltip.pointer_in = false
  assert w.resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform).box.bg == 0xff0000
  w.focused_field = 'next'
  focused := w.resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform)
  assert focused.box.outline_width == 3 && focused.frame == frame
 }
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {

fn compiled_scaled_content_immediate_0(mut app ScaledFixtureModel, frame Rect) Element {
	return $vml('fixtures/scaled_content_immediate_0.vml', frame)
}
}

$if (android || ios || linux || macos || windows) && !ui2_headless ? {

fn compiled_scaled_content_immediate_1(mut app ScaledFixtureModel, frame Rect) Element {
	return $vml('fixtures/scaled_content_immediate_1.vml', frame)
}
}
