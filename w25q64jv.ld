OUTPUT_FORMAT("elf32-littlearm", "elf32-bigarm", "elf32-littlearm")

ENTRY(isr_reset)

MEMORY {
    FLASH     (rx) : ORIGIN = 0x10000000, LENGTH = 8192K
    RAM      (rwx) : ORIGIN = 0x20000000, LENGTH = 256k
    BOOT2     (rx) : ORIGIN = 0x20041f00, LENGTH = 256
    SCRATCH_X(rwx) : ORIGIN = 0x20040000, LENGTH = 4k
    SCRATCH_Y(rwx) : ORIGIN = 0x20041000, LENGTH = 4k
}

SECTIONS {
    /* the first 256 bytes from flash are reserved for the second stage boot */
    .boot2 : {
        __boot2_start = .;
        KEEP(*(.boot2._stage2_boot))
        KEEP(*(.boot2))
        . = __boot2_start + LENGTH(BOOT2) - 4; /* reserve 4 bytes for patching a CRC */
        LONG(0xEFBEADDE); 
        __boot2_end = .;
    } >BOOT2 AT >FLASH =0x00

    /* program code and other executable data */
    .text : ALIGN(4) {
        __text_start = .;

        /* the interupt vectors as defined for the rp2040 */
        KEEP(*(.vectors));

        /* binary info header */
        __binary_info_header_start = .;
        KEEP(*(.binary_info_header))
        __binary_info_header_end = .;
        
        /* exception handlers */
        *(.text.isr*)
        *(.text*)

        KEEP(*(.init))
        KEEP(*(.fini))

        /* pull all c'tors into .text */
        *crtbegin.o(.ctors)
        *crtbegin?.o(.ctors)
        *(EXCLUDE_FILE(*crtend?.o *crtend.o) .ctors)
        *(SORT(.ctors.*))
        *(.ctors)
        
        /* followed by destructors */
        *crtbegin.o(.dtors)
        *crtbegin?.o(.dtors)
        *(EXCLUDE_FILE(*crtend?.o *crtend.o) .dtors)
        *(SORT(.dtors.*))
        *(.dtors)

        *(.eh_frame)

        __text_end = .;
    } >FLASH
    
    /* put constant (read-only) data into FLASH */
    .rodata : ALIGN(4) {
        __rodata_start = .;

        /* machine inspectable binary information */
        __binary_info_start = .;
        KEEP(*(.binary_info.keep.*))
        *(.binary_info.*)
        __binary_info_end = .;

        . = ALIGN(4);
        *(.rodata*)

        /* data marked as read only and that shall be stored in flash */
        . = ALIGN(4);
        KEEP(*(.flashdata*))

        __rodata_end = .;
    } >FLASH

    .ARM.extab : {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } >FLASH

    .ARM : {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } >FLASH

    /* runtime vector table shall be in RAM */
    .ram_vector_table (COPY): {
        *(.ram_vector_table)
    } >RAM

    /* initialized global variables for the striped RAM */
    .data : ALIGN(4){
        __data_start = .;

        *(.time_critical*)

        . = ALIGN(4);
        *(.data*)

        . = ALIGN(4);
        /* mutex data */
        PROVIDE_HIDDEN (__mutex_array_start = .);
        KEEP(*(SORT(.mutex_array.*)))
        KEEP(*(.mutex_array))
        PROVIDE_HIDDEN (__mutex_array_end = .);

        . = ALIGN(4);
        /* preinit data */
        PROVIDE_HIDDEN (__preinit_array_start = .);
        KEEP(*(SORT(.preinit_array.*)))
        KEEP(*(.preinit_array))
        PROVIDE_HIDDEN (__preinit_array_end = .);

        . = ALIGN(4);
        /* init data */
        PROVIDE_HIDDEN (__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE_HIDDEN (__init_array_end = .);

        . = ALIGN(4);
        /* finit data */
        PROVIDE_HIDDEN (__fini_array_start = .);
        *(SORT(.fini_array.*))
        *(.fini_array)
        PROVIDE_HIDDEN (__fini_array_end = .);

        __data_end = .;
    } >RAM AT >FLASH
    __data_source = LOADADDR(.data);

    /* uninitialized global variables for the striped RAM - keeps value between resets */
    .uninitialized_data (COPY): ALIGN(4) {
        *(.uninitialized_data*)
        *(.uninitialized_ram*)
    } >RAM

    /* uninitialized global variables for the striped RAM - set to 0 at runtime init */
    .bss : ALIGN(4) {
        __bss_start = .;

        *(.bss*)

        __bss_end = .;
    } >RAM

    /* heap for dymamic alocation */
    .heap (NOLOAD) : ALIGN(4) {
        __heap_start = .;

        KEEP(*(.heap*))
        . = . + 32*1024;

        __heap_end = .;
    } >RAM

    /* initialized global variables for the 1'st 4KB block */
    .scratch_x : {
        __scratch_x_start = .;

        *(.scratch_x.*)

        __scratch_x_end = .;
    } >SCRATCH_X AT >FLASH
    __scratch_x_source = LOADADDR(.scratch_x);

    /* core0 stack placed in the 1'st 4KB block */
    .stack0 (OVERLAY) : ALIGN(4) {
        __stack0_bottom = .;

        . = . + LENGTH(SCRATCH_X) - SIZEOF(.scratch_x);

        __stack0_top = .;
    } >SCRATCH_X

    /* initialized global variables for the 2'st 4KB block */
    .scratch_y : {
        __scratch_y_start = .;

        *(.scratch_y.*)

        __scratch_y_end = .;
    } >SCRATCH_Y AT >FLASH
    __scratch_y_source = LOADADDR(.scratch_y);

    /* core1 stack placed in the 1'st 4KB block */
    .stack1 (OVERLAY) : ALIGN(4) {
        __stack1_bottom = .;

        . = . + LENGTH(SCRATCH_Y) - SIZEOF(.scratch_y);

        __stack1_top = .;
    } >SCRATCH_Y

    /DISCARD/ : {
        libc.a(*)
        libm.a(*)
        libgcc.a(*)
    }

    .ARM.attributes 0 : {
        *(.ARM.attributes)
    }

    /* binary info header must be in the first 256 bytes (excluding boot2) */
    ASSERT( __binary_info_header_end - __text_start <= 256, "Binary info must be in first 256 bytes of the binary")
}

