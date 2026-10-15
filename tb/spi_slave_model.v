`timescale 1ns/1ps

// =============================================================================
// spi_slave_model.v  —  Fixed version
//
// BUG FIXED (second_transfer counter):
//   The original slave toggled second_transfer on EVERY negedge of SS
//   (i.e., every time SS was asserted).  Because the phantom transfer
//   in spi_shift kept SS asserted for an extra 8 clocks before releasing
//   it, the slave saw an extra SS deassert/reassert pair.  That extra
//   negedge reset second_transfer back to 0 so the slave loaded 0xA5
//   instead of 0x3C for the real Transfer 2.
//
//   Even with the phantom fixed in spi_shift, the original one-liner
//   toggle was fragile.  This version counts COMPLETED transfers (posedge
//   SS = transaction end) and uses that count to preload the correct byte
//   on the next negedge SS.
//
// OPERATION:
//   transfer_count = 0  =>  first transaction will send 0xA5
//   transfer_count = 1  =>  second transaction will send 0x3C
//   transfer_count ≥ 2  =>  wraps back to 0xA5 pattern (or extend as needed)
// =============================================================================

module spi_slave_model (
    input      rst,
    input      ss,      // active-low chip-select from ss_pad_o
    input      sclk,
    input      mosi,
    output reg miso
);

reg [7:0] shift_reg;
reg [1:0] transfer_count;   // counts completed transactions (posedge ss)

// ------------------------------------------------------------------
// Initialisation
// ------------------------------------------------------------------
initial begin
    shift_reg      = 8'hA5;
    miso           = 1'b0;
    transfer_count = 2'd0;
end

// ------------------------------------------------------------------
// On POSEDGE SS (end of transaction): increment completed counter.
// This fires AFTER the transaction is fully done, so the count is
// always "how many transactions have finished so far".
// ------------------------------------------------------------------
always @(posedge ss or posedge rst) begin
    if (rst) begin
        transfer_count <= 2'd0;
    end else begin
        // Increment; wraps naturally at 2 bits
        transfer_count <= transfer_count + 1;
    end
end

// ------------------------------------------------------------------
// On NEGEDGE SS (start of next transaction):
//   Pre-load shift_reg with the correct byte based on how many
//   transactions have already COMPLETED (transfer_count).
//   Pre-drive MISO with the MSB immediately so it is stable
//   before the master's first SCLK rising edge.
// ------------------------------------------------------------------
always @(negedge ss or posedge rst) begin
    if (rst) begin
        shift_reg <= 8'hA5;
        miso      <= 1'b0;
    end else begin
        case (transfer_count)
            2'd0: begin
                // First transaction: send 0xA5  (0xA5[7] = 1)
                shift_reg <= 8'hA5;
                miso      <= 1'b1;
            end
            2'd1: begin
                // Second transaction: send 0x3C  (0x3C[7] = 0)
                shift_reg <= 8'h3C;
                miso      <= 1'b0;
            end
            default: begin
                // Further transactions: send 0x00
                shift_reg <= 8'h00;
                miso      <= 1'b0;
            end
        endcase
    end
end

// ------------------------------------------------------------------
// Shift on negedge SCLK so the next bit is stable at posedge (Mode 0).
// When SS deasserts (posedge ss) tri-state / release MISO.
// ------------------------------------------------------------------
always @(negedge sclk or posedge ss) begin
    if (ss)
        miso <= 1'b0;
    else begin
        shift_reg <= {shift_reg[6:0], 1'b0};
        miso      <= shift_reg[6];   // drive the NEXT bit
    end
end

endmodule
