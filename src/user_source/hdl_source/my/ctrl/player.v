// =====================================================================
// 播放控制器（video_clk 域，每帧 frame_start 更新一次）
//   三种模式（KEY4 循环切换）：0 手动  1 定时轮播（周期 2/3/5/8 秒）  2 MV（图片跟着音乐的切图节点走）
//   KEY2 下一张在任何模式下都可用
//   转场：A 路 = 当前图，B 路 = 下一张；进度 t 线性 0→255，alpha = smoothstep(t) 缓入缓出
//   样式：其它模式每次轮换 0~3（淡入淡出/擦除/百叶窗/圆形）；
//         MV 模式用乐谱指定的电影感样式 4~7（亮度溶解/经白/经黑/长淡化），时长也更长（约 1.4s）
// 所有按键输入为单拍脉冲（已消抖）
// =====================================================================
module player #(
    parameter integer FADE_STEP = 4,         // 每帧 t 增量：4 → 64 帧 ≈ 1.07s
    parameter integer MV_STEP   = 3          // MV 转场：3 → 85 帧 ≈ 1.42s（gen_theme.py 的 TRANS_LEAD 取其一半）
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_start,
    input  wire       ready,                  // 图片已装载完成
    input  wire [2:0] img_count,              // 有效图片数
    input  wire       k_next,
    input  wire       k_auto,                 // 切换模式
    input  wire       fade_en,                // 0 = 直接切换
    input  wire       mv_sw,                  // 音乐切图节点（单拍）
    input  wire [2:0] mv_img,
    input  wire [1:0] mv_style,
    output reg  [1:0] slot_a,
    output reg  [1:0] slot_b,
    output wire [7:0] alpha,                  // B 路权重（已做缓动）
    output reg        fading,
    output reg  [2:0] style,
    output reg  [1:0] mode,
    output reg        music_restart,          // 进入 MV 模式时让音乐从头开始（单拍）
    input  wire [1:0] period_sel,             // 0:2s 1:3s 2:5s 3:8s（来自参数菜单）
    output wire [3:0] period_sec,
    output reg  [1:0] cur                     // 当前图片
);

assign period_sec = (period_sel == 2'd0) ? 4'd2 :
                    (period_sel == 2'd1) ? 4'd3 :
                    (period_sel == 2'd2) ? 4'd5 : 4'd8;

wire [9:0] period_frames = period_sec * 7'd60;   // 60 帧/秒

reg  [7:0] t;
ease_lut u_ease(.t(t), .a(alpha));

reg       next_req, mv_req;
reg [7:0] step;                               // 本次转场每帧步长
reg [2:0] mv_img_l;
reg [1:0] mv_style_l;
reg [9:0] frame_cnt;
reg [1:0] nxt;

wire [1:0] cur_plus1 = (img_count == 3'd0) ? 2'd0 :
                       ({1'b0, cur} + 3'd1 >= img_count) ? 2'd0 : cur + 2'd1;
wire       mv_ok     = mv_req && (mv_img_l < img_count) && (mv_img_l[1:0] != cur);
wire       use_mv    = mv_ok && !next_req;
wire       go        = next_req || mv_ok || (mode == 2'd1 && frame_cnt >= period_frames);
wire [1:0] target    = use_mv ? mv_img_l[1:0] : cur_plus1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        slot_a <= 2'd0; slot_b <= 2'd0; t <= 8'd0; fading <= 1'b0; style <= 3'd3; step <= FADE_STEP;
        mode <= 2'd0; music_restart <= 1'b0; cur <= 2'd0;
        next_req <= 1'b0; mv_req <= 1'b0; mv_img_l <= 3'd0; mv_style_l <= 2'd0;
        frame_cnt <= 10'd0; nxt <= 2'd0;
    end else begin
        music_restart <= 1'b0;
        if (k_auto) begin
            mode <= (mode == 2'd2) ? 2'd0 : mode + 2'd1;
            if (mode == 2'd1) music_restart <= 1'b1;            // 1 → 2：进入 MV
        end

        if (frame_start) begin
            if (!ready || img_count < 3'd2) begin
                next_req <= 1'b0; mv_req <= 1'b0; frame_cnt <= 10'd0;
            end else if (fading) begin
                // 转场进行中（期间来的请求留到结束后处理）
                if (t >= 8'd255 - step) begin
                    cur <= nxt; slot_a <= nxt; slot_b <= nxt;
                    t <= 8'd0; fading <= 1'b0;
                end else
                    t <= t + step;
            end else if (go) begin
                next_req  <= 1'b0;
                mv_req    <= 1'b0;
                frame_cnt <= 10'd0;
                nxt       <= target;
                if (fade_en) begin
                    slot_b <= target; t <= 8'd0; fading <= 1'b1;
                    style  <= use_mv ? {1'b1, mv_style_l} : {1'b0, style[1:0] + 2'd1};
                    step   <= use_mv ? MV_STEP[7:0] : FADE_STEP[7:0];
                end else begin
                    cur <= target; slot_a <= target; slot_b <= target;
                end
            end else begin
                mv_req    <= 1'b0;                           // 目标就是当前图：忽略
                frame_cnt <= (mode == 2'd1) ? frame_cnt + 10'd1 : 10'd0;
            end
        end

        // 请求登记放在最后：与帧处理同拍到来时不会被清掉
        if (k_next) next_req <= 1'b1;
        if (mv_sw && mode == 2'd2) begin mv_req <= 1'b1; mv_img_l <= mv_img; mv_style_l <= mv_style; end
    end
end

endmodule
