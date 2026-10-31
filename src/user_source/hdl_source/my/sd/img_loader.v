// =====================================================================
// 图片装载器：FAT32 文件系统解析 → 根目录找 *.BMP → BMP 解码 → 像素写入请求
//
// 与 "逐扇区搜索 BM 文件头" 不同，本模块按文件系统定位文件：
//   1. 读 0 号扇区：若是 MBR 则取第一个分区起始 LBA，否则当作 FAT32 引导扇区
//   2. 读引导扇区(BPB)：每簇扇区数、保留扇区、FAT 数量/大小、根目录簇号
//   3. 遍历根目录（沿 FAT 簇链），跳过删除项/长文件名/目录，记录前 MAX_IMG 个 .BMP
//   4. 逐个文件沿簇链读出，校验 BMP 头（BM、宽高、24 位），把像素按行翻转后
//      以 (地址, 像素) 形式输出给 SDRAM 写端口
//
// 输出：
//   px_valid / px_addr / px_data ：像素写请求（px_ready=0 时在扇区边界暂停）
//   img_count       : 有效图片数（0~MAX_IMG）
//   img_ok[k]       : 第 k 张已完整写入
//   done            : 全部装载结束
// =====================================================================
module img_loader #(
    parameter integer IMG_W     = 640,
    parameter integer IMG_H     = 480,
    parameter integer MAX_IMG   = 4,
    parameter integer SLOT_WORDS = 524288          // 每张图在 SDRAM 中占 2^19 字（2MB），地址高 2 位 = 槽号
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,            // 上升沿：重新扫描装载（复位后自动扫描一次）
    // ---- SD 卡扇区读接口（接 sd_card） ----
    input  wire        sd_ready,
    input  wire        sd_idle,          // 控制器空闲，可接收 rd_req
    output reg         rd_req,
    output reg  [31:0] rd_lba,
    input  wire [7:0]  rd_byte,
    input  wire        rd_byte_valid,
    input  wire        rd_done,
    input  wire        rd_err,
    // ---- 像素写出 ----
    input  wire        px_ready,         // 下游可接收至少一个扇区的像素（约 171 个）
    output reg         px_valid,
    output reg  [20:0] px_addr,
    output reg  [31:0] px_data,
    // ---- 状态 ----
    output reg  [2:0]  img_count,
    output reg  [3:0]  img_ok,
    output reg         done,
    output reg         fs_err,           // 文件系统无法识别
    output reg  [3:0]  dbg_state
);

// ---------------- 状态 ----------------
localparam S_IDLE   = 4'd0,
           S_MBR    = 4'd1,
           S_BPB    = 4'd2,
           S_DIR    = 4'd3,
           S_DIRNXT = 4'd4,
           S_FAT    = 4'd5,
           S_FILE   = 4'd6,
           S_FNXT   = 4'd7,
           S_DONE   = 4'd8,
           S_ERR    = 4'd9,
           S_RDWAIT = 4'd10;    // 等待一次扇区读完成（子程序）

reg [3:0]  state, ret_state, fat_ret;
reg [8:0]  bidx;                // 扇区内字节序号
reg [31:0] word32;              // 小端拼接移位寄存器

// FAT32 参数
reg [31:0] part_lba, fat_lba, data_lba, root_clus;
reg [7:0]  spc;                 // 每簇扇区数
reg [15:0] rsvd;
reg [7:0]  nfats;
reg [31:0] fatsz;
reg        mbr_is_vbr;          // 0 号扇区本身就是引导扇区
reg [7:0]  ptype;
reg        sig_ok;

// 当前簇链遍历
reg [31:0] cur_clus;
reg [7:0]  sec_in_clus;
reg [31:0] next_clus;

// 目录项解析
reg [7:0]  de_first;
reg [7:0]  de_attr;
reg [23:0] de_ext;
reg [15:0] de_clus_hi, de_clus_lo;
reg [31:0] de_size;
reg        dir_end;
reg [31:0] f_clus [0:MAX_IMG-1];
reg [31:0] f_size [0:MAX_IMG-1];
reg [2:0]  nfound;

// 文件读取
reg [2:0]  fidx;                // 当前文件
reg [31:0] fpos;                // 文件内字节偏移
reg [31:0] pix_off;
reg [31:0] bmp_w, bmp_h;
reg [15:0] bmp_bpp;
reg        hdr_ok;
reg [1:0]  cpos;                // BGR 字节位置
reg [23:0] pix_bgr;
reg [9:0]  px_x;
reg [9:0]  px_row;              // 文件中的行号（自下而上）
reg        file_bad;

// 簇号 → 起始扇区：每簇扇区数是 2 的幂，用移位代替乘法，并打一拍寄存（100MHz 时序）
// lba_ok = 寄存结果已对应当前 cur_clus，读扇区前必须等它为 1
reg  [2:0]  spc_sh;
reg  [31:0] clus_lba, clus_q;
wire        lba_ok = (clus_q == cur_clus);
always @(posedge clk) begin
    clus_q   <= cur_clus;
    clus_lba <= data_lba + ((cur_clus - 32'd2) << spc_sh);
end
always @(*) begin
    case (spc)
        8'd2: spc_sh = 3'd1;   8'd4: spc_sh = 3'd2;   8'd8: spc_sh = 3'd3;   8'd16: spc_sh = 3'd4;
        8'd32: spc_sh = 3'd5;  8'd64: spc_sh = 3'd6;  8'd128: spc_sh = 3'd7; default: spc_sh = 3'd0;
    endcase
end

// 发起读扇区
task read_sector(input [31:0] lba, input [3:0] ret);
    begin
        rd_lba    <= lba;
        rd_req    <= 1'b1;
        bidx      <= 9'd0;
        ret_state <= ret;
        state     <= S_RDWAIT;
    end
endtask

integer k;

// 复位后自动扫描一次；之后 start 每出现一次上升沿就重新扫描一次
reg start_d, scan_pend;
wire start_rise = scan_pend;
always @(posedge clk or posedge rst) begin
    if (rst) begin start_d <= 1'b0; scan_pend <= 1'b1; end
    else begin
        start_d <= start;
        if (start & ~start_d) scan_pend <= 1'b1;
        else if (state == S_IDLE && sd_ready) scan_pend <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE; ret_state <= S_IDLE; fat_ret <= S_IDLE;
        rd_req <= 1'b0; rd_lba <= 32'd0; bidx <= 9'd0; word32 <= 32'd0;
        px_valid <= 1'b0; px_addr <= 21'd0; px_data <= 32'd0;
        img_count <= 3'd0; img_ok <= 4'd0; done <= 1'b0; fs_err <= 1'b0; dbg_state <= 4'd0;
        part_lba <= 0; fat_lba <= 0; data_lba <= 0; root_clus <= 0; spc <= 0; rsvd <= 0;
        nfats <= 0; fatsz <= 0; mbr_is_vbr <= 0; ptype <= 0; sig_ok <= 0;
        cur_clus <= 0; sec_in_clus <= 0; next_clus <= 0;
        de_first <= 0; de_attr <= 0; de_ext <= 0; de_clus_hi <= 0; de_clus_lo <= 0; de_size <= 0;
        dir_end <= 0; nfound <= 0; fidx <= 0; fpos <= 0; pix_off <= 0; bmp_w <= 0; bmp_h <= 0;
        bmp_bpp <= 0; hdr_ok <= 0; cpos <= 0; pix_bgr <= 0; px_x <= 0; px_row <= 0; file_bad <= 0;
        for (k = 0; k < MAX_IMG; k = k + 1) begin f_clus[k] <= 0; f_size[k] <= 0; end
    end else begin
        px_valid <= 1'b0;

        case (state)
        S_IDLE: begin
            dbg_state <= 4'd0;
            if (start_rise && sd_ready) begin
                done <= 1'b0; fs_err <= 1'b0; img_ok <= 4'd0; img_count <= 3'd0; nfound <= 3'd0;
                sig_ok <= 1'b0; mbr_is_vbr <= 1'b0;
                read_sector(32'd0, S_MBR);
            end
        end

        // ---------- 子程序：等待扇区读完，期间按当前 ret_state 解析每个字节 ----------
        S_RDWAIT: begin
            if (rd_req && sd_idle) rd_req <= 1'b0;     // 控制器已接收请求
            if (rd_err) begin
                read_sector(rd_lba, ret_state);         // 读失败：重读同一扇区
            end else if (rd_byte_valid) begin
                bidx   <= bidx + 9'd1;
                word32 <= {rd_byte, word32[31:8]};      // 小端：新字节放最高位
                case (ret_state)
                // ---- 0 号扇区 ----
                S_MBR: begin
                    if (bidx == 9'd82 && rd_byte == "F") mbr_is_vbr <= 1'b1;   // "FAT32   " 起始
                    if (bidx == 9'd450) ptype <= rd_byte;                     // 0x1C2 分区类型
                    if (bidx == 9'd457) part_lba <= {rd_byte, word32[31:8]};   // 0x1C6..0x1C9
                    if (bidx == 9'd511) sig_ok <= (rd_byte == 8'hAA) && (word32[31:24] == 8'h55);
                end
                // ---- 引导扇区 BPB ----
                S_BPB: begin
                    if (bidx == 9'd13) spc   <= rd_byte;
                    if (bidx == 9'd15) rsvd  <= {rd_byte, word32[31:24]};
                    if (bidx == 9'd16) nfats <= rd_byte;
                    if (bidx == 9'd39) fatsz <= {rd_byte, word32[31:8]};
                    if (bidx == 9'd47) root_clus <= {rd_byte, word32[31:8]};
                    if (bidx == 9'd511) sig_ok <= (rd_byte == 8'hAA) && (word32[31:24] == 8'h55);
                end
                // ---- 目录扇区：每 32 字节一个目录项 ----
                S_DIRNXT: begin
                    case (bidx[4:0])
                        5'd0:  de_first <= rd_byte;
                        5'd10: de_ext   <= {word32[23:16], word32[31:24], rd_byte}; // 扩展名第 8,9,10 字节
                        5'd11: de_attr  <= rd_byte;
                        5'd21: de_clus_hi <= {rd_byte, word32[31:24]};
                        5'd27: de_clus_lo <= {rd_byte, word32[31:24]};
                        5'd31: begin
                            if (de_first == 8'h00) dir_end <= 1'b1;               // 目录结束
                            else if (!dir_end && de_first != 8'hE5 && de_attr != 8'h0F &&
                                     (de_attr & 8'h18) == 8'h00 && de_ext == "BMP" &&
                                     nfound < MAX_IMG) begin
                                f_clus[nfound] <= {de_clus_hi, de_clus_lo};
                                f_size[nfound] <= {rd_byte, word32[31:8]};
                                nfound <= nfound + 3'd1;
                            end
                        end
                        default: ;
                    endcase
                end
                // ---- FAT 扇区：取出 cur_clus 对应的表项 ----
                S_FAT: begin
                    if (bidx[8:2] == cur_clus[6:0] && bidx[1:0] == 2'd3)
                        next_clus <= {rd_byte[3:0], word32[31:8]};               // 低 28 位有效
                end
                // ---- 文件数据 ----
                S_FNXT: begin
                    fpos <= fpos + 32'd1;
                    if (fpos < 32'd54) begin
                        if (fpos == 32'd0  && rd_byte != "B") file_bad <= 1'b1;
                        if (fpos == 32'd1  && rd_byte != "M") file_bad <= 1'b1;
                        if (fpos == 32'd13) pix_off <= {rd_byte, word32[31:8]};
                        if (fpos == 32'd21) bmp_w   <= {rd_byte, word32[31:8]};
                        if (fpos == 32'd25) bmp_h   <= {rd_byte, word32[31:8]};
                        if (fpos == 32'd29) bmp_bpp <= {rd_byte, word32[31:24]};
                        if (fpos == 32'd53)
                            hdr_ok <= (bmp_w == IMG_W) && (bmp_h == IMG_H || bmp_h == -IMG_H) && (bmp_bpp == 16'd24);
                    end else if (!file_bad && hdr_ok && fpos >= pix_off && px_row < IMG_H) begin
                        // BGR 三字节组成一个像素
                        case (cpos)
                            2'd0: begin pix_bgr[7:0]  <= rd_byte; cpos <= 2'd1; end   // B
                            2'd1: begin pix_bgr[15:8] <= rd_byte; cpos <= 2'd2; end   // G
                            default: begin                                            // R
                                cpos     <= 2'd0;
                                px_valid <= 1'b1;
                                px_data  <= {rd_byte, pix_bgr[15:8], pix_bgr[7:0], 8'h00};   // {R,G,B,0}
                                // 正高度 = 自下而上存储，需翻转行号
                                px_addr  <= fidx * SLOT_WORDS +
                                            ((bmp_h[31] ? px_row : (IMG_H - 1 - px_row)) * IMG_W) + px_x;
                                if (px_x == IMG_W - 1) begin px_x <= 10'd0; px_row <= px_row + 10'd1; end
                                else px_x <= px_x + 10'd1;
                            end
                        endcase
                    end
                end
                default: ;
                endcase
            end else if (rd_done) begin
                state <= ret_state;
            end
        end

        // ---------- 0 号扇区判别 ----------
        S_MBR: begin
            dbg_state <= 4'd1;
            if (!sig_ok) state <= S_ERR;
            else if (mbr_is_vbr) begin part_lba <= 32'd0; sig_ok <= 1'b0; read_sector(32'd0, S_BPB); end
            else begin sig_ok <= 1'b0; read_sector(part_lba, S_BPB); end
        end
        // ---------- BPB → 计算各区起点，开始读根目录 ----------
        S_BPB: begin
            dbg_state <= 4'd2;
            if (!sig_ok || spc == 8'd0) state <= S_ERR;
            else begin
                fat_lba     <= part_lba + rsvd;
                data_lba    <= part_lba + rsvd + nfats * fatsz;
                cur_clus    <= root_clus;
                sec_in_clus <= 8'd0;
                dir_end     <= 1'b0;
                state       <= S_DIR;
            end
        end
        // ---------- 根目录：逐扇区读，簇读完查 FAT ----------
        S_DIR: begin
            dbg_state <= 4'd3;
            if (dir_end || nfound == MAX_IMG) begin
                img_count <= nfound; fidx <= 3'd0; state <= S_FILE;
                cur_clus <= 32'd0; sec_in_clus <= 8'd0; fpos <= 32'd0; file_bad <= 1'b0;
            end else if (sec_in_clus == spc) begin
                fat_ret <= S_DIR;
                read_sector(fat_lba + (cur_clus >> 7), S_FAT);
            end else if (lba_ok) begin
                read_sector(clus_lba + sec_in_clus, S_DIRNXT);
                sec_in_clus <= sec_in_clus + 8'd1;
            end
        end
        S_DIRNXT: state <= S_DIR;
        // ---------- FAT 查表完成：跳到下一簇或结束 ----------
        S_FAT: begin
            if (next_clus >= 32'h0FFFFFF8 || next_clus < 32'd2) begin
                if (fat_ret == S_DIR) dir_end <= 1'b1;
                else fpos <= 32'hFFFFFFFF;               // 文件簇链提前结束
                state <= fat_ret;
            end else begin
                cur_clus    <= next_clus;
                sec_in_clus <= 8'd0;
                state       <= fat_ret;
            end
        end
        // ---------- 逐个文件装载 ----------
        S_FILE: begin
            dbg_state <= 4'd4;
            if (fidx == nfound) begin
                state <= S_DONE;
            end else if (fpos == 32'd0 && sec_in_clus == 8'd0 && cur_clus != f_clus[fidx] && !file_bad) begin
                // 新文件开始
                cur_clus <= f_clus[fidx]; sec_in_clus <= 8'd0;
                cpos <= 2'd0; px_x <= 10'd0; px_row <= 10'd0; hdr_ok <= 1'b0; file_bad <= 1'b0;
            end else if (file_bad || fpos >= f_size[fidx] || px_row == IMG_H) begin
                // 本文件结束
                if (!file_bad && px_row == IMG_H) img_ok[fidx] <= 1'b1;
                fidx <= fidx + 3'd1; fpos <= 32'd0; sec_in_clus <= 8'd0;
                cur_clus <= 32'd0; file_bad <= 1'b0; px_row <= 10'd0;
            end else if (sec_in_clus == spc) begin
                fat_ret <= S_FILE;
                read_sector(fat_lba + (cur_clus >> 7), S_FAT);
            end else if (px_ready && lba_ok) begin
                read_sector(clus_lba + sec_in_clus, S_FNXT);
                sec_in_clus <= sec_in_clus + 8'd1;
            end
        end
        S_FNXT: state <= S_FILE;

        S_DONE: begin dbg_state <= 4'd5; done <= 1'b1; if (start_rise) state <= S_IDLE; end
        S_ERR:  begin dbg_state <= 4'hF; fs_err <= 1'b1; done <= 1'b1; if (start_rise) state <= S_IDLE; end
        default: state <= S_IDLE;
        endcase
    end
end

endmodule
