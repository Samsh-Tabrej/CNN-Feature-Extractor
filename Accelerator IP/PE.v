`timescale 1ns/1ps

module PE #(
    parameter numInputs   = 5,
    parameter numWeight   = 3,
    parameter dataWidth   = 8
)(
    input                           clk,
    input                           rst,
    input                           clear,
    input                           pe_enable,
    input                           myinputValid,
    input                           weightValid,
    input                           biasValid,
    input                           bias_req_enable,

    input       [dataWidth-1:0]     myinput,
    input signed [15:0]             weightValue,
    input signed [31:0]             biasValue,

    output reg                      bias_pop_req,
    output reg                      outvalid,
    output reg signed [31:0]        out,
    output reg                      pe_ready_for_next
);

    localparam N_OUT = numInputs - 2;
    localparam OUT_CNT_WIDTH = $clog2(numInputs);

    reg signed [31:0] psum_mac;
    reg signed [31:0] psum_stage;
    reg signed [31:0] bias;

    reg [1:0] mac_cnt;
    reg       bias_add_phase;
    reg [OUT_CNT_WIDTH-1:0] out_count;

    wire input_ready = myinputValid && pe_enable;
    wire is_last_mac = (mac_cnt == numWeight - 1);

    wire signed [31:0] input_ext = $signed({1'b0, myinput}) <<< 8;

    wire signed [31:0] mult_result;
    assign mult_result = $signed(input_ext) * $signed(weightValue);

    always @(posedge clk) begin
        if (rst)
            bias <= 0;
        else if (biasValid)
            bias <= biasValue;
    end

    always @(posedge clk) begin
        if (rst || clear)
            mac_cnt <= 0;
        else if (input_ready)
            mac_cnt <= is_last_mac ? 0 : mac_cnt + 1;
    end

    always @(posedge clk) begin
        if (rst || clear)
            psum_mac <= 0;
        else if (input_ready && mac_cnt == 0)
            psum_mac <= mult_result;
        else if (input_ready)
            psum_mac <= psum_mac + mult_result;
    end

    always @(posedge clk) begin
        if (input_ready && is_last_mac)
            psum_stage <= psum_mac + mult_result;
    end

    always @(posedge clk) begin
        if (rst || clear)
            bias_pop_req <= 0;
        else if (input_ready && mac_cnt == 0 && bias_req_enable)
            bias_pop_req <= 1;
        else
            bias_pop_req <= 0;
    end

    always @(posedge clk) begin
        if (rst || clear)
            bias_add_phase <= 0;
        else if (input_ready && is_last_mac)
            bias_add_phase <= 1;
        else
            bias_add_phase <= 0;
    end

    always @(posedge clk) begin
        if (rst || clear)
            out_count <= 0;
        else if (bias_add_phase) begin
            if (out_count == N_OUT - 1)
                out_count <= 0;
            else
                out_count <= out_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst || clear)
            pe_ready_for_next <= 0;
        else if (input_ready && is_last_mac && (out_count == N_OUT - 1))
            pe_ready_for_next <= 1;
        else
            pe_ready_for_next <= 0;
    end

    always @(posedge clk) begin
        if (rst || clear) begin
            outvalid <= 0;
            out <= 0;
        end else begin
            outvalid <= bias_add_phase;
            if (bias_add_phase)
                out <= psum_stage + bias;
        end
    end

    always @(posedge clk) begin
        if (!rst && pe_enable) begin
            $display("--------------------------------------------------");
            $display("[T=%0t] PE DEBUG", $time);
            $display("  mac_cnt       = %0d", mac_cnt);
            $display("  out_count     = %0d / %0d", out_count, N_OUT);
            $display("  input         = %0d", myinput);
            $display("  weight        = %0d (%.4f)", $signed(weightValue), $itor($signed(weightValue)) / 16384.0);
            $display("  mult_result   = %0d (%.6f)", $signed(mult_result), $itor($signed(mult_result)) / 4194304.0);
            if (input_ready && is_last_mac)
                $display("  >>> MAC GROUP COMPLETE <<<");
            if (bias_add_phase) begin
                $display("  >>> Bias Addition <<<");
                $display("     psum_stage = %0d (%.6f)", psum_stage, $itor(psum_stage) / 4194304.0);
                $display("     bias       = %0d (%.6f)", bias, $itor(bias) / 4194304.0);
            end
            if (outvalid) begin
                $display("  >>> Output <<<");
                $display("     out        = %0d (%.6f)", $signed(out), $itor($signed(out)) / 4194304.0);
            end
            if (pe_ready_for_next)
                $display("  >>> PE Ready For Next <<<");
        end
    end

endmodule
