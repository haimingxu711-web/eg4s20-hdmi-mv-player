# ============================================================
# my_top 时序约束
# 板级 50MHz（只用于上电复位计数，复位经同步器进入各域）与三个功能时钟域之间只通过 afifo（格雷码指针）和两级同步器交换数据，
# 因此声明为异步时钟组，避免工具把跨域路径当作同步路径去收敛。
#   clk        50MHz  板载时钟：上电复位 + SD 卡 / 图片装载
#   mem_clk   125MHz  SDRAM 调度（及 SDRAM IP 的相移时钟）
#   video_clk  25MHz  像素流 / 音频 / HDMI（与 5 倍串行时钟同源相关，保持同步分析）
# ============================================================
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks

rename_clock -name {mem_clk}     -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]

set_clock_groups -asynchronous \
    -group [get_clocks {clk}] \
    -group [get_clocks {mem_clk mem_clk_sft}] \
    -group [get_clocks {video_clk hdmi_5x_clk}]
