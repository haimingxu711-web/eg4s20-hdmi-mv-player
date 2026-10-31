"""
主题素材生成器：MIDI + 歌词 → 乐谱表 / 歌词表 / 汉字字库（.mif 给 TD 综合，.hex 给仿真）
换歌只改下面“用户配置区”，然后运行：  python gen_theme.py

歌词 lyrics.txt 写法（UTF-8，一行一句）：
    TITLE 歌名 - 原唱              第一行可选：歌名，前奏时显示
    @12.35 第一句歌词              @秒数 = 这句在 MIDI 时间轴上的开始时间（没写就接着上一句往后排）
    @15.80 [2] 第二句              [n] = 从这句开始切到第 n 张图；[n:样式] 指定转场样式（溶解/经白/经黑/淡入）
    爱__                           字后面每个 _ 表示这个字多唱一个音（拖腔）
    # 注释
也支持 LRC（[mm:ss.xx]歌词）和 .kar 卡拉OK 文件自带的逐字歌词（没有 lyrics.txt 时自动用）。
"""
import os, sys, struct, re, wave

# ======================= 用户配置区 =======================
THEME_DIR    = r"D:\FPGA\contest\theme"
MIDI_FILE    = "此生不换.mid"            # 或 song.kar
LYRICS_FILE  = "lyrics.txt"          # 不存在则用 MIDI 里的歌词事件
MELODY_TRACK = None                  # None = 自动；否则 (轨道号, 通道号)，运行一次看打印的列表
MEL_MIN_PITCH = 63                   # 钢琴左右手在同一轨时：只在这个音高以上找旋律（如 56 = G#3）
MEL_MIN_VEL   = 66                   # 只取力度 ≥ 这个值的音（演奏版 MIDI 主旋律通常弹得更响，如 68）
TRANSPOSE    = None                  # None = 自动按八度移到 C5 附近；或半音数
OFFSET_SEC   = 0.0                   # 歌词时间整体偏移（LRC 和 MIDI 对不齐时调）
START_SEC    = 12.9                  # 截取片段（MIDI 时间，秒）
END_SEC      = 110.5
NUM_IMAGES   = 4                     # 歌词里没写 [n] 时，按句数均匀分配切图点
TRANS_LEAD   = 0.7                   # 切图提前量（秒）= MV 转场时长(1.42s)的一半：转场中点对准这句第一个字
LOOP_STYLE   = "经黑"                # 唱完一遍回到开头（图 1）时的转场
DEFAULT_STYLE = "溶解"               # 没写样式时用
FONT         = r"C:\Windows\Fonts\msyhbd.ttc"
# =========================================================

FS = 48000
MAX_LINE = 22                        # 一行最多字数（24 像素一个字）
OUT = os.path.dirname(os.path.abspath(__file__))
# MV 转场样式（硬件 player 映射到 fx_fade 的 4~7：亮度溶解 / 经白 / 经黑 / 长淡化）
STYLE_NAMES = {"溶解": 0, "经白": 1, "白": 1, "经黑": 2, "黑": 2, "淡入": 3, "淡入淡出": 3}

# ---------------------------------------------------------------- MIDI 解析
def vlq(d, i):
    v = 0
    while True:
        b = d[i]; i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80: return v, i

def parse_midi(path):
    d = open(path, "rb").read()
    assert d[:4] == b"MThd", "不是 MIDI 文件"
    hl = int.from_bytes(d[4:8], "big")
    fmt, ntrk, div = struct.unpack(">HHH", d[8:14])
    assert not div & 0x8000, "不支持 SMPTE 时间格式"
    i, tracks = 8 + hl, []
    while len(tracks) < ntrk and i < len(d):
        tag, ln = d[i:i+4], int.from_bytes(d[i+4:i+8], "big")
        if tag != b"MTrk": i += 8 + ln; continue
        j, end, tick, run, ev = i + 8, i + 8 + ln, 0, 0, []
        while j < end:
            dt, j = vlq(d, j); tick += dt
            b = d[j]
            if b == 0xFF:
                typ = d[j+1]; l, k = vlq(d, j + 2)
                ev.append((tick, "meta", typ, d[k:k+l])); j = k + l
            elif b in (0xF0, 0xF7):
                l, k = vlq(d, j + 1); j = k + l
            else:
                if b & 0x80: run = b; j += 1
                n = 1 if run & 0xF0 in (0xC0, 0xD0) else 2
                ev.append((tick, "ch", run, d[j:j+n])); j += n
        tracks.append(ev); i = end
    return div, tracks

def tempo_map(div, tracks):
    tm = sorted((t, int.from_bytes(x, "big")) for tr in tracks for (t, k, typ, x) in tr if k == "meta" and typ == 0x51)
    pts, last_t, last_s, us = [], 0, 0.0, 500000
    for t, u in tm:
        last_s += (t - last_t) * us / div / 1e6; last_t = t; us = u
        pts.append((t, last_s, u))
    def sec(t):
        bt, bs, bu = 0, 0.0, 500000
        for (pt, ps, pu) in pts:
            if pt > t: break
            bt, bs, bu = pt, ps, pu
        return bs + (t - bt) * bu / div / 1e6
    return sec

def decode(b):
    for enc in ("utf-8", "gbk"):
        try: return b.decode(enc)
        except UnicodeDecodeError: pass
    return b.decode("latin-1")

def collect_notes(div, tracks, sec):
    groups = {}                                  # (轨道, 通道) -> [(开始秒, 结束秒, 音高)]
    names = {}
    for ti, tr in enumerate(tracks):
        on, vel = {}, {}
        for (t, k, st, x) in tr:
            if k == "meta" and st == 0x03: names[ti] = decode(x)
            if k != "ch": continue
            hi, ch = st & 0xF0, st & 0x0F
            if hi == 0x90 and x[1] > 0:
                on.setdefault((ch, x[0]), []).append(t)
                vel[(ch, x[0], t)] = x[1]
            elif hi == 0x80 or (hi == 0x90 and x[1] == 0):
                lst = on.get((ch, x[0]))
                if lst:
                    t0 = lst.pop(0)
                    if x[0] >= MEL_MIN_PITCH and vel.get((ch, x[0], t0), 127) >= MEL_MIN_VEL:
                        groups.setdefault((ti, ch), []).append((sec(t0), sec(t), x[0]))
    for v in groups.values(): v.sort()
    return groups, names

def mono_ratio(ns):
    ov = sum(1 for a, b in zip(ns, ns[1:]) if b[0] < a[1] - 0.02)
    return 1 - ov / max(1, len(ns))

def pick_melody(groups, names):
    print("轨道/通道 列表：")
    best, best_score = None, -1
    for (ti, ch), ns in sorted(groups.items()):
        ps = [p for _, _, p in ns]
        mr = mono_ratio(ns)
        nm = names.get(ti, "")
        print(f"  ({ti:2d},{ch:2d}) {nm[:20]:20s} 音符 {len(ns):4d}  音域 {min(ps)}~{max(ps)}  单音比例 {mr:.2f}")
        if ch == 9 or len(ns) < 20: continue
        score = len(ns) * mr * mr * (sum(ps) / len(ps))
        if re.search(r"melod|vocal|voice|lead|主旋律|人声|旋律", nm, re.I): score *= 4
        if score > best_score: best, best_score = (ti, ch), score
    return best

def skyline(ns):
    ns = sorted(ns, key=lambda n: (n[0], -n[2]))
    out = []
    for s, e, p in ns:
        if out and s < out[-1][1]:
            if s - out[-1][0] < 0.03:                   # 和弦：保留最高音；八度叠奏取低八度（音色不刺耳）
                if out[-1][2] - p == 12: out[-1] = (out[-1][0], max(out[-1][1], e), p)
                continue
            out[-1] = (out[-1][0], s, out[-1][2])       # 截断前一个音
        out.append((s, e, p))
    return [n for n in out if n[1] - n[0] >= 0.03]

# ---------------------------------------------------------------- 歌词
def parse_time(s):
    if ":" in s:
        m, x = s.split(":"); return int(m) * 60 + float(x)
    return float(s)

def read_lyrics_txt(path):
    """返回 title, [(时间或None, [(字, 音符数)], 切图(图号,样式)或None, 结束时间或None)]"""
    title, lines = None, []
    for raw in open(path, encoding="utf-8-sig"):
        s = raw.strip()
        if not s or s.startswith("#"): continue
        if s.upper().startswith("TITLE"): title = s[5:].strip(); continue
        t, img, te = None, None, None
        m = re.match(r"^\[(\d+):(\d+(?:\.\d+)?)\]", s)          # LRC
        if m:
            t = int(m.group(1)) * 60 + float(m.group(2)); s = s[m.end():].strip()
        m = re.match(r"^@([\d:.]+)(?:-([\d:.]+))?\s*", s)       # @开始 或 @开始-结束（时间窗）
        if m:
            t = parse_time(m.group(1)); s = s[m.end():]
            if m.group(2): te = parse_time(m.group(2)) + OFFSET_SEC
        m = re.match(r"^\[(\d)(?::(\S+?))?\]\s*", s)
        if m:
            st = m.group(2)
            img = (int(m.group(1)) - 1, None if st is None else STYLE_NAMES.get(st, int(st) if st.isdigit() else 0))
            s = s[m.end():]
        chars = []
        for c in s:
            if c.isspace():                                       # 空格保留为空白字位（不占音符）
                if chars and chars[-1][0] != " ": chars.append([" ", 0])
            elif c == "_" and chars: chars[-1][1] += 1
            elif c not in "，。、！？,.!?;；：:\"“”'‘’（）()…—-": chars.append([c, 1])
        while chars and chars[-1][0] == " ": chars.pop()
        if chars: lines.append((None if t is None else t + OFFSET_SEC, [tuple(c) for c in chars], img, te))
    return title, lines

def read_kar(tracks, sec):
    best = []
    for tr in tracks:
        ev = [(t, x) for (t, k, typ, x) in tr if k == "meta" and typ in (0x01, 0x05)]
        ev = [(t, decode(x)) for t, x in ev]
        ev = [(t, s) for t, s in ev if not s.startswith("@")]
        if len(ev) > len(best): best = ev
    lines, cur, title = [], [], None
    for t, s in best:
        if s.startswith(("\\", "/")) or "\r" in s or "\n" in s:
            if cur: lines.append(cur); cur = []
            s = s.lstrip("\\/").strip()
        cs = [c for c in s if not c.isspace()]
        for k, c in enumerate(cs): cur.append((sec(t) + k * 0.01, c))
    if cur: lines.append(cur)
    out = []
    for ln in lines:
        out.append((ln[0][0], [(c, 1) for _, c in ln], None, [tt for tt, _ in ln]))
    return title, out

# ---------------------------------------------------------------- 主流程
def main():
    midi = os.path.join(THEME_DIR, MIDI_FILE)
    div, tracks = parse_midi(midi)
    sec = tempo_map(div, tracks)
    groups, names = collect_notes(div, tracks, sec)
    mel = MELODY_TRACK or pick_melody(groups, names)
    print("主旋律：", mel)
    notes = skyline(groups[mel])
    # 截取片段
    end_sec = END_SEC if END_SEC is not None else 1e9
    notes = [(s - START_SEC, min(e, end_sec) - START_SEC, p) for s, e, p in notes if START_SEC <= s < end_sec]
    # 移调
    ps = sorted(p for _, _, p in notes)
    tr = TRANSPOSE if TRANSPOSE is not None else 12 * round((74 - ps[len(ps) // 2]) / 12)
    notes = [[s, e, max(1, min(127, p + tr)), 0, 0] for s, e, p in notes]     # [开始, 结束, 音高, tie, hold]
    print(f"音符 {len(notes)}，移调 {tr:+d}，音域 {min(n[2] for n in notes)}~{max(n[2] for n in notes)}")

    # ---- 歌词读取 ----
    lp = os.path.join(THEME_DIR, LYRICS_FILE) if LYRICS_FILE else ""
    char_times = None
    if lp and os.path.exists(lp):
        title, lyr = read_lyrics_txt(lp)
        lyr = [(None if t is None else t - START_SEC, cs, img, None if te is None else te - START_SEC) for t, cs, img, te in lyr]
    else:
        title, k = read_kar(tracks, sec)
        lyr = [(t - START_SEC, cs, None, None) for t, cs, _, _ in k]
        char_times = [[tt - START_SEC for tt in ts] for *_, ts in k]
    lyr_idx = [i for i, (t, cs, img, te) in enumerate(lyr) if t is None or t > -0.2]
    # 时间窗内音符比字少：把最长的音拆成两段连音（tie，听起来不变），直到够数
    def window(t, te): return [i for i, n in enumerate(notes) if t - 0.05 <= n[0] < te]
    for i in lyr_idx:
        t, cs, img, te = lyr[i]
        if t is None or te is None: continue
        need = sum(n for _, n in cs)
        idx = window(t, te)
        while idx and len(idx) < need:
            k = max(idx, key=lambda j: notes[j][1] - notes[j][0])
            s0, e0, p0, tie0, hold0 = notes[k]
            m = (s0 + e0) / 2
            notes[k] = [s0, m, p0, tie0, 1]
            notes.insert(k + 1, [m, e0, p0, 1, hold0])
            idx = window(t, te)
    lyr = [lyr[i] for i in lyr_idx]
    if char_times: char_times = [char_times[i] for i in lyr_idx]

    # ---- 字 → 音符对齐 ----
    starts = [n[0] for n in notes]
    def nearest(t, lo):
        best = None
        for i in range(lo, len(notes)):
            if best is None or abs(starts[i] - t) < abs(starts[best] - t): best = i
            if starts[i] > t + 1.0: break
        return best
    aligned = []                      # 每句：[(字, [音符号...])]
    pos, warn = 0, []
    for li, (t, cs, img, te) in enumerate(lyr):
        if pos >= len(notes): warn.append(f"第 {li+1} 句没有音符可对齐"); break
        if char_times:
            out = []
            for ci, (c, _) in enumerate(cs):
                k = nearest(char_times[li][ci], pos); out.append((c, [k])); pos = k + 1
        elif te is not None:
            # 有时间窗：窗内音符按顺序一字一音（_ 多占），多出来的音并给最后一个字（拖腔）
            idx = window(t, te)
            out, q = [], 0
            for c, n in cs:
                if n == 0: out.append((c, [])); continue
                ks = idx[q:q + n]
                if not ks: warn.append(f"第 {li+1} 句“{c}”起音符不够"); break
                out.append((c, ks)); q += n
            if out and q < len(idx): out[-1] = (out[-1][0], out[-1][1] + idx[q:])
            if idx: pos = idx[-1] + 1
        else:
            if t is not None: pos = nearest(t, pos)
            out = []
            for c, n in cs:
                if n == 0: out.append((c, [])); continue
                ks = list(range(pos, min(pos + n, len(notes))))
                if not ks: warn.append(f"第 {li+1} 句“{c}”起音符不够"); break
                out.append((c, ks)); pos = ks[-1] + 1
            nxt = next((x[0] for x in lyr[li+1:] if x[0] is not None), None)
            if nxt is not None and pos < len(notes) and starts[pos] < nxt - 0.3 and starts[pos] - notes[pos-1][1] < 0.1:
                warn.append(f"第 {li+1} 句后面到下一句之间还有音符没对上字（{starts[pos]:.2f}s），检查字数或加 _")
        aligned.append((out, img))
    for w in warn: print("  [注意]", w)

    # ---- 拆长句 ----
    lines = []                        # (字列表[(字, 音符号们)], 切图)
    for out, img in aligned:
        if not out: continue
        while len(out) > MAX_LINE:
            h = (len(out) + 1) // 2
            lines.append((out[:h], img)); out, img = out[h:], None
        lines.append((out, img))

    # ---- 字形表 ----
    glyph_chars = []
    def gid(c):
        if c not in glyph_chars: glyph_chars.append(c)
        return glyph_chars.index(c)
    all_chars = []                    # 全局字序：(字形号)
    line_tab = []                     # (标题?, 字数, 首字序号)
    if title:
        tt = [c for c in title if not c.isspace()][:MAX_LINE]
        line_tab.append((1, len(tt), 0)); all_chars += [gid(c) for c in tt]
    first_lyric_chr = len(all_chars)
    char_first_note, char_span, line_first_note = [], {}, []     # [(全局字号, 首音符)], {全局字号: (起, 止)}
    for out, _ in lines:
        line_tab.append((0, len(out), len(all_chars)))
        line_first_note.append(out[0][1][0])
        for c, ks in out:
            if ks:
                char_first_note.append((len(all_chars), ks[0]))
                char_span[len(all_chars)] = (notes[ks[0]][0], notes[ks[-1]][1])
            all_chars.append(gid(c))
    assert len(glyph_chars) <= 256, f"不同的字 {len(glyph_chars)} 个，超过 256"
    assert len(all_chars) <= 1024 and len(line_tab) <= 256
    print(f"歌词 {len(lines)} 句，{len(all_chars)} 字，不同的字 {len(glyph_chars)} 个")

    # ---- 切图点 ----
    markers = [(0.0, 0, STYLE_NAMES[LOOP_STYLE])]   # (时间, 图号, 样式)；事件 0 = 循环回开头
    has_img = any(img for _, img in lines)
    for li, (out, img) in enumerate(lines):
        t0 = notes[out[0][1][0]][0]
        if has_img and img:
            markers.append((t0, img[0], img[1]))
    if not has_img and NUM_IMAGES > 1 and lines:
        for k in range(1, NUM_IMAGES):
            li = round(k * len(lines) / NUM_IMAGES)
            markers.append((notes[lines[li][0][0][1][0]][0], k, None))
    mk = []
    for t, im, st in markers:
        if st is None: st = STYLE_NAMES[DEFAULT_STYLE]
        mk.append((max(0.0, t - (TRANS_LEAD if im else 0)), im, st))

    # ---- 事件表（音符 + 休止）----
    ev = []                           # [开始采样, 结束采样, 音高, 对应音符号或 None]
    tcur = 0
    for k, (s, e, p, ntie, nhold) in enumerate(notes):
        ss, ee = round(s * FS), round(e * FS)
        if ss > tcur + 240: ev.append([tcur, ss, 0, None, 0, 0])
        elif ev and ss > tcur: ev[-1][1] = ss
        ss = max(ss, tcur)
        ev.append([ss, max(ee, ss + 480), p, k, ntie, nhold]); tcur = ev[-1][1]
    ev.append([tcur, tcur + FS, 0, None, 0, 0])      # 结尾留 1 秒空白再循环
    k = 0
    while k < len(ev):                               # 时长字段 20 位（≤21 秒），过长的休止拆开
        if ev[k][1] - ev[k][0] > 20 * FS:
            ev.insert(k + 1, [ev[k][0] + 20 * FS, ev[k][1], 0, None, 0, 0]); ev[k][1] = ev[k][0] + 20 * FS
        k += 1
    # 切图点落在一个音中间时，把这个音拆成两段：前段 hold（不释放），后段 tie（不重新起音），听起来不变
    for t, im, st in mk:
        ts = round(t * FS)
        for i, e in enumerate(ev):
            if e[0] + 2400 < ts < e[1] - 2400:
                lg = 1 if e[2] else 0
                ev.insert(i + 1, [ts, e[1], e[2], None, lg, e[5]]); e[1] = ts; e[5] = lg
                break
    assert len(ev) <= 1024, f"事件 {len(ev)} 个超过 1024，请截短片段"
    note2ev = {e[3]: i for i, e in enumerate(ev) if e[3] is not None}
    chr_ev = {note2ev[n]: g for g, n in char_first_note}
    line_ev = {note2ev[n]: l + (1 if title else 0) for l, n in enumerate(line_first_note)}
    ev_img = {}
    for t, im, st in mk:
        i = min(range(len(ev)), key=lambda i: abs(ev[i][0] - t * FS))
        ev_img[i] = (im, st)
    ev_img[0] = ev_img.get(0, (0, STYLE_NAMES[LOOP_STYLE]))

    words, S, line = [], first_lyric_chr, 0
    timeline = []
    for i, (ss, ee, p, k, tie, hold) in enumerate(ev):
        cs = i in chr_ev
        if cs: S = chr_ev[i] + 1
        if i in line_ev: line = line_ev[i]
        spp = 0
        if cs:
            g = chr_ev[i]
            spp = max(1, min(65535, round((char_span[g][1] - char_span[g][0]) * FS / 24)))
        im, st = ev_img.get(i, (0, 0))
        isw = 1 if i in ev_img else 0
        endf = 1 if i == len(ev) - 1 else 0
        w = (p << 65) | ((ee - ss) << 45) | (S << 34) | (line << 26) | (int(cs) << 25) | (isw << 24) \
            | (im << 21) | (st << 19) | (endf << 18) | (spp << 2) | (tie << 1) | hold
        words.append(w)
        if isw: timeline.append(f"{ss/FS:7.2f}s  切到图 {im+1}  样式 {st}")
        if i in line_ev:
            ln = line_tab[line]
            txt = "".join(glyph_chars[all_chars[ln[2] + j]] for j in range(ln[1]))
            timeline.append(f"{ss/FS:7.2f}s  第 {line} 句  {txt}")

    # ---- 字库渲染 24x24, 2bpp ----
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    font = ImageFont.truetype(FONT, 21)
    ref = font.getbbox("国")
    glyph_words = []
    prev = Image.new("RGB", (24 * 16, 24 * ((len(glyph_chars) + 15) // 16)), (40, 60, 90))
    for gi, c in enumerate(glyph_chars):
        img = Image.new("L", (24, 24), 0)
        d = ImageDraw.Draw(img)
        bb = font.getbbox(c)
        x = (24 - (bb[2] - bb[0])) // 2 - bb[0]
        y = (24 - (ref[3] - ref[1])) // 2 - ref[1]
        d.text((x, y), c, font=font, fill=255)
        dil = img.point(lambda v: 255 if v >= 80 else 0).filter(ImageFilter.MaxFilter(3))
        for r in range(24):
            row = 0
            for cx in range(24):
                v = img.getpixel((cx, r))
                lv = 3 if v >= 160 else 2 if v >= 80 else 1 if dil.getpixel((cx, r)) else 0
                row = (row << 2) | lv
                col = [(40, 60, 90), (0, 0, 0), (128, 128, 128), (255, 255, 255)][lv]
                prev.putpixel(((gi % 16) * 24 + cx, (gi // 16) * 24 + r), col)
            glyph_words.append(row)
    prev.save(os.path.join(OUT, "glyph_preview.png"))

    # ---- 写文件 ----
    def write_rom(name, width, depth, data):
        data = list(data) + [0] * (depth - len(data))
        hd = (width + 3) // 4
        with open(os.path.join(OUT, name + ".hex"), "w") as f:
            for v in data: f.write(f"{v:0{hd}x}\n")
        with open(os.path.join(OUT, name + ".mif"), "w") as f:
            f.write(f"WIDTH={width};\nDEPTH={depth};\n\nADDRESS_RADIX=DEC;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n")
            for a, v in enumerate(data): f.write(f"\t{a}\t:\t{v:0{hd}X};\n")
            f.write("END;\n")
    gdepth = max(24, len(glyph_words))
    write_rom("score_mel", 72, 1024, words)
    write_rom("lyr_chr", 9, 1024, all_chars)
    write_rom("lyr_line", 16, 256, [(t << 15) | (n << 10) | p for t, n, p in line_tab])
    write_rom("glyph", 48, gdepth, glyph_words)
    od = OUT.replace("\\", "/")
    with open(os.path.join(OUT, "..", "common", "theme_cfg.vh"), "w", encoding="utf-8") as f:   # 放在 common（工程 include 目录）
        f.write("// 由 gen_theme.py 生成，请勿手改\n")
        for n in ("score_mel", "lyr_chr", "lyr_line", "glyph"):
            f.write(f'`define TH_{n.upper()}_MIF "{od}/{n}.mif"\n`define TH_{n.upper()}_HEX "{od}/{n}.hex"\n')
        f.write(f"`define TH_GLYPH_DEPTH {gdepth}\n`define TH_NLINES {len(line_tab)}\n`define TH_TITLE {1 if title else 0}\n")
    with open(os.path.join(OUT, "preview_timeline.txt"), "w", encoding="utf-8") as f:
        f.write(f"主旋律 {mel}，移调 {tr:+d}，事件 {len(ev)}，总长 {ev[-1][1]/FS:.1f}s\n")
        for w in warn: f.write("[注意] " + w + "\n")
        f.write("\n".join(timeline) + "\n")
    preview_wav(ev, os.path.join(OUT, "preview.wav"))
    print("完成：", OUT)

# ---------------------------------------------------------------- 试听（与硬件 aud_voice 同算法的浮点近似）
def preview_wav(ev, path):
    import numpy as np
    out = []
    ph = 0.0
    for ss, ee, p, *_ in ev:
        n = ee - ss
        t = np.arange(n)
        if p == 0:
            out.append(np.zeros(n)); continue
        f = 440 * 2 ** ((p - 69) / 12)
        phase = ph + 2 * np.pi * f * t / FS
        ph = (ph + 2 * np.pi * f * n / FS) % (2 * np.pi)
        s = 0.75 * np.sin(phase) + 0.25 * np.sin(2 * phase)
        env = np.minimum(1.0, t / 240.0)
        env = np.where(t < 240, env, 0.45 + 0.55 * np.exp(-(t - 240) / 8192.0))
        rel = np.clip((n - t) / 960.0, 0, 1)
        env = env * np.where(t > n - 960, np.exp(np.minimum(0.0, -(960 - (n - t)) / 128.0)), 1.0) * (rel > 0)
        out.append(s * env)
    a = np.concatenate(out)
    a = (a / max(1e-9, np.abs(a).max()) * 0.6 * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS); w.writeframes(a.tobytes())

if __name__ == "__main__":
    main()

