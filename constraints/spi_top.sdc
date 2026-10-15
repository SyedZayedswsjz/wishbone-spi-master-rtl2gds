###############################################################################
# spi_top.sdc  -  Timing constraints for Cadence Genus / Innovus / Tempus
#
# NOTE: This replaces the Vivado .xdc file. XDC is Xilinx (FPGA) only;
#       the Cadence ASIC flow reads standard SDC.
#
# Architecture note (important for interviews):
#   Every flop in this design is clocked by wb_clk_i. SCLK is NOT used as a
#   clock inside the chip - spi_clgen produces it as a registered data output
#   and the shift logic uses pos_edge/neg_edge enables. So there is only ONE
#   clock domain, and the SPI pins are constrained relative to wb_clk.
#   No create_generated_clock is needed for internal timing.
###############################################################################

set_units -time ns -capacitance pF

# ---------------------------------------------------------------------------
# Clock: 100 MHz to start (matches the testbench). Tighten later
# (e.g. 4.0 ns = 250 MHz) once the flow runs clean end to end.
# ---------------------------------------------------------------------------
set CLK_PERIOD 10.0

create_clock -name wb_clk -period $CLK_PERIOD [get_ports wb_clk_i]

set_clock_uncertainty -setup 0.20 [get_clocks wb_clk]   ;# jitter + pre-CTS skew margin
set_clock_uncertainty -hold  0.05 [get_clocks wb_clk]
set_clock_transition         0.10 [get_clocks wb_clk]   ;# ideal clock pre-CTS only

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
# Wishbone bus comes from on-chip logic in the same clock domain:
# assume the driving flop + wiring uses 40% of the cycle.
set WB_IN [get_ports {wb_adr_i* wb_dat_i* wb_sel_i* wb_we_i wb_stb_i wb_cyc_i}]
set_input_delay  -clock wb_clk -max [expr 0.4 * $CLK_PERIOD] $WB_IN
set_input_delay  -clock wb_clk -min 0.2                      $WB_IN

# MISO comes from an off-chip slave. It is captured by the miso_d flop.
set_input_delay  -clock wb_clk -max [expr 0.5 * $CLK_PERIOD] [get_ports miso_pad_i]
set_input_delay  -clock wb_clk -min 0.5                      [get_ports miso_pad_i]

# Asynchronous reset: timed for recovery/removal against wb_clk.
set_input_delay  -clock wb_clk -max [expr 0.3 * $CLK_PERIOD] [get_ports wb_rst_i]
set_input_delay  -clock wb_clk -min 0.2                      [get_ports wb_rst_i]

set_input_transition 0.10 [remove_from_collection [all_inputs] [get_ports wb_clk_i]]

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
set WB_OUT [get_ports {wb_dat_o* wb_ack_o wb_err_o wb_int_o}]
set_output_delay -clock wb_clk -max [expr 0.4 * $CLK_PERIOD] $WB_OUT
set_output_delay -clock wb_clk -min -0.1                     $WB_OUT

# SPI pads: all are flop outputs (sclk, mosi; ss through one inverter).
set SPI_OUT [get_ports {sclk_pad_o mosi_pad_o ss_pad_o*}]
set_output_delay -clock wb_clk -max [expr 0.5 * $CLK_PERIOD] $SPI_OUT
set_output_delay -clock wb_clk -min -0.1                     $SPI_OUT

set_load 0.02 [all_outputs]

# ---------------------------------------------------------------------------
# Design rules
# ---------------------------------------------------------------------------
set_max_transition 0.50 [current_design]
set_max_fanout     32   [current_design]
