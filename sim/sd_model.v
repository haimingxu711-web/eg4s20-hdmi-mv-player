// 仿真用 SD 卡模型（SPI 模式，SDHC），数据来自 disk.hex（每行 1 字节）
// 支持 CMD0/8/55/41/58/17；ACMD41 前 3 次返回"忙"
`timescale 1ns/1ps
module sd_model #(parameter DISK_BYTES = 4096*512, parameter HEXFILE = "disk.hex")(
    input  wire cs, input wire sclk, input wire mosi, output wire miso
);
reg [7:0] disk [0:DISK_BYTES-1];
initial $readmemh(HEXFILE, disk);

reg [7:0] rx_sh; integer rx_bits = 0;
reg [7:0] cmd [0:5]; integer cmd_n = 0;
reg [7:0] q [0:1023]; integer q_rd = 0, q_wr = 0;
reg [7:0] tx_byte = 8'hFF; integer tx_bit = 0;
integer acmd41_cnt = 0; reg app = 0;
assign miso = cs ? 1'b1 : tx_byte[7 - tx_bit];

task push(input [7:0] b); begin q[q_wr % 1024] = b; q_wr = q_wr + 1; end endtask

// 每收到一个完整字节：处理命令，并准备下一个要发的字节
always @(posedge sclk) if (!cs) begin
    rx_sh = {rx_sh[6:0], mosi};
    rx_bits = rx_bits + 1;
    if (rx_bits == 8) begin
        rx_bits = 0;
        if (cmd_n == 0 && rx_sh[7:6] == 2'b01) begin cmd[0] = rx_sh; cmd_n = 1; end
        else if (cmd_n > 0) begin
            cmd[cmd_n] = rx_sh; cmd_n = cmd_n + 1;
            if (cmd_n == 6) begin cmd_n = 0; exec; end
        end
    end
end
always @(negedge sclk) if (!cs) begin
    tx_bit = tx_bit + 1;
    if (tx_bit == 8) begin
        tx_bit = 0;
        if (q_rd != q_wr) begin tx_byte = q[q_rd % 1024]; q_rd = q_rd + 1; end
        else tx_byte = 8'hFF;
    end
end
always @(posedge cs) begin tx_bit = 0; tx_byte = 8'hFF; rx_bits = 0; end

task exec;
    reg [31:0] arg; integer i, base;
    begin
        arg = {cmd[1], cmd[2], cmd[3], cmd[4]};
        push(8'hFF);                                  // NCR
        case (cmd[0][5:0])
            0:  begin push(8'h01); app = 0; end
            8:  begin push(8'h01); push(8'h00); push(8'h00); push(8'h01); push(arg[7:0]); end
            55: begin push(8'h01); app = 1; end
            41: begin if (acmd41_cnt < 3) push(8'h01); else push(8'h00); acmd41_cnt = acmd41_cnt + 1; app = 0; end
            58: begin push(8'h00); push(8'hC0); push(8'hFF); push(8'h80); push(8'h00); end
            17: begin
                    push(8'h00); push(8'hFF); push(8'hFF); push(8'hFE);
                    base = arg * 512;
                    for (i = 0; i < 512; i = i + 1) push(disk[base + i]);
                    push(8'h12); push(8'h34);
                end
            default: push(8'h04);
        endcase
    end
endtask
endmodule
