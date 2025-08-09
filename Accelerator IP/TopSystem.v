`timescale 1ns / 1ps

module TopSystem #(
    parameter DATA_WIDTH        = 8,
    parameter WEIGHT_WIDTH      = 16,
    parameter BIAS_WIDTH        = 32,
    parameter IMG_SIZE          = 5,
    parameter KERNEL_SIZE       = 3,
    parameter N_PIXELS          = IMG_SIZE,
    parameter NUM_CHANNELS      = 3,
    parameter NUM_FILTERS       = 64,
    parameter BIAS_FIFO_DEPTH   = (IMG_SIZE - 2) * (IMG_SIZE - 2)
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // Image data
    input  wire [DATA_WIDTH-1:0]        img_pixel,
    input  wire                         img_valid,

    // Control
    input  wire                         enable,
    input  wire                         next_pixel,
    input  wire                         start_conv,
    input  wire                         conv_done,

    // Bias preload
    input  wire                         bias_preload_en,
    input  wire [$clog2(BIAS_FIFO_DEPTH)-1:0] bias_preload_addr,
    input  wire [BIAS_WIDTH-1:0]        bias_preload_data,
    input  wire                         bias_preload_done,

    // Weight preload
    input  wire                         weight_preload_en,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] weight_preload_addr_pe0,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] weight_preload_addr_pe1,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] weight_preload_addr_pe2,
    input  wire [WEIGHT_WIDTH-1:0]      weight_preload_data_pe0,
    input  wire [WEIGHT_WIDTH-1:0]      weight_preload_data_pe1,
    input  wire [WEIGHT_WIDTH-1:0]      weight_preload_data_pe2,

    input  wire                          load_weight_row,
    input  wire [$clog2(NUM_FILTERS)-1:0] filter_id,
    input  wire [$clog2(NUM_CHANNELS)-1:0] channel_id,

    output reg  [BIAS_WIDTH-1:0]        relu_output,
    output reg                          relu_valid
);

    // === Internal Wires ===
    wire [WEIGHT_WIDTH-1:0] w0, w1, w2;
    wire weight_valid;
    wire [BIAS_WIDTH-1:0] pu_out;
    wire fifo_empty, fifo_full;
    wire bias_pop_req;
    
    wire [BIAS_WIDTH-1:0]        fifo_data_out;
    wire                         pu_outvalid;

    wire pe_enable = start_conv && img_valid && !fifo_empty && !relu_phase;

    // === ReLU pop control FSM ===
    reg relu_phase = 0;
    reg [15:0] pop_counter = 0;

    localparam MAX_POP = BIAS_FIFO_DEPTH;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            relu_phase  <= 0;
            pop_counter <= 0;
            relu_valid  <= 0;
        end else begin
            relu_valid <= 0;

            if (conv_done && fifo_full) begin
                relu_phase  <= 1;
                pop_counter <= 0;
            end

            if (relu_phase && !fifo_empty) begin
                relu_valid <= 1;
                pop_counter <= pop_counter + 1;

                if (pop_counter == MAX_POP - 1)
                    relu_phase <= 0;
            end
        end
    end

    // === Final FIFO pop mux ===
  //  wire fifo_pop = (relu_phase && !fifo_empty) || bias_pop_req;
    wire fifo_pop = (relu_phase && !fifo_empty) || (bias_pop_req && !relu_phase);


    // === Filter Buffer ===
    FilterBuffer #(
        .DATA_WIDTH(WEIGHT_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE)
    ) filter_buf (
        .clk(clk),
        .rst(rst),
        .preload_en(weight_preload_en),
        .preload_addr_pe0(weight_preload_addr_pe0),
        .preload_data_pe0(weight_preload_data_pe0),
        .preload_addr_pe1(weight_preload_addr_pe1),
        .preload_data_pe1(weight_preload_data_pe1),
        .preload_addr_pe2(weight_preload_addr_pe2),
        .preload_data_pe2(weight_preload_data_pe2),
        .load_row(load_weight_row),
        .filter_id(filter_id),
        .channel_id(channel_id),
        .weight0(w0),
        .weight1(w1),
        .weight2(w2),
        .weight_valid(weight_valid)
    );

    // === Processing Unit ===
    PU #(
        .numWeight(3),
        .dataWidth(DATA_WIDTH),
        .N_pixels(N_PIXELS)
    ) pu_inst (
        .clk(clk),
        .rst(rst),
        .clear(1'b0),
        .pe_enable(pe_enable),
        .image_in(img_pixel),
        .image_valid(img_valid),
        .filter0(w0),
        .filter1(w1),
        .filter2(w2),
        .weight_valid(weight_valid),
        .biasValue(fifo_data_out),
        .biasValid(!fifo_empty),
        .pu_out(pu_out),
        .pu_outvalid(pu_outvalid),
        .bias_pop_req(bias_pop_req)
    );

    // === Bias FIFO ===
    BiasFIFO #(
        .DATA_WIDTH(BIAS_WIDTH),
        .DEPTH(BIAS_FIFO_DEPTH)
    ) bias_fifo (
        .clk(clk),
        .rst(rst),
        .push(pu_outvalid),
        .pop(fifo_pop),
        .data_in(pu_out),
        .data_out(fifo_data_out),
        .full(fifo_full),
        .empty(fifo_empty),

        .preload_en(bias_preload_en),
        .preload_addr(bias_preload_addr),
        .preload_data(bias_preload_data),
        .preload_done(bias_preload_done)
    );

    // === ReLU ===
    wire [BIAS_WIDTH-1:0] relu_result;
    ReLU #(
        .DATA_WIDTH(BIAS_WIDTH)
    ) relu_inst (
        .clk(clk),
        .enable(relu_valid),           // only active when valid
        .x(fifo_data_out),             // un-gated input
        .out(relu_result)
    );

    // === Output Register ===
    always @(posedge clk) begin
        if (relu_valid)
            relu_output <= relu_result;
    end

endmodule
