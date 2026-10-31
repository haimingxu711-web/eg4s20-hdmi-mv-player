// =====================================================================
// SD 卡控制器（SPI 模式）：上电初始化 + 单扇区读
//   支持 SDv1(SDSC，字节寻址) / SDv2 SDSC / SDHC/SDXC（块寻址），用 CMD58 判断
//   初始化：≥74 个时钟 → CMD0 → CMD8 → (CMD55+ACMD41)* → CMD58 → [CMD16]
//   读扇区：rd_req + rd_lba → 512 个 (byte, byte_valid) → rd_done（或 rd_err）
//   注意：板上 MISO 需在约束里开 PULLUP，否则部分卡初始化失败
// =====================================================================
module sd_card #(
    parameter [7:0]  SLOW_DIV    = 8'd125,       // 100MHz/250 = 400kHz
    parameter [7:0]  FAST_DIV    = 8'd2,         // 100MHz/4   = 25MHz
    parameter [23:0] ACMD41_MAX  = 24'd2000,     // ACMD41 最大重试次数（约 1s）
    parameter [23:0] TOKEN_MAX   = 24'd200000    // 等数据令牌的最大字节数
)(
    input  wire        clk,
    input  wire        rst,
    output reg         ready,          // 初始化完成
    output wire        idle,           // 处于就绪空闲，本拍可接收 rd_req
    output reg         init_err,       // 初始化失败（会自动重试）
    output reg  [3:0]  dbg_state,      // 调试：当前阶段（数码管显示用）
    input  wire        rd_req,
    input  wire [31:0] rd_lba,
    output reg  [7:0]  rd_byte,
    output reg         rd_byte_valid,
    output reg         rd_done,
    output reg         rd_err,
    output reg         sd_cs,
    output wire        sd_sclk,
    output wire        sd_mosi,
    input  wire        sd_miso
);

// ---------------- SPI 引擎 ----------------
reg  [7:0] half_div;
reg        spi_start;
reg  [7:0] spi_tx;
wire       spi_busy, spi_done;
wire [7:0] spi_rx;
sd_spi u_spi(
    .clk(clk), .rst(rst), .half_div(half_div), .start(spi_start), .tx(spi_tx),
    .busy(spi_busy), .done(spi_done), .rx(spi_rx),
    .sclk(sd_sclk), .mosi(sd_mosi), .miso(sd_miso)
);

// ---------------- 状态 ----------------
localparam S_RESET     = 5'd0,
           S_PWRUP     = 5'd1,   // CS 高，发 10 个 FF
           S_CMD0      = 5'd2,
           S_CMD8      = 5'd3,
           S_CMD55     = 5'd4,
           S_ACMD41    = 5'd5,
           S_CMD58     = 5'd6,
           S_CMD16     = 5'd7,
           S_READY     = 5'd8,
           S_CMD17     = 5'd9,
           S_TOKEN     = 5'd10,
           S_DATA      = 5'd11,
           S_CRC       = 5'd12,
           S_RD_END    = 5'd13,
           S_SEND      = 5'd16,  // 子程序：发 6 字节命令
           S_RESP      = 5'd17,  // 子程序：等 R1
           S_RESP_EXT  = 5'd18,  // 子程序：再读 4 字节（R3/R7）
           S_DESEL     = 5'd19,  // 子程序：拉高 CS + 8 个时钟
           S_ERR       = 5'd20;

reg [4:0]  state, ret_state;
assign idle = (state == S_READY);
reg [47:0] cmd_buf;
reg [2:0]  byte_idx;
reg [3:0]  poll_cnt;
reg [7:0]  r1;
reg [31:0] resp32;
reg        need_ext;
reg [23:0] tries;
reg [9:0]  data_cnt;
reg        v2, sdhc;

// SPI 单字节操作：xfer 发起，spi_done 时完成
reg xfer_pending;
task xfer(input [7:0] b);
    begin
        spi_tx       <= b;
        spi_start    <= 1'b1;
        xfer_pending <= 1'b1;
    end
endtask
wire xfer_ok = xfer_pending && spi_done;   // 本次字节完成

// 发命令：装载 cmd_buf 后跳到 S_SEND，最终回到 ret
task issue(input [5:0] idx, input [31:0] arg, input [7:0] crc, input ext, input [4:0] ret);
    begin
        cmd_buf   <= {2'b01, idx, arg, crc};
        need_ext  <= ext;
        byte_idx  <= 3'd0;
        ret_state <= ret;
        state     <= S_SEND;
    end
endtask

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_RESET; ret_state <= S_RESET;
        ready <= 1'b0; init_err <= 1'b0; dbg_state <= 4'd0;
        rd_byte <= 8'd0; rd_byte_valid <= 1'b0; rd_done <= 1'b0; rd_err <= 1'b0;
        sd_cs <= 1'b1; half_div <= SLOW_DIV; spi_start <= 1'b0; spi_tx <= 8'hFF;
        xfer_pending <= 1'b0; cmd_buf <= 48'd0; byte_idx <= 3'd0; poll_cnt <= 4'd0;
        r1 <= 8'hFF; resp32 <= 32'd0; need_ext <= 1'b0; tries <= 24'd0;
        data_cnt <= 10'd0; v2 <= 1'b0; sdhc <= 1'b0;
    end else begin
        spi_start     <= 1'b0;
        rd_byte_valid <= 1'b0;
        rd_done       <= 1'b0;
        rd_err        <= 1'b0;
        if (spi_done) xfer_pending <= 1'b0;

        case (state)
        // ------------------------------------------------ 初始化
        S_RESET: begin
            ready <= 1'b0; sd_cs <= 1'b1; half_div <= SLOW_DIV;
            dbg_state <= 4'd1; byte_idx <= 3'd0; tries <= 24'd0;
            state <= S_PWRUP;
        end
        S_PWRUP: begin                                   // 10 字节 FF = 80 个时钟
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                if (tries == 24'd9) begin tries <= 24'd0; state <= S_CMD0; end
                else tries <= tries + 24'd1;
            end
        end
        S_CMD0: begin
            dbg_state <= 4'd2;
            if (ret_state == S_CMD0 && r1 != 8'hFF) begin            // 从子程序返回
                ret_state <= S_RESET;
                if (r1 == 8'h01) state <= S_CMD8;
                else if (tries == 24'd200) state <= S_ERR;
                else begin tries <= tries + 24'd1; r1 <= 8'hFF; issue(6'd0, 32'h0, 8'h95, 1'b0, S_CMD0); end
            end else begin r1 <= 8'hFF; issue(6'd0, 32'h0, 8'h95, 1'b0, S_CMD0); end
        end
        S_CMD8: begin
            dbg_state <= 4'd3;
            if (ret_state == S_CMD8 && r1 != 8'hFF) begin
                ret_state <= S_RESET; tries <= 24'd0;
                v2 <= (r1 == 8'h01) && (resp32[7:0] == 8'hAA);
                state <= S_CMD55;
            end else begin r1 <= 8'hFF; issue(6'd8, 32'h000001AA, 8'h87, 1'b1, S_CMD8); end
        end
        S_CMD55: begin
            dbg_state <= 4'd4;
            if (ret_state == S_CMD55 && r1 != 8'hFF) begin
                ret_state <= S_RESET; state <= S_ACMD41;
            end else begin r1 <= 8'hFF; issue(6'd55, 32'h0, 8'h01, 1'b0, S_CMD55); end
        end
        S_ACMD41: begin
            dbg_state <= 4'd5;
            if (ret_state == S_ACMD41 && r1 != 8'hFF) begin
                ret_state <= S_RESET;
                if (r1 == 8'h00)
                    state <= v2 ? S_CMD58 : S_CMD16;
                else if (tries == ACMD41_MAX) state <= S_ERR;
                else begin tries <= tries + 24'd1; state <= S_CMD55; end
            end else begin r1 <= 8'hFF; issue(6'd41, v2 ? 32'h40000000 : 32'h0, 8'h01, 1'b0, S_ACMD41); end
        end
        S_CMD58: begin
            dbg_state <= 4'd6;
            if (ret_state == S_CMD58 && r1 != 8'hFF) begin
                ret_state <= S_RESET;
                sdhc  <= resp32[30];
                state <= resp32[30] ? S_READY : S_CMD16;
            end else begin r1 <= 8'hFF; issue(6'd58, 32'h0, 8'h01, 1'b1, S_CMD58); end
        end
        S_CMD16: begin
            dbg_state <= 4'd7;
            if (ret_state == S_CMD16 && r1 != 8'hFF) begin
                ret_state <= S_RESET; state <= S_READY;
            end else begin r1 <= 8'hFF; issue(6'd16, 32'd512, 8'h01, 1'b0, S_CMD16); end
        end
        S_ERR: begin                                    // 失败：标记后从头重试
            init_err <= 1'b1; dbg_state <= 4'hE;
            state <= S_RESET;
        end
        // ------------------------------------------------ 就绪 / 读扇区
        S_READY: begin
            ready <= 1'b1; init_err <= 1'b0; half_div <= FAST_DIV; dbg_state <= 4'd8;
            if (rd_req) begin
                r1 <= 8'hFF; ret_state <= S_CMD17;
                cmd_buf  <= {2'b01, 6'd17, (sdhc ? rd_lba : {rd_lba[22:0], 9'd0}), 8'h01};
                need_ext <= 1'b0; byte_idx <= 3'd0;
                state    <= S_SEND;
            end
        end
        S_CMD17: begin                                  // R1 已返回，CS 仍为低
            if (r1 == 8'h00) begin tries <= 24'd0; state <= S_TOKEN; end
            else begin rd_err <= 1'b1; state <= S_DESEL; ret_state <= S_READY; end
        end
        S_TOKEN: begin
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                if (spi_rx == 8'hFE) begin data_cnt <= 10'd0; state <= S_DATA; end
                else if (tries == TOKEN_MAX) begin rd_err <= 1'b1; ret_state <= S_READY; state <= S_DESEL; end
                else tries <= tries + 24'd1;
            end
        end
        S_DATA: begin
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                rd_byte <= spi_rx; rd_byte_valid <= 1'b1;
                if (data_cnt == 10'd511) begin data_cnt <= 10'd0; state <= S_CRC; end
                else data_cnt <= data_cnt + 10'd1;
            end
        end
        S_CRC: begin                                    // 丢弃 2 字节 CRC
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                if (data_cnt == 10'd1) begin rd_done <= 1'b1; ret_state <= S_READY; state <= S_DESEL; end
                else data_cnt <= data_cnt + 10'd1;
            end
        end
        // ------------------------------------------------ 子程序
        S_SEND: begin
            sd_cs <= 1'b0;
            if (!xfer_pending && !spi_busy) xfer(cmd_buf[47:40]);
            else if (xfer_ok) begin
                cmd_buf <= {cmd_buf[39:0], 8'hFF};
                if (byte_idx == 3'd5) begin byte_idx <= 3'd0; poll_cnt <= 4'd0; state <= S_RESP; end
                else byte_idx <= byte_idx + 3'd1;
            end
        end
        S_RESP: begin                                   // 最多轮询 10 字节等 R1（bit7=0）
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                if (!spi_rx[7]) begin
                    r1 <= spi_rx;
                    if (need_ext) begin byte_idx <= 3'd0; state <= S_RESP_EXT; end
                    else if (ret_state == S_CMD17) state <= S_CMD17;      // 读命令保持 CS 低
                    else state <= S_DESEL;
                end else if (poll_cnt == 4'd10) begin
                    r1 <= 8'hFE;                                           // 无应答：当作错误码
                    state <= S_DESEL;
                end else poll_cnt <= poll_cnt + 4'd1;
            end
        end
        S_RESP_EXT: begin
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) begin
                resp32 <= {resp32[23:0], spi_rx};
                if (byte_idx == 3'd3) state <= S_DESEL;
                else byte_idx <= byte_idx + 3'd1;
            end
        end
        S_DESEL: begin                                  // CS 拉高后再给 8 个时钟
            sd_cs <= 1'b1;
            if (!xfer_pending && !spi_busy) xfer(8'hFF);
            else if (xfer_ok) state <= ret_state;
        end
        default: state <= S_RESET;
        endcase
    end
end

endmodule
