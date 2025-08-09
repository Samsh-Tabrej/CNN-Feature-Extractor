`timescale 1ns / 1ps

module ReluPacker #(
    parameter NUM_PUS         = 64,
    parameter BIAS_WIDTH      = 32,
    parameter BIAS_FIFO_DEPTH = 25
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          relu_input_valid,
    input  wire [NUM_PUS*BIAS_WIDTH-1:0] relu_outputs_all,
    output reg                           relu_out_valid,
    output reg  [127:0]                  relu_out_data
);

    // === Local Params ===
    localparam ROW_WIDTH   = NUM_PUS * BIAS_WIDTH;
    localparam GROUP_WIDTH = 4 * BIAS_WIDTH;
    localparam NUM_GROUPS  = (NUM_PUS + 3) / 4; // ceil(NUM_PUS / 4)
    localparam ADDR_W_ROW  = $clog2(BIAS_FIFO_DEPTH);
    localparam ADDR_W_GRP  = $clog2(NUM_GROUPS);

    // === Buffer ===
    reg [ROW_WIDTH-1:0] storage [0:BIAS_FIFO_DEPTH-1];

    // === Pointers and flags ===
    reg [ADDR_W_ROW:0] wr_ptr;
    reg [ADDR_W_ROW:0] rd_ptr;
    reg [ADDR_W_GRP:0] group_index;

    reg buffering_done;
    reg streaming_active;

    // === Row read out of buffer ===
    reg [ROW_WIDTH-1:0] current_row;

    // === Input Buffering ===
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr         <= 0;
            buffering_done <= 0;
            streaming_active <= 0;
        end else begin
            if (!buffering_done && relu_input_valid) begin
                storage[wr_ptr] <= relu_outputs_all;
                $display("[T=%0t] Buffering row %0d: %h", $time, wr_ptr, relu_outputs_all);
                wr_ptr <= wr_ptr + 1;

                if (wr_ptr == BIAS_FIFO_DEPTH - 1) begin
                    buffering_done   <= 1;
                    streaming_active <= 1;
                    rd_ptr           <= 0;
                    group_index      <= 0;
                    $display("[T=%0t] All rows buffered. Starting streaming phase.", $time);
                end
            end
        end
    end

    // === Streaming Logic ===
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            relu_out_valid   <= 0;
            relu_out_data    <= 0;
            streaming_active <= 0;
            group_index      <= 0;
            rd_ptr           <= 0;
        end else begin
            relu_out_valid <= 0;

            if (streaming_active) begin
                current_row = storage[rd_ptr];
                $display("[T=%0t] LOAD_ROW: RD_PTR=%0d, Loaded Row = %h", $time, rd_ptr, current_row);

                // Default zero in case of partial group
                relu_out_data = 128'd0;

                if ((group_index * 4 + 3) < NUM_PUS) begin
                    relu_out_data = {
                        current_row[(group_index*4 + 3)*BIAS_WIDTH +: BIAS_WIDTH],
                        current_row[(group_index*4 + 2)*BIAS_WIDTH +: BIAS_WIDTH],
                        current_row[(group_index*4 + 1)*BIAS_WIDTH +: BIAS_WIDTH],
                        current_row[(group_index*4 + 0)*BIAS_WIDTH +: BIAS_WIDTH]
                    };
                end else begin
                    // Partial group handling
                    if ((group_index*4 + 0) < NUM_PUS)
                        relu_out_data[31:0]   = current_row[(group_index*4 + 0)*BIAS_WIDTH +: BIAS_WIDTH];
                    if ((group_index*4 + 1) < NUM_PUS)
                        relu_out_data[63:32]  = current_row[(group_index*4 + 1)*BIAS_WIDTH +: BIAS_WIDTH];
                    if ((group_index*4 + 2) < NUM_PUS)
                        relu_out_data[95:64]  = current_row[(group_index*4 + 2)*BIAS_WIDTH +: BIAS_WIDTH];
                    if ((group_index*4 + 3) < NUM_PUS)
                        relu_out_data[127:96] = current_row[(group_index*4 + 3)*BIAS_WIDTH +: BIAS_WIDTH];
                end

                relu_out_valid <= 1;

                $display("[T=%0t] RD_PTR=%0d, GROUP_INDEX=%0d, Packed ReLU => { %0d, %0d, %0d, %0d }", 
                    $time, rd_ptr, group_index,
                    $signed(relu_out_data[127:96]),
                    $signed(relu_out_data[95:64]),
                    $signed(relu_out_data[63:32]),
                    $signed(relu_out_data[31:0])
                );

                // Advance pointers
                if (group_index == NUM_GROUPS - 1) begin
                    group_index <= 0;
                    if (rd_ptr == BIAS_FIFO_DEPTH - 1) begin
                        streaming_active <= 0;
                    end else begin
                        rd_ptr <= rd_ptr + 1;
                    end
                end else begin
                    group_index <= group_index + 1;
                end
            end
        end
    end

endmodule
