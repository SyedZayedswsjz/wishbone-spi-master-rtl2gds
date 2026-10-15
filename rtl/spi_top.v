`timescale 1ns/1ps
`include "spi_defines.v"

module spi_top (
    input wb_clk_i,
    input wb_rst_i,

    input [4:0] wb_adr_i,
    input [31:0] wb_dat_i,
    output reg [31:0] wb_dat_o,

    input [3:0] wb_sel_i,
    input wb_we_i,
    input wb_stb_i,
    input wb_cyc_i,

    output reg wb_ack_o,
    output wb_err_o,
    output reg wb_int_o,

    output [`SPI_SS_NB-1:0] ss_pad_o,
    output sclk_pad_o,
    output mosi_pad_o,
    input  miso_pad_i
);

// REGISTERS
reg [`SPI_DIVIDER_LEN-1:0] divider;
reg [`SPI_CTRL_BIT_NB-1:0] ctrl;
reg [`SPI_SS_NB-1:0] ss;
reg [31:0] tx_reg;
reg [31:0] rx_reg;

// INTERNAL
wire [`SPI_MAX_CHAR-1:0] rx;   // FIX 3: full-width wire matches spi_shift p_out
wire tip, last_bit;
wire pos_edge, neg_edge;
reg tip_d;

// ADDRESS DECODE
wire spi_ctrl_sel = wb_cyc_i & wb_stb_i & (wb_adr_i == `SPI_CTRL);
wire spi_div_sel  = wb_cyc_i & wb_stb_i & (wb_adr_i == `SPI_DEVIDE);
wire spi_ss_sel   = wb_cyc_i & wb_stb_i & (wb_adr_i == `SPI_SS);
wire spi_tx_sel   = wb_cyc_i & wb_stb_i & (wb_adr_i == `SPI_TX_0);

// ACK (1-cycle response)
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        wb_ack_o <= 0;
    else
        wb_ack_o <= wb_cyc_i & wb_stb_i & ~wb_ack_o;   // single-cycle ack pulse
end

assign wb_err_o = 1'b0;

// WRITE REGISTERS
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        divider <= 0;
    else if (spi_div_sel && wb_we_i)
        divider <= wb_dat_i[`SPI_DIVIDER_LEN-1:0];
end

always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        ctrl <= 0;
    else if (spi_ctrl_sel && wb_we_i)
        ctrl <= wb_dat_i[`SPI_CTRL_BIT_NB-1:0];
    else if (tip_d && !tip)
        ctrl[`SPI_CTRL_GO] <= 0;   // auto-clear GO
end

// TIP EDGE DETECT
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        tip_d <= 0;
    else
        tip_d <= tip;
end

// SLAVE SELECT CONTROL
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        ss <= 0;
    else if (spi_ss_sel && wb_we_i)
        ss <= wb_dat_i[`SPI_SS_NB-1:0];
    else if (tip)
        ss <= ss;
    else if (tip_d && !tip)
        ss <= 0;
end

assign ss_pad_o = ~ss;

// TX REGISTER
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        tx_reg <= 0;
    else if (spi_tx_sel && wb_we_i)
        tx_reg <= wb_dat_i;
end

// RX BUFFER - FIX 4: capture only [7:0] from full-width rx bus
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        rx_reg <= 0;
    else if (tip_d && !tip)
        rx_reg <= {24'd0, rx[7:0]};   // capture lower 8 bits cleanly
end

// READ LOGIC (registered - stable)
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        wb_dat_o <= 0;
    else begin
        case (wb_adr_i)
            `SPI_RX_0:   wb_dat_o <= rx_reg;
            `SPI_CTRL:   wb_dat_o <= ctrl;
            `SPI_DEVIDE: wb_dat_o <= divider;
            `SPI_SS:     wb_dat_o <= ss;
            default:     wb_dat_o <= 0;
        endcase
    end
end

// INTERRUPT (transfer done)
always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i)
        wb_int_o <= 0;
    else if (ctrl[`SPI_CTRL_IE] && tip_d && !tip)
        wb_int_o <= 1;
    else if (wb_ack_o)
        wb_int_o <= 0;
end

// CLOCK GENERATOR
spi_clgen clgen (
    .clk_in(wb_clk_i),
    .rst(wb_rst_i),
    .go(ctrl[`SPI_CTRL_GO]),
    .enable(tip),
    .last_clk(last_bit),
    .divider(divider),
    .clk_out(sclk_pad_o),
    .pos_edge(pos_edge),
    .neg_edge(neg_edge)
);

// SHIFT ENGINE
spi_shift shift (
    .clk(wb_clk_i),
    .rst(wb_rst_i),

    .latch({4{spi_tx_sel & wb_we_i}}),
    .byte_sel(wb_sel_i),

    .len(ctrl[`SPI_CTRL_CHAR_LEN]),
    .lsb(ctrl[`SPI_CTRL_LSB]),
    .go(ctrl[`SPI_CTRL_GO]),

    .pos_edge(pos_edge),
    .neg_edge(neg_edge),
    .rx_negedge(ctrl[`SPI_CTRL_RX_NEGEDGE]),
    .tx_negedge(ctrl[`SPI_CTRL_TX_NEGEDGE]),

    .tip(tip),
    .last(last_bit),

    .p_in(tx_reg),
    .p_out(rx),

    .sclk(sclk_pad_o),
    .miso(miso_pad_i),
    .mosi(mosi_pad_o)
);

endmodule
