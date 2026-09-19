init_ui_screen:
{
    lda #0
    sta $d020
    sta $d021
    lda #$1b
    sta $d011
    lda #$c8
    sta $d016

    ldx #0
copy_initial_screen:
    lda SCREEN_MAP,x
    sta SCREEN,x
    lda SCREEN_MAP+256,x
    sta SCREEN+256,x
    lda SCREEN_MAP+512,x
    sta SCREEN+512,x
    lda SCREEN_MAP+768,x
    sta SCREEN+768,x
    lda COLOR_MAP,x
    sta COLOR_RAM,x
    lda COLOR_MAP+256,x
    sta COLOR_RAM+256,x
    lda COLOR_MAP+512,x
    sta COLOR_RAM+512,x
    lda COLOR_MAP+768,x
    sta COLOR_RAM+768,x
    dex
    bne copy_initial_screen
    rts
}

reset_screen_timer:
{
    lda #$30
    sta SCREEN_TIMER_BASE
    lda #'.'
    sta SCREEN_TIMER_BASE+1
    lda #$30
    sta SCREEN_TIMER_BASE+2
    sta SCREEN_TIMER_BASE+3
    lda #5
    sta ntsc_skip_ctr
    rts
}

sync_screen_timer:
{
    lda inference_frames
    sta zp_print_digit
    ldy inference_frames+1
    jsr reset_screen_timer
page:
    cpy #0
    beq low
    ldx #0
!:
    jsr tick_screen_timer_frame
    dex
    bne !-
    dey
    bne page
low:
    ldx zp_print_digit
    beq done
!:
    jsr tick_screen_timer_frame
    dex
    bne !-
done:
    rts
}

tick_screen_timer:
{
    lda SCREEN_TIMER_BASE+3
    clc
    adc #2
    cmp #$3a
    bcc store_hundredths
    sbc #10
    sta SCREEN_TIMER_BASE+3

    inc SCREEN_TIMER_BASE+2
    lda SCREEN_TIMER_BASE+2
    cmp #$3a
    bne timer_done
    lda #$30
    sta SCREEN_TIMER_BASE+2

    inc SCREEN_TIMER_BASE
    lda SCREEN_TIMER_BASE
    cmp #$3a
    bne timer_done
    lda #$30
    sta SCREEN_TIMER_BASE
timer_done:
    rts
store_hundredths:
    sta SCREEN_TIMER_BASE+3
    rts
}

show_label:
{
    pha
    clc
    adc #$30
    sta SCREEN_GROUND_TRUTH
    lda #32
    sta SCREEN_DETECT // clear detected
    pla
    rts
}

show_prediction:
{
    lda RESULT_CLASS
    clc
    adc #$30
    sta SCREEN_DETECT
    rts
}

print_decimal16:
{
    ldy #0
    lda #1
    sta zp_print_blanking
digit_loop:
    lda #$ff
    sta zp_print_digit
sub_loop:
    inc zp_print_digit
    sec
    lda zp_print_num
    sbc DECIMAL_DIVISORS_LO,y
    tax
    lda zp_print_num+1
    sbc DECIMAL_DIVISORS_HI,y
    bcc digit_done
    sta zp_print_num+1
    stx zp_print_num
    jmp sub_loop
digit_done:
    lda zp_print_blanking
    beq store_digit
    lda zp_print_digit
    bne show_nonzero
    tya
    clc
    adc zp_print_min_digits
    cmp #5
    bcs store_digit
    lda #32
    sta (zp_print_dest),y
    jmp digit_next
show_nonzero:
    lda #0
    sta zp_print_blanking
store_digit:
    lda zp_print_digit
    clc
    adc #$30
    sta (zp_print_dest),y
digit_next:
    iny
    cpy #5
    bne digit_loop
    rts
}

print_decimal16_score:
{
    lda #1
    sta zp_score_leading
    lda #4
    sta zp_score_first_col
    ldy #0
score_digit_loop:
    lda #$ff
    sta zp_print_digit
score_sub_loop:
    inc zp_print_digit
    sec
    lda zp_print_num
    sbc DECIMAL_DIVISORS_LO,y
    tax
    lda zp_print_num+1
    sbc DECIMAL_DIVISORS_HI,y
    bcc score_digit_done
    sta zp_print_num+1
    stx zp_print_num
    jmp score_sub_loop
score_digit_done:
    lda zp_score_leading
    beq score_digit_significant
    lda zp_print_digit
    bne first_significant
    cpy #4
    beq first_significant
    lda (zp_score_map_ptr),y
    sta (zp_print_dest),y
    jmp score_digit_next
first_significant:
    lda #0
    sta zp_score_leading
    sty zp_score_first_col
score_digit_significant:
    lda zp_print_digit
    clc
    adc #$30
    sta (zp_print_dest),y
score_digit_next:
    iny
    cpy #5
    bne score_digit_loop
    rts
}

DECIMAL_DIVISORS_LO: .byte <10000, <1000, <100, <10, <1
DECIMAL_DIVISORS_HI: .byte >10000, >1000, >100, >10, >1

print_signed16_score:
{
    lda #0
    sta zp_score_color
    lda zp_print_num+1
    bpl score_sign_done
    lda #1
    sta zp_score_color
    lda zp_print_num
    eor #$ff
    clc
    adc #1
    sta zp_print_num
    lda zp_print_num+1
    eor #$ff
    adc #0
    sta zp_print_num+1
score_sign_done:
    jsr print_decimal16_score
    lda zp_score_color
    beq signed_score_done
    ldy zp_score_first_col
    beq signed_score_done
    dey
    lda #45
    sta (zp_print_dest),y
signed_score_done:
    rts
}

show_scores:
{
    lda scores_visible
    bne visible
    rts
visible:
    lda #<(SCREEN+13*40+35)
    sta zp_print_dest
    lda #>(SCREEN+13*40+35)
    sta zp_print_dest+1
    lda #<(SCREEN_MAP+13*40+35)
    sta zp_score_map_ptr
    lda #>(SCREEN_MAP+13*40+35)
    sta zp_score_map_ptr+1
    ldx #0
score_loop:
    lda TTA_MODE
    cmp #TTA_EARLY_ONLY
    beq load_early_score
    lda SCORES,x
    sta zp_print_num
    lda SCORES+1,x
    sta zp_print_num+1
    jmp score_loaded
load_early_score:
    lda EARLY_SCORES,x
    sta zp_print_num
    lda EARLY_SCORES+1,x
    sta zp_print_num+1
score_loaded:
    stx zp_score_class
    jsr print_signed16_score
    ldx zp_score_class
    jsr next_score_row
    inx
    inx
    cpx #SCORE_BYTES
    bne score_loop

    jsr color_scores
    rts
}

next_score_row:
{
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
    rts
}

clear_scores:
{
    lda #<(SCREEN+13*40+33)
    sta zp_print_dest
    lda #>(SCREEN+13*40+33)
    sta zp_print_dest+1
    lda #<(SCREEN_MAP+13*40+33)
    sta zp_color_map_ptr
    lda #>(SCREEN_MAP+13*40+33)
    sta zp_color_map_ptr+1
    ldx #0
row_loop:
    ldy #0
col_loop:
    lda (zp_color_map_ptr),y
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
    lda zp_color_map_ptr
    adc #40
    sta zp_color_map_ptr
    bcc !+
    inc zp_color_map_ptr+1
!:
    inx
    cpx #10
    bne row_loop
    jsr clear_score_colors
    rts
}

toggle_scores_visible:
{
    lda scores_visible
    eor #1
    sta scores_visible
    bne now_visible
    jsr clear_scores
    rts
now_visible:
    jsr show_scores
    rts
}

show_counters:
{
    lda #<SCREEN_CORRECT
    sta zp_print_dest
    lda #>SCREEN_CORRECT
    sta zp_print_dest+1
    lda #<SCREEN_MAP_CORRECT
    sta zp_score_map_ptr
    lda #>SCREEN_MAP_CORRECT
    sta zp_score_map_ptr+1
    lda total_correct
    sta zp_print_num
    lda total_correct+1
    sta zp_print_num+1
    jsr print_signed16_score

    lda #<SCREEN_WRONG
    sta zp_print_dest
    lda #>SCREEN_WRONG
    sta zp_print_dest+1
    lda #<SCREEN_MAP_WRONG
    sta zp_score_map_ptr
    lda #>SCREEN_MAP_WRONG
    sta zp_score_map_ptr+1
    lda total_wrong
    sta zp_print_num
    lda total_wrong+1
    sta zp_print_num+1
    jsr print_signed16_score

    jsr show_accuracy_percentage
    rts
}

show_paint_prediction:
{
    lda RESULT_CLASS
    clc
    adc #$30
    sta SCREEN_DETECT
    rts
}

percentage_dividend:     .fill 4, 0
percentage_multiplicand: .fill 4, 0
percentage_multiplier:   .word 0
percentage_divisor:      .word 0
percentage_remainder:    .word 0

show_accuracy_percentage:
{
    lda #0
    sta percentage_dividend
    sta percentage_dividend+1
    sta percentage_dividend+2
    sta percentage_dividend+3
    lda total_correct
    sta percentage_multiplicand
    lda total_correct+1
    sta percentage_multiplicand+1
    lda #0
    sta percentage_multiplicand+2
    sta percentage_multiplicand+3
    lda #<10000
    sta percentage_multiplier
    lda #>10000
    sta percentage_multiplier+1
multiply_percentage:
    lda percentage_multiplier
    and #1
    beq shift_percentage_multiply
    clc
    lda percentage_dividend
    adc percentage_multiplicand
    sta percentage_dividend
    lda percentage_dividend+1
    adc percentage_multiplicand+1
    sta percentage_dividend+1
    lda percentage_dividend+2
    adc percentage_multiplicand+2
    sta percentage_dividend+2
    lda percentage_dividend+3
    adc percentage_multiplicand+3
    sta percentage_dividend+3
shift_percentage_multiply:
    asl percentage_multiplicand
    rol percentage_multiplicand+1
    rol percentage_multiplicand+2
    rol percentage_multiplicand+3
    lsr percentage_multiplier+1
    ror percentage_multiplier
    lda percentage_multiplier
    ora percentage_multiplier+1
    bne multiply_percentage

    lda total_shown
    sta percentage_divisor
    lda total_shown+1
    sta percentage_divisor+1
    lda #0
    sta percentage_remainder
    sta percentage_remainder+1
    lda percentage_divisor
    ora percentage_divisor+1
    beq percentage_divided
    ldx #32
divide_percentage:
    asl percentage_dividend
    rol percentage_dividend+1
    rol percentage_dividend+2
    rol percentage_dividend+3
    rol percentage_remainder
    rol percentage_remainder+1
    bcs subtract_percentage_divisor
    lda percentage_remainder+1
    cmp percentage_divisor+1
    bcc percentage_divide_next
    bne subtract_percentage_divisor
    lda percentage_remainder
    cmp percentage_divisor
    bcc percentage_divide_next
subtract_percentage_divisor:
    sec
    lda percentage_remainder
    sbc percentage_divisor
    sta percentage_remainder
    lda percentage_remainder+1
    sbc percentage_divisor+1
    sta percentage_remainder+1
    inc percentage_dividend
percentage_divide_next:
    dex
    bne divide_percentage
percentage_divided:
    lda #32
    sta SCREEN_ACCURACY-1
    lda #<SCREEN_ACCURACY
    sta zp_print_dest
    lda #>SCREEN_ACCURACY
    sta zp_print_dest+1
    lda percentage_dividend
    sta zp_print_num
    lda percentage_dividend+1
    sta zp_print_num+1
    lda #3
    sta zp_print_min_digits
    jsr print_decimal16

    lda SCREEN_ACCURACY+4
    sta SCREEN_ACCURACY+5
    lda SCREEN_ACCURACY+3
    sta SCREEN_ACCURACY+4
    lda #'.'
    sta SCREEN_ACCURACY+3
    lda #'%'
    sta SCREEN_ACCURACY+6
    rts
}

space_pressed:
{
    lda #$7f
    sta $dc00
    lda $dc01
    and #$10
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

clear_key_pressed:
{
    lda #$fb
    sta $dc00
    lda $dc01
    and #$10
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


scan_mode_keys:
{
    lda #$ff
    sta $dc02
    lda #$00
    sta $dc03
    lda #$ff
    sta $dc00
    lda $dc01
    and #$10
    sta mode_mouse_fire
    lda #$fe
    sta $dc00
    lda $dc01
    and #$10
    bne check_other_modes
    lda mode_mouse_fire
    beq check_other_modes
mode_auto:
    lda #0
    pha
    lda #$7f
    sta $dc00
    pla
    sec
    rts
check_other_modes:
    lda $dc01
    and #$20
    beq mode_fast
    lda $dc01
    and #$40
    beq mode_full
    lda $dc01
    and #$08
    beq mode_guru
    jmp no_mode_key
no_mode_key:
    lda #$7f
    sta $dc00
    clc
    rts
mode_guru:
    lda #3
    pha
    lda #$7f
    sta $dc00
    pla
    sec
    rts
mode_fast:
    lda #1
    pha
    lda #$7f
    sta $dc00
    pla
    sec
    rts
mode_full:
    lda #2
    pha
    lda #$7f
    sta $dc00
    pla
    sec
    rts
}

set_tta_mode:
{
    sta TTA_MODE
    asl
    asl
    tax
    lda #32
    ldy #0
clear_mode_name:
    sta SCREEN_MODE,y
    iny
    cpy #4
    bne clear_mode_name
    ldy #0
copy_mode_name:
    lda mode_name_table,x
    sta SCREEN_MODE,y
    inx
    iny
    cpy #4
    bne copy_mode_name
    rts
}

mode_name_table:
    .encoding "screencode_mixed"
    .text "auto"
    .text "fast"
    .text "full"
    .text "guru"
