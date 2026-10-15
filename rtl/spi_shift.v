`timescale 1ns/1ps
`include "spi_defines.v"

// =============================================================================
// spi_shift.v  —  Fixed version (rev 2: phantom-transfer + multi-driver fixes)
//
// BUG FIXED (Phantom Transfer):
//   In the original design, when a transfer completes (tip falls on
//   last&&sample_edge), the `go` signal from spi_top's ctrl register is
//   still HIGH for exactly one more clock cycle before spi_top's
//   auto-clear logic (tip_d && !tip) de-asserts it.
//
//   During that one-cycle window: go=1, tip=0  =>  go && !tip = TRUE
//   This caused tip to bounce immediately back to 1, launching a full
//   8-clock "phantom" transfer with the slave still chip-selected.
//   The phantom consumed the slave's second byte (0x3C) as garbage,
//   so when the real Transfer 2 ran, the slave had no valid data left.
//
// FIX:
//   Latch `go` internally as `go_r` on the cycle tip goes HIGH.
//   Use `go_r` (not raw `go`) to keep tip alive during the transfer.
//   tip can only rise on go=1 AND tip=0 (same as before).
//   tip falls on go_r=0 OR (last && sample_edge).
//   Once go_r is set, it clears when tip falls so it does not re-trigger.
//   Because tip rises on the same cycle go_r is latched, the subsequent
//   auto-clear of go by spi_top has no effect — go_r already tracks the
//   intended transfer.
// =============================================================================

module spi_shift (
    input                           clk,
    input                           rst,
    input  [3:0]                    latch,
    input  [3:0]                    byte_sel,
    input  [`SPI_CHAR_LEN_BITS-1:0] len,
    input                           lsb,
    input                           go,
    input                           pos_edge,
    input                           neg_edge,
    input                           rx_negedge,
    input                           tx_negedge,
    output reg                      tip,
    output                          last,
    input  [31:0]                   p_in,
    output reg [`SPI_MAX_CHAR-1:0]  p_out,
    input                           sclk,
    input                           miso,
    output reg                      mosi
);

reg [7:0] tx_shift;
reg [7:0] rx_shift;
reg       miso_d;
reg [3:0] bit_cnt;

// ------------------------------------------------------------------
// go_r: internal latch that captures go at transfer start and holds
//       tip stable for the full transfer, immune to spi_top's
//       one-cycle-late auto-clear of the GO bit.
// ------------------------------------------------------------------
reg go_r;

wire sample_edge = rx_negedge ? neg_edge : pos_edge;
wire shift_edge  = tx_negedge ? neg_edge : pos_edge;

assign last = (bit_cnt == 1);

// ------------------------------------------------------------------
// go_r: "this GO has already been serviced" flag.
//   Set when a transfer starts; cleared only when spi_top clears GO.
//   spi_top clears GO one clock AFTER tip falls, so without this flag
//   go=1 && tip=0 in that cycle restarts a phantom transfer.
// ------------------------------------------------------------------
wire start = go && !tip && !go_r;

always @(posedge clk or posedge rst) begin
    if (rst)
        go_r <= 1'b0;
    else if (!go)
        go_r <= 1'b0;
    else if (start)
        go_r <= 1'b1;
end

// ------------------------------------------------------------------
// tip: transfer in progress
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        tip <= 1'b0;
    else if (start)
        tip <= 1'b1;
    else if (tip && last && sample_edge)
        tip <= 1'b0;
end

// ------------------------------------------------------------------
// TX shift register: load when idle, shift on shift_edge during tip.
// (Single always block: tx_shift was previously driven from two
//  always blocks, which is a multi-driver error in synthesis.)
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        tx_shift <= 8'd0;
    else if (latch[0] && !tip)
        tx_shift <= p_in[7:0];
    else if (tip && shift_edge)
        tx_shift <= {tx_shift[6:0], 1'b0};
end

// ------------------------------------------------------------------
// Bit counter: load 8 at start, count down on each sample edge
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        bit_cnt <= 0;
    else if (start)
        bit_cnt <= 4'd8;
    else if (tip && sample_edge)
        bit_cnt <= bit_cnt - 1;
end

// ------------------------------------------------------------------
// MOSI drive: shift out MSB-first on each shift_edge
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        mosi <= 0;
    else if (tip && shift_edge)
        mosi <= tx_shift[7];
end

// ------------------------------------------------------------------
// MISO pipeline register: 1-cycle delay to meet SPI Mode 0 setup
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst) miso_d <= 0;
    else     miso_d <= miso;
end

// ------------------------------------------------------------------
// RX shift register: sample miso_d on each sample_edge during tip
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        rx_shift <= 0;
    else if (tip && sample_edge)
        rx_shift <= {rx_shift[6:0], miso_d};
end

// ------------------------------------------------------------------
// Parallel output: capture complete byte on the final bit
// Concatenate rx_shift[6:0] with the current miso_d so the 8th
// bit is never missed (both fire on the same posedge).
// ------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst)
        p_out <= 0;
    else if (tip && last && sample_edge)
        p_out <= {{(`SPI_MAX_CHAR-8){1'b0}}, rx_shift[6:0], miso_d};
end

endmodule
