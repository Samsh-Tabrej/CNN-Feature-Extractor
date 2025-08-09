`timescale 1 ns / 1 ps

module newIP_master_full_v1_0_M00_AXI #
(
    parameter   TOTAL_SCATTER = 768,
    parameter   TOTAL_RELU    = 192,

    parameter  C_M_TARGET_SLAVE_BASE_ADDR = 64'h0000000040000000,
    parameter integer C_M_AXI_BURST_LEN   = 1,
    parameter integer C_M_AXI_ID_WIDTH    = 12,
    parameter integer C_M_AXI_ADDR_WIDTH  = 64,
    parameter integer C_M_AXI_DATA_WIDTH  = 128,
    parameter integer C_M_AXI_AWUSER_WIDTH= 0,
    parameter integer C_M_AXI_ARUSER_WIDTH= 0,
    parameter integer C_M_AXI_WUSER_WIDTH = 0,
    parameter integer C_M_AXI_RUSER_WIDTH = 0,
    parameter integer C_M_AXI_BUSER_WIDTH = 0
)
(
    input wire [C_M_AXI_ADDR_WIDTH-1:0] input_Addr_Offset,
    input wire [C_M_AXI_ADDR_WIDTH-1:0] output_Addr_Offset,
    
    input  wire INIT_AXI_TXN,
    output wire TXN_DONE,
    output reg  ERROR,

    input  wire M_AXI_ACLK,
    input  wire M_AXI_ARESETN,

    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire       M_AXI_AWLOCK,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire [3:0] M_AXI_AWQOS,
    output wire [C_M_AXI_AWUSER_WIDTH-1:0] M_AXI_AWUSER,
    output wire       M_AXI_AWVALID,
    input  wire       M_AXI_AWREADY,

    output wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output wire       M_AXI_WLAST,
    output wire [C_M_AXI_WUSER_WIDTH-1:0] M_AXI_WUSER,
    output wire       M_AXI_WVALID,
    input  wire       M_AXI_WREADY,

    input  wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_BID,
    input  wire [1:0] M_AXI_BRESP,
    input  wire [C_M_AXI_BUSER_WIDTH-1:0] M_AXI_BUSER,
    input  wire       M_AXI_BVALID,
    output wire       M_AXI_BREADY,

    output wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,
    output wire [2:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output wire       M_AXI_ARLOCK,
    output wire [3:0] M_AXI_ARCACHE,
    output wire [2:0] M_AXI_ARPROT,
    output wire [3:0] M_AXI_ARQOS,
    output wire [C_M_AXI_ARUSER_WIDTH-1:0] M_AXI_ARUSER,
    output wire       M_AXI_ARVALID,
    input  wire       M_AXI_ARREADY,

    input  wire [C_M_AXI_ID_WIDTH-1:0] M_AXI_RID,
    input  wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0] M_AXI_RRESP,
    input  wire       M_AXI_RLAST,
    input  wire [C_M_AXI_RUSER_WIDTH-1:0] M_AXI_RUSER,
    input  wire       M_AXI_RVALID,
    output wire       M_AXI_RREADY
);

// ============================================
// Utility Functions
// ============================================
function integer clogb2 (input integer bit_depth);
begin
    for (clogb2=0; bit_depth>0; clogb2=clogb2+1)
        bit_depth = bit_depth >> 1;
end
endfunction

localparam integer C_TRANSACTIONS_NUM = clogb2(C_M_AXI_BURST_LEN - 1);
localparam integer C_MASTER_LENGTH    = 12;
localparam integer C_NO_BURSTS_REQ    = C_MASTER_LENGTH - clogb2((C_M_AXI_BURST_LEN * C_M_AXI_DATA_WIDTH / 8)-1);

// ============================================
// Accelerator FSM State Encoding
// ============================================
reg [2:0] accel_state;
localparam A_IDLE         = 3'd0,
           A_READ_SCATTER = 3'd1,
           A_SEND_SCATTER = 3'd2,
           A_WAIT_RELU    = 3'd3,
           A_WRITE_RELU   = 3'd4,
           A_DONE         = 3'd5;

// ============================================
// Internal Registers and Wires
// ============================================
reg [C_M_AXI_ADDR_WIDTH-1:0] axi_awaddr, axi_araddr;
reg [C_M_AXI_DATA_WIDTH-1:0] axi_wdata;
reg axi_awvalid, axi_wvalid, axi_wlast, axi_bready;
reg axi_arvalid, axi_rready;

reg [8:0] scatter_index;
reg [7:0] relu_index;
reg [127:0] scatter_data, relu_buffer;
reg scatter_valid, relu_valid_d;

assign M_AXI_AWID     = 0;
assign M_AXI_AWADDR   = C_M_TARGET_SLAVE_BASE_ADDR + output_Addr_Offset + axi_awaddr;
assign M_AXI_AWLEN    = C_M_AXI_BURST_LEN - 1;
assign M_AXI_AWSIZE   = clogb2((C_M_AXI_DATA_WIDTH / 8));
assign M_AXI_AWBURST  = 2'b01;
assign M_AXI_AWLOCK   = 0;
assign M_AXI_AWCACHE  = 4'b0010;
assign M_AXI_AWPROT   = 3'h0;
assign M_AXI_AWQOS    = 0;
assign M_AXI_AWUSER   = 0;
assign M_AXI_AWVALID  = axi_awvalid;

assign M_AXI_WDATA    = axi_wdata;
assign M_AXI_WSTRB    = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
assign M_AXI_WLAST    = axi_wlast;
assign M_AXI_WUSER    = 0;
assign M_AXI_WVALID   = axi_wvalid;

assign M_AXI_BREADY   = axi_bready;

assign M_AXI_ARID     = 0;
assign M_AXI_ARADDR   = C_M_TARGET_SLAVE_BASE_ADDR + input_Addr_Offset + axi_araddr;
assign M_AXI_ARLEN    = C_M_AXI_BURST_LEN - 1;
assign M_AXI_ARSIZE   = clogb2((C_M_AXI_DATA_WIDTH / 8));
assign M_AXI_ARBURST  = 2'b01;
assign M_AXI_ARLOCK   = 0;
assign M_AXI_ARCACHE  = 4'b0010;
assign M_AXI_ARPROT   = 3'h0;
assign M_AXI_ARQOS    = 0;
assign M_AXI_ARUSER   = 0;
assign M_AXI_ARVALID  = axi_arvalid;

assign M_AXI_RREADY   = axi_rready;

// ============================================
// INIT_AXI_TXN Pulse Generator
// ============================================
reg init_txn_ff, init_txn_ff2;
wire init_txn_pulse = (~init_txn_ff2) & init_txn_ff;

always @(posedge M_AXI_ACLK) begin
    if (!M_AXI_ARESETN) begin
        init_txn_ff  <= 0;
        init_txn_ff2 <= 0;
    end else begin
        init_txn_ff  <= INIT_AXI_TXN;
        init_txn_ff2 <= init_txn_ff;
    end
end

// ============================================
// Transaction Done Pulse
// ============================================
reg txn_done_pulse, txn_done_latched;
assign TXN_DONE = txn_done_pulse;

always @(posedge M_AXI_ACLK) begin
    if (!M_AXI_ARESETN) begin
        txn_done_pulse   <= 0;
        txn_done_latched <= 0;
    end else begin
        if (accel_state == A_DONE && !txn_done_latched) begin
            txn_done_pulse   <= 1;
            txn_done_latched <= 1;
        end else begin
            txn_done_pulse <= 0;
        end

        if (init_txn_pulse)
            txn_done_latched <= 0;
    end
end

// ============================================
// Error Detection
// ============================================
always @(posedge M_AXI_ACLK) begin
    if (!M_AXI_ARESETN)
        ERROR <= 0;
    else if ((M_AXI_BVALID && M_AXI_BRESP != 2'b00) || (M_AXI_RVALID && M_AXI_RRESP != 2'b00))
        ERROR <= 1;
end


// ============================================
// Accelerator Instance
// ============================================
Accelerator64 #(
    .NUM_PUS(16),
    .IMG_SIZE(10),
    .NUM_FILTERS(1),
    .NUM_CHANNELS(64)
) accelerator_inst (
    .clk(M_AXI_ACLK),
    .rst(~M_AXI_ARESETN),
    .scatter_valid(scatter_valid),
    .scatter_data(scatter_data),
    .channel_ready(channel_ready),
    .relu_out_data(relu_out_data),
    .relu_out_valid(relu_out_valid)
);

// ============================================
// FSM and AXI Control Logic
// ============================================
always @(posedge M_AXI_ACLK) begin
    if (!M_AXI_ARESETN) begin
        accel_state    <= A_IDLE;
        scatter_valid  <= 0;
        scatter_index  <= 0;
        relu_index     <= 0;
        relu_valid_d   <= 0;
        axi_arvalid    <= 0;
        axi_awvalid    <= 0;
        axi_wvalid     <= 0;
        axi_bready     <= 0;
        axi_wlast      <= 0;
        axi_rready     <= 0;
    end else begin
        // Defaults
        axi_arvalid    <= 0;
        axi_awvalid    <= 0;
        axi_wvalid     <= 0;
        axi_bready     <= 0;
        axi_wlast      <= 0;
        scatter_valid  <= 0;

        case (accel_state)

        A_IDLE: begin
            if (init_txn_pulse) begin
                scatter_index  <= 0;
                relu_index     <= 0;
                relu_valid_d   <= 0;
                accel_state    <= A_READ_SCATTER;
            end
        end

        A_READ_SCATTER: begin
            axi_araddr  <= scatter_index * 16;
            axi_arvalid <= 1;
            accel_state <= A_SEND_SCATTER;
        end

        A_SEND_SCATTER: begin
            if (M_AXI_ARREADY && axi_arvalid)
                axi_arvalid <= 0;

            if (M_AXI_RVALID) begin
                scatter_data  <= M_AXI_RDATA;
                scatter_valid <= 1;
            end

            if (scatter_valid && channel_ready) begin
                scatter_index <= scatter_index + 1;
                if (scatter_index == TOTAL_SCATTER - 1)
                    accel_state <= A_WAIT_RELU;
                else
                    accel_state <= A_READ_SCATTER;
            end
        end

        A_WAIT_RELU: begin
            if (relu_out_valid) begin
                relu_buffer   <= relu_out_data;
                relu_valid_d  <= 1;
                accel_state   <= A_WRITE_RELU;
            end
        end

        A_WRITE_RELU: begin
            if (relu_valid_d) begin
                axi_awaddr   <= relu_index * 16;
                axi_awvalid  <= 1;
                axi_wdata    <= relu_buffer;
                axi_wvalid   <= 1;
                axi_wlast    <= 1;
                axi_bready   <= 1;
                relu_valid_d <= 0;
            end

            if (M_AXI_AWREADY && axi_awvalid)
                axi_awvalid <= 0;
            if (M_AXI_WREADY && axi_wvalid)
                axi_wvalid  <= 0;

            if (M_AXI_BVALID && axi_bready) begin
                relu_index <= relu_index + 1;
                axi_bready <= 0;
                if (relu_index == TOTAL_RELU - 1)
                    accel_state <= A_DONE;
                else
                    accel_state <= A_WAIT_RELU;
            end
        end

        A_DONE: begin
            // Transaction is finished. Go back to IDLE.
            accel_state <= A_IDLE;
        end

        endcase
    end
end

// ============================================
// RREADY (Read Ready Logic)
// ============================================
always @(posedge M_AXI_ACLK) begin
    if (!M_AXI_ARESETN)
        axi_rready <= 0;
    else
        axi_rready <= (accel_state == A_SEND_SCATTER) && M_AXI_RVALID;
end

endmodule
