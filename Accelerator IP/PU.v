`timescale 1ns / 1ps

module PU #(
    parameter numWeight  = 3,
    parameter dataWidth  = 8,
    parameter fifoDepth  = 16,  
    parameter N_pixels   = 5
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          clear,
    input  wire                          pe_enable,

    input  wire [dataWidth-1:0]          image_in,
    input  wire                          image_valid,
    input  wire signed [2*dataWidth-1:0] filter0,
    input  wire signed [2*dataWidth-1:0] filter1,
    input  wire signed [2*dataWidth-1:0] filter2,
    input  wire                          weight_valid,

    input  wire signed [4*dataWidth-1:0] biasValue,
    input  wire                          biasValid,

    output wire signed [31:0]            pu_out,
    output wire                          pu_outvalid,

    output wire                          bias_pop_req
);

    localparam N_OUT = N_pixels - 2;
    localparam numbias = N_OUT * N_OUT;
    localparam BIAS_CNT_WIDTH = $clog2(numbias + 1);
    localparam OUT_CNT_WIDTH  = $clog2(numbias + 1);

    reg [BIAS_CNT_WIDTH-1:0] bias_pop_cnt;

    // === PE0 ===
    wire signed [31:0] pe0_out;
    wire               pe0_outvalid;
    wire               pe0_ready_for_next;
    wire               internal_bias_pop_req;

    // Bias counter
    always @(posedge clk) begin
        if (rst || clear || !pe_enable)
            bias_pop_cnt <= 0;
        else if (internal_bias_pop_req && bias_pop_cnt < numbias +1)
            bias_pop_cnt <= bias_pop_cnt + 1;
    end

    wire pe0_enable_internal     = pe_enable && (bias_pop_cnt < numbias +1);
    wire bias_req_enable_pe0     = (bias_pop_cnt < numbias);  // only request valid biases

    PE #(
        .numWeight(numWeight),
        .dataWidth(dataWidth),
        .numInputs(N_pixels)
    ) PE0 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .pe_enable(pe0_enable_internal),
        .myinputValid(image_valid),
        .weightValid(weight_valid),
        .biasValid(biasValid),
        .bias_req_enable(bias_req_enable_pe0),
        .myinput(image_in),
        .weightValue(filter0),
        .biasValue(biasValue),
        .outvalid(pe0_outvalid),
        .out(pe0_out),
        .pe_ready_for_next(pe0_ready_for_next),
        .bias_pop_req(internal_bias_pop_req)
    );

    assign bias_pop_req = internal_bias_pop_req && bias_req_enable_pe0;

    // === FIFO0: PE0 -> PE1 ===
    wire signed [31:0] fifo0_out;
    wire               fifo0_valid;

    ShiftFIFO #(.WIDTH(32), .DEPTH(N_OUT)) fifo0 (
        .clk(clk),
        .rst(rst),
        .push(pe0_outvalid),
        .data_in(pe0_out),
        .data_out(fifo0_out),
        .valid(fifo0_valid)
    );

    // === PE1 Control ===
    reg                   pe1_latched = 0;
    reg [OUT_CNT_WIDTH-1:0] pe1_out_count = 0;

    always @(posedge clk) begin
        if (rst || clear || !pe_enable) begin
            pe1_latched <= 0;
            pe1_out_count <= 0;
        end else if (pe0_ready_for_next) begin
            pe1_latched <= 1;
            pe1_out_count <= 0;
        end else if (pe1_outvalid) begin
            if (pe1_out_count == numbias - 1)
                pe1_latched <= 0;
            else
                pe1_out_count <= pe1_out_count + 1;
        end
    end

    wire pe1_enable_internal = pe_enable && (pe1_latched || pe0_ready_for_next);

    // === PE1 ===
    wire signed [31:0] pe1_out;
    wire               pe1_outvalid;
    wire               pe1_ready_for_next;

    PE #(
        .numWeight(numWeight),
        .dataWidth(dataWidth),
        .numInputs(N_pixels)
    ) PE1 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .pe_enable(pe1_enable_internal),
        .myinputValid(image_valid),
        .weightValid(weight_valid),
        .biasValid(fifo0_valid),
        .bias_req_enable(1'b1),
        .myinput(image_in),
        .weightValue(filter1),
        .biasValue(fifo0_out),
        .outvalid(pe1_outvalid),
        .out(pe1_out),
        .pe_ready_for_next(pe1_ready_for_next),
        .bias_pop_req()
    );

    // === FIFO1: PE1 → PE2 ===
    wire signed [31:0] fifo1_out;
    wire               fifo1_valid;

    ShiftFIFO #(.WIDTH(32), .DEPTH(N_OUT)) fifo1 (
        .clk(clk),
        .rst(rst),
        .push(pe1_outvalid),
        .data_in(pe1_out),
        .data_out(fifo1_out),
        .valid(fifo1_valid)
    );

    // === PE2 Control ===
    reg                   pe2_latched = 0;
    reg [OUT_CNT_WIDTH-1:0] pe2_out_count = 0;

    always @(posedge clk) begin
        if (rst || clear || !pe_enable) begin
            pe2_latched <= 0;
            pe2_out_count <= 0;
        end else if (pe1_ready_for_next) begin
            pe2_latched <= 1;
            pe2_out_count <= 0;
        end else if (pe2_outvalid) begin
            if (pe2_out_count == numbias - 1)
                pe2_latched <= 0;
            else
                pe2_out_count <= pe2_out_count + 1;
        end
    end

    wire pe2_enable_internal = pe_enable && (pe2_latched || pe1_ready_for_next);

    // === PE2 ===
    wire signed [31:0] pe2_out;
    wire               pe2_outvalid;

    PE #(
        .numWeight(numWeight),
        .dataWidth(dataWidth),
        .numInputs(N_pixels)
    ) PE2 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .pe_enable(pe2_enable_internal),
        .myinputValid(image_valid),
        .weightValid(weight_valid),
        .biasValid(fifo1_valid),
        .bias_req_enable(1'b1),
        .myinput(image_in),
        .weightValue(filter2),
        .biasValue(fifo1_out),
        .outvalid(pe2_outvalid),
        .out(pe2_out),
        .pe_ready_for_next(),
        .bias_pop_req()
    );

    // === Output ===
    assign pu_out      = pe2_out;
    assign pu_outvalid = pe2_outvalid;

endmodule
