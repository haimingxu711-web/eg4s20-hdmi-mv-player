// 顶层整体仿真：真实 my_top + 厂商 IP 替身（PLL/SDRAM/HDMI）+ SD 卡模型 + 按键
// 用 64x48 小图（defparam 改装载器尺寸）；显示端按线性像素序号 n=y*640+x (<3072) 比对
`timescale 1ns/1ps
`include "vid_defs.vh"

// ---------- 厂商 IP 替身 ----------
module video_pll(input refclk, output reg clk0_out = 0, output reg clk1_out = 0, input reset);
    always #20 clk0_out = ~clk0_out;   // 25MHz
    always #4  clk1_out = ~clk1_out;   // 125MHz
endmodule
module sys_pll(input refclk, output reg clk0_out = 0, output reg clk1_out = 0, output reg clk2_out = 1, input reset);
    always #5 clk0_out = ~clk0_out;    // 100MHz
    always #4 begin clk1_out = ~clk1_out; clk2_out = ~clk2_out; end
endmodule
module sdram(input Clk, input Clk_sft, input Rst, output Sdr_init_done, output Sdr_init_ref_vld, output Sdr_busy,
  input App_wr_en, input [20:0] App_wr_addr, input [3:0] App_wr_dm, input [31:0] App_wr_din,
  input App_rd_en, input [20:0] App_rd_addr, output Sdr_rd_en, output [31:0] Sdr_rd_dout);
    assign Sdr_init_ref_vld = 1'b0; assign Sdr_busy = 1'b0;
    sdram_ip_model m(.clk(Clk), .init_done(Sdr_init_done), .wr_en(App_wr_en), .wr_addr(App_wr_addr), .wr_din(App_wr_din),
                     .rd_en(App_rd_en), .rd_addr(App_rd_addr), .rd_valid(Sdr_rd_en), .rd_dout(Sdr_rd_dout));
endmodule
module hdmi_1_4b_transmitter_core_wrapper #(parameter DEVICE="EG", HTOTAL=0,HSA=0,HFP=0,HBP=0,HACTIVE=0,VTOTAL=0,VSA=0,VFP=0,VBP=0,VACTIVE=0,VIDEO_VIC=0,VIDEO_TPG="",VIDEO_FORMAT="",AUDIO_SAMPLE_RATE="",IIC_SCL_DIV=0)(
  input I_pixel_clk, input I_rst, input I_edid_read_trig, output O_edid_read_valid, output [7:0] O_edid_read_data,
  input I_axis_s_user, input I_axis_s_valid, input I_axis_s_last, input [23:0] I_axis_s_data, output O_axis_s_ready,
  input I_audio_valid, input [23:0] I_audio_left_data, input [23:0] I_audio_right_data,
  input I_acr_valid, input [19:0] I_acr_cts, input [19:0] I_acr_n, output O_video_locked, output O_ddc_scl, inout IO_ddc_sda,
  output [9:0] O_ch0_tmds_data, output [9:0] O_ch1_tmds_data, output [9:0] O_ch2_tmds_data, output [9:0] O_clk_tmds_data);
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="EG")(input I_pixel_clk, input I_serial_clk, input I_rst,
  input [9:0] I_tmds_channel_0, input [9:0] I_tmds_channel_1, input [9:0] I_tmds_channel_2, input [9:0] I_tmds_channel_clk,
  output O_tmds_ch0_p, output O_tmds_ch1_p, output O_tmds_ch2_p, output O_tmds_clk_p);
endmodule

module tb_top;
reg clk = 0; always #10 clk = ~clk;
reg rst_n = 0, key1 = 1, key2 = 1, key3 = 1;
reg sw1 = 1, sw2 = 0, sw3 = 0, sw4 = 0;           // 转场关闭：切图立即生效，便于比对
wire [5:0] seg_sel; wire [7:0] seg_data;
wire sd_ncs, sd_dclk, sd_mosi, sd_miso;
wire ddc_sda;
my_top dut(.clk(clk), .rst_n(rst_n), .key1(key1), .key3(key3), .key2(key2),
    .sw_audio_on(sw1), .sw2(sw2), .sw3(sw3), .sw4(sw4), .seg_sel(seg_sel), .seg_data(seg_data),
    .HDMI_CLK_P(), .HDMI_D2_P(), .HDMI_D1_P(), .HDMI_D0_P(), .HDMI_DDC_SCL(), .HDMI_DDC_SDA(ddc_sda),
    .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso));
sd_model u_card(.cs(sd_ncs), .sclk(sd_dclk), .mosi(sd_mosi), .miso(sd_miso));
defparam dut.u_ld.IMG_W = 64;
defparam dut.u_ld.IMG_H = 48;

// 期望：expect.hex 里地址 = 槽*4096 + 序号
reg [31:0] exp_mem [0:4*4096-1];
integer fd, r, a, d, i;
initial begin
    fd = $fopen("expect.hex", "r");
    while (!$feof(fd)) begin r = $fscanf(fd, "%h %h\n", a, d); if (r == 2) exp_mem[a] = d; end
end

// 显示端检查：v_src 是帧源输出（转场前），按线性序号比对前 3072 个像素
wire [`VB-1:0] vs = dut.v_src;
integer frame = 0, errs = 0, chk = 0, n;
always @(posedge dut.video_clk) begin
    if (dut.frame_start) begin
        if (chk > 0) $display("t=%0t frame %0d: cur=%0d slotA=%0d loaded=%0d cnt=%0d  checked=%0d errors=%0d",
                              $time, frame, dut.cur, dut.u_src.cur_slot_a, dut.loaded, dut.img_count, chk, errs);
        frame = frame + 1; errs = 0; chk = 0;
    end
    if (dut.loaded && `DE(vs)) begin
        n = `Y(vs) * 640 + `X(vs);
        if (n < 3072) begin
            chk = chk + 1;
            if (`RGB(vs) !== exp_mem[dut.u_src.cur_slot_a * 4096 + n][31:8]) errs = errs + 1;
        end
    end
end

initial begin
    #1000 rst_n = 1;
    wait (dut.loaded);
    $display("t=%0t loaded: img_count=%0d img_ok=%b", $time, dut.img_count, dut.img_ok);
    #50_000_000;                     // 看几帧
    $display("--- press KEY2 ---");
    key1 = 0; #30_000_000; key1 = 1;
    #50_000_000;
    $display("--- press KEY2 ---");
    key1 = 0; #30_000_000; key1 = 1;
    #40_000_000;
    $finish;
end
initial #400_000_000 begin $display("TIMEOUT sd=%h ld=%h", dut.sd_dbg, dut.ld_dbg); $finish; end
endmodule
