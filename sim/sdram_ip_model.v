// 仿真用 SDRAM IP 行为模型（接口同厂商 sdram 模块的用户侧）
// 读延迟固定 LAT 拍；检测读写同拍冲突
`timescale 1ns/1ps
module sdram_ip_model #(parameter LAT = 7, parameter AW = 21, parameter REF_INT = 3125, parameter REF_LEN = 10)(
    input  wire          clk,
    output reg           init_done,
    input  wire          ref_req,                       // 应用请求刷新（实测 IP 不会自动刷新）
    output wire          busy, output reg ref,          // 收到请求后挂起（busy=1），等读写空闲 2 拍后刷新 REF_LEN 拍；刷新期间的命令被丢弃
    input  wire          wr_en, input wire [AW-1:0] wr_addr, input wire [31:0] wr_din,
    input  wire          rd_en, input wire [AW-1:0] rd_addr,
    output wire          rd_valid, output wire [31:0] rd_dout
);
reg [31:0] mem [0:(1<<AW)-1];
reg [LAT-1:0] v_pipe = 0;
reg [31:0]    d_pipe [0:LAT-1];
integer i, cyc = 0, conflicts = 0, drops = 0;
reg pend = 0, ref_req_d = 0; integer idle = 0, rlen = 0, refs = 0;
initial begin init_done = 0; ref = 0; end
assign busy = ref | pend;
wire wr_ok = wr_en && !ref, rd_ok = rd_en && !ref;
always @(posedge clk) begin
    cyc = cyc + 1;
    if (cyc == 200) init_done <= 1;
    if (ref_req && !ref && !ref_req_d) begin pend <= 1; refs = refs + 1; end
    ref_req_d <= ref_req;
    idle = (wr_en || rd_en) ? 0 : idle + 1;
    if (ref) begin rlen = rlen + 1; if (rlen == REF_LEN) ref <= 0; end
    else if (pend && idle >= 2) begin pend <= 0; ref <= 1; rlen = 0; end
    if ((wr_en || rd_en) && ref) begin drops = drops + 1; if (drops < 4) $display("SDRAM DROP cmd during refresh at %0t", $time); end
    if (wr_ok) mem[wr_addr] <= wr_din;
    if (wr_en && rd_en) begin conflicts = conflicts + 1; if (conflicts < 4) $display("SDRAM CONFLICT rd&wr at %0t", $time); end
    v_pipe <= {v_pipe[LAT-2:0], rd_ok};
    d_pipe[0] <= mem[rd_addr];
    for (i = 1; i < LAT; i = i + 1) d_pipe[i] <= d_pipe[i-1];
end
assign rd_valid = v_pipe[LAT-1];
assign rd_dout  = d_pipe[LAT-1];
endmodule
