# Wishbone SPI Master: RTL-to-GDSII (Cadence flow)

## What was wrong (why the flow stalled)

1. **XDC instead of SDC.** `.xdc` is the Xilinx Vivado (FPGA) constraint format. Cadence Genus, Innovus and Tempus read **SDC**, so the flow had no usable constraints. A Vivado netlist (LUTs and flip-flops) also can't go into Innovus; the netlist must come from Genus with the standard-cell library. Use `constraints/spi_top.sdc`.
2. **Multi-driven register (`spi_shift.v`).** `tx_shift` was assigned in two `always` blocks. Simulation tolerates this, but synthesis flags it as an error or builds wrong logic. Merged into one block.
3. **Phantom transfer (`spi_shift.v`).** The `go_r` "fix" was declared but never used. After each transfer, GO stays high for one extra clock, so `tip` restarted immediately and ran an unwanted 8-bit transfer. `go_r` now marks a GO as already serviced.
4. **SCLK left high after a transfer (`spi_clgen.v`).** An 8-bit transfer is 15 SCLK toggles, so SCLK ended HIGH. The next transfer then began with a falling edge and every bit shifted by one: Transfer 2 read 0x78 instead of 0x3C. SCLK now returns to 0 when idle (SPI mode 0).
5. **Wishbone ACK (`spi_top.v`).** ACK stayed high for consecutive cycles. It's now a single-cycle pulse.

Original RTL: Transfer 2 **FAIL** (read 0x01). Fixed RTL: both transfers **PASS**. Diffs are in `rtl/CHANGES_*.diff`.

## Run order (all from `work/`)

| # | Step | Command | Check before moving on |
|---|---|---|---|
| 0 | Edit PDK paths | `scripts/pdk_paths.tcl` | Every path exists (`ls` it) |
| 1 | RTL sim | `xrun -access +rwc ../tb/*.v ../rtl/spi_{clgen,shift,top}.v -incdir ../rtl` | Both PASS |
| 2 | Synthesis | `genus -files ../scripts/genus.tcl -log genus` | `syn_timing.rpt` slack >= 0, no latches or unresolved cells |
| 3 | LEC | `lec -XL -nogui -dofile ../outputs/rtl2syn_lec.do` | Non-equivalent = 0 |
| 4 | Place & route | `innovus -stylus -files ../scripts/innovus.tcl -log innovus` | WNS >= 0 for setup and hold, `07_drc.rpt` = 0 |
| 5 | Signoff STA | `tempus -stylus -files ../scripts/tempus.tcl -log tempus` | `sta_violators.rpt` empty |
| 6 | IR drop | Voltus (script comes next) | Static IR drop < 5% VDD |
| 7 | DRC / LVS | Pegasus with the PDK rule deck on `outputs/spi_top.gds` | Clean |

## Notes

- Commands use the Innovus **Stylus** (Common UI) syntax. On older legacy Innovus, some names differ (for example `floorPlan` and `addRing`). Send me any "unknown command" error and I'll convert the script.
- Start at 100 MHz and 60% utilization. Once the flow is clean end to end, set `CLK_PERIOD` to 4.0 ns (250 MHz) and re-close timing.
- The design is fixed at 8 bits, MSB first. `len`, `lsb` and `byte_sel` are wired but unused, so Genus will warn about them. `p_out` is 128 bits wide, but 120 of them are constant 0 and synthesis removes them.
- Don't commit PDK files (LEF, `.lib`, GDS) to GitHub. Commit only your RTL, scripts and report summaries.
