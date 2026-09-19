.const PAIRED_POPCOUNT_MACROS_ACTIVE=1

.macro inlineItems(WEIGHTS, STRIDE, START, ITEMS, FINAL, patchAddrs, MATCH_COUNT, SUBTOTAL) {
    .errorif ((ITEMS & 1) != 0), "paired items require an even count"
    .for (var item=0; item<ITEMS; item+=2) {
        .var index0 = START+item
        .var index1 = START+item+1
        lda WEIGHTS+index0*STRIDE,y
        eor #$cc
        .eval patchAddrs.add(*-1)
        tax
        lda PAIR_STATE_FIRST,x
        sta !pair_second+ +2
        lda WEIGHTS+index1*STRIDE,y
        eor #$cc
        .eval patchAddrs.add(*-1)
        tax
!pair_second:
        lda $ff00,x
        .if (item != 0) { adc SUBTOTAL }
        .if (item+2 < ITEMS) { sta SUBTOTAL }
    }
    .if (START == 0) {
        // Seed the total; carry holds the high bit of a 256-match subtotal.
        // ROL also clears carry for the next chunk (A starts at zero).
        .if (FINAL) {
            tax
            lda #0; rol
        } else {
            sta MATCH_COUNT
            lda #0; rol; sta MATCH_COUNT+1
        }
    } else .if (FINAL) {
        .if (ITEMS == 32) { bcs !subtotal_wrapped+ }
        adc MATCH_COUNT; tax
        lda MATCH_COUNT+1; adc #0
        jmp !ready+
!subtotal_wrapped:
        ldx MATCH_COUNT
        lda MATCH_COUNT+1; adc #0
!ready:
    } else {
        .if (ITEMS == 32) { bcs !wrapped+ }
        adc MATCH_COUNT; sta MATCH_COUNT
        bcc !+
!wrapped:
        inc MATCH_COUNT+1
        clc
!:
    }
}


.macro earlyDotChunk() {
    clc
    .const EARLY_PAIRED_ITEMS=EARLY_PATCH_ITEMS & $fe
.for (var item=0; item<EARLY_PAIRED_ITEMS; item+=2) {
    lda EARLY_WEIGHTS+item*OUTPUT_CLASSES,y
    .eval early_patch_hi.add(*-1)
    eor #$cc
    .eval early_patch.add(*-1)
    tax
    lda PAIR_STATE_FIRST,x
    sta !pair_second+ +2
    lda EARLY_WEIGHTS+(item+1)*OUTPUT_CLASSES,y
    .eval early_patch_hi.add(*-1)
    eor #$cc
    .eval early_patch.add(*-1)
    tax
!pair_second:
    lda $ff00,x
    .if (item != 0) { adc zp_early_subtotal }
    sta zp_early_subtotal
}
.if ((EARLY_PATCH_ITEMS & 1) != 0) {
    lda EARLY_WEIGHTS+(EARLY_PATCH_ITEMS-1)*OUTPUT_CLASSES,y
    .eval early_patch_hi.add(*-1)
    eor #$cc
    .eval early_patch.add(*-1)
    tax
    lda XNOR_POPCOUNT,x
    .if (EARLY_PATCH_ITEMS != 1) { adc zp_early_subtotal }
    sta zp_early_subtotal
}
    tya; asl; tax
    lda SCORES,x; adc zp_early_subtotal; sta SCORES,x
    bcc !+
    inc SCORES+1,x
    // clc
!: 
}
