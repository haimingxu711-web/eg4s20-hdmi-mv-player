// =====================================================================
// 6 位数码管动态扫描（位选、段选均低有效；需 SW6 拨上切到数码管）
//   d0..d5：每位 5 位编码，0~15 = 十六进制数字，16 = 熄灭，17 = '-'，18 = 'P'，19 = 'L'
//   d0 为最左位
// =====================================================================
module seg_disp #(
    parameter integer CLK_HZ = 25_000_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [4:0] d0, d1, d2, d3, d4, d5,
    output reg  [5:0] seg_sel,
    output reg  [7:0] seg_data
);

localparam integer TICK = CLK_HZ / 6000;      // 每位约 1ms

reg [15:0] cnt;
reg [2:0]  pos;
reg [4:0]  code;

function [6:0] dec(input [4:0] c);           // {g,f,e,d,c,b,a}，0 = 点亮
    case (c)
        5'd0:  dec = 7'b1000000;  5'd1:  dec = 7'b1111001;
        5'd2:  dec = 7'b0100100;  5'd3:  dec = 7'b0110000;
        5'd4:  dec = 7'b0011001;  5'd5:  dec = 7'b0010010;
        5'd6:  dec = 7'b0000010;  5'd7:  dec = 7'b1111000;
        5'd8:  dec = 7'b0000000;  5'd9:  dec = 7'b0010000;
        5'd10: dec = 7'b0001000;  5'd11: dec = 7'b0000011;
        5'd12: dec = 7'b1000110;  5'd13: dec = 7'b0100001;
        5'd14: dec = 7'b0000110;  5'd15: dec = 7'b0001110;
        5'd17: dec = 7'b0111111;  5'd18: dec = 7'b0001100;
        5'd19: dec = 7'b1000111;
        default: dec = 7'b1111111;
    endcase
endfunction

always @(*) begin
    case (pos)
        3'd0: code = d0; 3'd1: code = d1; 3'd2: code = d2;
        3'd3: code = d3; 3'd4: code = d4; default: code = d5;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cnt <= 16'd0; pos <= 3'd0; seg_sel <= 6'b111111; seg_data <= 8'hFF;
    end else begin
        if (cnt == TICK - 1) begin
            cnt <= 16'd0;
            pos <= (pos == 3'd5) ? 3'd0 : pos + 3'd1;
        end else
            cnt <= cnt + 16'd1;
        seg_sel  <= ~(6'b000001 << pos);
        seg_data <= {1'b1, dec(code)};
    end
end

endmodule
