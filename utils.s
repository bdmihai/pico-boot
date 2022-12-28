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
   https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/pico_standard_link/crt0.S */

.syntax unified
.thumb

// Header must be in first 256 bytes of main image (i.e. excluding flash boot2).
// For flash builds we put it immediately after vector table; for NO_FLASH the
// vectors are at a +0x100 offset because the bootrom enters RAM images directly
// at their lowest address, so we put the header in the VTOR alignment hole.
.section .binary_info_header, "a"
binary_info_header:
    .word 0x7188ebf2            // BINARY_INFO_MARKER_START
    .word __binary_info_start
    .word __binary_info_end
    .word data_cpy_table        // we may need to decode pointers that are in RAM at runtime.
    .word 0xe71aa390            // BINARY_INFO_MARKER_END

/*-----------------------------------------------------------*/
/*                  __get_current_exception                  */
/*-----------------------------------------------------------*/
.section .text.util, "ax"
.global __get_current_exception
.type __get_current_exception,%function
.thumb_func
__get_current_exception:
    mrs  r0, ipsr
    uxtb r0, r0
    bx   lr

/*-----------------------------------------------------------*/
/*                         runtime_init                      */
/*-----------------------------------------------------------*/
.weak runtime_init
.type runtime_init,%function
.thumb_func
runtime_init:
    bx lr

/*-----------------------------------------------------------*/
/*                             exit                          */
/*-----------------------------------------------------------*/
.weak exit
.type exit,%function
.thumb_func
exit:
1:
    bkpt #0
    b 1b

.end
