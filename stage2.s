/*_____________________________________________________________________________
 │                                                                            |
 │ COPYRIGHT (C) 2022 Mihai Baneu                                             |
 │                                                                            |
 | Permission is hereby  granted,  free of charge,  to any person obtaining a |
 | copy of this software and associated documentation files (the "Software"), |
 | to deal in the Software without restriction,  including without limitation |
 | the rights to  use, copy, modify, merge, publish, distribute,  sublicense, |
 | and/or sell copies  of  the Software, and to permit  persons to  whom  the |
 | Software is furnished to do so, subject to the following conditions:       |
 |                                                                            |
 | The above  copyright notice  and this permission notice  shall be included |
 | in all copies or substantial portions of the Software.                     |
 |                                                                            |
 | THE SOFTWARE IS PROVIDED  "AS IS",  WITHOUT WARRANTY OF ANY KIND,  EXPRESS |
 | OR   IMPLIED,   INCLUDING   BUT   NOT   LIMITED   TO   THE  WARRANTIES  OF |
 | MERCHANTABILITY,  FITNESS FOR  A  PARTICULAR  PURPOSE AND NONINFRINGEMENT. |
 | IN NO  EVENT SHALL  THE AUTHORS  OR  COPYRIGHT  HOLDERS  BE LIABLE FOR ANY |
 | CLAIM, DAMAGES OR OTHER LIABILITY,  WHETHER IN AN ACTION OF CONTRACT, TORT |
 | OR OTHERWISE, ARISING FROM,  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR  |
 | THE USE OR OTHER DEALINGS IN THE SOFTWARE.                                 |
 |____________________________________________________________________________|
 |                                                                            |
 |  Author: Mihai Baneu                           Last modified: 18.Dec.2022  |
 |                                                                            |
 |___________________________________________________________________________*/

/* Original code part of the pico SDK
   https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/boot_stage2/boot2_w25q080.S */

#include "hardware/platform_defs.h"
#include "hardware/regs/addressmap.h"
#include "hardware/regs/ssi.h"
#include "hardware/regs/pads_qspi.h"
#include "hardware/regs/m0plus.h"

#define PADS_QSPI_SCKL_CONFIG    (2 << PADS_QSPI_GPIO_QSPI_SCLK_DRIVE_LSB | PADS_QSPI_GPIO_QSPI_SCLK_SLEWFAST_BITS)
#define PADS_QSPI_SD_CONFIG      (1 << PADS_QSPI_GPIO_QSPI_SD0_DRIVE_LSB  | PADS_QSPI_GPIO_QSPI_SD0_IE_BITS )
#define SSI_BAUDR_CONFIG         2
#define SSI_RX_SAMPLE_DLY_CONFIG 1

#define CMD_READ          0xEB  // "Read data fast quad IO" instruction
#define CMD_WRITE_ENABLE  0x06  // write enable instruction sets the Write Enable Latch (WEL) bit in the Status Register to a 1
#define CMD_READ_STATUS1  0x05  // read status register 1
#define CMD_READ_STATUS2  0x35  // read status register 2
#define CMD_WRITE_STATUS1 0x01  // write status register 1
#define CMD_WRITE_STATUS2 0x31  // write status register 2

// "Mode bits" are 8 special bits sent immediately after
// the address bits in a "Read Data Fast Quad I/O" command sequence. 
// On W25Q080, the four LSBs are don't care, and if MSBs == 0xa, the
// next read does not require the 0xeb instruction prefix.
#define MODE_CONTINUOUS_READ 0xa0

// The number of address + mode bits, divided by 4 (always 4, not function of
// interface width).
#define ADDR_L 8

// How many clocks of Hi-Z following the mode bits. For W25Q080, 4 dummy cycles
// are required.
#define WAIT_CYCLES 4

// QE Status flag
#define SREG_DATA 0x02  

// SSI configuration for setting the status registers on the flash
#define CTRL0_SPI_TXRX \
    (7 << SSI_CTRLR0_DFS_32_LSB)                                           | /* 8 bits per data frame */ \
    (SSI_CTRLR0_TMOD_VALUE_TX_AND_RX << SSI_CTRLR0_TMOD_LSB)

// SSI configuration for XIP usage
#define CTRLR0_ENTER_XIP \
   (SSI_CTRLR0_SPI_FRF_VALUE_QUAD << SSI_CTRLR0_SPI_FRF_LSB)               |                                    \
   (31 << SSI_CTRLR0_DFS_32_LSB)                                           | /* 32 data bits */                 \
   (SSI_CTRLR0_TMOD_VALUE_EEPROM_READ << SSI_CTRLR0_TMOD_LSB)                /* Send INST/ADDR, Receive Data */ 

// SSI SPI configuration for first XIP command
#define SPI_CTRLR0_ENTER_XIP \
    (ADDR_L << SSI_SPI_CTRLR0_ADDR_L_LSB)                                  | /* Address + mode bits */                                       \
    (WAIT_CYCLES << SSI_SPI_CTRLR0_WAIT_CYCLES_LSB)                        | /* Hi-Z dummy clocks following address + mode */                \
    (SSI_SPI_CTRLR0_INST_L_VALUE_8B << SSI_SPI_CTRLR0_INST_L_LSB)          | /* 8-bit instruction */                                         \
    (SSI_SPI_CTRLR0_TRANS_TYPE_VALUE_1C2A << SSI_SPI_CTRLR0_TRANS_TYPE_LSB)  /* Send Command in serial mode then address in Quad I/O mode */

// SSI SPI configuration for normal operation under XIP
#define SPI_CTRLR0_XIP \
    (MODE_CONTINUOUS_READ << SSI_SPI_CTRLR0_XIP_CMD_LSB)                   | /* Mode bits to keep flash in continuous read mode */                        \
    (ADDR_L << SSI_SPI_CTRLR0_ADDR_L_LSB)                                  | /* Total number of address + mode bits */                                    \
    (WAIT_CYCLES << SSI_SPI_CTRLR0_WAIT_CYCLES_LSB)                        | /* Hi-Z dummy clocks following address + mode */                             \
    (SSI_SPI_CTRLR0_INST_L_VALUE_NONE  << SSI_SPI_CTRLR0_INST_L_LSB)       | /* Do not send a command, instead send XIP_CMD as mode bits after address */ \
    (SSI_SPI_CTRLR0_TRANS_TYPE_VALUE_2C2A << SSI_SPI_CTRLR0_TRANS_TYPE_LSB)  /* Send Address in Quad I/O mode (and Command but that is zero bits long) */ 


.syntax unified
.thumb


/*-----------------------------------------------------------*/
/*                       wait_ssi_ready                      */
/*-----------------------------------------------------------*/
.section .boot2, "ax"
.type wait_ssi_ready,%function
.thumb_func
wait_ssi_ready:
    push {r0, r1, lr}

    // Command is complete when there is nothing left to send
    // (TX FIFO empty) and SSI is no longer busy (CSn deasserted)
1:
    ldr r1, [r3, #SSI_SR_OFFSET]
    movs r0, #SSI_SR_TFE_BITS
    tst r1, r0
    beq 1b
    movs r0, #SSI_SR_BUSY_BITS
    tst r1, r0
    bne 1b

    pop {r0, r1, pc}

.size wait_ssi_ready, .-wait_ssi_ready

/*-----------------------------------------------------------*/
/*                      read_flash_sreg                      */
/*-----------------------------------------------------------*/
.section .boot2, "ax"
.type read_flash_sreg,%function
.thumb_func
read_flash_sreg:
    push {lr}

    str r0, [r3, #SSI_DR0_OFFSET]
    str r0, [r3, #SSI_DR0_OFFSET]
    
    bl wait_ssi_ready

    ldr r0, [r3, #SSI_DR0_OFFSET]
    ldr r0, [r3, #SSI_DR0_OFFSET]

    pop {pc}

.size read_flash_sreg, .-read_flash_sreg

/*-----------------------------------------------------------*/
/*                      write_flash_sreg                      */
/*-----------------------------------------------------------*/
.section .boot2, "ax"
.type write_flash_sreg,%function
.thumb_func
write_flash_sreg:
    push {lr}

    str r0, [r3, #SSI_DR0_OFFSET]
    str r1, [r3, #SSI_DR0_OFFSET]
    
    bl wait_ssi_ready

    ldr r0, [r3, #SSI_DR0_OFFSET]
    ldr r0, [r3, #SSI_DR0_OFFSET]

    pop {pc}

.size write_flash_sreg, .-write_flash_sreg


/*-----------------------------------------------------------*/
/*                        _stage2_boot                       */
/*-----------------------------------------------------------*/
.section .boot2._stage2_boot, "ax"
.type _stage2_boot,%function
.global _stage2_boot
.thumb_func
_stage2_boot:
    /* force debug breakpoint */
    //bkpt 
    push {lr}

    /* SCLK 8mA drive, no slew limiting */
    ldr r3, =PADS_QSPI_BASE
    movs r0, #PADS_QSPI_SCKL_CONFIG
    str r0, [r3, #PADS_QSPI_GPIO_QSPI_SCLK_OFFSET]

    /* SDx disable input Schmitt to reduce delay */
    ldr r3, =PADS_QSPI_BASE
    movs r0, #PADS_QSPI_SD_CONFIG
    str r0, [r3, #PADS_QSPI_GPIO_QSPI_SD0_OFFSET]
    str r0, [r3, #PADS_QSPI_GPIO_QSPI_SD1_OFFSET]
    str r0, [r3, #PADS_QSPI_GPIO_QSPI_SD2_OFFSET]
    str r0, [r3, #PADS_QSPI_GPIO_QSPI_SD3_OFFSET]

    /* keep SSI BASE in r3 for the rest of the function */
    ldr r3, =XIP_SSI_BASE

    /* disable SSI for configuration */
    movs r1, #0
    str r1, [r3, #SSI_SSIENR_OFFSET]

    /* Set baud rate */
    movs r1, #SSI_BAUDR_CONFIG
    str r1, [r3, #SSI_BAUDR_OFFSET]

    // Set 1-cycle sample delay. If PICO_FLASH_SPI_CLKDIV == 2 then this means,
    // if the flash launches data on SCLK posedge, we capture it at the time that
    // the next SCLK posedge is launched. This is shortly before that posedge
    // arrives at the flash, so data hold time should be ok. 
    movs r1, #SSI_RX_SAMPLE_DLY_CONFIG
    movs r2, #SSI_RX_SAMPLE_DLY_OFFSET  // == 0xf0 so need 8 bits of offset significance
    str r1, [r3, r2]

    // QSPI parts usually need a Status Register-2 (31h) write command to enable 
    // QSPI mode (i.e. turn WPn and HOLDn into IO2/IO3)
    ldr r1, =(CTRL0_SPI_TXRX)
    str r1, [r3, #SSI_CTRLR0_OFFSET]

    /* enable SSI */
    movs r1, #1
    str r1, [r3, #SSI_SSIENR_OFFSET]

// TODO: fix the flash config for QSPI

//    /* write enable */
//    movs r0, #CMD_WRITE_ENABLE
//    str r0, [r3, #SSI_DR0_OFFSET]
//    bl wait_ssi_ready
//    ldr r0, [r3, #SSI_DR0_OFFSET]
//
//    /* set the QE flag */
//    movs r0, #CMD_WRITE_STATUS2
//    movs r1, #SREG_DATA
//    bl write_flash_sreg

1:
    movs r0, #CMD_READ_STATUS2
    bl read_flash_sreg
    movs r1, #SREG_DATA
    tst r0, r1
    beq 1b

    // Currently the flash expects an 8 bit serial command prefix on every
    // transfer, which is a waste of cycles. Perform a dummy Fast Read Quad I/O
    // command, with mode bits set such that the flash will not expect a serial
    // command prefix on *subsequent* transfers. We don't care about the results
    // of the read, the important part is the mode bits.

    /* disable SSI again so that it can be reconfigured */
    movs r1, #0
    str r1, [r3, #SSI_SSIENR_OFFSET]

    ldr r1, =(CTRLR0_ENTER_XIP)
    str r1, [r3, #SSI_CTRLR0_OFFSET]

    movs r1, #0x0                    // NDF=0 (single 32b read)
    str r1, [r3, #SSI_CTRLR1_OFFSET]

    ldr r1, =(SPI_CTRLR0_ENTER_XIP)
    ldr r0, =(XIP_SSI_BASE + SSI_SPI_CTRLR0_OFFSET)  // SPI_CTRL0 Register
    str r1, [r0]

    /* enable SSI */
    movs r1, #1
    str r1, [r3, #SSI_SSIENR_OFFSET]

    movs r1, #CMD_READ
    str r1, [r3, #SSI_DR0_OFFSET]    // Push SPI command into TX FIFO
    movs r1, #MODE_CONTINUOUS_READ   // 32-bit: 24 address bits (we don't care, so 0) and M[7:4]=1010
    str r1, [r3, #SSI_DR0_OFFSET]    // Push Address into TX FIFO - this will trigger the transaction

    // Poll for completion
    bl wait_ssi_ready

    // The flash is in a state where we can blast addresses in parallel, and get
    // parallel data back. Now configure the SSI to translate XIP bus accesses
    // into QSPI transfers of this form.

    /* disable SSI so that it can be reconfigured */
    movs r1, #0
    str r1, [r3, #SSI_SSIENR_OFFSET]

    // Note that the INST_L field is used to select what XIP data gets pushed into
    // the TX FIFO:
    //      INST_L_0_BITS   {ADDR[23:0],XIP_CMD[7:0]}       Load "mode bits" into XIP_CMD
    //      Anything else   {XIP_CMD[7:0],ADDR[23:0]}       Load SPI command into XIP_CMD
    ldr r1, =(SPI_CTRLR0_XIP)
    ldr r0, =(XIP_SSI_BASE + SSI_SPI_CTRLR0_OFFSET)
    str r1, [r0]

    /* enable SSI */
    movs r1, #1
    str r1, [r3, #SSI_SSIENR_OFFSET]

    /* set the vector and branch to the reset handler */

    ldr r0, =(XIP_BASE + 0x100)
    ldr r1, =(PPB_BASE + M0PLUS_VTOR_OFFSET)
    str r0, [r1]
    ldmia r0, {r0, r1}
    msr msp, r0
    bx r1

.size _stage2_boot, .-_stage2_boot

.end


