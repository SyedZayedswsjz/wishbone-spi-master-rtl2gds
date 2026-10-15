`timescale 1ns/1ps
`include "spi_defines.v"

module spi_clgen (
    input clk_in,
    input rst,
    input go,
    input enable,
    input last_clk,
    input [`SPI_DIVIDER_LEN-1:0] divider,
    output reg clk_out,
    output reg pos_edge,
    output reg neg_edge
);

reg [`SPI_DIVIDER_LEN-1:0] cnt;

wire cnt_zero = (cnt == 0);

//////////////////////////////////////////////////
// COUNTER (FIXED)
//////////////////////////////////////////////////
always @(posedge clk_in or posedge rst) begin
    if (rst)
        cnt <= 0;

    else if (!enable)
        cnt <= divider;

    else if (cnt_zero)
        cnt <= divider;

    else
        cnt <= cnt - 1;
end

//////////////////////////////////////////////////
// CLOCK GENERATION (FIXED)
//////////////////////////////////////////////////
always @(posedge clk_in or posedge rst) begin
    if (rst)
        clk_out <= 1'b0;

    // Return SCLK to idle-low (CPOL=0) between transfers. An 8-bit
    // transfer ends after 15 toggles, so without this SCLK was left
    // HIGH and the next transfer started with a falling edge.
    else if (!enable)
        clk_out <= 1'b0;

    else if (cnt_zero)
        clk_out <= ~clk_out;
end

//////////////////////////////////////////////////
// EDGE GENERATION (CLEAN FIX)
//////////////////////////////////////////////////
always @(posedge clk_in or posedge rst) begin
    if (rst) begin
        pos_edge <= 0;
        neg_edge <= 0;
    end else begin
        pos_edge <= (enable && cnt_zero && clk_out == 0);
        neg_edge <= (enable && cnt_zero && clk_out == 1);
    end
end

endmodule
