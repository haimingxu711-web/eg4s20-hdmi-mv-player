// =====================================================================
// 帧源（video_clk 域）：把 mem_ctrl 的两路读流变回像素流
//   每帧在消隐期向 mem_ctrl 发请求（翻转 req_tgl），槽号 slot_a / slot_b 在此刻锁存
//   主输出 vo.rgb = A 路像素；B 路像素同拍从 rgb_b 输出（转场效果用）
//   相对输入延迟 1 拍（FIFO 读出延迟）
// =====================================================================
`include "vid_defs.vh"

module vid_frame_src(
    input  wire           clk,
    input  wire           rst,
    input  wire [`VB-1:0] vi,              // 来自 vid_timing
    input  wire           frame_start,     // 来自 vid_timing（场同步开始，消隐期）
    input  wire [1:0]     slot_a,
    input  wire [1:0]     slot_b,
    // ---- 接 mem_ctrl ----
    output reg            a_req_tgl,
    output reg  [1:0]     a_slot,
    output wire           a_rd,
    input  wire [23:0]    a_rgb,
    output reg            b_req_tgl,
    output reg  [1:0]     b_slot,
    output wire           b_rd,
    input  wire [23:0]    b_rgb,
    // ---- 输出 ----
    output wire [`VB-1:0] vo,
    output wire [23:0]    rgb_b,
    output reg  [1:0]     cur_slot_a,      // 本帧实际显示的槽（与画面对齐）
    output reg  [1:0]     cur_slot_b
);

assign a_rd  = `DE(vi);
assign b_rd  = `DE(vi);

reg [2:0]     fs_d;
reg [`VB-1:0] vi_d;                        // 与 FIFO 读出数据对齐的像素流

// t 拍发出读，t+1 拍 FIFO 给出该像素，因此与延迟一拍的 vi_d 拼接
assign vo    = `DE(vi_d) ? `VSET_RGB(vi_d, a_rgb) : vi_d;
assign rgb_b = b_rgb;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        a_req_tgl <= 1'b0; b_req_tgl <= 1'b0; a_slot <= 2'd0; b_slot <= 2'd0;
        fs_d <= 3'd0; vi_d <= {1'b1, 1'b1, 45'd0}; cur_slot_a <= 2'd0; cur_slot_b <= 2'd0;
    end else begin
        fs_d <= {fs_d[1:0], frame_start};
        vi_d <= vi;
        // frame_start 后一拍采槽号（上游控制器在 frame_start 当拍更新），再隔 2 拍翻转请求
        if (fs_d[0]) begin a_slot <= slot_a; b_slot <= slot_b; end
        if (fs_d[2]) begin
            a_req_tgl  <= ~a_req_tgl;  b_req_tgl  <= ~b_req_tgl;
            cur_slot_a <= a_slot;      cur_slot_b <= b_slot;
        end
    end
end

endmodule
