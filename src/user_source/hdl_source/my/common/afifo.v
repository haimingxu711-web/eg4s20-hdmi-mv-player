// =====================================================================
// 通用异步 FIFO（跨时钟域，格雷码指针）
//   WIDTH/AW：数据位宽、深度 = 2^AW
//   rd_data 在 rd_en 后一拍有效（标准模式）
//   aclr：异步清空（两侧各自同步释放）
//   wr_used / rd_used：写侧/读侧看到的占用数（保守估计，比实际滞后 1~3 拍）
// =====================================================================
module afifo #(
    parameter WIDTH = 32,
    parameter AW    = 10
)(
    input  wire             aclr,
    input  wire             wr_clk,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire             full,
    output reg  [AW:0]      wr_used,
    input  wire             rd_clk,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] rd_data,
    output wire             empty,
    output reg  [AW:0]      rd_used
);

reg [WIDTH-1:0] mem [0:(1<<AW)-1];
reg [AW:0]      wbin, wgray;        // 写指针（二进制/格雷码）
reg [AW:0]      rbin, rgray;        // 读指针

// ---- 复位同步 ----
reg [1:0] wrst_s, rrst_s;
always @(posedge wr_clk or posedge aclr) if (aclr) wrst_s <= 2'b11; else wrst_s <= {wrst_s[0], 1'b0};
always @(posedge rd_clk or posedge aclr) if (aclr) rrst_s <= 2'b11; else rrst_s <= {rrst_s[0], 1'b0};
wire wrst = wrst_s[1];
wire rrst = rrst_s[1];

function [AW:0] b2g(input [AW:0] b); b2g = b ^ (b >> 1); endfunction
function [AW:0] g2b(input [AW:0] g);
    integer i;
    begin
        g2b[AW] = g[AW];
        for (i = AW - 1; i >= 0; i = i - 1) g2b[i] = g2b[i+1] ^ g[i];
    end
endfunction

// ---- 写侧 ----
reg  [AW:0] rgray_w1, rgray_w2;
reg  [AW:0] rbin_w;                 // 格雷→二进制单独打一拍（时序），只会让 full 更保守
assign full = (wbin - rbin_w) == (1 << AW);
wire do_wr = wr_en && !full;

always @(posedge wr_clk) if (do_wr) mem[wbin[AW-1:0]] <= wr_data;

always @(posedge wr_clk or posedge wrst) begin
    if (wrst) begin
        wbin <= 0; wgray <= 0; rgray_w1 <= 0; rgray_w2 <= 0; rbin_w <= 0; wr_used <= 0;
    end else begin
        rgray_w1 <= rgray; rgray_w2 <= rgray_w1; rbin_w <= g2b(rgray_w2);
        if (do_wr) begin
            wbin  <= wbin + 1'b1;
            wgray <= b2g(wbin + 1'b1);
        end
        wr_used <= wbin - rbin_w;           // 只用寄存器相减（时序），比实际值最多滞后一拍
    end
end

// ---- 读侧 ----
reg  [AW:0] wgray_r1, wgray_r2;
reg  [AW:0] wbin_r;                 // 同上，只会让 empty 更保守
assign empty = (rbin == wbin_r);
wire do_rd = rd_en && !empty;

always @(posedge rd_clk) if (do_rd) rd_data <= mem[rbin[AW-1:0]];

always @(posedge rd_clk or posedge rrst) begin
    if (rrst) begin
        rbin <= 0; rgray <= 0; wgray_r1 <= 0; wgray_r2 <= 0; wbin_r <= 0; rd_used <= 0;
    end else begin
        wgray_r1 <= wgray; wgray_r2 <= wgray_r1; wbin_r <= g2b(wgray_r2);
        if (do_rd) begin
            rbin  <= rbin + 1'b1;
            rgray <= b2g(rbin + 1'b1);
        end
        rd_used <= wbin_r - rbin;           // 同上
    end
end

endmodule
