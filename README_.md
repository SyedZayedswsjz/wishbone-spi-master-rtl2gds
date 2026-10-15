# Wishbone SPI Master: RTL Debug & Cadence RTL-to-GDSII Flow

A Wishbone-compliant SPI master controller. I debugged it at RTL until it passed a self-checking testbench, wrote the timing constraints, and set it up for physical implementation with Cadence Genus, Conformal, Innovus and Tempus.

> **Origin:** Based on the [OpenCores SPI core](https://opencores.org/projects/spi) by Simon Srot (LGPL-2.1). The original copyright headers are kept. The bug fixes, testbench, constraints and implementation scripts in this repository are my own work.

---

## Features

- Wishbone B3 slave interface (32-bit data, single-cycle ACK)
- SPI master, mode 0 (CPOL=0, CPHA=0), MSB first, 8-bit transfers
- Programmable SCLK divider (16-bit)
- 8 slave-select lines, automatically released at the end of a transfer
- Transfer-complete interrupt
- **Single clock domain:** SCLK is generated as a registered output, and the shift logic uses edge enables rather than a second clock. This keeps static timing analysis simple and avoids clock-domain crossings.

## Block diagram

```
            +--------------------------- spi_top ----------------------------+
 Wishbone   |  +-------------+   divider   +-----------+  pos/neg edge       |
 wb_*  <--->|  |  Register   |------------>| spi_clgen |-----------+         |---> sclk_pad_o
            |  |  file + ACK |   go/ctrl   +-----------+           v         |
            |  | (CTRL, DIV, |------------------------------>+-----------+   |---> mosi_pad_o
            |  |  SS, TX,RX) |<------------- rx, tip -------| spi_shift |<--|---- miso_pad_i
            |  +-------------+                              +-----------+   |
            |         |------------------ ss -------------------------------|---> ss_pad_o[7:0]
            +--------------------------------------------------------------+
```

## Register map (word address on `wb_adr_i`)

| Addr | Register | Access | Description |
|---|---|---|---|
| 0 | TX / RX | W / R | Write: TX byte. Read: last received byte |
| 4 | CTRL | R/W | [8] GO (cleared by hardware), [9] RX_NEGEDGE, [10] TX_NEGEDGE, [12] IE |
| 5 | DIVIDER | R/W | SCLK = wb_clk / (2 × (DIVIDER + 1)) |
| 6 | SS | R/W | Slave-select mask (active-low on the pads) |

## Bugs found and fixed

The design as received passed Transfer 1 but **failed Transfer 2** (it read `0x01` instead of `0x3C`) and could not be synthesized cleanly.

| # | Bug | Symptom | Fix |
|---|---|---|---|
| 1 | **Phantom transfer:** GO is cleared one cycle after `tip` falls, so `go && !tip` restarted a transfer | An unwanted 8-bit transfer after every real one | Added a `go_r` flag marking GO as serviced. A new transfer needs a fresh GO |
| 2 | **SCLK idle level:** an 8-bit transfer is 15 toggles, so SCLK was left HIGH | The next transfer began on a falling edge, shifting every bit by one (`0x3C` read as `0x78`) | Force SCLK low when idle (CPOL=0) |
| 3 | **Multi-driven register:** `tx_shift` was assigned in two `always` blocks | Synthesis error (multiple drivers) | Merged into one `always` block |
| 4 | **Wishbone ACK** stayed high on consecutive cycles | Violates single-cycle handshake | `ack <= cyc & stb & ~ack` |
| 5 | **FPGA constraints in an ASIC flow:** only an `.xdc` (Vivado) file existed | Cadence tools had no usable timing constraints | Wrote an SDC: clock, IO delays, uncertainty, design rules |

Line-by-line changes: [`rtl/CHANGES_*.diff`](rtl/)

## Verification

Self-checking testbench with a Wishbone master bus model and a mode-0 SPI slave model:

```
*** Transfer 1  PASS ***                      (MOSI sends 0xA5, slave returns 0xA5)
*** Transfer 2  PASS  — serial-to-parallel slave->master OK ***   (MISO 0x3C)
```

Run (Cadence Xcelium):
```bash
xrun -access +rwc -incdir rtl tb/*.v rtl/spi_clgen.v rtl/spi_shift.v rtl/spi_top.v
```

## Physical implementation flow

| Step | Tool | Script | Status |
|---|---|---|---|
| Synthesis | Genus | `scripts/genus.tcl` | In progress |
| Equivalence check | Conformal LEC | `scripts/lec.do` | In progress |
| Floorplan → power plan → place → CTS → route | Innovus | `scripts/innovus.tcl` | In progress |
| Signoff STA (OCV, SI) | Tempus | `scripts/tempus.tcl` | In progress |
| IR drop | Voltus | — | Planned |
| DRC / LVS | Pegasus | — | Planned |

Timing setup: 2 corners (slow/setup, fast/hold) in `scripts/mmmc.tcl`; constraints in `constraints/spi_top.sdc`.

### Results

*To be updated after implementation.*

| Metric | Value |
|---|---|
| Technology | 45 nm (GPDK045) |
| Target frequency | 100 MHz (then 250 MHz) |
| Cell area / utilization | — |
| Setup WNS / TNS | — |
| Hold WNS | — |
| Clock skew | — |
| Power | — |
| DRC / LVS | — |

## Repository layout

```
rtl/          Fixed RTL and change diffs
tb/           Testbench, Wishbone master model, SPI slave model
constraints/  SDC timing constraints
scripts/      Genus, Conformal, Innovus, Tempus scripts and MMMC setup
```

PDK and library files are licensed and are not included. Set your local paths in `scripts/pdk_paths.tcl`.

## License

LGPL-2.1, following the original OpenCores SPI core.
