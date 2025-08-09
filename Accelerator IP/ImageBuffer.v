`timescale 1ns / 1ps

module ImageBuffer #(
    parameter IMG_SIZE   = 5,
    parameter DATA_WIDTH = 8,
    parameter STEP       = 1
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 clear,

    input  wire                 enable,
    input  wire                 preload_done,
    input  wire                 next_pixel,

    input  wire                 preload_en,
    input  wire [DATA_WIDTH-1:0] preload_pixel,
    input  wire [$clog2(IMG_SIZE*IMG_SIZE)-1:0] preload_addr,

    output reg  [DATA_WIDTH-1:0] image_out,
    output reg                   image_valid
);

    // === Internal SRAM ===
    reg [DATA_WIDTH-1:0] image_sram [0:IMG_SIZE*IMG_SIZE-1];

    // === Preload Logic ===
    always @(posedge clk) begin
        if (preload_en) begin
            image_sram[preload_addr] <= preload_pixel;
            $display("[T=%0t] [ImageBuffer] PRELOAD: mem[%0d] <= %0d", $time, preload_addr, preload_pixel);
        end
    end

    // === Address Generator ===
    localparam KERNEL    = 3;
    localparam OUT_SIZE  = IMG_SIZE - KERNEL + 1;

    reg [$clog2(IMG_SIZE)-1:0] row, col, k;
    wire [$clog2(IMG_SIZE*IMG_SIZE)-1:0] read_addr;

    assign read_addr = row * IMG_SIZE + col + k;

    // === Streaming Logic ===
    always @(posedge clk) begin
        if (rst || clear) begin
            row <= 0;
            col <= 0;
            k   <= 0;
            image_out   <= 0;
            image_valid <= 0;
        end else if (enable && preload_done && next_pixel) begin
            image_out   <= image_sram[read_addr];
            image_valid <= 1;

            $display("[T=%0t] [ImageBuffer] Streaming pixel: read_addr=%0d, out=%0d, row=%0d, col=%0d, k=%0d",
                      $time, read_addr, image_sram[read_addr], row, col, k);
            $display("[T=%0t] [ImageBuffer] image_out VALID: %0d", $time, image_out);

            if (k == KERNEL - 1) begin
                k <= 0;
                if (col == OUT_SIZE - 1) begin
                    col <= 0;
                    row <= row + 1;
                end else begin
                    col <= col + STEP;
                end
            end else begin
                k <= k + 1;
            end
        end else begin
            image_valid <= 0;
        end
    end

endmodule
