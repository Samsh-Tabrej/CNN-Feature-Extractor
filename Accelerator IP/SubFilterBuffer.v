//****working filter buffer multichannel****

`timescale 1ns/1ps

module SubFilterBuffer #(
    parameter DATA_WIDTH   = 16,
    parameter NUM_FILTERS  = 1,
    parameter NUM_CHANNELS = 1,
    parameter KERNEL_SIZE  = 3,
    parameter PE_INDEX     = 0  // Use 0 for PE0, 1 for PE1, 2 for PE2
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    preload_en,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS*KERNEL_SIZE)-1:0] preload_addr,
    input  wire [DATA_WIDTH-1:0]   preload_data,

    // Row load control
    input  wire                    load_row,
    input  wire [$clog2(NUM_FILTERS*NUM_CHANNELS)-1:0] row_index,

    // Streaming output
    output reg  [DATA_WIDTH-1:0]   weight,
    output reg                     weight_valid
);

    localparam TOTAL_ROWS = NUM_FILTERS * NUM_CHANNELS;
    localparam SRAM_DEPTH = TOTAL_ROWS * KERNEL_SIZE;

    reg [DATA_WIDTH-1:0] sram [0:SRAM_DEPTH-1];
    reg [DATA_WIDTH-1:0] rf   [0:KERNEL_SIZE-1];

    reg [$clog2(KERNEL_SIZE)-1:0] rf_idx;
    reg loaded;

    // === Preload SRAM ===
    always @(posedge clk) begin
        if (preload_en) begin
            sram[preload_addr] <= preload_data;
            $display("[T=%0t] [PE%0d][PRELOAD] SRAM[%0d] <= %0d", $time, PE_INDEX, preload_addr, $signed(preload_data));
        end
    end

    // === Load RF and stream ===
    integer base;
    always @(posedge clk) begin
        if (rst) begin
            rf_idx       <= 0;
            weight       <= 0;
            weight_valid <= 0;
            loaded       <= 0;
        end else if (load_row) begin
            base = row_index * KERNEL_SIZE;
            rf[0] <= sram[base + 0];
            rf[1] <= sram[base + 1];
            rf[2] <= sram[base + 2];
            rf_idx <= 0;
            loaded <= 1;
            weight_valid <= 0;

        end else if (loaded) begin
            weight       <= rf[rf_idx];
            weight_valid <= 1;
            rf_idx <= (rf_idx == KERNEL_SIZE - 1) ? 0 : rf_idx + 1;
        end else begin
            weight_valid <= 0;
        end
    end

endmodule
