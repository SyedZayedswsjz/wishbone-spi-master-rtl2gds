###############################################################################
# pdk_paths.tcl  -  EDIT THIS FILE FIRST. Every other script sources it.
#
# File names below follow the Cadence GPDK045 / gsclib045 layout, but names
# differ between PDK releases. Check your install and fix each path:
#     ls $PDK_ROOT/gsclib045/lef  $PDK_ROOT/gsclib045/timing  ...
###############################################################################

set DESIGN   spi_top
set PROJ     [file normalize [file dirname [info script]]/..]

set PDK_ROOT /path/to/gpdk045                         ;# <-- EDIT

# --- Liberty timing libraries (one per corner) ----------------------------
set LIB_SLOW $PDK_ROOT/gsclib045/timing/slow_vdd1v0_basicCells.lib   ;# setup corner
set LIB_FAST $PDK_ROOT/gsclib045/timing/fast_vdd1v2_basicCells.lib   ;# hold corner

# --- LEF: technology LEF first, then standard-cell LEF --------------------
set TECH_LEF $PDK_ROOT/gsclib045/lef/gsclib045_tech.lef
set CELL_LEF $PDK_ROOT/gsclib045/lef/gsclib045_macro.lef

# --- RC extraction ---------------------------------------------------------
set QRC_TECH $PDK_ROOT/gpdk045/qrc/typical/qrcTechFile                ;# <-- EDIT
# If you have no QRC file yet, use a cap table instead (see mmmc.tcl).

# --- GDS of standard cells + layer map (for write_stream / DRC / LVS) ----
set CELL_GDS $PDK_ROOT/gsclib045/gds/gsclib045.gds
set GDS_MAP  $PDK_ROOT/gpdk045/streamOut.map                          ;# <-- EDIT

# --- Physical cell names (check your LEF) ----------------------------------
set SITE        CoreSite
set FILLER_CELLS {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set TIE_CELLS    {TIEHI TIELO}

# --- Power nets and routing layers ----------------------------------------
set PWR VDD
set GND VSS
set RING_LAYER_H  Metal9
set RING_LAYER_V  Metal8
set STRIPE_LAYER  Metal8
set PIN_LAYER_H   Metal4
set PIN_LAYER_V   Metal3

# --- Directories -----------------------------------------------------------
set RTL_DIR $PROJ/rtl
set SDC     $PROJ/constraints/spi_top.sdc
set OUT_DIR $PROJ/outputs
set RPT_DIR $PROJ/reports
file mkdir $OUT_DIR $RPT_DIR
