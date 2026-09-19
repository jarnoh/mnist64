.const PAIRED_POPCOUNT_MACROS_ACTIVE=0

.macro inlineItems(WEIGHTS, STRIDE, START, ITEMS, FINAL, patchAddrs, MATCH_COUNT, SUBTOTAL) {
    .errorif (ITEMS < 1 || ITEMS > 32), "must contain 1..32 bytes"
    .for (var item=0; item<ITEMS; item++) {
        .var index = START+item
        lda WEIGHTS+index*STRIDE,y
        eor #$cc
        .eval patchAddrs.add(*-1)
        tax
        lda XNOR_POPCOUNT,x
        .if(item!=0) adc SUBTOTAL
        sta SUBTOTAL
    }
    .if (FINAL) {
        .if (ITEMS == 32) { bcs !subtotal_wrapped+ }
        lda MATCH_COUNT; adc SUBTOTAL; tax
        lda MATCH_COUNT+1; adc #0
        jmp !ready+
!subtotal_wrapped:
        ldx MATCH_COUNT
        lda MATCH_COUNT+1; adc #0
!ready:
    } else {
        .if (ITEMS == 32) { bcs !wrapped+ }
        lda MATCH_COUNT; adc SUBTOTAL; sta MATCH_COUNT
        bcc !+
!wrapped:
        inc MATCH_COUNT+1
        clc
!:
    }
}


.macro earlyDotChunk() {
    clc
.for (var item=0; item<EARLY_PATCH_ITEMS; item++) {
    lda EARLY_WEIGHTS+item*OUTPUT_CLASSES,y
    .eval early_patch_hi.add(*-1)
    eor #$cc
    .eval early_patch.add(*-1)
    tax
    lda XNOR_POPCOUNT,x
    .if (item != 0) { adc zp_early_subtotal }
    sta zp_early_subtotal
}
    tya; asl; tax
    lda SCORES,x; adc zp_early_subtotal; sta SCORES,x
    bcc !+
    inc SCORES+1,x
    // clc
!:
}

