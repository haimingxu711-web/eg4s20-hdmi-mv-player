// =====================================================================
// 演唱小人图层（右下角 Q 版茂茂）：64x64 像素画放大 2 倍显示（128x128）
//   精灵 4 帧（gen_avatar.py 生成）：0 闭嘴  1 小张嘴  2 大张嘴  3 眨眼
//   嘴型跟随主旋律包络（env）：唱歌词时 env 高 → 大张嘴，中 → 小张嘴，休止 → 闭嘴
//   每个新音符起头时往下“点头”几个像素再弹回；约每 3.5 秒眨一次眼
//   每帧消隐期锁存一次状态，画面不撕裂；调色板索引 0 = 透明
// 延迟 3 拍（精灵 ROM 1 拍 + 调色板 ROM 1 拍 + 输出 1 拍）
// =====================================================================
`include "vid_defs.vh"
`include "avatar_cfg.vh"

module fx_avatar #(
    parameter [9:0]  X0       = 10'd512,       // 左上角
    parameter [9:0]  Y0       = 10'd266,
    parameter [15:0] ENV_WIDE = 16'hB000,      // 包络高于此值：大张嘴
    parameter [15:0] ENV_OPEN = 16'h2800       // 包络高于此值：小张嘴
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,
    input  wire           sing,               // 正在唱歌词（前奏/歌名时不张嘴）
    input  wire [15:0]    env,                // 主旋律包络
    input  wire           note_on,            // 新音符起头（单拍）
    input  wire [`VB-1:0] vi,
    output reg  [`VB-1:0] vo
);

// ---------------- 每帧更新动画状态 ----------------
reg vs_d;
always @(posedge clk) vs_d <= `VS(vi);
wire fstart = vs_d & ~`VS(vi);

reg       note_hit;                           // 本帧内来过新音符
reg [1:0] frame_id;
reg [1:0] bob;                                // 下沉像素（x2 显示）
reg [2:0] bob_t;
reg [7:0] blink_t;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        note_hit <= 1'b0; frame_id <= 2'd0; bob <= 2'd0; bob_t <= 3'd0; blink_t <= 8'd0;
    end else begin
        if (note_on && sing) note_hit <= 1'b1;
        if (fstart) begin
            note_hit <= 1'b0;
            blink_t  <= (blink_t == 8'd209) ? 8'd0 : blink_t + 8'd1;     // 210 帧一个周期
            // 点头：新音符 → 下沉 2，之后每 3 帧回升 1
            if (note_hit) begin bob <= 2'd2; bob_t <= 3'd0; end
            else if (bob != 2'd0) begin
                if (bob_t == 3'd2) begin bob_t <= 3'd0; bob <= bob - 2'd1; end
                else bob_t <= bob_t + 3'd1;
            end
            // 嘴型 / 眨眼
            if (sing && env > ENV_WIDE)      frame_id <= 2'd2;
            else if (sing && env > ENV_OPEN) frame_id <= 2'd1;
            else if (blink_t >= 8'd202)      frame_id <= 2'd3;          // 最后 8 帧闭眼
            else                             frame_id <= 2'd0;
        end
    end
end

// ---------------- 第 0 拍：定位，查精灵 ----------------
wire [9:0]  x  = `X(vi);
wire [9:0]  y  = `Y(vi);
wire [9:0]  ty = Y0 + {7'd0, bob, 1'b0};      // 下沉量放大 2 倍
wire        inb = en && `DE(vi) && (x >= X0) && (x < X0 + 10'd128) && (y >= ty) && (y < ty + 10'd128);
wire [9:0]  lx = x - X0;
wire [9:0]  ly = y - ty;
wire [13:0] addr = {frame_id, ly[6:1], lx[6:1]};
wire [3:0]  ci;
rom_sp #(.W(4), .AW(14), .DEPTH(16384), .MIF(`AV_AVATAR_MIF), .HEX(`AV_AVATAR_HEX)) u_spr(
    .clk(clk), .addr(addr), .q(ci));

reg [`VB-1:0] v1;
reg           in1;
always @(posedge clk) begin v1 <= vi; in1 <= inb; end

// ---------------- 第 1 拍：查调色板 ----------------
wire [23:0] pc;
rom_sp #(.W(24), .AW(4), .DEPTH(16), .MIF(`AV_AVATAR_PAL_MIF), .HEX(`AV_AVATAR_PAL_HEX)) u_pal(
    .clk(clk), .addr(ci), .q(pc));

reg [`VB-1:0] v2;
reg           in2, op2;
always @(posedge clk) begin v2 <= v1; in2 <= in1; op2 <= (ci != 4'd0); end

// ===================== 用户代码区：合成 =====================
wire [23:0] rgb_new = op2 ? pc : `RGB(v2);
// ===========================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (in2 && `DE(v2)) ? `VSET_RGB(v2, rgb_new) : v2;
end

endmodule
