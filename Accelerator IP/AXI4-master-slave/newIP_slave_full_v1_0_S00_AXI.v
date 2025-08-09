`timescale 1 ns / 1 ps

module newIP_slave_full_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_ID_WIDTH = 12,
    parameter integer C_S_AXI_DATA_WIDTH = 128,
    parameter integer C_S_AXI_ADDR_WIDTH = 64,
    parameter integer C_S_AXI_AWUSER_WIDTH = 0,
    parameter integer C_S_AXI_ARUSER_WIDTH = 0,
    parameter integer C_S_AXI_WUSER_WIDTH = 0,
    parameter integer C_S_AXI_RUSER_WIDTH = 0,
    parameter integer C_S_AXI_BUSER_WIDTH = 0
)
(
    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,

    input wire [C_S_AXI_ID_WIDTH-1:0]     S_AXI_AWID,
    input wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input wire [7:0]                      S_AXI_AWLEN,
    input wire [2:0]                      S_AXI_AWSIZE,
    input wire [1:0]                      S_AXI_AWBURST,
    input wire                            S_AXI_AWLOCK,
    input wire [3:0]                      S_AXI_AWCACHE,
    input wire [2:0]                      S_AXI_AWPROT,
    input wire [3:0]                      S_AXI_AWQOS,
    input wire [3:0]                      S_AXI_AWREGION,
    input wire [C_S_AXI_AWUSER_WIDTH-1:0] S_AXI_AWUSER,
    input wire                            S_AXI_AWVALID,
    output wire                           S_AXI_AWREADY,

    input wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire                            S_AXI_WLAST,
    input wire [C_S_AXI_WUSER_WIDTH-1:0]  S_AXI_WUSER,
    input wire                            S_AXI_WVALID,
    output wire                           S_AXI_WREADY,

    output reg [C_S_AXI_ID_WIDTH-1:0]     S_AXI_BID,
    output reg [1:0]                      S_AXI_BRESP,
    output reg [C_S_AXI_BUSER_WIDTH-1:0]  S_AXI_BUSER,
    output reg                            S_AXI_BVALID,
    input wire                            S_AXI_BREADY,

    input wire [C_S_AXI_ID_WIDTH-1:0]     S_AXI_ARID,
    input wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input wire [7:0]                      S_AXI_ARLEN,
    input wire [2:0]                      S_AXI_ARSIZE,
    input wire [1:0]                      S_AXI_ARBURST,
    input wire                            S_AXI_ARLOCK,
    input wire [3:0]                      S_AXI_ARCACHE,
    input wire [2:0]                      S_AXI_ARPROT,
    input wire [3:0]                      S_AXI_ARQOS,
    input wire [3:0]                      S_AXI_ARREGION,
    input wire [C_S_AXI_ARUSER_WIDTH-1:0] S_AXI_ARUSER,
    input wire                            S_AXI_ARVALID,
    output wire                           S_AXI_ARREADY,

    output reg [C_S_AXI_ID_WIDTH-1:0]     S_AXI_RID,
    output reg [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg [1:0]                      S_AXI_RRESP,
    output reg                            S_AXI_RLAST,
    output reg [C_S_AXI_RUSER_WIDTH-1:0]  S_AXI_RUSER,
    output reg                            S_AXI_RVALID,
    input wire                            S_AXI_RREADY,

    output wire [C_S_AXI_ADDR_WIDTH-1:0]  input_Addr_Offset,
    output wire [C_S_AXI_ADDR_WIDTH-1:0]  output_Addr_Offset,
    output wire                           INIT_AXI_TXN,
    input wire                            TXN_DONE,
    input wire                            ERROR
);

// =====================================
// Internal Register Declarations
// =====================================
reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_reg;
reg                          awaddr_valid;
reg [C_S_AXI_DATA_WIDTH-1:0] wdata_reg;
reg                          wdata_valid;

// Pulse generator for INIT_AXI_TXN
reg start_operation;
reg start_d;
assign INIT_AXI_TXN = start_operation & ~start_d;

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        start_d <= 1'b0;
    else
        start_d <= start_operation;
end

// Simple register-backed addressable memory
reg [C_S_AXI_DATA_WIDTH-1:0] memory_array [0:255];

// FSM state declarations
localparam [1:0] W_IDLE = 2'b00, W_WAIT = 2'b01, W_RESP = 2'b10;
reg [1:0] state_write;

// AW/W handshake
assign S_AXI_AWREADY = !awaddr_valid;
assign S_AXI_WREADY  = !wdata_valid;

// ==========================================
// Write FSM and Memory Backend
// ==========================================

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        awaddr_valid <= 1'b0;
        awaddr_reg   <= 0;
        wdata_valid  <= 1'b0;
        wdata_reg    <= 0;
        S_AXI_BVALID <= 0;
        state_write  <= W_IDLE;
    end else begin
        // Capture AWADDR
        if (S_AXI_AWVALID && S_AXI_AWREADY) begin
            awaddr_reg   <= S_AXI_AWADDR;
            awaddr_valid <= 1'b1;
        end

        // Capture WDATA
        if (S_AXI_WVALID && S_AXI_WREADY) begin
            wdata_reg   <= S_AXI_WDATA;
            wdata_valid <= 1'b1;
        end

        case (state_write)
            W_IDLE: begin
                if (awaddr_valid && wdata_valid) begin
                    // Commit write
                    memory_array[awaddr_reg[9:2]] <= wdata_reg;

                    // Response
                    S_AXI_BVALID <= 1;
                    S_AXI_BRESP  <= 2'b00; // OKAY
                    state_write  <= W_RESP;

                    // Clear flags
                    awaddr_valid <= 0;
                    wdata_valid  <= 0;
                end
            end

            W_RESP: begin
                if (S_AXI_BVALID && S_AXI_BREADY) begin
                    S_AXI_BVALID <= 0;
                    state_write  <= W_IDLE;
                end
            end
        endcase
    end
end

// ==========================================
// AXI Read Channel Logic
// ==========================================

assign S_AXI_ARREADY = 1'b1; // always ready to accept ARADDR

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        S_AXI_RVALID <= 0;
        S_AXI_RRESP  <= 2'b00;
        S_AXI_RLAST  <= 1;
    end else begin
        if (S_AXI_ARVALID && S_AXI_ARREADY) begin
            S_AXI_RDATA <= memory_array[S_AXI_ARADDR[9:2]];
            S_AXI_RRESP <= 2'b00; // OKAY
            S_AXI_RVALID <= 1;
            S_AXI_RLAST  <= 1;
        end else if (S_AXI_RVALID && S_AXI_RREADY) begin
            S_AXI_RVALID <= 0;
        end
    end
end

// ==========================================
// Simple Register-Mapped Configuration Registers
// ==========================================

// Use address decoding if you want special registers mapped in future
// For now, assume memory_array holds input/output addr offsets too

assign input_Addr_Offset  = memory_array[0]; // at address 0x00
assign output_Addr_Offset = memory_array[1]; // at address 0x10

// Start trigger
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
        start_operation <= 0;
    else if (S_AXI_WVALID && S_AXI_WREADY && awaddr_reg[9:2] == 2) // address 0x20
        start_operation <= 1'b1;
    else if (TXN_DONE)
        start_operation <= 1'b0;
end

endmodule
