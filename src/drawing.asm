clear_paint_canvas:
{
    lda #0
    ldx #0
canvas_page0:
    sta intensity_canvas,x
    inx
    bne canvas_page0
canvas_page1:
    sta intensity_canvas+256,x
    inx
    cpx #24*12-256
    bne canvas_page1
    jsr draw_canvas_image
    rts
}

init_mouse:
{
    lda #$ff
    sta $dc02
    lda #$00
    sta $dc03
    lda #$7f
    sta $dc00
    ldx #4
    ldy #199
wait:
    dey
    bne wait
    dex
    bne wait
    lda $d419
    sta old_potx
    lda $d41a
    sta old_poty
    lda #160
    sta mouse_x_lo
    lda #0
    sta mouse_x_hi
    lda #100
    sta mouse_y_lo
    lda #0
    sta mouse_y_hi
    ldx #63
copy_sprite:
    lda CROSSHAIR_SPRITE,x
    sta $0340,x
    lda AMIGAZZ_GRAY_SPRITE,x
    sta $0380,x
    lda AMIGAZZ_BLACK_SPRITE,x
    sta $03c0,x
    dex
    bpl copy_sprite
    lda #($0340/$40)
    sta SCREEN+$3f8
    lda #1
    sta $d027
    sta $d015
    lda #0
    sta $d010
    jsr update_crosshair
    rts
}

show_inference_cursor:
{
    lda #($03c0/$40)
    sta SCREEN+$3f8
    lda #($0380/$40)
    sta SCREEN+$3f9
    jsr sync_inference_cursor
    lda #0
    sta $d027
    lda #15
    sta $d028
    lda $d015
    ora #3
    sta $d015
    rts
}

sync_inference_cursor:
{
    lda $d000
    sta $d002
    lda $d001
    sta $d003
    lda $d010
    and #1
    beq clear9bit
    lda $d010
    ora #2
    sta $d010
    rts
clear9bit:
    lda $d010
    and #$fd
    sta $d010
    rts
}

show_crosshair_cursor:
{
    lda #($0340/$40)
    sta SCREEN+$3f8
    lda #1
    sta $d027
    lda $d015
    and #$fd
    ora #1
    sta $d015
    rts
}

update_mouse:
{
    lda #$7f
    sta $dc00
    lda $d419
    ldy old_potx
    jsr mouse_movement
    beq no_x_move
    sty old_potx
    clc
    adc mouse_x_lo
    sta mouse_x_lo
    txa
    adc mouse_x_hi
    sta mouse_x_hi
no_x_move:

    lda $d41a
    ldy old_poty
    jsr mouse_movement
    beq no_y_move
    sty old_poty
    clc
    eor #$ff
    adc #1
    clc
    adc mouse_y_lo
    sta mouse_y_lo
    txa
    eor #$ff
    adc mouse_y_hi
    sta mouse_y_hi
no_y_move:
    jmp bound_mouse
}

mouse_movement:
{
    sty old_pot_temp
    tay
    sec
    sbc old_pot_temp
    and #$7f
    cmp #$40
    bcs negative
    lsr
    beq no_move
    ldx #0
    cmp #0
    rts
negative:
    ora #$80
    cmp #$ff
    beq no_move
    sec
    ror
    ldx #$ff
    cmp #0
no_move:
    rts
}

bound_mouse:
{
    lda mouse_x_hi
    bmi x_min
    cmp #2
    bcs x_max
    cmp #1
    bne bound_y
    lda mouse_x_lo
    cmp #64
    bcc bound_y
x_max:
    lda #63
    sta mouse_x_lo
    lda #1
    sta mouse_x_hi
    bne bound_y
x_min:
    lda #0
    sta mouse_x_lo
    sta mouse_x_hi
bound_y:
    lda mouse_y_hi
    bmi y_min
    bne y_max
    lda mouse_y_lo
    cmp #200
    bcc done
y_max:
    lda #199
    sta mouse_y_lo
    lda #0
    sta mouse_y_hi
    rts
y_min:
    lda #0
    sta mouse_y_lo
    sta mouse_y_hi
done:
    rts
}

update_crosshair:
{
    clc
    lda mouse_x_lo
    adc #17
    sta $d000
    lda mouse_x_hi
    adc #0
    and #1
    sta zp_mouse_delta
    lda $d010
    and #$fe
    ora zp_mouse_delta
!:
    sta $d010
    clc
    lda mouse_y_lo
    adc #43
    sta $d001
    rts
}

mouse_button_pressed:
{
    lda #$ff
    sta $dc00
    lda $dc01
    and #$10
    sta mouse_fire_state
    pha
    lda #$7f
    sta $dc00
    pla
    bne released
    sec
    rts
released:
    clc
    rts
}

read_joystick:
{
    lda #$ff
    sta $dc00
    lda #$00
    sta $dc02
    lda $dc00
    sta joystick_state
    lda #$7f
    sta $dc00
    lda #$ff
    sta $dc02
    rts
}

joystick_button_pressed:
{
    jsr read_joystick
}
joystick_button_from_state:
{
    lda joystick_state
    and #$10
    bne released
    sec
    rts
released:
    clc
    rts
}

canvas_button_pressed:
{
    lda #0
    sta paint_button_state
    jsr mouse_button_pressed
    bcs pressed
    jsr joystick_button_pressed
    bcc released
pressed:
    lda #1
    sta paint_button_state
    sec
    rts
released:
    clc
    rts
}

update_joystick:
{
    jsr read_joystick
    lda joystick_state
    and #$04                  // LEFT
    bne no_left
    sec
    lda mouse_x_lo
    sbc #2
    sta mouse_x_lo
    lda mouse_x_hi
    sbc #0
    sta mouse_x_hi
no_left:
    lda joystick_state
    and #$08                  // RIGHT
    bne no_right
    clc
    lda mouse_x_lo
    adc #2
    sta mouse_x_lo
    lda mouse_x_hi
    adc #0
    sta mouse_x_hi
no_right:
    lda joystick_state
    and #$01                  // UP
    bne no_up
    sec
    lda mouse_y_lo
    sbc #2
    sta mouse_y_lo
    lda mouse_y_hi
    sbc #0
    sta mouse_y_hi
no_up:
    lda joystick_state
    and #$02                  // DOWN
    bne no_down
    clc
    lda mouse_y_lo
    adc #2
    sta mouse_y_lo
    lda mouse_y_hi
    adc #0
    sta mouse_y_hi
no_down:
    jmp bound_mouse
}

paint_brush:
{
    lda mouse_x_hi
    beq !+
    rts
!:
    lda mouse_x_lo
    cmp #64
    bcs !+
    rts
!:
    sec
    sbc #64
    sta line_target_col
    lda mouse_y_lo
    cmp #192
    bcc !+
    rts
!:
    sta line_target_row
    lda stroke_active
    bne continue_stroke
    jsr clear_paint_canvas
    lda #1
    sta stroke_active
    lda #0
    sta zp_stroke_moved
    lda line_target_col
    sta mouse_col
    lda line_target_row
    sta mouse_row
    rts
continue_stroke:
    lda line_target_col
    sec
    sbc mouse_col
    bcs x_positive
    eor #$ff
    adc #1
    sta line_dx
    lda #$ff
    sta line_sx
    bne have_dx
x_positive:
    sta line_dx
    lda #1
    sta line_sx
have_dx:
    lda line_target_row
    sec
    sbc mouse_row
    bcs y_positive
    eor #$ff
    adc #1
    sta line_dy
    lda #$ff
    sta line_sy
    bne have_dy
y_positive:
    sta line_dy
    lda #1
    sta line_sy
have_dy:
    lda line_dx
    ora line_dy
    bne moved
    rts
moved:
    lda #1
    sta zp_stroke_moved
    lda line_dx
    cmp #64
    bcs jump_stroke
    lda line_dy
    cmp #64
    bcs jump_stroke
    lda line_dx
    sec
    sbc line_dy
    sta line_err
    lda #192
    sta line_steps
line:
    dec line_steps
    beq jump_stroke
    jsr subpixel_stamp
    lda mouse_col
    cmp line_target_col
    bne advance
    lda mouse_row
    cmp line_target_row
    bne advance
    rts
jump_stroke:
    lda line_target_col
    sta mouse_col
    lda line_target_row
    sta mouse_row
    jsr subpixel_stamp
    rts
advance:
    lda line_err
    asl
    sta line_e2
    lda line_dy
    eor #$ff
    clc
    adc #1
    eor #$80
    sta line_compare
    lda line_e2
    eor #$80
    cmp line_compare
    bcc no_x_step
    lda line_err
    sec
    sbc line_dy
    sta line_err
    lda mouse_col
    clc
    adc line_sx
    sta mouse_col
no_x_step:
    lda line_dx
    eor #$80
    sta line_compare
    lda line_e2
    eor #$80
    cmp line_compare
    beq y_step
    bcs line
y_step:
    lda line_err
    clc
    adc line_dx
    sta line_err
    lda mouse_row
    clc
    adc line_sy
    sta mouse_row
    jmp line
}

subpixel_stamp:
{
    lda mouse_col
    sec
    sbc #4
    bcs !+
    lda #0
!:
    sta zp_stamp_x
    lda mouse_row
    sec
    sbc #4
    bcs !+
    lda #0
!:
    sta zp_stamp_y

    lda zp_stamp_x
    and #7
    asl
    sta zp_frac_x
    lda zp_stamp_y
    and #7
    asl
    sta zp_frac_y
    lda #16
    sec
    sbc zp_frac_x
    sta zp_inv_x
    lda #16
    sec
    sbc zp_frac_y
    sta zp_inv_y
    lda zp_stamp_x
    lsr
    lsr
    lsr
    sta zp_target_col
    lda zp_stamp_y
    lsr
    lsr
    lsr
    sta zp_target_row
    lda zp_inv_x
    ldx zp_inv_y
    jsr multiply_4bit
    sta zp_brush_amount
    jsr composite_pixel
    inc zp_target_col
    lda zp_target_col
    cmp #24
    bcs lower_row
    lda zp_frac_x
    ldx zp_inv_y
    jsr multiply_4bit
    sta zp_brush_amount
    jsr composite_pixel
lower_row:
    dec zp_target_col
    inc zp_target_row
    lda zp_target_row
    cmp #24
    bcs done
    lda zp_inv_x
    ldx zp_frac_y
    jsr multiply_4bit
    sta zp_brush_amount
    jsr composite_pixel
    inc zp_target_col
    lda zp_target_col
    cmp #24
    bcs done
    lda zp_frac_x
    ldx zp_frac_y
    jsr multiply_4bit
    sta zp_brush_amount
    jsr composite_pixel
done:
    rts
}

multiply_4bit:
{
    sta zp_multiply_value_lo
    lda #0
    sta zp_multiply_value_hi
    sta zp_multiply_result_lo
    sta zp_multiply_result_hi
    stx zp_multiply_bits
loop:
    lsr zp_multiply_bits
    bcc no_add
    clc
    lda zp_multiply_result_lo
    adc zp_multiply_value_lo
    sta zp_multiply_result_lo
    lda zp_multiply_result_hi
    adc zp_multiply_value_hi
    sta zp_multiply_result_hi
no_add:
    asl zp_multiply_value_lo
    rol zp_multiply_value_hi
    lda zp_multiply_bits
    bne loop
    lda zp_multiply_result_hi
    beq low_byte
    lda #255
    rts
low_byte:
    lda zp_multiply_result_lo
    rts
}

composite_pixel:
{
    lda zp_target_col
    cmp #24
    bcc !+
    jmp done
!:
    lda zp_target_row
    cmp #VISIBLE_IMAGE_HEIGHT
    bcc !+
    jmp done
!:
    lda zp_brush_amount
    lsr
    lsr
    lsr
    cmp #16
    bcc !+
    lda #15
!:
    bne !+
    jmp done
!:
    sta zp_packed_level
    ldx zp_target_row
    lda intensity_lo,x
    sta zp_canvas_ptr
    lda intensity_hi,x
    sta zp_canvas_ptr+1
    lda zp_target_col
    lsr
    tay
    lda (zp_canvas_ptr),y
    sta zp_packed_canvas_byte
    lda zp_target_col
    and #1
    bne high_nibble
    lda zp_packed_canvas_byte
    and #$0f
    cmp zp_packed_level
    bcs done
    lda zp_packed_canvas_byte
    and #$f0
    ora zp_packed_level
    sta (zp_canvas_ptr),y
    bne preview
high_nibble:
    lda zp_packed_canvas_byte
    lsr
    lsr
    lsr
    lsr
    cmp zp_packed_level
    bcs done
    lda zp_packed_level
    asl
    asl
    asl
    asl
    sta zp_packed_level_shifted
    lda zp_packed_canvas_byte
    and #$0f
    ora zp_packed_level_shifted
    sta (zp_canvas_ptr),y
preview:
    lda zp_packed_level
    cmp #5
    bcc one
    cmp #11
    bcc two
    ldx #3
    bne color
one:
    ldx #1
    bne color
two:
    ldx #2
color:
    lda DRAW_GRAY,x
    ldx zp_target_row
    pha
    lda paint_screen_lo,x
    sta zp_screen_ptr
    lda paint_screen_hi,x
    sta zp_screen_ptr+1
    lda paint_color_lo,x
    sta zp_color_ptr
    lda paint_color_hi,x
    sta zp_color_ptr+1
    pla
    sta zp_packed_level_shifted
    ldy zp_target_col
    lda #$a0
    sta (zp_screen_ptr),y
    lda zp_packed_level_shifted
    sta (zp_color_ptr),y
done:
    rts
}

old_potx:     .byte 0
old_poty:     .byte 0
old_pot_temp: .byte 0
mouse_x_lo:   .byte 160
mouse_x_hi:   .byte 0
mouse_y_lo:   .byte 100
mouse_y_hi:   .byte 0
mouse_col:    .byte 12
mouse_row:    .byte 12
joystick_state:.byte $ff
joystick_mode: .byte 0
mode_scan_divider: .byte 0
mode_mouse_fire: .byte $10
mouse_fire_state:.byte $10
stroke_active: .byte 0
line_target_col:.byte 0
line_target_row:.byte 0
line_dx:       .byte 0
line_dy:       .byte 0
line_sx:       .byte 0
line_sy:       .byte 0
line_err:      .byte 0
line_e2:       .byte 0
line_compare:  .byte 0
line_steps:    .byte 0

intensity_canvas: .fill 24*12, 0
intensity_lo:
.for (var row=0; row<24; row++) .byte <(intensity_canvas+row*12)
intensity_hi:
.for (var row=0; row<24; row++) .byte >(intensity_canvas+row*12)

paint_color_lo:
.for (var row=0; row<24; row++) .byte <(COLOR_RAM+row*40+DRAW_COL)
paint_color_hi:
.for (var row=0; row<24; row++) .byte >(COLOR_RAM+row*40+DRAW_COL)

paint_screen_lo:
.for (var row=0; row<24; row++) .byte <(SCREEN+row*40+DRAW_COL)
paint_screen_hi:
.for (var row=0; row<24; row++) .byte >(SCREEN+row*40+DRAW_COL)

draw_image:
{
    lda #<(COLOR_RAM+DRAW_COL)
    sta zp_color_ptr
    lda #>(COLOR_RAM+DRAW_COL)
    sta zp_color_ptr+1
    lda #<(SCREEN+DRAW_COL)
    sta zp_screen_ptr
    lda #>(SCREEN+DRAW_COL)
    sta zp_screen_ptr+1
    lda draw_wrong_mode
    beq use_normal_map
    lda #<(SCHEISSE_COLOR_MAP+DRAW_COL)
    sta zp_color_map_ptr
    lda #>(SCHEISSE_COLOR_MAP+DRAW_COL)
    sta zp_color_map_ptr+1
    jmp map_selected
use_normal_map:
    lda #<(COLOR_MAP+DRAW_COL)
    sta zp_color_map_ptr
    lda #>(COLOR_MAP+DRAW_COL)
    sta zp_color_map_ptr+1
map_selected:
    lda #<(SCREEN_MAP+DRAW_COL)
    sta zp_canvas_ptr
    lda #>(SCREEN_MAP+DRAW_COL)
    sta zp_canvas_ptr+1
    lda #0
    sta zp_draw_row
    sta zp_conv_dest_offset
row:
    lda #0
    sta zp_draw_col
plane_byte:
    ldy zp_conv_dest_offset
    lda PLANE0,y
    sta zp_conv_plane0_acc
    lda PLANE1,y
    sta zp_conv_plane1_acc
    ora zp_conv_plane0_acc
    bne !+
    jmp totally_black8
!:
    ldy zp_draw_col
    .for(var i=0;i<8;i++) {
        lda #0
        lsr zp_conv_plane1_acc
        rol
        lsr zp_conv_plane0_acc
        rol
        tax
        cpx #0
        bne non_black
        lda (zp_canvas_ptr),y
        sta (zp_screen_ptr),y
        lda (zp_color_map_ptr),y
        sta (zp_color_ptr),y
        jmp pixel_done
non_black:
        lda #$a0
        sta (zp_screen_ptr),y
        lda DRAW_GRAY,x
        sta (zp_color_ptr),y
pixel_done:
        iny
    }
    jmp pixels_done
totally_black8:
    ldy zp_draw_col
    .for(var i=0;i<8;i++) {
        lda (zp_canvas_ptr),y
        sta (zp_screen_ptr),y
        lda (zp_color_map_ptr),y
        sta (zp_color_ptr),y
        iny
    }
pixels_done:
    inc zp_conv_dest_offset
    cpy #24
    beq row_done
    sty zp_draw_col
    jmp plane_byte
row_done:
    clc
    lda zp_color_ptr
    adc #40
    sta zp_color_ptr
    bcc !+
    inc zp_color_ptr+1
!:
    clc
    lda zp_screen_ptr
    adc #40
    sta zp_screen_ptr
    bcc !+
    inc zp_screen_ptr+1
!:
    clc
    lda zp_color_map_ptr
    adc #40
    sta zp_color_map_ptr
    bcc !+
    inc zp_color_map_ptr+1
!:
    clc
    lda zp_canvas_ptr
    adc #40
    sta zp_canvas_ptr
    bcc !+
    inc zp_canvas_ptr+1
!:
    inc zp_draw_row
    lda zp_draw_row
    cmp #VISIBLE_IMAGE_HEIGHT
    beq done
    jmp row
done:
    rts
}

copy_image_to_planes:
{
    ldy #0
copy_plane0:
    lda (zp_image_ptr),y
    sta PLANE0,y
    iny
    cpy #PLANE_BYTES
    bne copy_plane0
    ldx #0
copy_plane1:
    lda (zp_image_ptr),y
    sta PLANE1,x
    iny
    inx
    cpx #PLANE_BYTES
    bne copy_plane1
    rts
}

convert_canvas_to_planes:
{
    lda #<intensity_canvas
    sta zp_conv_src_ptr
    lda #>intensity_canvas
    sta zp_conv_src_ptr+1
    lda #0
    sta zp_conv_dest_offset
    sta zp_conv_row
row:
    ldy #0
pair:
    lda #0
    sta zp_conv_plane0_acc
    sta zp_conv_plane1_acc
    tya
    clc
    adc #3
    tay
    lda (zp_conv_src_ptr),y
    jsr emit_byte
    dey
    lda (zp_conv_src_ptr),y
    jsr emit_byte
    dey
    lda (zp_conv_src_ptr),y
    jsr emit_byte
    dey
    lda (zp_conv_src_ptr),y
    jsr emit_byte
    ldx zp_conv_dest_offset
    lda zp_conv_plane0_acc
    sta PLANE0,x
    lda zp_conv_plane1_acc
    sta PLANE1,x
    inc zp_conv_dest_offset
    tya
    clc
    adc #4
    tay
    cpy #12
    bne pair
    clc
    lda zp_conv_src_ptr
    adc #12
    sta zp_conv_src_ptr
    bcc !+
    inc zp_conv_src_ptr+1
!:
    inc zp_conv_row
    lda zp_conv_row
    cmp #24
    bne row
    rts

emit_byte:
    sta zp_conv_src_byte
    lsr
    lsr
    lsr
    lsr
    tax
    lda QUANT_TABLE,x
    lsr
    rol zp_conv_plane0_acc
    lsr
    rol zp_conv_plane1_acc
    lda zp_conv_src_byte
    and #$0f
    tax
    lda QUANT_TABLE,x
    lsr
    rol zp_conv_plane0_acc
    lsr
    rol zp_conv_plane1_acc
    rts
}

run_inference_banked:
{
    lda canvas_mode_active
    beq !+
    jsr show_inference_cursor
    jsr reset_screen_timer
!:
    lda #0
    sta inference_frames
    sta inference_frames+1
    sta inference_frames+2
    lda #1
    sta inference_active
    lda $01
    sta saved_port
    lda #$34
    sta $01
    jsr run_inference
    pha
    lda #0
    sta inference_active
    lda saved_port
    sta $01
    lda canvas_mode_active
    beq !+
    jsr show_crosshair_cursor
!:
    pla
    rts
saved_port: .byte 0
}

classify_streamed_image:
{
    jsr copy_image_to_planes
    jmp run_inference_banked
}

classify_paint_canvas:
{
    jsr convert_canvas_to_planes
    jmp run_inference_banked
}

run_paint_mode:
{
    lda #1
    sta canvas_mode_active
    lda #0
    sta $dd0e
    sta paint_armed
    sta stroke_active
    sta display_input_pending
    lda #$20
    sta SCREEN+12*40+3
    lda #0
    sta paint_s_key_held
    jsr clear_scores
    lda #0
    jsr paint_stats_colors
    jsr clear_paint_canvas
    jsr init_mouse
paint_mode:
    jsr wait_frame
    jsr update_mouse
    jsr update_joystick
    jsr update_crosshair
    jsr canvas_button_pressed
    php
    jsr scan_paint_input
    plp
handle_paint_button:
    bcc paint_button_up
    lda paint_armed
    beq no_paint
    jsr paint_brush
    jmp no_paint
paint_button_up:
    lda stroke_active
    beq no_stroke_just_ended
    lda zp_stroke_moved
    beq no_stroke_just_ended
    jsr classify_paint_canvas
    jsr show_paint_prediction
    jsr show_scores
    lda RESULT_CLASS
    jsr sample_play
no_stroke_just_ended:
    lda #0
    sta stroke_active
    lda #1
    sta paint_armed
no_paint:
    lda paint_button_state
    bne paint_mode
scan_paint_keys:
    jsr space_pressed
    bcs leave_paint_mode
    jmp paint_mode

leave_paint_mode:
    lda #0
    sta canvas_mode_active
    lda $d015
    and #$fc
    sta $d015
    lda #0
    sta $d021
    lda #$7f
    sta $dc00
    lda #1
    jsr paint_stats_colors
    rts
}

.align 64
CROSSHAIR_SPRITE:
    SpriteLine("........................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine("........................")
    SpriteLine("######.#.######.........")
    SpriteLine("........................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine(".......#................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    .byte 0

AMIGAZZ_GRAY_SPRITE:
    SpriteLine(".....##.................")
    SpriteLine("....####.#..............")
    SpriteLine("..#########.............")
    SpriteLine(".##########.............")
    SpriteLine(".##....#####............")
    SpriteLine(".####.#######...........")
    SpriteLine("####.########...........")
    SpriteLine(".##....#######..........")
    SpriteLine(".#######....##..........")
    SpriteLine("..########.####.........")
    SpriteLine(".########.####..........")
    SpriteLine("..######....##..........")
    SpriteLine("...##########...........")
    SpriteLine(".....#######............")
    SpriteLine(".......###..............")
    SpriteLine(".....###................")
    SpriteLine("....######..............")
    SpriteLine(".....##.#...............")
    SpriteLine("........................")
    SpriteLine("........##..............")
    SpriteLine(".........##.............")
    .byte 0

AMIGAZZ_BLACK_SPRITE:
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("...####.................")
    SpriteLine(".....#..................")
    SpriteLine("....#...................")
    SpriteLine("...####.................")
    SpriteLine("........####............")
    SpriteLine("..........#.............")
    SpriteLine(".........#..............")
    SpriteLine("........####............")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    SpriteLine("........................")
    .byte 0

DRAW_GRAY:
    .byte 0,12,15,1

QUANT_TABLE:
    .byte 0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3
