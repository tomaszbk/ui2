// vtest vflags: -d ui2_custom_rendering
// vfmt off
@[has_globals]
module ui2

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
 fn test_scaled_hit_clipping_and_inverse_slider() {
  previous := g_gg_app.ctx
  g_gg_app.ctx = &DrawContext{content_transform:ContentTransform{scale:0.5,y:60}}
  defer { g_gg_app.ctx = previous; g_hit_targets = []HitTarget{} }
  g_hit_targets = []HitTarget{}
  add_hit_target(HitTarget{id:'inside',x:-20,y:100,w:120,h:40},rect(0,0,1280,720))
  assert hit_test(20,115).id == 'inside'
  assert hit_test(20,30).id == ''
  target := HitTarget{slider:true,slider_frame:rect(100,100,200,40),slider_spec:SliderSpec{min:0,max:100},content_transform:ContentTransform{scale:0.5,y:60}}
  assert slider_target_value(target,100,120) == 50
  assert target_pointer_event_id('drag',HitTarget{action_id:'move',content_transform:ContentTransform{scale:0.5,y:60}},36,92) == 'pointer:drag:move:72.0:64.0'
 }

 fn test_scaled_scroll_keeps_logical_offsets() {
  previous := g_gg_app.ctx
  g_gg_app.ctx = &DrawContext{content_transform:ContentTransform{scale:0.5,y:60}}
  defer { g_gg_app.ctx = previous; reset_scroll_frame(); g_scroll_offsets.clear() }
  reset_scroll_frame()
  g_scroll_offsets.clear()
  register_scroll_view('pane',rect(0,0,200,100),rect(0,0,1280,720),300,true,true,false)
  assert scroll_hit_test(40,80) == 'pane'
  assert scroll_hit_test(40,20) == ''
  apply_scroll_chain(['pane'],25)
  assert scroll_offset('pane') == 50
  assert scroll_maximum('pane') == 200
 }
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
 struct ScaledFixtureModel {
pub:
 title string = 'Fixed title'
 }
 fn test_model_vml_fixed_composition_does_not_reflow() {
  source := 'Screen { units: "logical" ScaledContent { content_width: 1280 content_height: 720 Column { Label { text: app.title height: 42 } View { height: 100 } } } }'
  a := element_from_vml_model(source,ScaledFixtureModel{},rect(0,0,640,360))!
  b := element_from_vml_model(source,ScaledFixtureModel{},rect(0,0,1440,900))!
  assert a.children[0].children[0].frame == b.children[0].children[0].frame
  assert a.children[0].children[0].frame.width == 1280
  assert a.children[0].children[0].children[0].text == 'Fixed title'
 }
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
 fn test_scroll_transform_snapshots_do_not_cross_windows() {
  original := g_gg_app.ctx
  first := new_custom_window_state()
  second := new_custom_window_state()
  previous := activate_custom_window_state(first)
  defer { activate_custom_window_state(previous); g_gg_app.ctx = original }
  g_gg_app.ctx = &DrawContext{content_transform:ContentTransform{scale:0.5}}
  register_scroll_view('pane',rect(0,0,200,100),rect(0,0,200,100),300,true,true,false)
  activate_custom_window_state(second)
  g_gg_app.ctx = &DrawContext{content_transform:ContentTransform{scale:2}}
  register_scroll_view('pane',rect(0,0,200,100),rect(0,0,200,100),300,true,true,false)
  apply_scroll_chain(['pane'],20)
  assert scroll_offset('pane') == 10
  activate_custom_window_state(first)
  apply_scroll_chain(['pane'],20)
  assert scroll_offset('pane') == 40
  assert g_scroll_transforms['pane'].scale == 0.5
  activate_custom_window_state(second)
  assert scroll_offset('pane') == 10
  assert g_scroll_transforms['pane'].scale == 2
 }
}

$if (android || linux || ((macos || windows) && ui2_custom_rendering ?)) && !ui2_headless ? {
 fn test_scaled_visual_states_use_inverse_pointer_and_keep_hit_bounds() {
  previous_tooltip := g_tooltip
  previous_touch := g_touch
  previous_focus := g_focused_field
  defer { g_tooltip = previous_tooltip; g_touch = previous_touch; g_focused_field = previous_focus }
  transform := ContentTransform{scale:0.5,y:60}
  frame := rect(100,100,200,40)
  el := with_interaction_style(button('next','Next',frame,BoxStyle{},TextStyle{units:.logical}),InteractionStyle{
   hover:BoxStylePatch{bg:u32(0x00ff00)}
   focus:BoxStylePatch{outline_width:f64(3),outline_offset:f64(3)}
   pressed:BoxStylePatch{bg:u32(0xff0000)}
   hover_text:TextStylePatch{color:u32(0)}
  })
  g_tooltip = TooltipState{pointer_in:true,pointer_x:100,pointer_y:120}
  g_touch = TouchState{}
  g_focused_field = ''
  hover := resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform)
  assert hover.box.bg == 0x00ff00 && hover.text_style.color == 0
  assert hover.frame == frame && hover.text_style.units == .logical
  // Letterbox and a parent clip exclude the same inverse pointer.
  assert resolve_custom_visual_style(el,frame,rect(0,0,80,720),transform).box.bg == el.box.bg
  g_tooltip.pointer_y = 30
  assert resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform).box.bg == el.box.bg
  // A touch press need not have generated a mouse hover event.
  g_touch = TouchState{down:true,current_x:100,current_y:120,pressed_id:'next'}
  g_tooltip.pointer_in = false
  assert resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform).box.bg == 0xff0000
  g_focused_field = 'next'
  focused := resolve_custom_visual_style(el,frame,rect(0,0,1280,720),transform)
  assert focused.box.outline_width == 3 && focused.frame == frame
 }
}
