`timescale 1ns/1ps

// =============================================================================
// tb_spi_top.v  —  Two-transfer SPI testbench
//
// Transfer 1 : Master -> Slave   (MOSI carries 0xA5, bit-serial)
// Transfer 2 : Slave  -> Master  (MISO carries 0x3C, bit-serial)
//
//   The serial-to-parallel path in Transfer 2 is made fully visible:
//   - A [S2P] monitor block samples MISO on every SCLK posedge
//   - Each arriving bit is printed individually
//   - After bit 0 the reconstructed parallel byte is displayed
//   - The same byte then travels over the 32-bit Wishbone bus to the master
// =============================================================================

module tb_spi_top;

reg clk;
reg rst;

wire [31:0] adr;
wire [31:0] dat_i, dat_o;
wire we, stb, cyc, ack, err, intr;
wire [3:0] sel;

wire [7:0] ss;
wire sclk, mosi, miso;

reg [31:0] q;
reg [31:0] ctrl_val;

// Registers used by the serial-to-parallel monitor
reg [7:0] serial_capture;   // rebuilt bit-by-bit from MISO
integer   bit_index;         // counts down 7..0 (MSB first, SPI Mode 0)
reg       monitor_active;    // gate: only watch Transfer 2

// ADDRESS MAP  (word offsets — spi_top uses wb_adr_i[4:0] directly)
parameter SPI_TX_0 = 0;
parameter SPI_RX_0 = 0;
parameter SPI_CTRL = 4;
parameter SPI_DIV  = 5;
parameter SPI_SS   = 6;

// -----------------------------------------------------------------------
// CLOCK  100 MHz
// -----------------------------------------------------------------------
initial clk = 0;
always  #5  clk = ~clk;

// -----------------------------------------------------------------------
// WISHBONE MASTER
// -----------------------------------------------------------------------
wb_master_model master (
    .clk (clk),  .rst (rst),
    .adr (adr),  .dout(dat_i), .din(dat_o),
    .cyc (cyc),  .stb (stb),   .we (we),   .sel(sel),
    .ack (ack),  .err (err),   .rty(1'b0)
);

// -----------------------------------------------------------------------
// DUT
// -----------------------------------------------------------------------
spi_top dut (
    .wb_clk_i  (clk),      .wb_rst_i  (rst),
    .wb_adr_i  (adr[4:0]),
    .wb_dat_i  (dat_i),    .wb_dat_o  (dat_o),
    .wb_sel_i  (sel),      .wb_we_i   (we),
    .wb_stb_i  (stb),      .wb_cyc_i  (cyc),
    .wb_ack_o  (ack),      .wb_err_o  (err),
    .wb_int_o  (intr),
    .ss_pad_o  (ss),
    .sclk_pad_o(sclk),
    .mosi_pad_o(mosi),
    .miso_pad_i(miso)
);

// -----------------------------------------------------------------------
// SPI SLAVE  (1st SS assertion -> sends 0xA5 ; 2nd -> sends 0x3C)
// -----------------------------------------------------------------------
spi_slave_model slave (
    .rst (rst),
    .ss  (ss[0]),
    .sclk(sclk),
    .mosi(mosi),
    .miso(miso)
);

// =======================================================================
// SERIAL-TO-PARALLEL MONITOR
//
// Active only during Transfer 2 (monitor_active = 1).
//
// SPI Mode 0: master samples MISO on the RISING edge of SCLK.
// The spi_shift module does exactly the same — this monitor mirrors
// that hardware behaviour so the console output matches the waveform.
//
// Each iteration:
//   1. Print the raw 1-bit value on the MISO wire (serial)
//   2. Store it in serial_capture at the correct bit position
//   3. After the 8th bit, print the assembled parallel byte
// =======================================================================
initial begin
    monitor_active = 0;
    serial_capture = 8'h00;
    bit_index      = 7;     // start at MSB
end

always @(posedge sclk) begin
    if (monitor_active && (ss[0] == 0)) begin   // ss[0] is active-low

        // ---- SERIAL stage: one bit arrives on the MISO wire ----
        serial_capture[bit_index] = miso;

        $display("[S2P]  SERIAL  : bit[%0d] received on MISO = %b   | partial parallel = %08b",
                 bit_index, miso, serial_capture);

        if (bit_index == 0) begin
            // ---- PARALLEL stage: all 8 bits assembled ----
            $display("[S2P]  -----------------------------------------------------------");
            $display("[S2P]  PARALLEL: all 8 serial bits shifted into rx_shift register");
            $display("[S2P]            assembled byte = 0x%02h  (binary: %08b)",
                     serial_capture, serial_capture);
            $display("[S2P]            spi_top will latch this into rx_reg on tip fall");
            $display("[S2P]            master reads it over 32-bit Wishbone bus next.");
            $display("[S2P]  -----------------------------------------------------------");
            bit_index = 7;   // reset for any future transfer
        end else begin
            bit_index = bit_index - 1;
        end

    end
end

// =======================================================================
// MAIN TEST SEQUENCE
// =======================================================================
initial begin
    rst = 1;
    repeat(20) @(posedge clk);
    rst = 0;
    repeat(5)  @(posedge clk);

    $display("");
    $display("============================================================");
    $display("  SPI DUAL-TRANSFER TEST");
    $display("============================================================");

    // -------------------------------------------------------------------
    // TRANSFER 1 : Master -> Slave   (MOSI = 0xA5)
    // -------------------------------------------------------------------
    $display("");
    $display("---- Transfer 1 : Master -> Slave  [MOSI = 0xA5] ----");
    $display("  Parallel 0xA5 loaded into TX register by master.");
    $display("  spi_shift serialises it MSB-first on MOSI (8 SCLK cycles).");

    master.wb_write(1, SPI_DIV,  32'd2);
    master.wb_write(1, SPI_TX_0, 32'hA5);
    master.wb_write(1, SPI_SS,   32'h01);
    master.wb_write(1, SPI_CTRL, 32'h0000_0108);   // GO=1, char_len=8

    ctrl_val = 32'h0000_0108;
    while (ctrl_val[8])
        master.wb_read(1, SPI_CTRL, ctrl_val);

    $display("Transfer 1 done  (GO auto-cleared by hardware).");
    repeat(10) @(posedge clk);

    master.wb_read(1, SPI_RX_0, q);
    $display("Transfer 1  RX = 0x%h", q);
    if (q[7:0] == 8'hA5) $display("*** Transfer 1  PASS ***");
    else                  $display("*** Transfer 1  FAIL ***  got 0x%h", q[7:0]);

    repeat(10) @(posedge clk);

    // -------------------------------------------------------------------
    // TRANSFER 2 : Slave -> Master   (MISO = 0x3C, serial -> parallel)
    // -------------------------------------------------------------------
    $display("");
    $display("============================================================");
    $display("  Transfer 2 : Slave -> Master  [MISO carries 0x3C]");
    $display("------------------------------------------------------------");
    $display("  DATA PATH (serial-to-parallel):");
    $display("  [1] Slave pre-loads shift_reg = 0x3C, drives MISO MSB-first.");
    $display("  [2] spi_shift samples MISO on each SCLK posedge -> rx_shift.");
    $display("  [3] After 8 clocks: p_out[7:0] = complete parallel byte.");
    $display("  [4] spi_top latches p_out into rx_reg on falling edge of tip.");
    $display("  [5] Master reads rx_reg over 32-bit Wishbone (parallel).");
    $display("  [S2P] monitor below shows every serial bit then the parallel result.");
    $display("============================================================");

    // Arm the serial-to-parallel monitor BEFORE asserting GO
    serial_capture = 8'h00;
    bit_index      = 7;
    monitor_active = 1;

    master.wb_write(1, SPI_TX_0, 32'h00);          // dummy TX byte (master sends 0)
    master.wb_write(1, SPI_SS,   32'h01);
    master.wb_write(1, SPI_CTRL, 32'h0000_0108);   // GO=1, char_len=8

    ctrl_val = 32'h0000_0108;
    while (ctrl_val[8])
        master.wb_read(1, SPI_CTRL, ctrl_val);

    monitor_active = 0;   // disarm monitor

    $display("");
    $display("Transfer 2 done  (GO auto-cleared by hardware).");
    $display("  [5] Reading assembled parallel byte from rx_reg via Wishbone ...");
    repeat(10) @(posedge clk);

    master.wb_read(1, SPI_RX_0, q);
    $display("  Wishbone RX = 0x%h  (32-bit parallel read — expected 0x0000003c)", q);

    if (q[7:0] == 8'h3C)
        $display("*** Transfer 2  PASS  — serial-to-parallel slave->master OK ***");
    else
        $display("*** Transfer 2  FAIL ***  got 0x%h", q[7:0]);

    $display("");
    $display("============================================================");
    $display("  ALL TESTS DONE");
    $display("============================================================");

    #100;
    $finish;
end

// Timeout watchdog
initial begin
    #400000;
    $display("TIMEOUT — simulation ran too long");
    $finish;
end

endmodule
