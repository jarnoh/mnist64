    * = $0800
    jmp start

.const NUM_DATASET_IMAGES = 10000

.const NUM_TEST_IMAGES = 32
.const TEST_IMAGES = $8e00
.const TEST_LABELS = $8d00
.const TEST_LABELS_LEN = 256

.const zp_current_disk = $f2
.const zp_wait_disk = $f3

.const zp_conv_src_ptr    = $40
.const zp_conv_dest_offset= $42
.const zp_conv_row        = $43
.const zp_conv_src_byte   = $44
.const zp_conv_plane0_acc = $45
.const zp_conv_plane1_acc = $46

.const zp_print_num  = $40
.const zp_print_dest = $42
.const zp_print_digit= $44
.const zp_print_min_digits = $49
.const zp_print_blanking = $4a

.const zp_score_class = $45
.const zp_score_leading = $46
.const zp_score_first_col = $47
.const zp_score_color = $48
.const zp_score_map_ptr = $4b
.const zp_copy_count = $4d

#import "generated_model_header.asm"
#import "demo_layout.asm"
#import "macros.asm"
#import "build_defaults.asm"
#import "inc_irq.asm"
.const VISIBLE_IMAGE_HEIGHT=23

.const LOOKUP_TABLES_ORIGIN=INFERENCE_END

.const SCREEN_MAP  = $7600 // loaded 40x25 screen map
.const COLOR_MAP   = $7a00 // loaded 40x25 color map
.const SCHEISSE_COLOR_MAP   = $7e00 // scheisse 40x25 color map


inference_abort_hook_code:
    lda canvas_request_latch
    beq !+
    sec
    rts
!:
    clc
    rts
.errorif (inference_abort_hook_code != INFERENCE_ABORT_HOOK), "inference_abort_hook_code moved; update INFERENCE_ABORT_HOOK in demo_layout.asm"

inference_display_hook_code:
{
    lda $01
    pha
    lda #$35
    sta $01
    jsr run_auto_advance_now
    pla
    sta $01
    rts
}
.errorif (inference_display_hook_code != INFERENCE_DISPLAY_HOOK), "inference_display_hook_code moved; update INFERENCE_DISPLAY_HOOK in demo_layout.asm"

inference_early_hook_code:
{
    lda canvas_mode_active
    bne done
    lda $01
    pha
    lda #$35
    sta $01
    jsr show_prediction
    jsr show_scores
    pla
    sta $01
done:
    rts
}
.errorif (inference_early_hook_code != INFERENCE_EARLY_HOOK), "inference_early_hook_code moved; update INFERENCE_EARLY_HOOK in demo_layout.asm"

image_index:    .byte 0
image_index_hi: .byte 0

paint_armed:    .byte 0
canvas_mode_active: .byte 0
auto_advance_ready:  .byte 0
last_guess_wrong:    .byte 0
draw_wrong_mode:     .byte 0
display_input_pending: .byte 0
paint_button_state: .byte 0
canvas_request_latch: .byte 0
scores_visible: .byte 1
paint_s_key_held: .byte 0
s_key_held:     .byte 0
scheisse_test_pending: .byte 0

total_shown:      .word 0
total_correct:    .word 0
total_wrong:      .word 0
inference_active: .byte 0
inference_frames: .byte 0, 0, 0
irq_frame_counter: .byte 0

.const SCREEN       = $0400
.const COLOR_RAM    = $d800
.const DRAW_COL     = 8

.const SCREEN_TIMER_BASE = SCREEN+4*40+1
.const SCREEN_GROUND_TRUTH = SCREEN+8*40+1
.const SCREEN_DETECT       = SCREEN+1*40+1
.const SCREEN_MODE = SCREEN+1*40+35
.const SCREEN_ACCURACY = SCREEN+4*40+33
.const SCREEN_CORRECT = SCREEN+7*40+(38-4)
.const SCREEN_WRONG   = SCREEN+10*40+(38-4)
.const SCREEN_MAP_CORRECT = SCREEN_MAP+7*40+(38-4)
.const SCREEN_MAP_WRONG   = SCREEN_MAP+10*40+(38-4)

.const zp_image_ptr    = $10
.const zp_color_ptr    = $14
.const zp_draw_row     = $16
.const zp_draw_col     = $17
.const zp_brush_amount = $1a
.const zp_target_col   = $1b
.const zp_target_row   = $1c
.const zp_mouse_delta  = $1d
.const zp_canvas_ptr   = $1e
.const zp_screen_ptr   = $22
.const zp_color_map_ptr= $24

.const zp_stamp_x              = $26
.const zp_stamp_y              = $27
.const zp_frac_x               = $28
.const zp_frac_y               = $29
.const zp_inv_x                = $2a
.const zp_inv_y                = $2b
.const zp_multiply_value_lo    = $2c
.const zp_multiply_value_hi    = $2d
.const zp_multiply_result_lo   = $2e
.const zp_multiply_result_hi   = $2f
.const zp_multiply_bits        = $30
.const zp_packed_level         = $31
.const zp_packed_level_shifted = $32
.const zp_packed_canvas_byte   = $33
.const zp_stroke_moved         = $34

#import "scroller.asm"

start:
{
    sei
    lda #$7f
    sta $dc0d
    lda $dc0d

    lda #$ff
    sta $dc02
    lda #$00
    sta $dc03
    lda #$7f
    sta $dc00

    jsr detect_video_standard

    jsr init_ui_screen

    lda #0
    sta zp_current_disk        
    sta zp_wait_disk            

    jsr scroll_init

    // start scroller
    lda #$01
    sta $d01a
    irq_setup(trampoline, 0)
    cli

    jsr $200

    lda TTA_MODE
    jsr set_tta_mode

    jsr sample_init

    lda #<TEST_IMAGES
    sta zp_image_ptr
    lda #>TEST_IMAGES
    sta zp_image_ptr+1
    lda #0
    sta image_index
    sta image_index_hi

next_image:
    lda #0
    sta auto_advance_ready
    lda #1
    sta display_input_pending

    jsr classify_streamed_image
    lda canvas_request_latch
    beq !+
    jmp enter_latched_paint
!:

wait_display_deadline:
    lda canvas_request_latch
    beq !+
    jmp enter_latched_paint
!:
    lda auto_advance_ready
    bne display_inference_result
    jsr wait_frame
    jmp wait_display_deadline
display_inference_result:
    jsr show_prediction
    jsr show_scores

    inc total_shown
    bne !+
    inc total_shown+1
!:
    ldx image_index
    lda TEST_LABELS,x
    cmp RESULT_CLASS
    beq correct_guess
    lda #1
    sta last_guess_wrong
    sta draw_wrong_mode
    inc total_wrong
    bne !+
    inc total_wrong+1
!:
    jsr copy_scheisse_colors
    jsr copy_image_to_planes
    lda #9
    sta DRAW_GRAY
    jsr draw_image
    lda #0
    sta DRAW_GRAY
    sta draw_wrong_mode
    lda #10 // scheisse
    jmp play_sample
correct_guess:
    lda last_guess_wrong
    beq guess_was_already_correct
    jsr restore_colors
    jsr copy_image_to_planes
    jsr draw_image
guess_was_already_correct:
    lda #0
    sta last_guess_wrong
    inc total_correct
    bne !+
    inc total_correct+1
!:
    lda RESULT_CLASS
play_sample:
    jsr sample_play
    jsr show_counters

wait_some:
    jsr wait_frame
    lda canvas_request_latch
    beq !+
    jmp enter_latched_paint
!:
    lda scheisse_test_pending
    beq !+
    lda #0
    sta scheisse_test_pending
    jsr test_scheisse
!:
no_digit_key:
    lda auto_advance_ready
    beq wait_some
    lda TTA_MODE
    cmp #TTA_AUTO
    bne check_sample_playing
    lda last_guess_wrong
    beq advance_image
check_sample_playing:
    lda $dd0e
    and #$01
    bne wait_some

advance_image:
    lda total_shown
    cmp #<NUM_DATASET_IMAGES
    bne do_advance
    lda total_shown+1
    cmp #>NUM_DATASET_IMAGES
    bne do_advance
    jmp dataset_exhausted
do_advance:
    clc
    lda zp_image_ptr
    adc #144
    sta zp_image_ptr
    bcc !+
    inc zp_image_ptr+1
!:
    jsr increment_image_index
    lda image_index
    and #(NUM_TEST_IMAGES-1)
    bne !+
    lda #<TEST_IMAGES
    sta zp_image_ptr
    lda #>TEST_IMAGES
    sta zp_image_ptr+1

    jsr load_more

!:    
    jmp next_image


load_more:
    jsr $200

    lda zp_current_disk
    cmp zp_wait_disk
    beq !+

    lda zp_scroll_ptr
    pha
    lda zp_scroll_ptr+1
    pha

    jsr scroll_begin_disk_message

    lda #2
    sta $d020
    jsr $200 // hidden
    lda #3
    sta $d020
    jsr $200 // disk change

    pla
    sta zp_scroll_ptr+1
    pla
    sta zp_scroll_ptr

    jsr scroll_end_disk_message

    lda #0
    sta $d020
!:
    rts

dataset_exhausted:
    jsr clear_paint_canvas
dataset_exhausted_wait:
    jsr wait_frame
    lda canvas_request_latch
    beq dataset_exhausted_wait
    tax
    lda #0
    sta canvas_request_latch
    lda #0
    cpx #2
    bne dataset_exhausted_mouse
    lda #1
dataset_exhausted_mouse:
    sta joystick_mode
    jsr run_paint_mode
    jsr clear_paint_canvas
    jmp dataset_exhausted_wait

enter_mouse_paint:
    lda #0
    sta joystick_mode
    jsr run_paint_mode
    jmp next_image
enter_joystick_paint:
    lda #1
    sta joystick_mode
    jsr run_paint_mode
    jmp next_image

enter_latched_paint:
    tax
    lda #0
    sta canvas_request_latch 
    cpx #2
    bne !+
    jmp enter_joystick_paint
!:
    jmp enter_mouse_paint
}

trampoline:
    irq_enter()
    jmp irq

#import "ui.asm"

run_auto_advance_now: {
    lda #1
    sta auto_advance_ready
    lda display_input_pending
    beq auto_advance_ticked
    lda canvas_mode_active
    bne auto_advance_ticked
    lda last_guess_wrong
    beq skip_restore
    jsr restore_colors
    lda #0
    sta last_guess_wrong
skip_restore:
    lda #0
    sta inference_active
    jsr draw_image
    lda #1
    sta inference_active
    jsr sync_screen_timer
    lda #0
    sta display_input_pending
    ldx image_index
    lda TEST_LABELS,x
    jsr show_label
auto_advance_ticked:    
    rts
}

scan_canvas_request_irq:
{
    lda canvas_mode_active
    bne done
    lda canvas_request_latch
    bne done
    jsr mouse_button_pressed
    bcc check_joystick
    lda #1
    sta canvas_request_latch
    rts
check_joystick:
    jsr joystick_button_pressed
    bcc done
    lda #2
    sta canvas_request_latch
done:
    rts
}

irq:
{
    irq_wait_rasterline(236)
    lda #$17
    sta $d018
//    sta $d020
    lda fine_scroll
    ora #$c0
    sta $d016

    lda canvas_mode_active
    beq no_canvas_cursor_irq
    lda inference_active
    beq no_canvas_cursor_irq
    jsr update_mouse
    jsr update_joystick
    jsr update_crosshair
    jsr sync_inference_cursor
no_canvas_cursor_irq:

    lda mode_scan_divider
    beq do_mode_scan_irq
    dec mode_scan_divider
    bne mode_scan_done_irq
do_mode_scan_irq:
    lda #3
    sta mode_scan_divider
    jsr scan_mode_keys
    bcc no_mode_change_irq
    jsr set_tta_mode
no_mode_change_irq:
mode_scan_done_irq:

    irq_wait_rasterline(252)
    lda #$14
    sta $d018
//    sta $d020
    lda #$c8
    sta $d016

    inc irq_frame_counter
//    lda #3
//    sta $d020

    lda inference_active
    beq clock_ticked
    inc inference_frames
    bne tick_screen
    inc inference_frames+1
    bne tick_screen
    inc inference_frames+2
tick_screen:
    lda display_input_pending
    bne clock_ticked
    jsr tick_screen_timer_frame
clock_ticked:

    jsr scroll_tick

//    lda #4
//    sta $d020

    jsr scan_canvas_request_irq
    jsr scan_scheisse_test_irq

    jmp irq
}

increment_image_index:
{
    inc image_index
    bne done
    inc image_index_hi
done:
    rts
}

#import "drawing.asm"

tick_screen_timer_frame:
{
    lda video_is_pal
    beq check_ntsc
    jsr tick_screen_timer
    rts
check_ntsc:
    lda ntsc_skip_ctr
    beq skip_frame
    dec ntsc_skip_ctr
    jsr tick_screen_timer
    rts
skip_frame:
    lda #5
    sta ntsc_skip_ctr
    rts
}

ntsc_skip_ctr: .byte 5
video_is_pal: .byte 1

detect_video_standard:
{
    cli
wait_line0:
    lda $d011
    bmi wait_line0
    lda $d012
    bne wait_line0
wait_bit7:
    lda $d011
    bpl wait_bit7
    ldx #0
    ldy #0
count_bit7:
    inx
    bne no_wrap
    iny
no_wrap:
    lda $d011
    bmi count_bit7
    cpy #0
    beq set_ntsc
    lda #1
    jmp store_result
set_ntsc:
    lda #0
store_result:
    sta video_is_pal
    sei
    rts
}

wait_frame:
{
    lda irq_frame_counter
wait:
    cmp irq_frame_counter
    beq wait
    rts
}

#import "inference.sym"
.errorif (ACT1 != DEMO_ACT1), "demo ACT1 moved; rebuild the external lookup layout"
.errorif (INFERENCE_END > $6000), "inference grew past the lookup tables' fixed $6000 origin"

copy_colors_skip_canvas:
{
    ldx #(VISIBLE_IMAGE_HEIGHT/2)
pair_loop:
    lda #DRAW_COL
    jsr copy_segment
    lda #24
    jsr skip_segment
    lda #(2*(40-DRAW_COL-24))
    jsr copy_segment
    lda #24
    jsr skip_segment
    lda #DRAW_COL
    jsr copy_segment
    dex
    bne pair_loop
    lda #DRAW_COL
    jsr copy_segment
    lda #24
    jsr skip_segment
    lda #(40-DRAW_COL-24)
    jsr copy_segment
    lda #((25-VISIBLE_IMAGE_HEIGHT)*40)
    jsr copy_segment
    rts

copy_segment:
    sta zp_copy_count
    ldy #0
copy_loop:
    lda (zp_color_map_ptr),y
    sta (zp_color_ptr),y
    iny
    cpy zp_copy_count
    bne copy_loop
    jmp advance_ptrs
skip_segment:
    sta zp_copy_count
advance_ptrs:
    clc
    lda zp_color_map_ptr
    adc zp_copy_count
    sta zp_color_map_ptr
    bcc !+
    inc zp_color_map_ptr+1
!:
    clc
    lda zp_color_ptr
    adc zp_copy_count
    sta zp_color_ptr
    bcc !+
    inc zp_color_ptr+1
!:
    rts
}

copy_scheisse_colors:
{
    lda #<SCHEISSE_COLOR_MAP
    sta zp_color_map_ptr
    lda #>SCHEISSE_COLOR_MAP
    sta zp_color_map_ptr+1
    lda #<COLOR_RAM
    sta zp_color_ptr
    lda #>COLOR_RAM
    sta zp_color_ptr+1
    jmp copy_colors_skip_canvas
}

restore_colors:
{
    lda #<COLOR_MAP
    sta zp_color_map_ptr
    lda #>COLOR_MAP
    sta zp_color_map_ptr+1
    lda #<COLOR_RAM
    sta zp_color_ptr
    lda #>COLOR_RAM
    sta zp_color_ptr+1
    jmp copy_colors_skip_canvas
}

s_key_pressed:
{
    lda #$fd
    sta $dc00
    lda $dc01
    and #$20
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

scan_scheisse_test_irq:
{
    lda canvas_mode_active
    beq !+
    lda #0
    sta s_key_held
    rts
!:
    jsr s_key_pressed
    bcs key_down
    lda #0
    sta s_key_held
    rts
key_down:
    lda s_key_held
    bne done
    lda #1
    sta s_key_held
    sta scheisse_test_pending
done:
    rts
}

test_scheisse:
{
    jsr copy_scheisse_colors
    jsr copy_image_to_planes
    lda #1
    sta draw_wrong_mode
    lda #9
    sta DRAW_GRAY
    jsr draw_image
    lda #0
    sta DRAW_GRAY
    sta draw_wrong_mode
    lda #10 // scheisse
    jsr sample_play
wait_sample:
    jsr wait_frame
    lda $dd0e
    and #$01
    bne wait_sample
    jsr restore_colors
    jsr copy_image_to_planes
    jsr draw_image
    rts
}

test_scheisse_paint:
{
    jsr copy_scheisse_colors
    jsr convert_canvas_to_planes
    lda #1
    sta draw_wrong_mode
    lda #9
    sta DRAW_GRAY
    jsr draw_image
    lda #0
    sta DRAW_GRAY
    sta draw_wrong_mode
    lda #10 // scheisse
    jsr sample_play
wait_sample:
    jsr wait_frame
    lda $dd0e
    and #$01
    bne wait_sample
    jsr restore_colors
    jsr convert_canvas_to_planes
    jsr draw_image
    rts
}

scan_paint_input:
{
    lda paint_button_state
    bne done
    jsr scan_paint_scheisse_test
done:
    rts
}

scan_paint_scheisse_test:
{
    jsr s_key_pressed
    bcs key_down
    lda #0
    sta paint_s_key_held
    rts
key_down:
    lda paint_s_key_held
    bne done
    lda #1
    sta paint_s_key_held
    jsr test_scheisse_paint
done:
    rts
}

draw_canvas_image:
{
    lda #<(COLOR_RAM+DRAW_COL); sta zp_color_ptr
    lda #>(COLOR_RAM+DRAW_COL); sta zp_color_ptr+1
    lda #<(SCREEN+DRAW_COL); sta zp_screen_ptr
    lda #>(SCREEN+DRAW_COL); sta zp_screen_ptr+1
    lda #<(COLOR_MAP+DRAW_COL); sta zp_color_map_ptr
    lda #>(COLOR_MAP+DRAW_COL); sta zp_color_map_ptr+1
    lda #<(SCREEN_MAP+DRAW_COL); sta zp_canvas_ptr
    lda #>(SCREEN_MAP+DRAW_COL); sta zp_canvas_ptr+1
    lda #<intensity_canvas; sta zp_conv_src_ptr
    lda #>intensity_canvas; sta zp_conv_src_ptr+1
    lda #0; sta zp_draw_row
row:
    ldy #0
pixel:
    lda (zp_conv_src_ptr),y
    and #$0f
    beq background
    cmp #6; bcc light
    cmp #11; bcc medium
    ldx #3; bne overlay
light:
    ldx #1; bne overlay
medium:
    ldx #2
overlay:
    lda #$a0; sta (zp_screen_ptr),y
    lda DRAW_GRAY,x; sta (zp_color_ptr),y
    jmp next_pixel
background:
    lda (zp_canvas_ptr),y; sta (zp_screen_ptr),y
    lda (zp_color_map_ptr),y; sta (zp_color_ptr),y
next_pixel:
    iny; cpy #24; bne pixel
    clc; lda zp_conv_src_ptr; adc #12; sta zp_conv_src_ptr
    bcc !+; inc zp_conv_src_ptr+1
!:
    clc; lda zp_color_ptr; adc #40; sta zp_color_ptr
    bcc !+; inc zp_color_ptr+1
!:
    clc; lda zp_screen_ptr; adc #40; sta zp_screen_ptr
    bcc !+; inc zp_screen_ptr+1
!:
    clc; lda zp_color_map_ptr; adc #40; sta zp_color_map_ptr
    bcc !+; inc zp_color_map_ptr+1
!:
    clc; lda zp_canvas_ptr; adc #40; sta zp_canvas_ptr
    bcc !+; inc zp_canvas_ptr+1
!:
    inc zp_draw_row
    lda zp_draw_row; cmp #VISIBLE_IMAGE_HEIGHT; bne row
    rts
}

color_scores:
{
    lda #<(COLOR_RAM+13*40+34)
    sta zp_print_dest
    lda #>(COLOR_RAM+13*40+34)
    sta zp_print_dest+1
    lda #<(COLOR_MAP+13*40+34)
    sta zp_score_map_ptr
    lda #>(COLOR_MAP+13*40+34)
    sta zp_score_map_ptr+1
    ldx #0
row_loop:
    txa
    cmp RESULT_CLASS
    bne use_map
    ldy #5
highlight_loop:
    lda #15
    sta (zp_print_dest),y
    dey
    bpl highlight_loop
    jmp row_next
use_map:
    ldy #5
map_loop:
    lda (zp_score_map_ptr),y
    sta (zp_print_dest),y
    dey
    bpl map_loop
row_next:
    clc
    lda zp_print_dest
    adc #40
    sta zp_print_dest
    bcc !+
    inc zp_print_dest+1
!:
    clc
    lda zp_score_map_ptr
    adc #40
    sta zp_score_map_ptr
    bcc !+
    inc zp_score_map_ptr+1
!:
    inx
    cpx #10
    bne row_loop
    rts
}

clear_score_colors:
{
    lda #<(COLOR_RAM+13*40+33)
    sta zp_print_dest
    lda #>(COLOR_RAM+13*40+33)
    sta zp_print_dest+1
    lda #<(COLOR_MAP+13*40+33)
    sta zp_score_map_ptr
    lda #>(COLOR_MAP+13*40+33)
    sta zp_score_map_ptr+1
    ldx #0
row_loop:
    ldy #0
col_loop:
    lda (zp_score_map_ptr),y
    sta (zp_print_dest),y
    iny
    cpy #7
    bne col_loop
    clc
    lda zp_print_dest
    adc #40
    sta zp_print_dest
    bcc !+
    inc zp_print_dest+1
!:
    clc
    lda zp_score_map_ptr
    adc #40
    sta zp_score_map_ptr
    bcc !+
    inc zp_score_map_ptr+1
!:
    inx
    cpx #10
    bne row_loop
    rts
}

STATS_RECTS:
    .word 6*40+0
    .byte 6, 3
    .word 3*40+32
    .byte 8, 8
.const STATS_RECT_COUNT = 2

// A = 0 -> paint the stats panels black
// A != 0 -> restore them from COLOR_MAP
paint_stats_colors:
{
    sta ps_mode
    ldx #0
rect_loop:
    lda STATS_RECTS+0,x
    sta zp_print_dest
    sta zp_score_map_ptr
    lda STATS_RECTS+1,x
    pha
    clc
    adc #>COLOR_RAM
    sta zp_print_dest+1
    pla
    clc
    adc #>COLOR_MAP
    sta zp_score_map_ptr+1
    lda STATS_RECTS+2,x
    sta ps_width
    lda STATS_RECTS+3,x
    sta ps_height
    stx ps_idx
row_loop:
    ldy #0
col_loop:
    lda ps_mode
    bne copy_map
    lda #0
    jmp put
copy_map:
    lda (zp_score_map_ptr),y
put:
    sta (zp_print_dest),y
    iny
    cpy ps_width
    bne col_loop
    clc
    lda zp_print_dest
    adc #40
    sta zp_print_dest
    bcc !+
    inc zp_print_dest+1
!:
    clc
    lda zp_score_map_ptr
    adc #40
    sta zp_score_map_ptr
    bcc !+
    inc zp_score_map_ptr+1
!:
    dec ps_height
    bne row_loop
    lda ps_idx
    clc
    adc #4
    tax
    cpx #(STATS_RECT_COUNT*4)
    bne rect_loop
    rts
ps_mode:   .byte 0
ps_width:  .byte 0
ps_height: .byte 0
ps_idx:    .byte 0
}

DEMO_END:
.errorif (DEMO_END > AUDIO_ORIGIN), "demo.asm's own resident code grew past AUDIO_ORIGIN; Spindle loads audio.prg right on top of it"
