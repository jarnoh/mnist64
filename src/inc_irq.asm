// from https://trident64.github.io/overlapping-irq-handlers/

#importonce

.macro irq_setup_a(irqhandler) {
    sta $d012 // Set the low 8 bits of the rasterline in $d012
    lda #<irqhandler
    sta $fffe
    lda #>irqhandler
    sta $ffff // Set the interrupt handler address
}
.macro irq_setup(irqhandler, rasterline) {
    lda #rasterline
    sta $d012 // Set the low 8 bits of the rasterline in $d012
    lda $d011 // Set the 9th bit of the rasterline in the 8th bit of $d011
    .if (rasterline < $100) {
        and #$7f
    } else {
        ora #$80
    }
    sta $d011

    lda #<irqhandler
    sta $fffe
    lda #>irqhandler
    sta $ffff // Set the interrupt handler address
}
.macro irq_enter() {
    pha
    txa
    pha
    tya
    pha  // Store registers on the stack

    lda $1
    pha
    lda #$35
    sta $1
}
.macro irq_leave() {
    inc $d019 // Acknowledge the raster interrupt
    pla
    sta $1
    pla
    tay
    pla
    tax
    pla  // Restore processor registers from the stack
    rti  // Return from interrupt
}

.macro irq_wait_rasterline(rasterline) {
    irq_setup(anonymous, rasterline)
    irq_leave()
anonymous:
    irq_enter()
}

.macro irq_wait_rasterline_a() {
    irq_setup_a(anonymous)
    irq_leave()
anonymous:
    irq_enter()
}


.macro irq_call_wait_rasterline(subroutine, rasterline) {
   irq_setup(next, rasterline)

running: lda #0
    bne dont_call
    inc running + 1
    inc $d019
    cli
    jsr subroutine
    lda #0
    sta running + 1
dont_call:
    irq_leave()
next:
    irq_enter()
}

