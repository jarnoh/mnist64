#import "macros.asm"

.function popcount8(value) {
    .return ((value>>0)&1)+((value>>1)&1)+((value>>2)&1)+((value>>3)&1)+((value>>4)&1)+((value>>5)&1)+((value>>6)&1)+((value>>7)&1)
}

*=LOOKUP_TABLES_ORIGIN "Lookup tables"

.align 256
#if USE_PAIRED_POPCOUNT
#else
XNOR_POPCOUNT: .fill 256, 8-popcount8(i)
#endif

.align 256
C1_PAIR_TABLE: .fill 64*64, (CONV1_KERNEL_W-popcount8(i&63)+2*(CONV1_KERNEL_W-popcount8((i&63)^(i>>6))))

SHR6:
.for (var i=0; i<256; i++) .byte ((i >> 6) & CONV1_ROW_MASK)
SHR4:
.for (var i=0; i<256; i++) .byte ((i >> 4) & CONV1_ROW_MASK)
LOW4_SHL4:
.for (var i=0; i<256; i++) .byte (((i & 15) << 4) & CONV1_ROW_MASK)
SHL2:
.for (var i=0; i<256; i++) .byte ((i << 2) & CONV1_ROW_MASK)

C1_PAIR_ADDR_LO: .fill 64, <(C1_PAIR_TABLE+i*64)
assertSamePage(C1_PAIR_ADDR_LO)
C1_PAIR_ADDR_HI: .fill 64, >(C1_PAIR_TABLE+i*64)
assertSamePage(C1_PAIR_ADDR_HI)

C2_POS_LO:
.for (var y=0; y<CONV2_OUT_SIDE_H; y++) .for (var x=0; x<CONV2_OUT_SIDE_W; x++) .byte <(ACT1+(y*CONV2_STRIDE*CONV1_OUT_SIDE_W+x*CONV2_STRIDE)*(CONV1_FILTERS/8))
assertSamePage(C2_POS_LO)
C2_POS_HI:
.for (var y=0; y<CONV2_OUT_SIDE_H; y++) .for (var x=0; x<CONV2_OUT_SIDE_W; x++) .byte >(ACT1+(y*CONV2_STRIDE*CONV1_OUT_SIDE_W+x*CONV2_STRIDE)*(CONV1_FILTERS/8))
assertSamePage(C2_POS_HI)

.align 256
FILTER_BYTE_INDEX:
.for (var i=0; i<HIDDEN_UNITS; i++) .byte i/8
assertSamePage(FILTER_BYTE_INDEX)

LOOKUP_TABLES_END:

.label PAIR_STATE_FIRST=PAIR_STATE_ORIGIN
#if USE_PAIRED_POPCOUNT
.errorif (* > PAIR_STATE_ORIGIN), "test payload overlaps pair-state lookup tables"
*=PAIR_STATE_ORIGIN "Pair-state lookup tables"
.for (var value=0; value<256; value++) .byte (>(PAIR_STATE_ORIGIN+256))+(8-popcount8(value))
XNOR_POPCOUNT:
.for (var state=0; state<=8; state++) {
    .for (var value=0; value<256; value++) .byte state+(8-popcount8(value))
}
#endif
