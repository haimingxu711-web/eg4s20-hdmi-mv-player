// =====================================================================
// SDRAM 访问调度（mem_clk 域，接厂商 SDRAM IP）
//   写口：装载器的 (地址, 像素) 经异步 FIFO 送入，每攒满 BURST 字连续写入一批（写使能不断，地址连续且不跨页）
//   读口：两路独立帧流 A / B（转场时同时读两张图），各带一个到 video_clk 的异步 FIFO
//
// 帧流协议：视频侧每帧在消隐期翻转 req_tgl，并给出要读的槽号 slot；
//   本模块检测到翻转后：停止发读 → 等在途数据回完 → 清空该路 FIFO → 从槽起始地址重新读
//   这样每帧都重新对齐，任何偶发错位都不会累积。
// SDRAM IP 使用约束：每拍一字，读写不重叠，单次连续 ≤ BURST 字。
// 刷新：IP 的自动刷新实测不工作（不显示的图片放久了出现固定位置噪点），
//   由本模块每 REF_PERIOD 拍在读写空闲时拉 app_ref_req 请求一次刷新（8192 次/64ms）。
// =====================================================================
module mem_ctrl #(
    parameter integer FRAME_WORDS = 307200,
    parameter integer SLOT_WORDS  = 524288,
    parameter integer BURST       = 128,
    parameter integer RD_AW       = 10,           // 读 FIFO 深度 2^RD_AW
    parameter integer REF_PERIOD  = 780           // 刷新请求间隔（拍）：100MHz 下 7.8us
)(
    input  wire        mem_clk,
    input  wire        rst,
    // ---- SDRAM IP ----
    input  wire        sdr_init_done,
    input  wire        sdr_busy,                  // IP 忙
    input  wire        sdr_ref,                   // IP 正在初始化/刷新（Sdr_init_ref_vld）
    output reg  [7:0]  dbg_ref_rate,              // 调试：每 65536 拍内 IP 刷新次数（饱和 255）
    output reg         app_ref_req,               // 请求 IP 做一次刷新
    output reg         app_wr_en,
    output reg  [20:0] app_wr_addr,
    output reg  [31:0] app_wr_din,
    output reg         app_rd_en,
    output reg  [20:0] app_rd_addr,
    input  wire        sdr_rd_en,
    input  wire [31:0] sdr_rd_dout,
    // ---- 写口（装载器侧时钟） ----
    input  wire        wr_clk,
    input  wire        px_valid,
    input  wire [20:0] px_addr,
    input  wire [31:0] px_data,
    output wire        px_ready,
    // ---- 读口（视频时钟） ----
    input  wire        vid_clk,
    input  wire        a_req_tgl,  input wire [1:0] a_slot,
    input  wire        a_rd,       output wire [23:0] a_rgb,
    input  wire        b_req_tgl,  input wire [1:0] b_slot,
    input  wire        b_rd,       output wire [23:0] b_rgb
);

// ------------------------------------------------ 写 FIFO（装载器 → mem）
wire        wf_empty;
wire [52:0] wf_q;
wire [9:0]  wf_wused, wf_rused;
reg         wf_rd;
afifo #(.WIDTH(53), .AW(9)) u_wfifo(
    .aclr(rst),
    .wr_clk(wr_clk), .wr_en(px_valid), .wr_data({px_addr, px_data}), .full(), .wr_used(wf_wused),
    .rd_clk(mem_clk), .rd_en(wf_rd), .rd_data(wf_q), .empty(wf_empty), .rd_used(wf_rused)
);
assign px_ready = (wf_wused < 10'd300);           // 至少还能放一个扇区（171 像素）

// ------------------------------------------------ 读流（两路，结构相同）
reg  [1:0]  s_tgl_s1, s_tgl_s2, s_tgl_s3;        // 两路请求翻转同步
reg  [1:0]  s_clr;                               // 两路 FIFO 清空
wire [RD_AW:0] s_wused0, s_wused1;
reg  [20:0] s_addr   [0:1];
reg  [19:0] s_remain [0:1];
reg  [1:0]  s_flush;                             // 该路等待清空中
reg         cur_stream;                          // 当前读批次属于哪一路

afifo #(.WIDTH(24), .AW(RD_AW)) u_afifo(
    .aclr(rst | s_clr[0]),
    .wr_clk(mem_clk), .wr_en(sdr_rd_en & (cur_stream == 1'b0) & ~s_flush[0]), .wr_data(sdr_rd_dout[31:8]),
    .full(), .wr_used(s_wused0),
    .rd_clk(vid_clk), .rd_en(a_rd), .rd_data(a_rgb), .empty(), .rd_used()
);
afifo #(.WIDTH(24), .AW(RD_AW)) u_bfifo(
    .aclr(rst | s_clr[1]),
    .wr_clk(mem_clk), .wr_en(sdr_rd_en & (cur_stream == 1'b1) & ~s_flush[1]), .wr_data(sdr_rd_dout[31:8]),
    .full(), .wr_used(s_wused1),
    .rd_clk(vid_clk), .rd_en(b_rd), .rd_data(b_rgb), .empty(), .rd_used()
);

// 槽号跨时钟：在翻转被检测到时采样（视频侧保证翻转前槽号已稳定）
reg [1:0] a_slot_s, b_slot_s;
always @(posedge mem_clk) begin a_slot_s <= a_slot; b_slot_s <= b_slot; end

// ------------------------------------------------ 调度状态机
localparam M_IDLE = 3'd0, M_RD = 3'd1, M_RD_WAIT = 3'd2, M_WR = 3'd3, M_GAP = 3'd4, M_REF = 3'd5;
reg [2:0]  m_state;
reg [9:0]  ref_tmr;            // 刷新请求计时
reg        ref_due;            // 该请求刷新了
reg [6:0]  ref_wait;           // 等待 IP 完成刷新（超时 128 拍，IP 不响应也不会卡住）
reg        ref_ack;            // 已看到 IP 的刷新指示
reg [8:0]  cnt;
reg [8:0]  outstanding;        // 已发出未返回的读字数
reg [3:0]  gap;
reg        wf_q_valid;         // wf_rd 后一拍数据有效

// 该路是否需要补数据：打一拍寄存（时序）。只在 IDLE 且无在途读时使用；
// 进入 IDLE 前至少经过 4 拍 GAP，寄存值已是最新，滞后只会让判断更保守
reg need0, need1;
always @(posedge mem_clk) begin
    need0 <= !s_flush[0] && s_remain[0] != 0 && (s_wused0 < (1 << RD_AW) - BURST);
    need1 <= !s_flush[1] && s_remain[1] != 0 && (s_wused1 < (1 << RD_AW) - BURST);
end

// 给 IP 自动刷新让路：IP 忙/刷新时不开新批次（参考安路例程 app_wrrd.v 的用法）
wire can_start = !sdr_busy && !sdr_ref;

// 调试：统计 IP 刷新频率（Sdr_init_ref_vld 上升沿个数 / 65536 拍）
reg        ref_d;
reg [15:0] win;
reg [8:0]  ref_cnt;
always @(posedge mem_clk or posedge rst) begin
    if (rst) begin ref_d <= 1'b0; win <= 16'd0; ref_cnt <= 9'd0; dbg_ref_rate <= 8'd0; end
    else begin
        ref_d <= sdr_ref;
        win   <= win + 16'd1;
        if (win == 16'hFFFF) begin
            dbg_ref_rate <= ref_cnt[8] ? 8'hFF : ref_cnt[7:0];
            ref_cnt      <= 9'd0;
        end else if (sdr_ref && !ref_d && !ref_cnt[8])
            ref_cnt <= ref_cnt + 9'd1;
    end
end

integer i;
always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        m_state <= M_IDLE; cur_stream <= 1'b0; cnt <= 0; outstanding <= 0; gap <= 0;
        ref_tmr <= 0; ref_due <= 0; ref_wait <= 0; ref_ack <= 0; app_ref_req <= 0;
        app_wr_en <= 0; app_wr_addr <= 0; app_wr_din <= 0; app_rd_en <= 0; app_rd_addr <= 0;
        wf_rd <= 0; wf_q_valid <= 0;
        s_tgl_s1 <= 0; s_tgl_s2 <= 0; s_tgl_s3 <= 0; s_clr <= 0; s_flush <= 0;
        for (i = 0; i < 2; i = i + 1) begin s_addr[i] <= 0; s_remain[i] <= 0; end
    end else begin
        app_wr_en  <= 1'b0;
        app_rd_en  <= 1'b0;
        wf_rd      <= 1'b0;
        wf_q_valid <= wf_rd;
        s_clr      <= 2'b00;

        // 在途读计数
        outstanding <= outstanding + (app_rd_en ? 9'd1 : 9'd0) - (sdr_rd_en ? 9'd1 : 9'd0);

        // 帧请求：检测翻转 → 标记该路待清空
        s_tgl_s1 <= {b_req_tgl, a_req_tgl};
        s_tgl_s2 <= s_tgl_s1;
        s_tgl_s3 <= s_tgl_s2;
        for (i = 0; i < 2; i = i + 1)
            if (s_tgl_s2[i] != s_tgl_s3[i]) s_flush[i] <= 1'b1;

        // 刷新计时：每 REF_PERIOD 拍要求一次
        if (ref_tmr == REF_PERIOD - 1) begin ref_tmr <= 10'd0; ref_due <= 1'b1; end
        else ref_tmr <= ref_tmr + 10'd1;

        // 写数据出 FIFO 后下一拍送 SDRAM
        if (wf_q_valid) begin
            app_wr_en   <= 1'b1;
            app_wr_addr <= wf_q[52:32];
            app_wr_din  <= wf_q[31:0];
        end

        case (m_state)
        M_IDLE: begin
            if (!sdr_init_done) ;
            else if (s_flush != 2'b00 && outstanding == 0) begin
                // 清空待重启的读流（此时没有在途数据）
                for (i = 0; i < 2; i = i + 1) if (s_flush[i]) begin
                    s_clr[i]    <= 1'b1;
                    s_flush[i]  <= 1'b0;
                    s_addr[i]   <= (i == 0 ? a_slot_s : b_slot_s) * SLOT_WORDS;
                    s_remain[i] <= FRAME_WORDS;
                end
                gap <= 4'd8; m_state <= M_GAP;           // 等 FIFO 复位完成
            end else if (ref_due && outstanding == 0) begin
                // 读写都已结束：请求 IP 刷新一次
                app_ref_req <= 1'b1; ref_wait <= 7'd0; ref_ack <= 1'b0; m_state <= M_REF;
            end else if (!can_start) ;                    // 给 IP 刷新让路
            else if (outstanding == 0 && (need0 || need1)) begin
                // 优先给缓冲更少的一路
                cur_stream <= (need0 && need1) ? (s_wused1 < s_wused0) : need1;
                cnt <= 0; m_state <= M_RD;
            end else if (wf_rused >= BURST) begin
                // 攒够一整批（BURST 字 = 同一行内对齐的连续地址）再写，保证写使能连续不断
                cnt <= 0; m_state <= M_WR;
            end
        end
        M_RD: if (!sdr_ref) begin                         // 连续发 BURST 个读（IP 刷新时暂停）
            app_rd_en   <= 1'b1;
            app_rd_addr <= s_addr[cur_stream];
            s_addr[cur_stream]   <= s_addr[cur_stream] + 21'd1;
            s_remain[cur_stream] <= s_remain[cur_stream] - 20'd1;
            cnt <= cnt + 9'd1;
            if (cnt == BURST - 1 || s_remain[cur_stream] == 20'd1 || s_flush[cur_stream]) m_state <= M_RD_WAIT;
        end
        M_RD_WAIT: begin                                  // 等这批读数据全部回来
            if (outstanding == 0 && !app_rd_en) begin gap <= 4'd4; m_state <= M_GAP; end
        end
        M_WR: begin                                       // 连续 BURST 拍取 FIFO → 连续 BURST 拍写 SDRAM
            if (cnt != BURST) begin
                wf_rd <= 1'b1;
                cnt   <= cnt + 9'd1;
            end else if (!wf_rd && !wf_q_valid) begin
                gap <= 4'd4; m_state <= M_GAP;
            end
        end
        M_REF: begin                                      // 保持请求，直到看到 IP 刷新开始并结束（或超时）
            ref_wait <= ref_wait + 7'd1;
            if (sdr_ref) ref_ack <= 1'b1;
            if ((ref_ack && !sdr_ref) || ref_wait == 7'd127) begin
                app_ref_req <= 1'b0; ref_due <= 1'b0; gap <= 4'd4; m_state <= M_GAP;
            end
        end
        M_GAP: begin
            if (gap == 0) m_state <= M_IDLE; else gap <= gap - 4'd1;
        end
        default: m_state <= M_IDLE;
        endcase
    end
end

endmodule
