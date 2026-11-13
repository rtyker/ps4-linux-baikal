/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20250404 (64-bit version)
 * Copyright (c) 2000 - 2025 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of DSDT.aml
 *
 * Original Table Header:
 *     Signature        "DSDT"
 *     Length           0x0000018C (396)
 *     Revision         0x02
 *     Checksum         0x2C
 *     OEM ID           "SIE   "
 *     OEM Table ID     "ORBIS   "
 *     OEM Revision     0x20121002 (538054658)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20110211 (537985553)
 */
DefinitionBlock ("", "DSDT", 2, "SIE   ", "ORBIS   ", 0x20121002)
{
    Scope (_PR)
    {
        Processor (C000, 0x00, 0x00000000, 0x00){}
        Processor (C001, 0x01, 0x00000000, 0x00){}
        Processor (C002, 0x02, 0x00000000, 0x00){}
        Processor (C003, 0x03, 0x00000000, 0x00){}
        Processor (C004, 0x04, 0x00000000, 0x00){}
        Processor (C005, 0x05, 0x00000000, 0x00){}
        Processor (C006, 0x06, 0x00000000, 0x00){}
        Processor (C007, 0x07, 0x00000000, 0x00){}
    }

    Name (_S0, Package (0x04)  // _S0_: S0 System State
    {
        Zero, 
        Zero, 
        Zero, 
        Zero
    })
    Name (_S3, Package (0x04)  // _S3_: S3 System State
    {
        0x03, 
        0x03, 
        Zero, 
        Zero
    })
    Name (_S5, Package (0x04)  // _S5_: S5 System State
    {
        0x05, 
        0x05, 
        Zero, 
        Zero
    })
    Name (WKST, Package (0x02)
    {
        Zero, 
        Zero
    })
    Method (_PTS, 1, NotSerialized)  // _PTS: Prepare To Sleep
    {
        WKST [Zero] = Zero
        WKST [One] = Zero
    }

    Method (_TTS, 1, NotSerialized)  // _TTS: Transition To State
    {
    }

    Method (_WAK, 1, NotSerialized)  // _WAK: Wake
    {
        Return (WKST) /* \WKST */
    }

    Scope (_SI)
    {
        Method (_SST, 1, NotSerialized)  // _SST: System Status
        {
        }
    }

    Scope (_GPE)
    {
    }

    Name (GINT, One)
    Scope (_SB)
    {
        Method (_PIC, 1, NotSerialized)  // _PIC: Interrupt Model
        {
            GINT = Arg0
        }

        Name (PRT0, Package (0x01)
        {
            Package (0x04)
            {
                0x0007FFFF, 
                Zero, 
                Zero, 
                0x13
            }
        })
        Device (PCI0)
        {
            Name (_HID, EisaId ("PNP0A03") /* PCI Bus */)  // _HID: Hardware ID
            Name (_ADR, 0x00180000)  // _ADR: Address
            Method (_BBN, 0, NotSerialized)  // _BBN: BIOS Bus Number
            {
                Return (Zero)
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0B)
            }

            Method (_PRT, 0, NotSerialized)  // _PRT: PCI Routing Table
            {
                Return (PRT0) /* \_SB_.PRT0 */
            }

            Name (CRS0, ResourceTemplate ()
            {
                IO (Decode16,
                    0x0CF8,             // Range Minimum
                    0x0CF8,             // Range Maximum
                    0x01,               // Alignment
                    0x08,               // Length
                    )
            })
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Return (CRS0) /* \_SB_.PCI0.CRS0 */
            }
        }
    }
}

