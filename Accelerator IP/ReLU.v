module ReLU #(
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    enable, 
    input  wire [DATA_WIDTH-1:0]   x,
    output reg  [DATA_WIDTH-1:0]   out
);

    always @(posedge clk) begin
        if (enable) begin
            if ($signed(x) >= 0)
                out <= x;
            else
                out <= 0;
        end
    end

endmodule
