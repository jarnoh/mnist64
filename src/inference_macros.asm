#import "macros.asm"

#if USE_PAIRED_POPCOUNT
#import "inference_macros_pair.asm"
#else
#import "inference_macros_single.asm"
#endif
.errorif (PAIRED_POPCOUNT_MACROS_ACTIVE != USE_PAIRED_POPCOUNT), "USE_PAIRED_POPCOUNT const and the #define'd preprocessor flag are out of sync -- #if only sees #define, not .const, so both must be toggled together at each build entry point"

.macro extractPatchRowFinish(r) {
.if (CONV1_KERNEL_W <= 6) {
    eor c1_p0_patch.get(r)
    tax
    lda C1_PAIR_ADDR_LO,x
    sta c1_table_patch.get(r)
    lda C1_PAIR_ADDR_HI,x
    sta c1_table_patch.get(r)+1
} else {
    sta c1_bit1_patch.get(r)
}
}

.macro extractPatchRowPlane0(r) {
.if (CONV1_KERNEL_W <= 6) {
    sta c1_p0_patch.get(r)
} else {
    sta c1_bit0_patch.get(r)
}
}

.macro extractPatchRowPhase0(r) {
    lda PLANE0+(r*3),y
    and #CONV1_ROW_MASK
    extractPatchRowPlane0(r)
    lda PLANE1+(r*3),y
    and #CONV1_ROW_MASK
    extractPatchRowFinish(r)
}

.macro extractPatchRowPhase2(r) {
.if (CONV1_KERNEL_W <= 6) {
    lda PLANE0+(r*3),y; lsr; lsr
.if (CONV1_KERNEL_W < 6) {
    and #CONV1_ROW_MASK
}
} else {
    lda PLANE0+(r*3),y; lsr; lsr; sta zp_conv1_extract_tmp
    lda PLANE0+(r*3)+1,y; ror; ror; ror; and #$c0; ora zp_conv1_extract_tmp
    and #CONV1_ROW_MASK
}
    extractPatchRowPlane0(r)
.if (CONV1_KERNEL_W <= 6) {
    lda PLANE1+(r*3),y; lsr; lsr
.if (CONV1_KERNEL_W < 6) {
    and #CONV1_ROW_MASK
}
} else {
    lda PLANE1+(r*3),y; lsr; lsr; sta zp_conv1_extract_tmp
    lda PLANE1+(r*3)+1,y; ror; ror; ror; and #$c0; ora zp_conv1_extract_tmp
    and #CONV1_ROW_MASK
}
    extractPatchRowFinish(r)
}

.macro extractPatchRowPhase4(r) {
    ldx PLANE0+(r*3),y; lda SHR4,x
    ldx PLANE0+(r*3)+1,y; ora LOW4_SHL4,x
    extractPatchRowPlane0(r)
    ldx PLANE1+(r*3),y; lda SHR4,x
    ldx PLANE1+(r*3)+1,y; ora LOW4_SHL4,x
    extractPatchRowFinish(r)
}

.macro extractPatchRowPhase6(r) {
    ldx PLANE0+(r*3),y; lda SHR6,x
    ldx PLANE0+(r*3)+1,y; ora SHL2,x
    extractPatchRowPlane0(r)
    ldx PLANE1+(r*3),y; lda SHR6,x
    ldx PLANE1+(r*3)+1,y; ora SHL2,x
    extractPatchRowFinish(r)
}


.macro inlineFinalItemsCompare(THRESH_LO, THRESH_HI) {
    cmp THRESH_HI,y
    bne !done+
    txa
    cmp THRESH_LO,y
!done:
}

.macro inlineConv2Dot(patchAddrs) {
    clc
    .if (PAIRED_POPCOUNT_MACROS_ACTIVE == 0) {
        lda #0; sta zp_conv2_match_count; sta zp_conv2_match_count+1
    }
    .const CONV2_ITEMS=CONV2_KERNEL*CONV2_KERNEL*(CONV1_FILTERS/8)
    .for (var start=0; start<CONV2_ITEMS; start+=32) {
        inlineItems(CONV2_WEIGHTS, CONV2_WEIGHT_STRIDE, start,
                    min(32, CONV2_ITEMS-start), start+32>=CONV2_ITEMS, patchAddrs,
                    zp_conv2_match_count, zp_conv2_subtotal)
    }
    inlineFinalItemsCompare(CONV2_MATCH_THRESHOLDS_LO, CONV2_MATCH_THRESHOLDS_HI)
}

.macro inlineHiddenDot(patchAddrs) {
    clc
    .if (PAIRED_POPCOUNT_MACROS_ACTIVE == 0) {
        lda #0; sta zp_hidden_match_count; sta zp_hidden_match_count+1
    }
    .for (var start=0; start<ACT2_BYTES; start+=32) {
        inlineItems(HIDDEN_WEIGHTS, HIDDEN_UNITS, start,
                    min(32, ACT2_BYTES-start), start+32>=ACT2_BYTES, patchAddrs,
                    zp_hidden_match_count, zp_hidden_subtotal)
    }
    inlineFinalItemsCompare(HIDDEN_MATCH_THRESHOLDS_LO, HIDDEN_MATCH_THRESHOLDS_HI)
}


.macro patchEarlyChunkAbs(ACT_BASE) {
    lda zp_early_weight_page
.for (var item=0; item<EARLY_PATCH_ITEMS; item++) {
    sta early_patch_hi.get(item)
}
    ldy zp_early_act_offset
.for (var item=0; item<EARLY_PATCH_ITEMS; item++) {
    lda ACT_BASE+item,y
    sta early_patch.get(item)
}
    tya
    clc
    adc #EARLY_PATCH_ITEMS
    sta zp_early_act_offset
}
