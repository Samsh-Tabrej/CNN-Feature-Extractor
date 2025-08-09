`timescale 1ns/1ps

module BiasFIFO #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 4
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire                   push,
    input  wire                   pop,
    input  wire [DATA_WIDTH-1:0]  data_in,
    output reg  [DATA_WIDTH-1:0]  data_out,
    output wire                   full,
    output wire                   empty,

    // Preload interface
    input  wire                   preload_en,
    input  wire [$clog2(DEPTH)-1:0] preload_addr,
    input  wire [DATA_WIDTH-1:0]  preload_data,
    input  wire                   preload_done
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] rd_ptr = 0;
    reg [ADDR_WIDTH-1:0] wr_ptr = 0;
    reg [ADDR_WIDTH:0]   count  = 0;

    // FIFO Preload: data written directly into memory
    always @(posedge clk) begin
        if (preload_en) begin
            fifo_mem[preload_addr] <= preload_data;
            $display("### [FIFO] Time %0t: PRELOAD %0d to addr %0d", $time, preload_data, preload_addr);
        end
    end

    // FIFO Commit: update pointers and count after preload
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else if (preload_done) begin
            //wr_ptr <= DEPTH[ADDR_WIDTH-1:0];
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= DEPTH;
            $display("### [FIFO] Time %0t: COMMIT preload, count=%0d", $time, DEPTH);
        end else begin
            // Push
            if (push && !full && !preload_en) begin
                fifo_mem[wr_ptr] <= data_in;
                wr_ptr <= wr_ptr + 1;
                $display(">>> [FIFO] Time %0t: PUSH %0d to addr %0d", $time, data_in, wr_ptr);
            end
            // Pop
            if (pop && !empty && !preload_en) begin
                data_out <= fifo_mem[rd_ptr];
                fifo_mem[rd_ptr] <= 0;
                $display("<<< [FIFO] Time %0t: POP -> %0d from addr %0d", $time, fifo_mem[rd_ptr], rd_ptr);
                rd_ptr <= rd_ptr + 1;
            end

            // Count update
            case ({push && !full && !preload_en, pop && !empty && !preload_en})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end
    always @(posedge clk) begin
    if (pop && !empty)
        $display("[FIFO] T=%0t | POP -> %0d from addr %0d", $time, data_out, rd_ptr);
    end
// === Debug: matrix print ===
integer row, col, idx;
integer SQRT;

always @(posedge clk) begin
    if (!rst) begin
        // Compute square root for 2D visualization
        SQRT = 1;
        while (SQRT * SQRT < DEPTH)
            SQRT = SQRT + 1;

        if (SQRT * SQRT != DEPTH) begin
            $display("[T=%0t] WARNING: DEPTH=%0d is not a perfect square!", $time, DEPTH);
        end else begin
            $display("[T=%0t] BiasFIFO Contents (Decimal, Normal Order):", $time);
            for (row = 0; row < SQRT; row = row + 1) begin
                $write("  ");
                for (col = 0; col < SQRT; col = col + 1) begin
                    idx = row * SQRT + col;
                    $write("%10.6f ", $itor($signed(fifo_mem[idx])) / 4194304.0);
                end
                $write("\n");
            end
            $display("--------------------------------------------------");
        end
    end
end


    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule
