`timescale 1ns/1ps

module ShiftFIFO #(
    parameter WIDTH = 32,
    parameter DEPTH = 3
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              push,              // Enable to shift + insert new data
    input  wire [WIDTH-1:0]  data_in,
    output wire [WIDTH-1:0]  data_out,          // Oldest data (tail)
    output wire              valid              // Valid when DEPTH entries pushed
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [$clog2(DEPTH+1):0] count;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= 0;
        end else if (push) begin
            // Shift right and insert new data at mem[0]
            for (i = DEPTH-1; i > 0; i = i - 1)
                mem[i] <= mem[i-1];
            mem[0] <= data_in;

            if (count < DEPTH)
                count <= count + 1;
        end
    end

    assign data_out = mem[DEPTH-1];
    assign valid    = (count == DEPTH);

endmodule