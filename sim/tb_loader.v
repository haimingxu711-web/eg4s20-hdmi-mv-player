// SD 驱动 + FAT32/BMP 装载器 联合仿真：对比写出的像素与 expect.hex
`timescale 1ns/1ps
module tb_loader;
parameter W = 64, H = 48, SLOT = 4096;
reg clk = 0, rst = 1; always #5 clk = ~clk;      // 100MHz

wire cs, sclk, mosi, miso;
wire ready, idle, init_err; wire [3:0] sd_dbg;
wire rd_req, rd_bv, rd_done, rd_err; wire [31:0] rd_lba; wire [7:0] rd_byte;
sd_card #(.SLOW_DIV(8'd4), .FAST_DIV(8'd1), .ACMD41_MAX(24'd50)) u_sd(
    .clk(clk), .rst(rst), .ready(ready), .idle(idle), .init_err(init_err), .dbg_state(sd_dbg),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv),
    .rd_done(rd_done), .rd_err(rd_err),
    .sd_cs(cs), .sd_sclk(sclk), .sd_mosi(mosi), .sd_miso(miso));
sd_model u_card(.cs(cs), .sclk(sclk), .mosi(mosi), .miso(miso));

wire px_valid; wire [20:0] px_addr; wire [31:0] px_data;
wire [2:0] img_count; wire [3:0] img_ok, ld_dbg; wire done, fs_err;
img_loader #(.IMG_W(W), .IMG_H(H), .MAX_IMG(4), .SLOT_WORDS(SLOT)) u_ld(
    .clk(clk), .rst(rst), .start(1'b1), .sd_ready(ready), .sd_idle(idle),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv),
    .rd_done(rd_done), .rd_err(rd_err),
    .px_ready(1'b1), .px_valid(px_valid), .px_addr(px_addr), .px_data(px_data),
    .img_count(img_count), .img_ok(img_ok), .done(done), .fs_err(fs_err), .dbg_state(ld_dbg));

reg [31:0] mem [0:4*SLOT-1];
integer i, nwr = 0, errs = 0, a, d, fd, r;
always @(posedge clk) if (px_valid) begin mem[px_addr] <= px_data; nwr = nwr + 1; end

initial begin
    for (i = 0; i < 4*SLOT; i = i + 1) mem[i] = 32'hDEADBEEF;
    #100 rst = 0;
    wait (done);
    #100;
    $display("done: fs_err=%0d img_count=%0d img_ok=%b pixels_written=%0d (expect %0d)", fs_err, img_count, img_ok, nwr, 4*W*H);
    fd = $fopen("expect.hex", "r");
    while (!$feof(fd)) begin
        r = $fscanf(fd, "%h %h\n", a, d);
        if (r == 2 && mem[a] !== d) begin
            if (errs < 5) $display("MISMATCH addr=%h got=%h exp=%h", a, mem[a], d);
            errs = errs + 1;
        end
    end
    $display("compare errors = %0d", errs);
    $finish;
end
initial begin #200_000_000 $display("TIMEOUT sd_dbg=%h ld_dbg=%h", sd_dbg, ld_dbg); $finish; end
endmodule
