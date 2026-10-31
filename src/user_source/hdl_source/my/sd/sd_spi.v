// =====================================================================
// SPI 字节收发引擎（模式 0：SCLK 空闲低，上升沿采样，下降沿出数）
//   half_div : SCLK 半周期 = half_div 个系统时钟（≥1）
//   start    : 发起一次 8 位收发（busy=0 时有效）
//   done     : 收发完成单拍脉冲，rx 有效
// =====================================================================
module sd_spi(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] half_div,
    input  wire       start,
    input  wire [7:0] tx,
    output reg        busy,
    output reg        done,
    output reg  [7:0] rx,
    output reg        sclk,
    output wire       mosi,
    input  wire       miso
);

reg [7:0] sh_tx;
reg [7:0] div_cnt;
reg [3:0] edge_cnt;          // 16 个沿 = 8 位

assign mosi = sh_tx[7];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        busy <= 1'b0; done <= 1'b0; rx <= 8'hFF;
        sclk <= 1'b0; sh_tx <= 8'hFF; div_cnt <= 8'd0; edge_cnt <= 4'd0;
    end else begin
        done <= 1'b0;
        if (!busy) begin
            sclk <= 1'b0;
            if (start) begin
                busy     <= 1'b1;
                sh_tx    <= tx;
                div_cnt  <= 8'd0;
                edge_cnt <= 4'd0;
            end
        end else if (div_cnt == half_div - 1) begin
            div_cnt <= 8'd0;
            sclk    <= ~sclk;
            // MISO 在下降沿（卡移出新位之前的一刻）采样：
            //   25MHz 时上升沿采样只离上一个下降沿 20ns，而卡输出延迟最大 14ns + 引脚/走线约 8ns，余量为负，
            //   会偶发采错一位（图片出现固定位置的亮色噪点）；改到下降沿后有 ~40ns 建立时间，
            //   卡在看到这个下降沿之后才换数据，保持时间由 SCLK 输出延迟保证
            if (sclk) begin                     // 下降沿：采样当前位，再移出下一位
                rx    <= {rx[6:0], miso};
                sh_tx <= {sh_tx[6:0], 1'b1};
            end
            edge_cnt <= edge_cnt + 4'd1;
            if (edge_cnt == 4'd15) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end else
            div_cnt <= div_cnt + 8'd1;
    end
end

endmodule
