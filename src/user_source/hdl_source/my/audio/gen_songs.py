# 生成 aud_song_rom.v：音符相位增量表 + 4 首旋律（每张图一首）
# 修改旋律：编辑下面 SONGS，运行 python gen_songs.py 重新生成
import sys, os
FS = 48000
NAMES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
def note_idx(n):           # 'C4' -> 1 ... 'C6' -> 25；'-' 休止 -> 0
    if n == '-': return 0
    name, octv = n[:-1], int(n[-1])
    return (octv - 4) * 12 + NAMES.index(name) + 1
def freq(i): return 261.6256 * 2 ** ((i - 1) / 12)
# 每项 (音符, 时值[八分音符个数])
SONGS = [
  ("小星星", [('C4',2),('C4',2),('G4',2),('G4',2),('A4',2),('A4',2),('G4',4),
              ('F4',2),('F4',2),('E4',2),('E4',2),('D4',2),('D4',2),('C4',4)]),
  ("欢乐颂", [('E4',2),('E4',2),('F4',2),('G4',2),('G4',2),('F4',2),('E4',2),('D4',2),
              ('C4',2),('C4',2),('D4',2),('E4',2),('E4',3),('D4',1),('D4',4)]),
  ("两只老虎", [('C4',2),('D4',2),('E4',2),('C4',2),('C4',2),('D4',2),('E4',2),('C4',2),
                ('E4',2),('F4',2),('G4',4),('E4',2),('F4',2),('G4',4)]),
  ("生日快乐", [('G4',1),('G4',1),('A4',2),('G4',2),('C5',2),('B4',4),
                ('G4',1),('G4',1),('A4',2),('G4',2),('D5',2),('C5',4)]),
]
STEPS = 32
L = []
L.append("// 由 gen_songs.py 生成，请勿手改")
L.append("module aud_song_rom(")
L.append("    input  wire [1:0]  song,")
L.append("    input  wire [4:0]  step,")
L.append("    output reg  [4:0]  note,      // 0=休止，1=C4 … 25=C6")
L.append("    output reg  [2:0]  len,       // 时值（八分音符个数），0 表示本曲结束、回到开头")
L.append("    input  wire [4:0]  note_q,")
L.append("    output reg  [31:0] phase_inc  // DDS 相位增量 = f/48000*2^32")
L.append(");")
L.append("always @(*) begin")
L.append("    note = 5'd0; len = 3'd0;")
L.append("    case ({song, step})")
for si, (title, seq) in enumerate(SONGS):
    L.append(f"        // 曲 {si}: {title}")
    for k, (n, ln) in enumerate(seq + [('-', 2)]):     # 结尾留一拍空白
        L.append(f"        {{2'd{si}, 5'd{k}}}: begin note = 5'd{note_idx(n)}; len = 3'd{ln}; end")
L.append("        default: begin note = 5'd0; len = 3'd0; end")
L.append("    endcase")
L.append("end")
L.append("always @(*) begin")
L.append("    case (note_q)")
for i in range(1, 26):
    L.append(f"        5'd{i}: phase_inc = 32'd{int(round(freq(i) / FS * 2**32))};")
L.append("        default: phase_inc = 32'd0;")
L.append("    endcase")
L.append("end")
L.append("endmodule")
out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "aud_song_rom.v")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("written", out)
