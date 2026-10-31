// 全链路仿真：SD 卡模型 → sd_card → img_loader → mem_ctrl → SDRAM 模型 → vid_frame_src
// 用小分辨率（W x H）加速；检查：装载完成后，A 路每帧显示的像素 == 该槽的期望图像；
// 并在运行中切换 A/B 槽，验证每帧都能正确重新对齐。
`timescale 1ns/1ps
`include "vid_defs.vh"
module tb_system;
parameter W = 64, H = 48, SLOT = 4096;
reg clk100 = 0, clk125 = 0, clk25 = 0, rst = 1;
always #5    clk100 = ~clk100;
always #4    clk125 = ~clk125;
always #20   clk25  = ~clk25;

// ---- SD ----
wire cs, sclk, mosi, miso, ready, idle, init_err; wire [3:0] sd_dbg;
wire rd_req, rd_bv, rd_done, rd_err; wire [31:0] rd_lba; wire [7:0] rd_byte;
sd_card #(.SLOW_DIV(8'd4), .FAST_DIV(8'd1), .ACMD41_MAX(24'd50)) u_sd(
    .clk(clk100), .rst(rst), .ready(ready), .idle(idle), .init_err(init_err), .dbg_state(sd_dbg),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv), .rd_done(rd_done), .rd_err(rd_err),
    .sd_cs(cs), .sd_sclk(sclk), .sd_mosi(mosi), .sd_miso(miso));
sd_model u_card(.cs(cs), .sclk(sclk), .mosi(mosi), .miso(miso));

wire px_valid, px_ready; wire [20:0] px_addr; wire [31:0] px_data;
wire [2:0] img_count; wire [3:0] img_ok, ld_dbg; wire done, fs_err;
img_loader #(.IMG_W(W), .IMG_H(H), .SLOT_WORDS(SLOT)) u_ld(
    .clk(clk100), .rst(rst), .start(1'b1), .sd_ready(ready), .sd_idle(idle),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv), .rd_done(rd_done), .rd_err(rd_err),
    .px_ready(px_ready), .px_valid(px_valid), .px_addr(px_addr), .px_data(px_data),
    .img_count(img_count), .img_ok(img_ok), .done(done), .fs_err(fs_err), .dbg_state(ld_dbg));

// ---- SDRAM ----
wire init_done, app_wr_en, app_rd_en, sdr_rd_en; wire [20:0] app_wr_addr, app_rd_addr; wire [31:0] app_wr_din, sdr_rd_dout;
wire sdr_busy, sdr_ref, ref_req;
sdram_ip_model u_sdr(.clk(clk125), .init_done(init_done), .ref_req(ref_req), .busy(sdr_busy), .ref(sdr_ref), .wr_en(app_wr_en), .wr_addr(app_wr_addr), .wr_din(app_wr_din),
    .rd_en(app_rd_en), .rd_addr(app_rd_addr), .rd_valid(sdr_rd_en), .rd_dout(sdr_rd_dout));

wire a_tgl, b_tgl, a_rd, b_rd; wire [1:0] a_slot, b_slot; wire [23:0] a_rgb, b_rgb;
mem_ctrl #(.FRAME_WORDS(W*H), .SLOT_WORDS(SLOT), .BURST(32), .RD_AW(7)) u_mem(
    .mem_clk(clk125), .rst(rst), .sdr_init_done(init_done), .sdr_busy(sdr_busy), .sdr_ref(sdr_ref), .app_ref_req(ref_req), .dbg_ref_rate(),
    .app_wr_en(app_wr_en), .app_wr_addr(app_wr_addr), .app_wr_din(app_wr_din),
    .app_rd_en(app_rd_en), .app_rd_addr(app_rd_addr), .sdr_rd_en(sdr_rd_en), .sdr_rd_dout(sdr_rd_dout),
    .wr_clk(clk100), .px_valid(px_valid), .px_addr(px_addr), .px_data(px_data), .px_ready(px_ready),
    .vid_clk(clk25),
    .a_req_tgl(a_tgl), .a_slot(a_slot), .a_rd(a_rd), .a_rgb(a_rgb),
    .b_req_tgl(b_tgl), .b_slot(b_slot), .b_rd(b_rd), .b_rgb(b_rgb));

// ---- 视频 ----
wire [`VB-1:0] v_tim, v_src; wire fs; wire [23:0] rgb_b; wire [1:0] cur_a, cur_b;
reg  [1:0] sel_a = 0, sel_b = 1;
vid_timing #(.H_ACTIVE(W), .H_FP(4), .H_SYNC(8), .H_BP(4), .V_ACTIVE(H), .V_FP(2), .V_SYNC(2), .V_BP(20))
    u_tim(.clk(clk25), .rst(rst), .vo(v_tim), .frame_start(fs));
vid_frame_src u_src(.clk(clk25), .rst(rst), .vi(v_tim), .frame_start(fs), .slot_a(sel_a), .slot_b(sel_b),
    .a_req_tgl(a_tgl), .a_slot(a_slot), .a_rd(a_rd), .a_rgb(a_rgb),
    .b_req_tgl(b_tgl), .b_slot(b_slot), .b_rd(b_rd), .b_rgb(b_rgb),
    .vo(v_src), .rgb_b(rgb_b), .cur_slot_a(cur_a), .cur_slot_b(cur_b));

// ---- 期望图像 ----
reg [31:0] exp_mem [0:4*SLOT-1];
integer fd, r, a, d, i;
initial begin
    for (i = 0; i < 4*SLOT; i = i + 1) exp_mem[i] = 0;
    fd = $fopen("expect.hex", "r");
    while (!$feof(fd)) begin r = $fscanf(fd, "%h %h\n", a, d); if (r == 2) exp_mem[a] = d; end
end

// ---- 逐帧检查 ----
integer frame = 0, errs_a = 0, errs_b = 0, checked = 0, frame_errs = 0;
reg checking = 0;
always @(posedge clk25) begin
    if (fs) begin
        if (checking) begin
            $display("frame %0d slotA=%0d slotB=%0d  errA=%0d errB=%0d", frame, cur_a, cur_b, errs_a, errs_b);
            if (errs_a || errs_b) frame_errs = frame_errs + 1;
            checked = checked + 1;
        end
        errs_a = 0; errs_b = 0; frame = frame + 1;
        checking = done && (frame > 2);
        // 每帧轮换槽号
        if (done) begin sel_a = sel_a + 1; sel_b = sel_b + 3; end
    end
    if (checking && `DE(v_src)) begin
        if (`RGB(v_src) !== exp_mem[cur_a*SLOT + `Y(v_src)*W + `X(v_src)][31:8]) errs_a = errs_a + 1;
        if (rgb_b       !== exp_mem[cur_b*SLOT + `Y(v_src)*W + `X(v_src)][31:8]) errs_b = errs_b + 1;
    end
    if (checked == 8) begin
        $display("RESULT: img_ok=%b frames checked=%0d, frames with errors=%0d, cmds dropped by refresh=%0d, refreshes=%0d (expect ~%0d)", img_ok, checked, frame_errs, u_sdr.drops, u_sdr.refs, $time/8/780);
        $finish;
    end
end
initial begin #100 rst = 0; end
initial begin #400_000_000 $display("TIMEOUT done=%0d sd=%h ld=%h", done, sd_dbg, ld_dbg); $finish; end
endmodule
