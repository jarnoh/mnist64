.const zp_scroll_ptr = $20

.const SCROLL_ROW   = SCREEN + 24 * 40
.const SCROLL_COLOR = COLOR_RAM + 24 * 40

fine_scroll:    .byte 7

scroll_init:
    lda SCROLL_START_PTR
    sta zp_scroll_ptr
    lda SCROLL_START_PTR+1
    sta zp_scroll_ptr+1
    rts

scroll_tick:
{
    dec fine_scroll
    dec fine_scroll
    bpl done

    lda #6
    sta fine_scroll

    ldx #0
shift_row:
    lda SCROLL_ROW+1,x
    sta SCROLL_ROW,x
    inx
    cpx #39
    bne shift_row

    ldy #0
    lda (zp_scroll_ptr),y
    sta SCROLL_ROW+39

    inc zp_scroll_ptr
    bne pointer_incremented
    inc zp_scroll_ptr+1
pointer_incremented:

    lda (zp_scroll_ptr),y
    cmp #$ff
    bne done

    lda SCROLL_START_PTR
    sta zp_scroll_ptr
    lda SCROLL_START_PTR+1
    sta zp_scroll_ptr+1
done:
    rts
}

scroll_begin_disk_message:
    lda #<scroll_next_side
    sta zp_scroll_ptr
    sta SCROLL_START_PTR
    lda #>scroll_next_side
    sta zp_scroll_ptr+1
    sta SCROLL_START_PTR+1
    rts

scroll_end_disk_message:
    lda #<scroll_text
    sta SCROLL_START_PTR
    lda #>scroll_text
    sta SCROLL_START_PTR+1
    rts

SCROLL_START_PTR:
    .byte <scroll_text, >scroll_text

.var msg = "   INSERT DISK   "
scroll_next_side:
.for (var i = 0; i < msg.size(); i++) .byte msg.charAt(i)
scroll_next_side2:
.for (var i = 0; i < msg.size(); i++) .byte msg.charAt(i) | $80
.byte $ff

// reverse

scroll_text:
.encoding "screencode_mixed"
.text "COMPLEX presents a New World Record with  "
.byte 95,95,95,95,95
.text " MNIST64 "
.byte 95,95,95,95,95
.text "       Image digit recognizer for your favourite supercomputer!"
.text "       The task is to recognize hand drawn numbers 0-9."
.text "       Draw your own digits with 1351 mouse in port 1 or joystick in port 2."
.text "       Press SPACE to continue dataset traversal."
.text "       Press f1/f3/f5/f7 to toggle auto/fast/full/guru model"
.text "       The record breaking performance: average inference 0.653 seconds "
.byte 31,31,31
.text "  Accuracy is also state of the art: 99.42% ...or up to 99.53% in guru mode which takes two full passes."
.text "       The speed comes from 6502 optimized model architecture and hardcore machine code optimization "
.text "       Are you up to the challenge?  Can you significantly beat the record in performance or accuracy?  All this fame could be yours!  "
.text "       Paper with model architecture, test results and source code: github.com/jarnoh/mnist64"
.text "       MNIST64 comes on 6 disk sides for 10000 images from MNIST test set, providing you hours of artificial fun!   "
.text "           "
.text "       Credits:"
.text "       code by jmagic"
.text "       graphics by jate"
.text "       bepop audio codec by Aleksi Eeben"
.text "       spindle loader by LFT"
.text "       "
.text "       Released in PsyKoz 2026 @ Kuhmoinen, Finland"
.text "           "
.byte $ff
