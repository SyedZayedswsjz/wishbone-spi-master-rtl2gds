`timescale 1ns/1ps

module wb_master_model (
output reg [31:0] adr,
output reg [31:0] dout,
input [31:0] din,

output reg cyc,
output reg stb,
output reg we,
output reg [3:0] sel,

input ack,
input err,
input rty,

input clk,
input rst

);

// Reset logic
always @(posedge clk) begin
    if (rst) begin
        adr  <= 0;
        dout <= 0;
        cyc  <= 0;
        stb  <= 0;
        we   <= 0;
        sel  <= 4'hF;
    end
end

// WRITE TASK
task wb_write;
input [31:0] delay;
input [31:0] addr;
input [31:0] data;
begin
    repeat(delay) @(posedge clk);

    @(posedge clk);
    adr  <= addr;
    dout <= data;
    we   <= 1;
    cyc  <= 1;
    stb  <= 1;

    $display("WB WRITE START addr=%h data=%h", addr, data);

    wait (ack == 1);

    @(posedge clk);   // hold cycle

    cyc <= 0;
    stb <= 0;
    we  <= 0;

    $display("WB WRITE DONE");
end
endtask

// READ TASK - FIX 5: capture din one cycle AFTER ack+hold
// wb_dat_o in spi_top is registered, so it's valid the cycle AFTER ack.
task wb_read;
input  [31:0] delay;
input  [31:0] addr;
output [31:0] data;
begin
    repeat(delay) @(posedge clk);

    @(posedge clk);
    adr <= addr;
    we  <= 0;
    cyc <= 1;
    stb <= 1;

    $display("WB READ START addr=%h", addr);

    wait (ack == 1);

    @(posedge clk);   // hold cycle — wb_dat_o stable here for registered slave

    data = din;       // sample AFTER hold: data is now valid

    cyc <= 0;
    stb <= 0;

    $display("WB READ DONE data=%h", data);
end
endtask

// COMPARE
task wb_cmp;
input [31:0] delay;
input [31:0] addr;
input [31:0] exp;
reg [31:0] rdata;
begin
    wb_read(delay, addr, rdata);
    if (rdata !== exp)
        $display("ERROR: addr=%h expected=%h got=%h", addr, exp, rdata);
    else
        $display("OK: addr=%h data=%h", addr, rdata);
end
endtask

endmodule
