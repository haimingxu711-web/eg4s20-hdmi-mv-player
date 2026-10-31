# 生成测试主题素材（公版旋律《小星星》+ 自编占位歌词）→ D:\FPGA\contest\theme_test
# 两条轨道：轨道 1 伴奏和弦（用来测试自动挑主旋律），轨道 2 主旋律；前奏 2 小节只有伴奏
import os, struct
OUT = r"D:\FPGA\contest\theme_test"
os.makedirs(OUT, exist_ok=True)
DIV, BPM = 480, 100
def vlq(v):
    b = [v & 0x7F]; v >>= 7
    while v: b.insert(0, (v & 0x7F) | 0x80); v >>= 7
    return bytes(b)
def track(events):                      # events: (tick, bytes)
    events.sort(key=lambda e: e[0]); out, last = b"", 0
    for t, data in events: out += vlq(t - last) + data; last = t
    out += vlq(0) + b"\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(out)) + out
N = dict(C=60, D=62, E=64, F=65, G=67, A=69, B=71)
phr = ["CCGGAAG", "FFEEDDC", "GGFFEED", "GGFFEED", "CCGGAAG", "FFEEDDCC"]
mel = [(b"\xFF\x03" + vlq(6) + b"Melody", 0)]
mel = [(0, b"\xFF\x03" + vlq(6) + b"Melody")]
t = 8 * DIV                              # 前奏 2 小节
for p in phr:
    lens = [1] * (len(p) - 1) + [2] if len(p) == 7 else [1] * 6 + [1, 1]
    for c, l in zip(p, lens):
        mel.append((t, bytes([0x90, N[c], 90]))); mel.append((t + l * DIV - 10, bytes([0x80, N[c], 0]))); t += l * DIV
acc = [(0, b"\xFF\x51\x03" + (60_000_000 // BPM).to_bytes(3, "big")), (0, b"\xFF\x03" + vlq(5) + b"Piano")]
for bar in range(t // (4 * DIV) + 1):
    for k, n in enumerate([48, 52, 55]):
        acc.append((bar * 4 * DIV + k * DIV, bytes([0x91, n, 60]))); acc.append((bar * 4 * DIV + k * DIV + 3 * DIV, bytes([0x81, n, 0])))
data = b"MThd" + struct.pack(">IHHH", 6, 1, 2, DIV) + track(acc) + track(mel)
open(os.path.join(OUT, "song.mid"), "wb").write(data)
beat = 60 / BPM
L = ["TITLE 四季小星星 - 测试", "# 测试用自编歌词"]
txt = ["春风吹过小河边", "柳枝轻摇绿满天", "[2] 夏日蝉鸣荷花香", "[3:擦除] 秋叶金黄落山间", "冬雪飘飘盖田野", "[4:圆形] 四季轮回又一年_"]
for i, s in enumerate(txt):
    L.append(f"@{(8 + 8 * i) * beat:.2f} {s}")
open(os.path.join(OUT, "lyrics.txt"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print("ok", OUT)
