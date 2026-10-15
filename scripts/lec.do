// lec.do  -  Conformal LEC: RTL vs synthesized netlist
// Simplest option: run the file Genus generates instead:
//     lec -XL -nogui -dofile ../outputs/rtl2syn_lec.do
// This hand-written version is here so you can see what LEC actually does.
// Run from work/:  lec -XL -nogui -dofile ../scripts/lec.do
// Edit the .lib path below to match pdk_paths.tcl.

set log file ../reports/lec.log -replace

read library -liberty /path/to/gpdk045/gsclib045/timing/slow_vdd1v0_basicCells.lib

read design -golden  -verilog2k -define SYNTHESIS \
     -include ../rtl ../rtl/spi_clgen.v ../rtl/spi_shift.v ../rtl/spi_top.v
read design -revised -verilog ../outputs/spi_top_syn.v

set system mode lec
add compared points -all
compare

report compare data -class nonequivalent > ../reports/lec_nonequivalent.rpt
report verification -verbose             > ../reports/lec_summary.rpt
exit -force
