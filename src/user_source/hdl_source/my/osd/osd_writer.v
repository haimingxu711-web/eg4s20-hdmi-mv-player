// 由 gen_osd.py 生成，请修改 gen_osd.py 后重新生成
// 持续把状态栏（第 0 行）和字幕（第 28 行）写入 osd_layer 的字符 RAM
module osd_writer(
    input  wire              clk,
    input  wire              rst,
    input  wire              status_on,      // 显示状态栏
    input  wire              sub_on,         // 显示字幕
    input  wire              set_mode,
    input  wire [1:0]        item,
    input  wire [1:0]        cur,
    input  wire [2:0]        img_count,
    input  wire [1:0]        mode,
    input  wire [3:0]        period_sec,
    input  wire signed [3:0] brightness,
    input  wire [3:0]        contrast,
    input  wire [3:0]        volume,
    input  wire              fade_on,
    output reg               wr_en,
    output reg  [11:0]       wr_addr,
    output reg  [6:0]        wr_char
);
reg [6:0] col;
reg       row_sel;                 // 0 = 状态栏，1 = 字幕
reg [6:0] st_c, sb_c;
always @(*) begin
    case (col)
        7'd0: st_c = 7'd32;
        7'd1: st_c = 7'd73;
        7'd2: st_c = 7'd77;
        7'd3: st_c = 7'd71;
        7'd4: st_c = 7'd32;
        7'd5: st_c = (7'd48 + {5'd0, cur} + 7'd1);
        7'd6: st_c = 7'd47;
        7'd7: st_c = (7'd48 + {4'd0, img_count});
        7'd8: st_c = 7'd32;
        7'd9: st_c = 7'd32;
        7'd10: st_c = 7'd77;
        7'd11: st_c = 7'd79;
        7'd12: st_c = 7'd68;
        7'd13: st_c = 7'd69;
        7'd14: st_c = 7'd32;
        7'd15: st_c = (mode == 2'd2 ? 7'd32 : mode == 2'd1 ? 7'd65 : 7'd77);
        7'd16: st_c = (mode == 2'd2 ? 7'd77 : mode == 2'd1 ? 7'd85 : 7'd65);
        7'd17: st_c = (mode == 2'd2 ? 7'd86 : mode == 2'd1 ? 7'd84 : 7'd78);
        7'd18: st_c = 7'd32;
        7'd19: st_c = ((set_mode && item == 2'd3) ? 7'd62 : 7'd32);
        7'd20: st_c = 7'd80;
        7'd21: st_c = 7'd69;
        7'd22: st_c = 7'd82;
        7'd23: st_c = 7'd73;
        7'd24: st_c = 7'd79;
        7'd25: st_c = 7'd68;
        7'd26: st_c = 7'd32;
        7'd27: st_c = (7'd48 + {3'd0, period_sec});
        7'd28: st_c = 7'd115;
        7'd29: st_c = 7'd32;
        7'd30: st_c = ((set_mode && item == 2'd0) ? 7'd62 : 7'd32);
        7'd31: st_c = 7'd66;
        7'd32: st_c = 7'd82;
        7'd33: st_c = 7'd73;
        7'd34: st_c = 7'd71;
        7'd35: st_c = 7'd72;
        7'd36: st_c = 7'd84;
        7'd37: st_c = 7'd32;
        7'd38: st_c = (brightness[3] ? 7'd45 : 7'd43);
        7'd39: st_c = (7'd48 + {3'd0, (brightness[3] ? -brightness : brightness)});
        7'd40: st_c = 7'd32;
        7'd41: st_c = ((set_mode && item == 2'd1) ? 7'd62 : 7'd32);
        7'd42: st_c = 7'd67;
        7'd43: st_c = 7'd79;
        7'd44: st_c = 7'd78;
        7'd45: st_c = 7'd84;
        7'd46: st_c = 7'd82;
        7'd47: st_c = 7'd65;
        7'd48: st_c = 7'd83;
        7'd49: st_c = 7'd84;
        7'd50: st_c = 7'd32;
        7'd51: st_c = (7'd48 + (contrast >= 4'd10 ? 7'd1 : 7'd0));
        7'd52: st_c = (7'd48 + {3'd0, (contrast >= 4'd10 ? contrast - 4'd10 : contrast)});
        7'd53: st_c = 7'd32;
        7'd54: st_c = ((set_mode && item == 2'd2) ? 7'd62 : 7'd32);
        7'd55: st_c = 7'd86;
        7'd56: st_c = 7'd79;
        7'd57: st_c = 7'd76;
        7'd58: st_c = 7'd85;
        7'd59: st_c = 7'd77;
        7'd60: st_c = 7'd69;
        7'd61: st_c = 7'd32;
        7'd62: st_c = (7'd48 + (volume >= 4'd10 ? 7'd1 : 7'd0));
        7'd63: st_c = (7'd48 + {3'd0, (volume >= 4'd10 ? volume - 4'd10 : volume)});
        7'd64: st_c = 7'd32;
        7'd65: st_c = 7'd32;
        7'd66: st_c = 7'd70;
        7'd67: st_c = 7'd65;
        7'd68: st_c = 7'd68;
        7'd69: st_c = 7'd69;
        7'd70: st_c = 7'd32;
        7'd71: st_c = (fade_on ? 7'd32 : 7'd79);
        7'd72: st_c = (fade_on ? 7'd79 : 7'd70);
        7'd73: st_c = (fade_on ? 7'd78 : 7'd70);
        default: st_c = 7'd32;
    endcase
    case (col)
        7'd0: sb_c = 7'd32;
        7'd1: sb_c = 7'd32;
        7'd2: sb_c = 7'd65;
        7'd3: sb_c = 7'd110;
        7'd4: sb_c = 7'd108;
        7'd5: sb_c = 7'd111;
        7'd6: sb_c = 7'd103;
        7'd7: sb_c = 7'd105;
        7'd8: sb_c = 7'd99;
        7'd9: sb_c = 7'd32;
        7'd10: sb_c = 7'd69;
        7'd11: sb_c = 7'd71;
        7'd12: sb_c = 7'd52;
        7'd13: sb_c = 7'd83;
        7'd14: sb_c = 7'd50;
        7'd15: sb_c = 7'd48;
        7'd16: sb_c = 7'd32;
        7'd17: sb_c = 7'd72;
        7'd18: sb_c = 7'd68;
        7'd19: sb_c = 7'd77;
        7'd20: sb_c = 7'd73;
        7'd21: sb_c = 7'd32;
        7'd22: sb_c = 7'd77;
        7'd23: sb_c = 7'd117;
        7'd24: sb_c = 7'd108;
        7'd25: sb_c = 7'd116;
        7'd26: sb_c = 7'd105;
        7'd27: sb_c = 7'd109;
        7'd28: sb_c = 7'd101;
        7'd29: sb_c = 7'd100;
        7'd30: sb_c = 7'd105;
        7'd31: sb_c = 7'd97;
        7'd32: sb_c = 7'd32;
        7'd33: sb_c = 7'd80;
        7'd34: sb_c = 7'd108;
        7'd35: sb_c = 7'd97;
        7'd36: sb_c = 7'd121;
        7'd37: sb_c = 7'd101;
        7'd38: sb_c = 7'd114;
        7'd39: sb_c = 7'd32;
        7'd40: sb_c = 7'd32;
        7'd41: sb_c = 7'd42;
        7'd42: sb_c = 7'd42;
        7'd43: sb_c = 7'd42;
        7'd44: sb_c = 7'd32;
        7'd45: sb_c = 7'd32;
        7'd46: sb_c = 7'd70;
        7'd47: sb_c = 7'd65;
        7'd48: sb_c = 7'd84;
        7'd49: sb_c = 7'd51;
        7'd50: sb_c = 7'd50;
        7'd51: sb_c = 7'd32;
        7'd52: sb_c = 7'd43;
        7'd53: sb_c = 7'd32;
        7'd54: sb_c = 7'd83;
        7'd55: sb_c = 7'd68;
        7'd56: sb_c = 7'd82;
        7'd57: sb_c = 7'd65;
        7'd58: sb_c = 7'd77;
        7'd59: sb_c = 7'd32;
        7'd60: sb_c = 7'd112;
        7'd61: sb_c = 7'd114;
        7'd62: sb_c = 7'd101;
        7'd63: sb_c = 7'd108;
        7'd64: sb_c = 7'd111;
        7'd65: sb_c = 7'd97;
        7'd66: sb_c = 7'd100;
        7'd67: sb_c = 7'd32;
        7'd68: sb_c = 7'd43;
        7'd69: sb_c = 7'd32;
        7'd70: sb_c = 7'd68;
        7'd71: sb_c = 7'd68;
        7'd72: sb_c = 7'd83;
        7'd73: sb_c = 7'd32;
        7'd74: sb_c = 7'd109;
        7'd75: sb_c = 7'd117;
        7'd76: sb_c = 7'd115;
        7'd77: sb_c = 7'd105;
        7'd78: sb_c = 7'd99;
        7'd79: sb_c = 7'd32;
        default: sb_c = 7'd32;
    endcase
end
// 复位后先把整个字符 RAM（2400 格）清成透明(0)，再循环刷新两行
reg [11:0] clr_addr;
reg        clearing;
always @(posedge clk or posedge rst) begin
    if (rst) begin col <= 7'd0; row_sel <= 1'b0; wr_en <= 1'b0; wr_addr <= 12'd0; wr_char <= 7'd32;
                   clr_addr <= 12'd0; clearing <= 1'b1; end
    else if (clearing) begin
        wr_en <= 1'b1; wr_addr <= clr_addr; wr_char <= 7'd0;
        if (clr_addr == 12'd2399) clearing <= 1'b0; else clr_addr <= clr_addr + 12'd1;
    end else begin
        wr_en   <= 1'b1;
        wr_addr <= row_sel ? (12'd28 * 12'd80 + col) : {5'd0, col};
        wr_char <= row_sel ? (sub_on ? sb_c : 7'd0) : (status_on ? st_c : 7'd0);   // 0 = 透明
        if (col == 7'd79) begin col <= 7'd0; row_sel <= ~row_sel; end
        else col <= col + 7'd1;
    end
end
endmodule
