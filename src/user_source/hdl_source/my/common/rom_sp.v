// =====================================================================
// 单口只读存储器（块 RAM），读延迟 1 拍
//   综合：安路 EG_LOGIC_BRAM，内容来自 MIF 文件（Quartus 同款格式）
//   仿真：定义 SIM 宏时改用 $readmemh 读 HEX 文件（每行一个字）
// 两种文件都由 theme/gen_theme.py 生成，路径写在 theme_cfg.vh 里
// =====================================================================
module rom_sp #(
    parameter integer W     = 8,           // 数据位宽
    parameter integer AW    = 10,          // 地址位宽
    parameter integer DEPTH = 1024,        // 实际深度（≤ 2^AW）
    parameter         MIF   = "none.mif",
    parameter         HEX   = "none.hex",
    parameter         IMPL  = "AUTO"       // 块 RAM 类型："AUTO" / "9K" / "32K"（大表放 32K 省 9K 块）
)(
    input  wire          clk,
    input  wire [AW-1:0] addr,
    output wire [W-1:0]  q
);

`ifdef SIM
reg [W-1:0] mem [0:DEPTH-1];
reg [W-1:0] q_r;
initial $readmemh(HEX, mem);
always @(posedge clk) q_r <= (addr < DEPTH) ? mem[addr] : {W{1'b0}};
assign q = q_r;
`else
// TD 要求地址位宽与深度严格对应（= ceil(log2(DEPTH))），这里按深度自动算，只用地址低位
function integer clog2;
    input integer n;
    integer k;
    begin
        clog2 = 0;
        for (k = n - 1; k > 0; k = k >> 1) clog2 = clog2 + 1;
    end
endfunction
localparam integer IAW = (DEPTH < 2) ? 1 : clog2(DEPTH);
EG_LOGIC_BRAM #(
    .DATA_WIDTH_A(W), .ADDR_WIDTH_A(IAW), .DATA_DEPTH_A(DEPTH),
    .DATA_WIDTH_B(W), .ADDR_WIDTH_B(IAW), .DATA_DEPTH_B(DEPTH),
    .MODE("SP"), .REGMODE_A("NOREG"), .IMPLEMENT(IMPL),
    .DEBUGGABLE("NO"), .PACKABLE("NO"), .INIT_FILE(MIF), .FILL_ALL("NONE")
) u_bram(
    .dia({W{1'b0}}), .dib({W{1'b0}}),
    .addra(addr[IAW-1:0]), .addrb({IAW{1'b0}}),
    .cea(1'b1), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0),
    .clka(clk), .clkb(1'b0), .wea(1'b0), .web(1'b0),
    .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0),
    .doa(q), .dob()
);
`endif

endmodule
