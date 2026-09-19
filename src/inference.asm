#import "generated_model_header.asm"
#import "demo_layout.asm"
#import "macros.asm"

#import "build_defaults.asm"
#import "audio.sym"

*=sample_s_end "Inference"

#import "lookup.sym"
#import "model_symbols.asm"

.label inference_abort_hook=INFERENCE_ABORT_HOOK
.label inference_display_hook=INFERENCE_DISPLAY_HOOK
.label inference_early_hook=INFERENCE_EARLY_HOOK

// temp zp stuff, destroyed between layers

.const zp_conv1_output_ptr=$40
.const zp_conv1_positions_remaining=$42
.const zp_conv1_column=$43
.const zp_conv1_plane_offset=$44
.const zp_conv1_packed_output=$45
.const zp_conv1_match_count=$46
.const zp_conv1_extract_tmp=$48

.const zp_early_weight_page=$40
.const zp_early_act_offset=$42
.const zp_early_phase=$43
.const zp_early_chunks_remaining=$44
.const zp_early_subtotal=$48
.const zp_early_scale_class_index=$40
.const zp_early_scaled_score=$46
.const zp_early_margin_low=$48

.const zp_argmax_class_index=$40
.const zp_argmax_best=$41
.const zp_argmax_candidate=$43

.const zp_runnerup_class_index=$40
.const zp_runnerup_saved=$41
.const zp_runnerup_score=$43
.const zp_runnerup_candidate_staging=$45

.const zp_early_top2_class=$40
.const zp_early_top2_second=$43

.const zp_signed_ge_candidate=$43
.const zp_signed_ge_reference=$45
.const zp_signed_ge_candidate_key=$48

.const zp_conv2_output_ptr=$40
.const zp_conv2_position=$42
.const zp_conv2_input_ptr=$43
.const zp_conv2_packed_output=$45
.const zp_conv2_match_count=$46
.const zp_conv2_subtotal=$48

.const zp_hidden_packed_output=$45
.const zp_hidden_match_count=$46
.const zp_hidden_subtotal=$48

.const zp_output_active_count=$40
.const zp_output_activation_bits=$41
.const zp_output_bits_remaining=$42

.const zp_tta_margin=$40

#import "inference_macros.asm"

.macro inferenceAbort() {
    .if (ENABLE_INFERENCE_ABORT == 1) {
        jsr inference_abort_hook
        bcc !+
        lda #$ff
        rts
    !:
    }
}



run_inference:
    lda TTA_MODE
    sta INF_MODE
    jsr run_conv1
cyc_after_conv1:
    inferenceAbort()
    jsr inference_display_hook
.if (INCLUDE_VERIFICATION_SCORES == 1) {
    jsr run_early
cyc_after_early:
    lda RESULT_CLASS; sta EARLY_CLASS
    ldx #(SCORE_BYTES-1)
!:
    lda SCORES,x; sta EARLY_SCORES,x
    dex; bpl !-
    .byte $80,$00 // timing NOP
} else {
    lda INF_MODE
    cmp #TTA_FULL
    bcs ri_go_full2
    jsr run_early
cyc_after_early:
    php
    lda RESULT_CLASS; sta EARLY_CLASS
    ldx #(SCORE_BYTES-1)
!:
    lda SCORES,x; sta EARLY_SCORES,x
    dex; bpl !-
    jsr inference_early_hook
    lda INF_MODE
    cmp #TTA_EARLY_ONLY
    beq ri_take_early
    cmp #TTA_AUTO
    bne ri_go_full
    plp
    bcs ri_early_done
    jmp ri_go_full2
ri_take_early:
    plp
ri_early_done:
    lda #0; sta TTA_HIT
    jmp ri_done
ri_go_full:
    plp
ri_go_full2:
}
    jsr run_conv2
cyc_after_conv2:
    inferenceAbort()
    jsr run_hidden
cyc_after_hidden:
    inferenceAbort()
    jsr run_output
cyc_after_output:
    inferenceAbort()
    jsr argmax
cyc_after_argmax:
    lda INF_MODE
    cmp #TTA_FULL2X
    beq ri_tta_always
    cmp #TTA_AUTO
    beq ri_tta_gate
    jmp ri_tta_never
ri_tta_gate:
    jsr tta_gate
    jmp ri_tta_check
ri_tta_never:
    sec
    jmp ri_tta_check
ri_tta_always:
    clc
ri_tta_check:
    lda #0; sta TTA_HIT
    bcs ri_done
    lda #1; sta TTA_HIT
    ldx #(SCORE_BYTES-1)
ri_save_scores:
    lda SCORES,x; sta SCORES_A,x
    dex; bpl ri_save_scores
    jsr shift_planes_up_in_place
    jsr run_conv1
    inferenceAbort()
    jsr run_conv2
    inferenceAbort()
    jsr run_hidden
    inferenceAbort()
    jsr run_output
    inferenceAbort()
    jsr sum_scores_with_a
    jsr argmax
ri_done:
    lda INF_MODE
    cmp #TTA_EARLY_ONLY
    bne !+
    lda EARLY_CLASS; sta RESULT_CLASS
!:
    lda RESULT_CLASS
    rts


.var c1_p0_patch = List()
.var c1_table_patch = List()
.var c1_bit0_patch = List()
.var c1_bit1_patch = List()
run_conv1: {
    lda #<ACT1; sta zp_conv1_output_ptr
    lda #>ACT1; sta zp_conv1_output_ptr+1
    lda #(CONV1_OUT_SIDE_H*CONV1_OUT_SIDE_W); sta zp_conv1_positions_remaining
    lda #0
    sta zp_conv1_column
    sta zp_conv1_plane_offset
    jmp rc1_extract
rc1_filter_start:
    lda #$01; sta zp_conv1_packed_output
    ldy #(CONV1_FILTERS-1)
.if (CONV1_KERNEL_W <= 6) {
    clc
}
rc1_filter:
    //lda #0; sta zp_conv1_match_count
.if (CONV1_KERNEL_W <= 6) {
.for (var n=0; n<CONV1_KERNEL_H; n++) {
    lda CONV1_WEIGHTS+n*CONV1_FILTERS,y
    eor #$cc
    .eval c1_p0_patch.add(*-1)
    tax
    lda C1_PAIR_TABLE,x
    .eval c1_table_patch.add(*-2)
    .if (n != 0) { adc zp_conv1_match_count }
    .if (n != CONV1_KERNEL_H-1) { sta zp_conv1_match_count }
}
} else {
    lda #0; sta zp_conv1_match_count
.for (var n=0; n<CONV1_KERNEL_H; n++) {
    lda CONV1_WEIGHTS+n*CONV1_FILTERS,y
    eor #$cc
    .eval c1_bit0_patch.add(*-1)
    tax
    lda XNOR_POPCOUNT,x
    clc; adc zp_conv1_match_count; sta zp_conv1_match_count
    lda CONV1_WEIGHTS+n*CONV1_FILTERS,y
    eor #$cc
    .eval c1_bit1_patch.add(*-1)
    tax
    lda XNOR_POPCOUNT,x
    asl
    clc; adc zp_conv1_match_count
    .if (n != CONV1_KERNEL_H-1) { sta zp_conv1_match_count }
}
}
    cmp CONV1_MATCH_THRESHOLDS,y
.if (CONV1_ALL_POSITIVE == 0) {
    tya; tax
    lda CONV1_POLARITY,x
    bne rc1_push
    bcs rc1_false
    sec; bcs rc1_push
rc1_false:
    clc
}
rc1_push:
    rol zp_conv1_packed_output
    bcc rc1_packed
    tya; tax
    ldy FILTER_BYTE_INDEX,x
    lda zp_conv1_packed_output; sta (zp_conv1_output_ptr),y
    lda #$01; sta zp_conv1_packed_output
    txa; tay
.if (CONV1_KERNEL_W <= 6) {
    clc
}
rc1_packed:
    dey
    bpl rc1_filter
rc1_filters_done:
    clc
    lda zp_conv1_output_ptr; adc #(CONV1_FILTERS/8); sta zp_conv1_output_ptr
    bcc !+
    inc zp_conv1_output_ptr+1
!:
    inc zp_conv1_column
    lda zp_conv1_column; cmp #CONV1_OUT_SIDE_W
    bne rc1_advance_column
    lda #0; sta zp_conv1_column
    clc
    lda zp_conv1_plane_offset; adc #(C1_SOURCE_ROW_STEP-2); sta zp_conv1_plane_offset
    jmp rc1_check_done
rc1_advance_column:
    and #3
    bne rc1_check_done
    inc zp_conv1_plane_offset
rc1_check_done:
    dec zp_conv1_positions_remaining
    bne rc1_pos
rc1_done:
    rts

rc1_pos:
rc1_extract:
    ldy zp_conv1_plane_offset
    lda zp_conv1_column
    and #3
    lsr
    bcc rce_even_phase
    beq rce_go_phase2
    jmp rce_phase6
rce_even_phase:
    beq rce_go_phase0
    jmp rce_phase4
rce_go_phase2:
    jmp rce_phase2
rce_go_phase0:
    jmp rce_phase0
rce_phase0:
.for (var r=0; r<CONV1_KERNEL_H; r++) extractPatchRowPhase0(r)
    jmp rc1_filter_start
rce_phase2:
.for (var r=0; r<CONV1_KERNEL_H; r++) extractPatchRowPhase2(r)
    jmp rc1_filter_start
rce_phase4:
.for (var r=0; r<CONV1_KERNEL_H; r++) extractPatchRowPhase4(r)
    jmp rc1_filter_start
rce_phase6:
.for (var r=0; r<CONV1_KERNEL_H; r++) extractPatchRowPhase6(r)
    jmp rc1_filter_start
}


.var c2_patch = List()
run_conv2: {
    lda #<ACT2; sta zp_conv2_output_ptr
    lda #>ACT2; sta zp_conv2_output_ptr+1
    lda #0; sta zp_conv2_position
rc2_pos:
    ldx zp_conv2_position
    lda C2_POS_LO,x; sta zp_conv2_input_ptr
    lda C2_POS_HI,x; sta zp_conv2_input_ptr+1
    jsr patch_conv2
    lda #$01; sta zp_conv2_packed_output
    ldy #(CONV2_FILTERS-1)
rc2_filter:
    inlineConv2Dot(c2_patch)
.if (CONV2_ALL_POSITIVE == 0) {
    tya; tax
    lda CONV2_POLARITY,x
    bne rc2_push
    bcs rc2_false
    sec; bcs rc2_push
rc2_false:
    clc
}
rc2_push:
    rol zp_conv2_packed_output
    bcc rc2_packed
    tya; tax
    ldy FILTER_BYTE_INDEX,x
    lda zp_conv2_packed_output; sta (zp_conv2_output_ptr),y
    lda #$01; sta zp_conv2_packed_output
    txa; tay
rc2_packed:
    dey
    bmi rc2_filters_done
    jmp rc2_filter
rc2_filters_done:
    clc
    lda zp_conv2_output_ptr; adc #(CONV2_FILTERS/8); sta zp_conv2_output_ptr
    bcc !+
    inc zp_conv2_output_ptr+1
!:
    inc zp_conv2_position
    lda zp_conv2_position; cmp #(CONV2_OUT_SIDE_H*CONV2_OUT_SIDE_W)
    beq rc2_done
    jmp rc2_pos
rc2_done:
    rts

patch_conv2:
.for (var py=0; py<CONV2_KERNEL; py++) {
    ldy #(py*CONV1_OUT_SIDE_W*(CONV1_FILTERS/8))
    .for (var bx=0; bx<CONV2_KERNEL*(CONV1_FILTERS/8); bx++) {
        lda (zp_conv2_input_ptr),y
        sta c2_patch.get(py*CONV2_KERNEL*(CONV1_FILTERS/8)+bx)
        .if (bx < CONV2_KERNEL*(CONV1_FILTERS/8)-1) { iny }
    }
}
    rts
}

.var hidden_patch = List()
run_hidden: {
    jsr patch_hidden
    lda #$01; sta zp_hidden_packed_output
    ldy #(HIDDEN_UNITS-1)
rh_loop:
    inlineHiddenDot(hidden_patch)
.if (HIDDEN_ALL_POSITIVE == 0) {
    tya; tax
    lda HIDDEN_POLARITY,x
    bne rh_push
    bcs rh_false
    sec; bcs rh_push
rh_false:
    clc
}
rh_push:
    rol zp_hidden_packed_output
    bcc rh_packed
    tya; tax
    ldy FILTER_BYTE_INDEX,x
    lda zp_hidden_packed_output; sta HACT,y
    lda #$01; sta zp_hidden_packed_output
    txa; tay
rh_packed:
    dey
    bmi rh_done
    jmp rh_loop
rh_done:
    rts

patch_hidden:
.for (var item=0; item<ACT2_BYTES; item++) {
    lda ACT2+item
    sta hidden_patch.get(item)
}
    rts
}



.var early_patch = List()
.var early_patch_hi = List()
.const EARLY_PATCH_ITEMS=ACT1_BYTES/EARLY_PATCH_CHUNKS
.errorif (ACT1_BYTES != EARLY_PATCH_CHUNKS*EARLY_PATCH_ITEMS), "ACT1_BYTES must be an exact multiple of EARLY_PATCH_CHUNKS"

.const EARLY_PATCH_PHASE_A_CHUNKS=floor(256/EARLY_PATCH_ITEMS)
.const EARLY_PATCH_PHASE_B_CHUNKS=EARLY_PATCH_CHUNKS-EARLY_PATCH_PHASE_A_CHUNKS
.const EARLY_PATCH_PHASE_B_BASE=EARLY_PATCH_PHASE_A_CHUNKS*EARLY_PATCH_ITEMS
.errorif ((EARLY_PATCH_PHASE_A_CHUNKS-1)*EARLY_PATCH_ITEMS+(EARLY_PATCH_ITEMS-1) > 255), "phase A offset+item exceeds Y range"
.errorif (EARLY_PATCH_PHASE_B_CHUNKS < 1), "phase B must have at least one chunk"
.errorif ((EARLY_PATCH_PHASE_B_CHUNKS-1)*EARLY_PATCH_ITEMS+(EARLY_PATCH_ITEMS-1) > 255), "phase B offset+item exceeds Y range"

run_early: {
    lda #>EARLY_WEIGHTS; sta zp_early_weight_page
    lda #0; sta zp_early_act_offset
    sta zp_early_phase
    ldx #(SCORE_BYTES-1)
re_clear_scores:
    sta SCORES,x
    dex; bpl re_clear_scores
    lda #EARLY_PATCH_PHASE_A_CHUNKS; sta zp_early_chunks_remaining
    jmp re_chunk
re_class:
    earlyDotChunk()
    dey
    bmi re_class_done
    jmp re_class
re_class_done:
    dec zp_early_chunks_remaining
    bne re_more_chunks
    lda zp_early_phase
    bne re_chunks_done_dispatch
    jmp re_phase_switch
re_chunks_done_dispatch:
    jmp re_chunks_done
re_more_chunks:
    inc zp_early_weight_page
    jmp re_chunk

re_phase_switch:
    inc zp_early_weight_page
    lda #1; sta zp_early_phase
    lda #0; sta zp_early_act_offset
    lda #EARLY_PATCH_PHASE_B_CHUNKS; sta zp_early_chunks_remaining
    jmp re_chunk

re_chunks_done:
    jmp re_scale_start
re_chunk:
    lda zp_early_phase
    beq re_chunk_phase_a
    jmp re_chunk_phase_b
re_chunk_phase_a:
    patchEarlyChunkAbs(ACT1) // earlyDotChunk needs to be evaluated first
    jmp re_chunk_common
re_chunk_phase_b:
    patchEarlyChunkAbs(ACT1+EARLY_PATCH_PHASE_B_BASE)
re_chunk_common:
    ldy #(OUTPUT_CLASSES-1)
    jmp re_class

re_scale_start:
.if (EARLY_BIAS_ALL_ZERO == 1) {
    ldx #0
re_scale:
    asl SCORES,x
    rol SCORES+1,x
    inx; inx
    cpx #SCORE_BYTES; bne re_scale
} else {
    lda #0; sta zp_early_scale_class_index
re_scale:
    lda zp_early_scale_class_index; asl; tax
    lda SCORES,x; sta zp_early_scaled_score
    lda SCORES+1,x; sta zp_early_scaled_score+1
    asl zp_early_scaled_score; rol zp_early_scaled_score+1
    ldx zp_early_scale_class_index
    clc
    lda zp_early_scaled_score; adc EARLY_BIAS_LO,x; sta zp_early_scaled_score
    lda zp_early_scaled_score+1; adc EARLY_BIAS_HI,x; sta zp_early_scaled_score+1
    lda zp_early_scale_class_index; asl; tax
    lda zp_early_scaled_score; sta SCORES,x
    lda zp_early_scaled_score+1; sta SCORES+1,x
    inc zp_early_scale_class_index
    lda zp_early_scale_class_index; cmp #OUTPUT_CLASSES; bne re_scale
}
.if (EARLY_BIAS_ALL_ZERO == 1) {
    jsr early_top2
} else {
    jsr argmax
    jsr find_runnerup
    lda zp_runnerup_score; sta zp_early_top2_second
    lda zp_runnerup_score+1; sta zp_early_top2_second+1
}
    lda RESULT_CLASS; asl; tax
    sec
    lda SCORES,x; sbc zp_early_top2_second; sta zp_early_margin_low
    lda SCORES+1,x; sbc zp_early_top2_second+1
    bne re_accept
    lda zp_early_margin_low
    ldy RESULT_CLASS
    cmp EARLY_THRESHOLDS,y
    rts
re_accept:
    sec
    rts

// unsigned single-pass top-two scan over SCORES
early_top2: {
    lda SCORES; sta zp_argmax_best
    lda SCORES+1; sta zp_argmax_best+1
    lda #0; sta zp_early_top2_second
    lda #0; sta zp_early_top2_second+1
    lda #0; sta RESULT_CLASS
    lda #1; sta zp_early_top2_class
    ldx #2
et_loop:
    lda SCORES+1,x
    cmp zp_argmax_best+1
    bcc et_check_second
    bne et_new_best
    lda SCORES,x
    cmp zp_argmax_best
    bcc et_check_second
et_new_best:
    lda zp_argmax_best; sta zp_early_top2_second
    lda zp_argmax_best+1; sta zp_early_top2_second+1
    lda SCORES,x; sta zp_argmax_best
    lda SCORES+1,x; sta zp_argmax_best+1
    lda zp_early_top2_class; sta RESULT_CLASS
    jmp et_next
et_check_second:
    lda SCORES+1,x
    cmp zp_early_top2_second+1
    bcc et_next
    bne et_new_second
    lda SCORES,x
    cmp zp_early_top2_second
    bcc et_next
et_new_second:
    lda SCORES,x; sta zp_early_top2_second
    lda SCORES+1,x; sta zp_early_top2_second+1
et_next:
    inx; inx
    inc zp_early_top2_class
    lda zp_early_top2_class; cmp #OUTPUT_CLASSES; bne et_loop
    rts
}
}

find_runnerup: {
    lda #0; sta zp_runnerup_score
    lda #$80; sta zp_runnerup_score+1
    lda #0; sta zp_runnerup_class_index
fr_loop:
    lda zp_runnerup_class_index; cmp RESULT_CLASS; beq fr_next
    asl; tax
    lda SCORES,x; sta zp_runnerup_candidate_staging
    lda SCORES+1,x; sta zp_runnerup_candidate_staging+1
    lda zp_runnerup_score; sta zp_runnerup_saved
    lda zp_runnerup_score+1; sta zp_runnerup_saved+1
    lda zp_runnerup_candidate_staging; sta zp_signed_ge_candidate
    lda zp_runnerup_candidate_staging+1; sta zp_signed_ge_candidate+1
    lda zp_runnerup_saved; sta zp_signed_ge_reference
    lda zp_runnerup_saved+1; sta zp_signed_ge_reference+1
    jsr signed_ge
    bcc fr_restore
    jmp fr_next
fr_restore:
    lda zp_signed_ge_reference; sta zp_runnerup_score
    lda zp_signed_ge_reference+1; sta zp_runnerup_score+1
fr_next:
    inc zp_runnerup_class_index
    lda zp_runnerup_class_index; cmp #OUTPUT_CLASSES; bne fr_loop
    rts
}

tta_gate: {
    jsr find_runnerup
    lda RESULT_CLASS; asl; tax
    sec
    lda SCORES,x; sbc zp_runnerup_score; sta zp_tta_margin
    lda SCORES+1,x; sbc zp_runnerup_score+1; sta zp_tta_margin+1
    ldy RESULT_CLASS
    lda zp_tta_margin+1; cmp TTA_THRESHOLDS_HI,y
    bne tg_cmp_done
    lda zp_tta_margin; cmp TTA_THRESHOLDS_LO,y
tg_cmp_done:
    rts
}

sum_scores_with_a: {
    ldx #0
ssa_loop:
    clc
    lda SCORES,x; adc SCORES_A,x; sta SCORES,x
    inx
    lda SCORES,x; adc SCORES_A,x; sta SCORES,x
    inx
    cpx #SCORE_BYTES; bne ssa_loop
    rts
}

shift_planes_up_in_place: {
    ldy #0
spu_loop:
    lda PLANE0+C1_PLANE_ROW_BYTES,y; sta PLANE0,y
    lda PLANE1+C1_PLANE_ROW_BYTES,y; sta PLANE1,y
    iny
    cpy #((IMAGE_SIDE-1)*C1_PLANE_ROW_BYTES); bne spu_loop
    rts
}

run_output: {
.for (var class=0; class<OUTPUT_CLASSES; class++) {
    lda OUTPUT_HALF_BASE_LO+class; sta SCORES+class*2
    lda OUTPUT_HALF_BASE_HI+class; sta SCORES+class*2+1
}
    lda #0; sta zp_output_active_count
    ldx #0
    ldy #0
ro_byte:
    lda HACT,x; sta zp_output_activation_bits
    lda #8; sta zp_output_bits_remaining
ro_bit:
    lsr zp_output_activation_bits
    bcs !active+
    jmp ro_skip
!active:
    inc zp_output_active_count
.for (var class=0; class<OUTPUT_CLASSES; class++) {
    clc
    lda SCORES+class*2
    adc OUTPUT_WEIGHTS_U8+class*OUTPUT_WEIGHT_STRIDE,y
    sta SCORES+class*2
    lda SCORES+class*2+1
    adc #0
    sta SCORES+class*2+1
}
ro_skip:
    iny
    dec zp_output_bits_remaining
    beq !byte_done+
    jmp ro_bit
!byte_done:
    inx; cpx #HIDDEN_ACT_BYTES
    beq !normalize+
    jmp ro_byte
!normalize:
    ldx #0
    ldy #0
ro_normalize:
    asl SCORES,x
    rol SCORES+1,x
    lda OUTPUT_BASE_PARITY,y
    beq !even+
    inc SCORES,x
!even:
    sec
    lda SCORES+1,x
    sbc zp_output_active_count
    sta SCORES+1,x
    inx; inx
    iny; cpy #OUTPUT_CLASSES
    bne ro_normalize
    rts
}

signed_ge: {
    lda zp_signed_ge_candidate+1; eor #$80; sta zp_signed_ge_candidate_key
    lda zp_signed_ge_reference+1; eor #$80; cmp zp_signed_ge_candidate_key
    beq sg_low
    bcc sg_true
    clc; rts
sg_low:
    lda zp_signed_ge_candidate; cmp zp_signed_ge_reference; rts
sg_true:
    sec; rts
}

argmax: {
    lda SCORES; sta zp_argmax_best
    lda SCORES+1; sta zp_argmax_best+1
    lda #0; sta RESULT_CLASS
    lda #1; sta zp_argmax_class_index
am_loop:
    lda zp_argmax_class_index; asl; tax
    lda SCORES,x; sta zp_argmax_candidate
    lda SCORES+1,x; sta zp_argmax_candidate+1
    lda zp_argmax_best; sta zp_signed_ge_reference
    lda zp_argmax_best+1; sta zp_signed_ge_reference+1
    jsr signed_ge
    bcc am_next
    lda zp_argmax_candidate; sta zp_argmax_best
    lda zp_argmax_candidate+1; sta zp_argmax_best+1
    lda zp_argmax_class_index; sta RESULT_CLASS
am_next:
    inc zp_argmax_class_index
    lda zp_argmax_class_index; cmp #OUTPUT_CLASSES; bne am_loop
    rts
}

*=* "Inference Variables"

SAVED_PORT: .byte 0
RESULT_DONE: .byte 0
RESULT_CLASS: .byte 0
RESULT_CORRECT: .byte 0
TTA_HIT: .byte 0
EARLY_CLASS: .byte 0
TTA_MODE: .byte TTA_DEFAULT_MODE
INF_MODE: .byte TTA_DEFAULT_MODE // TTA_MODE latched at inference start; IRQ may change TTA_MODE mid-run

.align 256
*=* "Inference Arrays"
ACT2: .fill ACT2_BYTES,0
HACT: .fill HIDDEN_ACT_BYTES,0
ACT1: .fill ACT1_BYTES,0
ACT1_END:

.align 256
PLANE0: .fill PLANE_BYTES,0
PLANE1: .fill PLANE_BYTES,0

SCORES: .fill SCORE_BYTES,0
EARLY_SCORES: .fill SCORE_BYTES,0
SCORES_A: .fill SCORE_BYTES,0
INFERENCE_END:
