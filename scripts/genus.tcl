###############################################################################
# genus.tcl  -  Logic synthesis with Cadence Genus
# Run from the work/ directory:   genus -files ../scripts/genus.tcl -log genus
###############################################################################
source ../scripts/pdk_paths.tcl

set_db information_level 7
set_db hdl_error_on_blackbox true

# --- Libraries -------------------------------------------------------------
read_libs $LIB_SLOW
read_physical -lef [list $TECH_LEF $CELL_LEF]     ;# lets Genus estimate wire load from LEF

# --- RTL -------------------------------------------------------------------
set_db init_hdl_search_path $RTL_DIR               ;# resolves `include "spi_defines.v"
read_hdl -language v2001 {spi_clgen.v spi_shift.v spi_top.v}
elaborate $DESIGN
check_design -unresolved > $RPT_DIR/syn_check_design.rpt

# --- Constraints -----------------------------------------------------------
read_sdc $SDC
check_timing_intent -verbose > $RPT_DIR/syn_check_timing.rpt

# Keep flop names readable for debug, use tie cells for constants
set_db auto_ungroup none
set_db use_tiehilo_for_const unique

# --- Synthesis -------------------------------------------------------------
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium

syn_generic
syn_map
syn_opt

# --- Reports ---------------------------------------------------------------
report_timing -max_paths 10 > $RPT_DIR/syn_timing.rpt
report_area                 > $RPT_DIR/syn_area.rpt
report_gates                > $RPT_DIR/syn_gates.rpt
report_qor                  > $RPT_DIR/syn_qor.rpt
report_power                > $RPT_DIR/syn_power.rpt
report_messages             > $RPT_DIR/syn_messages.rpt

# --- Outputs for Innovus and Conformal ------------------------------------
write_hdl                     > $OUT_DIR/${DESIGN}_syn.v
write_sdc                     > $OUT_DIR/${DESIGN}_syn.sdc
write_do_lec -golden_design rtl -revised_design $OUT_DIR/${DESIGN}_syn.v \
             > $OUT_DIR/rtl2syn_lec.do

puts "\n=== Genus done. Check reports/syn_timing.rpt for slack (must be >= 0) ===\n"
exit
