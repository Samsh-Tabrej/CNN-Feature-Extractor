`timescale 1ns / 1ps

module Accelerator64 #(
    parameter NUM_PUS           = 64,
    parameter IMG_SIZE          = 34,
    parameter NUM_FILTERS       = 1,
    parameter NUM_CHANNELS      = 64
)(
    input  wire clk,
    input  wire rst,
    input  wire scatter_valid,
    input  wire [127:0] scatter_data,
    output wire channel_ready,
    output wire [127:0] relu_out_data,
    output wire         relu_out_valid
);

    localparam KERNEL_SIZE       = 3;
    localparam DATA_WIDTH        = 8; 
    localparam WEIGHT_WIDTH      = 16;
    localparam BIAS_WIDTH        = 32;
    localparam N_PIXELS          = IMG_SIZE;
    localparam STEP              = 1;
    localparam IMG_ADDR_WIDTH    = $clog2(IMG_SIZE * IMG_SIZE);
    localparam BIAS_FIFO_DEPTH   = (IMG_SIZE - 2) * (IMG_SIZE - 2);
    localparam ADDR_WIDTH         = 8;
    
    // === Internal Wires ===
    wire clear, start_conv, next_pixel;
    wire image_preload_done;
    wire [NUM_PUS-1:0] bias_preload_done;
    wire [NUM_PUS-1:0] load_weight_row;
    wire [NUM_PUS*8-1:0] filter_id;
    wire [NUM_PUS*8-1:0] channel_id;

    wire image_preload_en;
    wire [DATA_WIDTH-1:0] image_preload_pixel;
    wire [IMG_ADDR_WIDTH-1:0] image_preload_addr;
    wire img_valid;
    wire [DATA_WIDTH-1:0] img_pixel;

    wire [NUM_PUS-1:0] bias_preload_en;
    wire [NUM_PUS*ADDR_WIDTH-1:0] bias_addr;
    wire [NUM_PUS*BIAS_WIDTH-1:0] bias_data;
    wire [NUM_PUS-1:0] weight_preload_en;
    wire [NUM_PUS*ADDR_WIDTH-1:0] weight_addr_pe0, weight_addr_pe1, weight_addr_pe2;
    wire [NUM_PUS*WEIGHT_WIDTH-1:0] weight_data_pe0, weight_data_pe1, weight_data_pe2;
    
    wire conv_done;

    wire [NUM_PUS*BIAS_WIDTH-1:0] relu_outputs_all;
    wire [NUM_PUS-1:0]            relu_valid_all;

    // === Convolution Activity Register ===
    reg conv_active;
    always @(posedge clk or posedge rst) begin
        if (rst)
            conv_active <= 0;
        else if (start_conv)
            conv_active <= 1;
        else if (conv_done)
            conv_active <= 0;
    end

    // === Image Buffer ===
    ImageBuffer #(
        .IMG_SIZE(IMG_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .STEP(STEP)
    ) image_buffer_inst (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(conv_active),
        .preload_done(image_preload_done),
        .next_pixel(next_pixel),
        .preload_en(image_preload_en),
        .preload_pixel(image_preload_pixel),
        .preload_addr(image_preload_addr),
        .image_out(img_pixel),
        .image_valid(img_valid)
    );

    // === Scatter Controller ===
    ScatterSimple #(
        .NUM_PUS(NUM_PUS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .IMG_ADDR_WIDTH(IMG_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .BIAS_WIDTH(BIAS_WIDTH),
        .IMG_SIZE(IMG_SIZE)
    ) scatter_inst (
        .clk(clk),
        .rst(rst),
        .valid(scatter_valid),
        .data(scatter_data),
        .ready(),

        .image_preload_en(image_preload_en),
        .image_preload_pixel(image_preload_pixel),
        .image_preload_addr(image_preload_addr),

        .bias_preload_en(bias_preload_en),
        .bias_addr(bias_addr),
        .bias_data(bias_data),

        .weight_preload_en(weight_preload_en),
        .weight_addr_pe0(weight_addr_pe0),
        .weight_addr_pe1(weight_addr_pe1),
        .weight_addr_pe2(weight_addr_pe2),
        .weight_data_pe0(weight_data_pe0),
        .weight_data_pe1(weight_data_pe1),
        .weight_data_pe2(weight_data_pe2),

        .filter_id(filter_id),
        .channel_id(channel_id),

        .clear(clear),
        .image_preload_done(image_preload_done),
        .bias_preload_done(bias_preload_done),
        .load_weight_row(load_weight_row),
        .channel_ready(channel_ready),
        .start_conv(start_conv),
        .next_pixel(next_pixel),
        .conv_done(conv_done)
    );

    // === Processing Units ===
    genvar i;
    generate
        for (i = 0; i < NUM_PUS; i = i + 1) begin : PU_ARRAY
            TopSystem #(
                .DATA_WIDTH(DATA_WIDTH),
                .WEIGHT_WIDTH(WEIGHT_WIDTH),
                .BIAS_WIDTH(BIAS_WIDTH),
                .IMG_SIZE(IMG_SIZE),
                .KERNEL_SIZE(KERNEL_SIZE),
                .N_PIXELS(N_PIXELS),
                .NUM_FILTERS(NUM_FILTERS),
                .NUM_CHANNELS(NUM_CHANNELS),
                .BIAS_FIFO_DEPTH(BIAS_FIFO_DEPTH)
            ) pu_core (
                .clk(clk),
                .rst(rst),
                .clear(clear),

                .img_pixel(img_pixel),
                .img_valid(img_valid),

                .enable(conv_active),
                .start_conv(conv_active),
                .next_pixel(next_pixel),
                .conv_done(conv_done),

                .bias_preload_en(bias_preload_en[i]),
                .bias_preload_addr(bias_addr[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .bias_preload_data(bias_data[i*BIAS_WIDTH +: BIAS_WIDTH]),
                .bias_preload_done(bias_preload_done[i]),

                .weight_preload_en(weight_preload_en[i]),
                .weight_preload_addr_pe0(weight_addr_pe0[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .weight_preload_addr_pe1(weight_addr_pe1[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .weight_preload_addr_pe2(weight_addr_pe2[i*ADDR_WIDTH +: ADDR_WIDTH]),
                .weight_preload_data_pe0(weight_data_pe0[i*WEIGHT_WIDTH +: WEIGHT_WIDTH]),
                .weight_preload_data_pe1(weight_data_pe1[i*WEIGHT_WIDTH +: WEIGHT_WIDTH]),
                .weight_preload_data_pe2(weight_data_pe2[i*WEIGHT_WIDTH +: WEIGHT_WIDTH]),

                .load_weight_row(load_weight_row[i]),
                .filter_id(filter_id[i*8 +: 8]),
                .channel_id(channel_id[i*8 +: 8]),

                .relu_output(relu_outputs_all[i*BIAS_WIDTH +: BIAS_WIDTH]),
                .relu_valid(relu_valid_all[i])
            );
        end
    endgenerate

    // === ReLU Output Aggregator ===
    wire relu_input_valid = &relu_valid_all;  // all PUs have valid ReLU data
    reg relu_input_valid_d = 0;
    reg relu_valid_dd = 0;
    
    always @ (posedge clk) begin
        relu_input_valid_d <= relu_input_valid;
        relu_valid_dd      <= relu_input_valid_d;
    end

    ReluPacker #(
        .NUM_PUS(NUM_PUS),
        .BIAS_WIDTH(BIAS_WIDTH),
        .BIAS_FIFO_DEPTH(BIAS_FIFO_DEPTH)
    ) relu_packer_inst (
        .clk(clk),
        .rst(rst),

        .relu_input_valid(relu_valid_dd),
        .relu_outputs_all(relu_outputs_all),

        .relu_out_valid(relu_out_valid),
        .relu_out_data(relu_out_data)
    );

endmodule