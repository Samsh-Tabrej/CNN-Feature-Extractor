`timescale 1ns/1ps

module FilterBuffer #(
    parameter DATA_WIDTH    = 16,
    parameter NUM_FILTERS   = 1,
    parameter NUM_CHANNELS  = 1,
    parameter KERNEL_SIZE   = 3
)(
    input  wire                            clk,
    input  wire                            rst,

    input  wire                            preload_en,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] preload_addr_pe0,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] preload_addr_pe1,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] preload_addr_pe2,
    input  wire [DATA_WIDTH-1:0]           preload_data_pe0,
    input  wire [DATA_WIDTH-1:0]           preload_data_pe1,
    input  wire [DATA_WIDTH-1:0]           preload_data_pe2,

    // Row selection
    input  wire                            load_row,
    input  wire [$clog2(NUM_FILTERS)-1:0]  filter_id,
    input  wire [$clog2(NUM_CHANNELS)-1:0] channel_id,

    // Output weights
    output wire [DATA_WIDTH-1:0]           weight0,
    output wire [DATA_WIDTH-1:0]           weight1,
    output wire [DATA_WIDTH-1:0]           weight2,
    output wire                            weight_valid
);

    wire [$clog2(NUM_FILTERS*NUM_CHANNELS)-1:0] row_index;
    assign row_index = filter_id * NUM_CHANNELS + channel_id;

    SubFilterBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .PE_INDEX(0)
    ) pe0 (
        .clk(clk), .rst(rst),
        .preload_en(preload_en),
        .preload_addr(preload_addr_pe0),
        .preload_data(preload_data_pe0),
        .load_row(load_row),
        .row_index(row_index),
        .weight(weight0),
        .weight_valid(weight_valid)
    );

    SubFilterBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .PE_INDEX(1)
    ) pe1 (
        .clk(clk), .rst(rst),
        .preload_en(preload_en),
        .preload_addr(preload_addr_pe1),
        .preload_data(preload_data_pe1),
        .load_row(load_row),
        .row_index(row_index),
        .weight(weight1),
        .weight_valid()
    );

    SubFilterBuffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .PE_INDEX(2)
    ) pe2 (
        .clk(clk), .rst(rst),
        .preload_en(preload_en),
        .preload_addr(preload_addr_pe2),
        .preload_data(preload_data_pe2),
        .load_row(load_row),
        .row_index(row_index),
        .weight(weight2),
        .weight_valid()
    );

endmodule
