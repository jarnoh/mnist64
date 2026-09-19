// sample playback, from bepop code, but hacked to use non-padded samples
#import "demo_layout.asm"
*=AUDIO_ORIGIN "Audio"

.const SAMPLE_BYTE=$03
.const SAMPLE_BITS=$04
.const SAMPLE_OUT=$fc
.const SAMPLE_PTR=$fd
.const SAMPLE_PTR_HI=$fe
.const SAMPLE_TIMER_PAL=252
.const SAMPLE_TIMER_NTSC=262
.const SAMPLE_DC=8

sample_end_lo: .byte 0
sample_end_hi: .byte 0

sample_init:
{
    ldx #$17
    lda #$00
clear_sid:
    sta $d400,x
    dex
    bpl clear_sid

    lda #$f0
    sta $d406
    sta $d40d
    sta $d414
    lda #$41
    sta $d404
    sta $d40b
    sta $d412

    lda #$00
    sta $dd0e
    lda #$1e
    sta $dd0d
    lda #$81
    sta $dd0d
    bit $dd0d

    lda #<sample_nmi
    sta $fffa
    lda #>sample_nmi
    sta $fffb

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
    beq is_ntsc
    lda #<SAMPLE_TIMER_PAL
    sta $dd04
    lda #>SAMPLE_TIMER_PAL
    sta $dd05
    rts
is_ntsc:
    lda #<SAMPLE_TIMER_NTSC
    sta $dd04
    lda #>SAMPLE_TIMER_NTSC
    sta $dd05

    rts
}

// A = sample index (digits 0..9, startup sample_s = 10). Full 16-bit start and
// end addresses allow clips to be packed without page-alignment padding.
sample_play:
{
    tax
    lda #$00
    sta $dd0e
    bit $dd0d

    lda sample_start_hi,x
    sta SAMPLE_PTR_HI
    lda sample_start_lo,x
    sta SAMPLE_PTR
    lda #$01
    sta SAMPLE_BITS
    lda sample_end_lo_table,x
    sta sample_end_lo
    lda sample_end_hi_table,x
    sta sample_end_hi
    lda #SAMPLE_DC
    sta SAMPLE_OUT

    lda #$11                  // Force the latch into the counter and start.
    sta $dd0e
    rts
}

sample_start_lo:
    .byte <sample_0, <sample_1, <sample_2, <sample_3, <sample_4
    .byte <sample_5, <sample_6, <sample_7, <sample_8, <sample_9, <sample_s
sample_start_hi:
    .byte >sample_0, >sample_1, >sample_2, >sample_3, >sample_4
    .byte >sample_5, >sample_6, >sample_7, >sample_8, >sample_9, >sample_s
sample_end_lo_table:
    .byte <sample_0_end, <sample_1_end, <sample_2_end, <sample_3_end, <sample_4_end
    .byte <sample_5_end, <sample_6_end, <sample_7_end, <sample_8_end, <sample_9_end, <sample_s_end
sample_end_hi_table:
    .byte >sample_0_end, >sample_1_end, >sample_2_end, >sample_3_end, >sample_4_end
    .byte >sample_5_end, >sample_6_end, >sample_7_end, >sample_8_end, >sample_9_end, >sample_s_end

.align 256
sample_lookup_table:
    .byte 2, 6, 9, 13

// Port of the CODEC=1 path from tools/C-64/bepop64-comp.s and 2bitdelta.s.
sample_nmi:
{
    sta nmi_a_smc+1
    dec $00
    lda SAMPLE_OUT
    sta $d418
    //sta $d020
    bit $dd0d              // acknowledge the interrupt (see bepop64-comp.s's NMI)

    dec SAMPLE_BITS
    bne next_bits

    // The hot path does not use Y. Preserve it only when a new byte is needed.
    lda SAMPLE_PTR
    cmp sample_end_lo
    bne refill
    lda SAMPLE_PTR_HI
    cmp sample_end_hi
    beq stop
refill:
    sty refill_y_smc+1
    ldy #$00
    lda (SAMPLE_PTR),y
refill_y_smc:
    ldy #$cc
    sta SAMPLE_BYTE
    lda #$04
    sta SAMPLE_BITS
    inc SAMPLE_PTR
    bne next_bits
    inc SAMPLE_PTR_HI
    jmp next_bits

get_lookup:
    dec SAMPLE_BITS
    bne get_lookup_bits
    lda SAMPLE_PTR
    cmp sample_end_lo
    bne lookup_refill
    lda SAMPLE_PTR_HI
    cmp sample_end_hi
    beq stop
lookup_refill:
    sty lookup_refill_y_smc+1
    ldy #$00
    lda (SAMPLE_PTR),y
lookup_refill_y_smc:
    ldy #$cc
    sta SAMPLE_BYTE
    lda #$04
    sta SAMPLE_BITS
    inc SAMPLE_PTR
    bne get_lookup_bits
    inc SAMPLE_PTR_HI
    jmp get_lookup_bits

get_lookup_bits:
    lda #$00
    asl SAMPLE_BYTE
    rol
    asl SAMPLE_BYTE
    rol
.if ((sample_lookup_table & $ff) != 0) {
    adc #<sample_lookup_table
}
    sta lookup_smc+1
lookup_smc:
    lda sample_lookup_table
    sta SAMPLE_OUT
    bpl done

next_bits:
    lda SAMPLE_OUT
    asl SAMPLE_BYTE
    bcc zero_or_one
    asl SAMPLE_BYTE
    bcs get_lookup
    // Carry is clear for code 10, so SBC #0 subtracts one.
    sbc #$00
    bpl output

zero_or_one:
    asl SAMPLE_BYTE
    bcc output
    // Carry is set for code 01, so ADC #0 adds one.
    adc #$00
output:
    sta SAMPLE_OUT
done:
    inc $00
nmi_a_smc:
    lda #$cc
    rti

stop:
    lda #$00
    sta $dd0e
    beq done
}

*=* "Samples"
sample_0:
    .import binary "data/01_0.c1"
sample_0_end:
sample_1:
    .import binary "data/02_1.c1"
sample_1_end:
sample_2:
    .import binary "data/03_2.c1"
sample_2_end:
sample_3:
    .import binary "data/04_3.c1"
sample_3_end:
sample_4:
    .import binary "data/05_4.c1"
sample_4_end:
sample_5:
    .import binary "data/06_5.c1"
sample_5_end:
sample_6:
    .import binary "data/07_6.c1"
sample_6_end:
sample_7:
    .import binary "data/08_7.c1"
sample_7_end:
sample_8:
    .import binary "data/09_8.c1"
sample_8_end:
sample_9:
    .import binary "data/10_9.c1"
sample_9_end:
sample_s:
    .import binary "data/00_scheisse.c1"
sample_s_end:
