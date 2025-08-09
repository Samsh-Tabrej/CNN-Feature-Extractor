`timescale 1ns / 1ps

module ScatterSimple #(
    parameter NUM_PUS         = 64,
    parameter NUM_CHANNELS    = 3,
    parameter ADDR_WIDTH      = 8,
    parameter IMG_ADDR_WIDTH  = 12,
    parameter DATA_WIDTH      = 8,
    parameter WEIGHT_WIDTH    = 16,
    parameter BIAS_WIDTH      = 32,
    parameter IMG_SIZE        = 10
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          valid,
    input  wire [127:0]                  data,
    output wire                          ready,

    output reg                           image_preload_en,
    output reg [DATA_WIDTH-1:0]          image_preload_pixel,
    output reg [IMG_ADDR_WIDTH-1:0]      image_preload_addr,

    output reg [NUM_PUS-1:0]             bias_preload_en,
    output reg [NUM_PUS*ADDR_WIDTH-1:0]  bias_addr,
    output reg [NUM_PUS*BIAS_WIDTH-1:0]  bias_data,

    output reg [NUM_PUS-1:0]             weight_preload_en,
    output reg [NUM_PUS*ADDR_WIDTH-1:0]  weight_addr_pe0,
    output reg [NUM_PUS*ADDR_WIDTH-1:0]  weight_addr_pe1,
    output reg [NUM_PUS*ADDR_WIDTH-1:0]  weight_addr_pe2,
    output reg [NUM_PUS*WEIGHT_WIDTH-1:0] weight_data_pe0,
    output reg [NUM_PUS*WEIGHT_WIDTH-1:0] weight_data_pe1,
    output reg [NUM_PUS*WEIGHT_WIDTH-1:0] weight_data_pe2,
    output reg [NUM_PUS*8-1:0]            filter_id,
    output reg [NUM_PUS*8-1:0]            channel_id,

    output reg                           clear,
    output reg                           image_preload_done,
    output reg [NUM_PUS-1:0]             bias_preload_done,
    output reg [NUM_PUS-1:0]             load_weight_row,
    output reg                           start_conv,
    output reg                           next_pixel,
    output reg                           channel_ready,
    output wire                          conv_done  // 1-cycle pulse
);

    assign ready = 1'b1;

    // Packet field extraction
    wire [1:0]  pkt_type         = data[127:126];
    wire [5:0]  pu_id            = data[125:120];
    wire [7:0]  filter_id_wt     = data[119:112];
    wire [7:0]  channel_id_wt    = data[111:104];
    wire [7:0]  bias_addr_field  = data[103:96];
    wire [31:0] bias_data_field  = data[95:64];
    wire [7:0]  image_addr_field = data[103:96];
    wire [7:0]  image_pixel_field= data[95:88];

    wire [7:0]  addr_pe0         = data[103:96];
    wire [15:0] data_pe0         = data[95:80];
    wire [7:0]  addr_pe1         = data[79:72];
    wire [15:0] data_pe1         = data[71:56];
    wire [7:0]  addr_pe2         = data[55:48];
    wire [15:0] data_pe2         = data[47:32];

    // FSM state
    reg [3:0] state;
    localparam IDLE             = 0,
               WAIT_IMAGE       = 1,
               WAIT_LAST_PIXEL  = 2,
               IMAGE_DONE       = 3,
               BIAS_DONE        = 4,
               LOAD_WEIGHT_ROW  = 5,
               WAIT_START_CONV  = 6,
               START_CONV       = 7,
               NEXT_PIXEL       = 8,
               DONE_CHANNEL     = 9,
               DONE_ALL         = 10;

    reg [7:0] ch;
    reg [15:0] pixel_count;
    reg [15:0] conv_counter;

    localparam TOTAL_PIXELS = IMG_SIZE * IMG_SIZE;
    localparam CONV_LATENCY = IMG_SIZE * (IMG_SIZE - 2) * 3;

    // conv_done as 1-cycle pulse
    reg final_conv_done, conv_done_reg, conv_done_next;
    assign conv_done = final_conv_done;
                   //= conv_done_reg;

    // Per-channel ID latches
    reg [7:0] filter_id_latch [NUM_PUS-1:0];
    reg [7:0] channel_id_latch[NUM_PUS-1:0];

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset logic
            image_preload_en    <= 0;
            image_preload_pixel <= 0;
            image_preload_addr  <= 0;
            bias_addr           <= 0;
            bias_data           <= 0;
            weight_addr_pe0     <= 0;
            weight_data_pe0     <= 0;
            weight_addr_pe1     <= 0;
            weight_data_pe1     <= 0;
            weight_addr_pe2     <= 0;
            weight_data_pe2     <= 0;
            filter_id           <= 0;
            channel_id          <= 0;

            for (i = 0; i < NUM_PUS; i = i + 1) begin
                bias_preload_en[i]    <= 0;
                weight_preload_en[i]  <= 0;
                filter_id_latch[i]    <= 0;
                channel_id_latch[i]   <= 0;
            end

            image_preload_done <= 0;
            bias_preload_done  <= 0;
            load_weight_row    <= 0;
            start_conv         <= 0;
            next_pixel         <= 0;
            clear              <= 0;
            channel_ready      <= 0;
final_conv_done<=0;
            conv_done_reg      <= 0;
            conv_done_next     <= 0;
            pixel_count        <= 0;
            conv_counter       <= 0;
            ch                 <= 0;
            state              <= IDLE;
        end else begin
            // Clear single-cycle signals
            bias_preload_en   <= 0;
            bias_preload_done <= 0;
            weight_preload_en <= 0;
            load_weight_row   <= 0;
            start_conv        <= 0;
            channel_ready     <= 0;
            conv_done_next    <= 0;

            case (state)
                IDLE: begin
                    clear <= 1;
                    conv_done_next <= 0;
                    channel_ready  <= 0;
                    state <= WAIT_IMAGE;
                    $display("[T=%0t] State=IDLE → WAIT_IMAGE (ch=%0d)", $time, ch);
                end

                WAIT_IMAGE: begin
                    clear <= 0;
                    channel_ready <= 1;
                    if (valid && pkt_type == 2'b00 && channel_id_wt == ch) begin
                        image_preload_en    <= 1;
                        channel_ready       <= 0;
                        image_preload_addr  <= image_addr_field;
                        image_preload_pixel <= image_pixel_field;
                        pixel_count <= pixel_count + 1;

                        $display("[T=%0t] [WAIT_IMAGE] ch=%0d Addr=%0d Pixel=%0d",
                                 $time, ch, image_addr_field, image_pixel_field);

                        if (pixel_count == TOTAL_PIXELS - 1)
                            state <= WAIT_LAST_PIXEL;
                    end
                end

                WAIT_LAST_PIXEL: begin
                    image_preload_en   <= 0;
                    image_preload_done <= 1;
                    pixel_count        <= 0;
                    $display("[T=%0t] [WAIT_LAST_PIXEL] Image preload done for ch=%0d", $time, ch);
                    state <= IMAGE_DONE;
                end

                IMAGE_DONE: begin
                    bias_preload_done <= {NUM_PUS{1'b1}};
                    $display("[T=%0t] State=IMAGE_DONE → BIAS_DONE", $time);
                    state <= BIAS_DONE;
                end

                BIAS_DONE: begin
                    bias_preload_done <= 0;
                    load_weight_row   <= {NUM_PUS{1'b1}};
                    state <= LOAD_WEIGHT_ROW;

                    for (i = 0; i < NUM_PUS; i = i + 1) begin
                        filter_id[i*8 +: 8]  <= filter_id_latch[i];
                        channel_id[i*8 +: 8] <= channel_id_latch[i];
                    end
                    $display("[T=%0t] State=BIAS_DONE → LOAD_WEIGHT_ROW", $time);
                end

                LOAD_WEIGHT_ROW: begin
                    load_weight_row <= 0;
                    conv_counter <= 0;
                    state <= WAIT_START_CONV;
                    $display("[T=%0t] State=LOAD_WEIGHT_ROW → WAIT_START_CONV", $time);
                end

                WAIT_START_CONV: begin
                    conv_counter <= conv_counter + 1;
                    if (conv_counter == 2) begin
                        conv_counter <= 0;
                        start_conv <= 1;
                        state <= START_CONV;
                        $display("[T=%0t] Starting Convolution for ch=%0d", $time, ch);
                    end
                end

                START_CONV: begin
                    start_conv   <= 0;
                    next_pixel   <= 1;
                    conv_counter <= 1;
                    state        <= NEXT_PIXEL;
                end

                NEXT_PIXEL: begin
                    conv_counter <= conv_counter + 1;
                    if (conv_counter == CONV_LATENCY) begin
                        next_pixel <= 0;
                        image_preload_done <= 0;
                        state <= DONE_CHANNEL;
                        $display("[T=%0t] Finished Convolution for ch=%0d", $time, ch);
                    end
                end

                DONE_CHANNEL: begin
                    ch <= ch + 1;
                    if (ch == NUM_CHANNELS - 1)
                        state <= DONE_ALL;
                    else
                        state <= IDLE;
                end

                DONE_ALL: begin
                    clear <= 0;
                    conv_done_next <= 1; // 1-cycle pulse
                    ch <= 0;
                end
            endcase

            // === Packet processing ===
            if (valid) begin
                case (pkt_type)
                    2'b01: begin // BIAS
                        bias_preload_en[pu_id] <= 1;
                        bias_addr[pu_id*ADDR_WIDTH +: ADDR_WIDTH] <= bias_addr_field;
                        bias_data[pu_id*BIAS_WIDTH +: BIAS_WIDTH] <= bias_data_field;
                        $display("[T=%0t] BIAS: PU%0d Addr=%0d Data=%0d",
                                 $time, pu_id, bias_addr_field, bias_data_field);
                    end

                    2'b10: begin // WEIGHT
                        weight_preload_en[pu_id] <= 1;
                        weight_addr_pe0[pu_id*ADDR_WIDTH +: ADDR_WIDTH]     <= addr_pe0;
                        weight_data_pe0[pu_id*WEIGHT_WIDTH +: WEIGHT_WIDTH] <= data_pe0;
                        weight_addr_pe1[pu_id*ADDR_WIDTH +: ADDR_WIDTH]     <= addr_pe1;
                        weight_data_pe1[pu_id*WEIGHT_WIDTH +: WEIGHT_WIDTH] <= data_pe1;
                        weight_addr_pe2[pu_id*ADDR_WIDTH +: ADDR_WIDTH]     <= addr_pe2;
                        weight_data_pe2[pu_id*WEIGHT_WIDTH +: WEIGHT_WIDTH] <= data_pe2;

                        filter_id_latch[pu_id]  <= filter_id_wt;
                        channel_id_latch[pu_id] <= channel_id_wt;

                        $display("[T=%0t] WEIGHT: PU%0d CH=%0d FID=%0d",
                                 $time, pu_id, channel_id_wt, filter_id_wt);
                    end
                endcase
            end

            // Update conv_done register
            conv_done_reg <= conv_done_next;
            final_conv_done <= conv_done_reg;
        end
    end
endmodule