// 由 gen_songs.py 生成，请勿手改
module aud_song_rom(
    input  wire [1:0]  song,
    input  wire [4:0]  step,
    output reg  [4:0]  note,      // 0=休止，1=C4 … 25=C6
    output reg  [2:0]  len,       // 时值（八分音符个数），0 表示本曲结束、回到开头
    input  wire [4:0]  note_q,
    output reg  [31:0] phase_inc  // DDS 相位增量 = f/48000*2^32
);
always @(*) begin
    note = 5'd0; len = 3'd0;
    case ({song, step})
        // 曲 0: 小星星
        {2'd0, 5'd0}: begin note = 5'd1; len = 3'd2; end
        {2'd0, 5'd1}: begin note = 5'd1; len = 3'd2; end
        {2'd0, 5'd2}: begin note = 5'd8; len = 3'd2; end
        {2'd0, 5'd3}: begin note = 5'd8; len = 3'd2; end
        {2'd0, 5'd4}: begin note = 5'd10; len = 3'd2; end
        {2'd0, 5'd5}: begin note = 5'd10; len = 3'd2; end
        {2'd0, 5'd6}: begin note = 5'd8; len = 3'd4; end
        {2'd0, 5'd7}: begin note = 5'd6; len = 3'd2; end
        {2'd0, 5'd8}: begin note = 5'd6; len = 3'd2; end
        {2'd0, 5'd9}: begin note = 5'd5; len = 3'd2; end
        {2'd0, 5'd10}: begin note = 5'd5; len = 3'd2; end
        {2'd0, 5'd11}: begin note = 5'd3; len = 3'd2; end
        {2'd0, 5'd12}: begin note = 5'd3; len = 3'd2; end
        {2'd0, 5'd13}: begin note = 5'd1; len = 3'd4; end
        {2'd0, 5'd14}: begin note = 5'd0; len = 3'd2; end
        // 曲 1: 欢乐颂
        {2'd1, 5'd0}: begin note = 5'd5; len = 3'd2; end
        {2'd1, 5'd1}: begin note = 5'd5; len = 3'd2; end
        {2'd1, 5'd2}: begin note = 5'd6; len = 3'd2; end
        {2'd1, 5'd3}: begin note = 5'd8; len = 3'd2; end
        {2'd1, 5'd4}: begin note = 5'd8; len = 3'd2; end
        {2'd1, 5'd5}: begin note = 5'd6; len = 3'd2; end
        {2'd1, 5'd6}: begin note = 5'd5; len = 3'd2; end
        {2'd1, 5'd7}: begin note = 5'd3; len = 3'd2; end
        {2'd1, 5'd8}: begin note = 5'd1; len = 3'd2; end
        {2'd1, 5'd9}: begin note = 5'd1; len = 3'd2; end
        {2'd1, 5'd10}: begin note = 5'd3; len = 3'd2; end
        {2'd1, 5'd11}: begin note = 5'd5; len = 3'd2; end
        {2'd1, 5'd12}: begin note = 5'd5; len = 3'd3; end
        {2'd1, 5'd13}: begin note = 5'd3; len = 3'd1; end
        {2'd1, 5'd14}: begin note = 5'd3; len = 3'd4; end
        {2'd1, 5'd15}: begin note = 5'd0; len = 3'd2; end
        // 曲 2: 两只老虎
        {2'd2, 5'd0}: begin note = 5'd1; len = 3'd2; end
        {2'd2, 5'd1}: begin note = 5'd3; len = 3'd2; end
        {2'd2, 5'd2}: begin note = 5'd5; len = 3'd2; end
        {2'd2, 5'd3}: begin note = 5'd1; len = 3'd2; end
        {2'd2, 5'd4}: begin note = 5'd1; len = 3'd2; end
        {2'd2, 5'd5}: begin note = 5'd3; len = 3'd2; end
        {2'd2, 5'd6}: begin note = 5'd5; len = 3'd2; end
        {2'd2, 5'd7}: begin note = 5'd1; len = 3'd2; end
        {2'd2, 5'd8}: begin note = 5'd5; len = 3'd2; end
        {2'd2, 5'd9}: begin note = 5'd6; len = 3'd2; end
        {2'd2, 5'd10}: begin note = 5'd8; len = 3'd4; end
        {2'd2, 5'd11}: begin note = 5'd5; len = 3'd2; end
        {2'd2, 5'd12}: begin note = 5'd6; len = 3'd2; end
        {2'd2, 5'd13}: begin note = 5'd8; len = 3'd4; end
        {2'd2, 5'd14}: begin note = 5'd0; len = 3'd2; end
        // 曲 3: 生日快乐
        {2'd3, 5'd0}: begin note = 5'd8; len = 3'd1; end
        {2'd3, 5'd1}: begin note = 5'd8; len = 3'd1; end
        {2'd3, 5'd2}: begin note = 5'd10; len = 3'd2; end
        {2'd3, 5'd3}: begin note = 5'd8; len = 3'd2; end
        {2'd3, 5'd4}: begin note = 5'd13; len = 3'd2; end
        {2'd3, 5'd5}: begin note = 5'd12; len = 3'd4; end
        {2'd3, 5'd6}: begin note = 5'd8; len = 3'd1; end
        {2'd3, 5'd7}: begin note = 5'd8; len = 3'd1; end
        {2'd3, 5'd8}: begin note = 5'd10; len = 3'd2; end
        {2'd3, 5'd9}: begin note = 5'd8; len = 3'd2; end
        {2'd3, 5'd10}: begin note = 5'd15; len = 3'd2; end
        {2'd3, 5'd11}: begin note = 5'd13; len = 3'd4; end
        {2'd3, 5'd12}: begin note = 5'd0; len = 3'd2; end
        default: begin note = 5'd0; len = 3'd0; end
    endcase
end
always @(*) begin
    case (note_q)
        5'd1: phase_inc = 32'd23409862;
        5'd2: phase_inc = 32'd24801885;
        5'd3: phase_inc = 32'd26276682;
        5'd4: phase_inc = 32'd27839175;
        5'd5: phase_inc = 32'd29494578;
        5'd6: phase_inc = 32'd31248417;
        5'd7: phase_inc = 32'd33106545;
        5'd8: phase_inc = 32'd35075163;
        5'd9: phase_inc = 32'd37160840;
        5'd10: phase_inc = 32'd39370539;
        5'd11: phase_inc = 32'd41711633;
        5'd12: phase_inc = 32'd44191936;
        5'd13: phase_inc = 32'd46819725;
        5'd14: phase_inc = 32'd49603771;
        5'd15: phase_inc = 32'd52553364;
        5'd16: phase_inc = 32'd55678350;
        5'd17: phase_inc = 32'd58989157;
        5'd18: phase_inc = 32'd62496835;
        5'd19: phase_inc = 32'd66213090;
        5'd20: phase_inc = 32'd70150325;
        5'd21: phase_inc = 32'd74321680;
        5'd22: phase_inc = 32'd78741078;
        5'd23: phase_inc = 32'd83423266;
        5'd24: phase_inc = 32'd88383871;
        5'd25: phase_inc = 32'd93639450;
        default: phase_inc = 32'd0;
    endcase
end
endmodule
