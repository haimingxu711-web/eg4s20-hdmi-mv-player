"""
生成用于仿真的小型 FAT32 磁盘镜像 + 期望的 SDRAM 内容。
特意制造各种情况来考验 img_loader：
  - MBR + 分区（分区从 LBA 64 开始）
  - 每簇 1 扇区（每个文件都要沿 FAT 簇链走很多步）
  - 一个文件故意碎片化（簇号不连续）
  - 目录里有：长文件名项、已删除的 BMP、TXT 文件、子目录、5 张 BMP（只应取前 4 张）
  - 有自下而上(正高度)和自上而下(负高度)两种 BMP
用法: python make_fat32_image.py <输出目录> [W H]
输出: disk.hex（每行 1 字节，$readmemh 用）、expect.hex（地址 数据）
"""
import sys, os, struct, random

out = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 else 64
H = int(sys.argv[3]) if len(sys.argv) > 3 else 48
SLOT = 4096 if W * H <= 4096 else 524288
SEC = 512
PART = 64          # 分区起始 LBA
RSVD = 32
NFATS = 2
FATSZ = 8          # 每个 FAT 8 扇区 = 1024 个表项
SPC = 1
TOTAL = 4096       # 镜像总扇区数
data_lba = PART + RSVD + NFATS * FATSZ
disk = bytearray(TOTAL * SEC)
fat = [0] * (FATSZ * SEC // 4)
fat[0] = 0x0FFFFFF8; fat[1] = 0x0FFFFFFF
next_free = [3]    # 簇 2 = 根目录

def alloc(n, fragment=False):
    clus = []
    for i in range(n):
        if fragment and i % 3 == 2:
            next_free[0] += 2          # 跳过两个簇制造碎片
        clus.append(next_free[0]); next_free[0] += 1
    for a, b in zip(clus, clus[1:]): fat[a] = b
    fat[clus[-1]] = 0x0FFFFFFF
    return clus

def write_file(data, fragment=False):
    n = (len(data) + SEC - 1) // SEC
    clus = alloc(n, fragment)
    for i, c in enumerate(clus):
        lba = data_lba + (c - 2) * SPC
        chunk = data[i * SEC:(i + 1) * SEC]
        disk[lba * SEC: lba * SEC + len(chunk)] = chunk
    return clus[0]

def make_bmp(seed, topdown=False, w=W, h=H):
    rnd = random.Random(seed)
    px = [[(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(w)] for _ in range(h)]
    rows = b''
    order = range(h) if topdown else range(h - 1, -1, -1)
    for y in order:                          # 文件里的行顺序
        r = b''.join(bytes((b, g, r_)) for (r_, g, b) in px[y])
        r += b'\0' * ((4 - len(r) % 4) % 4)
        rows += r
    hdr = b'BM' + struct.pack('<IHHI', 54 + len(rows), 0, 0, 54)
    hdr += struct.pack('<IiiHHIIiiII', 40, w, -h if topdown else h, 1, 24, 0, len(rows), 2835, 2835, 0, 0)
    return hdr + rows, px

def dirent(name83, attr, clus, size, first=None):
    e = bytearray(name83.encode('ascii').ljust(11)[:11])
    if first is not None: e[0] = first
    e += bytes([attr]) + b'\0' * 8 + struct.pack('<H', clus >> 16) + b'\0' * 4 + struct.pack('<HI', clus & 0xFFFF, size)
    return bytes(e)

entries = [dirent('FPGA       ', 0x08, 0, 0)]               # 卷标
expect = {}
bmps = []
specs = [(1, False, False), (2, True, True), (3, False, True), (4, True, False), (5, False, False)]
for i, (seed, topdown, frag) in enumerate(specs):
    data, px = make_bmp(seed, topdown)
    c = write_file(data, frag)
    bmps.append((c, len(data), px))
# 干扰项
txt_c = write_file(b'hello fpga\n' * 50)
entries.append(dirent('DELETED BMP', 0x20, bmps[4][0], bmps[4][1], first=0xE5))   # 已删除
entries.append(bytes([0x41]) + b'\0' * 10 + bytes([0x0F]) + b'\0' * 20)          # 长文件名项
entries.append(dirent('README  TXT', 0x20, txt_c, 550))
entries.append(dirent('SUBDIR     ', 0x10, txt_c, 0))                           # 子目录（名字不是 BMP 也测属性）
entries.append(dirent('FAKEDIR BMP', 0x10, txt_c, 0))                           # 扩展名 BMP 的目录，必须跳过
for i, (c, sz, px) in enumerate(bmps):
    entries.append(dirent(f'IMG{i}    BMP', 0x20, c, sz))
# 根目录写到簇 2，并扩展到第二个簇（测试目录簇链）
root = b''.join(entries)
root = root[:SEC].ljust(SEC, b'\0') if len(root) <= SEC else root
dir_clus2 = next_free[0]; next_free[0] += 1
fat[2] = dir_clus2; fat[dir_clus2] = 0x0FFFFFFF
# 前 16 项放簇 2，其余放第二个目录簇
blob = root.ljust(2 * SEC, b'\0')
disk[data_lba * SEC: (data_lba + 1) * SEC] = blob[:SEC]
l2 = data_lba + (dir_clus2 - 2)
disk[l2 * SEC: (l2 + 1) * SEC] = blob[SEC:2 * SEC]
# 让目录分布到两个簇：在簇 2 前面填 12 个已删除项把真实项挤到后面
pad = b''.join(dirent('OLD     BMP', 0x20, 0, 0, first=0xE5) for _ in range(12))
blob = (pad + b''.join(entries)).ljust(2 * SEC, b'\0')
disk[data_lba * SEC: (data_lba + 1) * SEC] = blob[:SEC]
disk[l2 * SEC: (l2 + 1) * SEC] = blob[SEC:2 * SEC]

# FAT 表
fatb = b''.join(struct.pack('<I', v) for v in fat)
for k in range(NFATS):
    o = (PART + RSVD + k * FATSZ) * SEC
    disk[o:o + len(fatb)] = fatb
# 引导扇区
bs = bytearray(SEC)
bs[0:3] = b'\xEB\x58\x90'; bs[3:11] = b'MSWIN4.1'
struct.pack_into('<HBHBHHBHHHII', bs, 11, SEC, SPC, RSVD, NFATS, 0, 0, 0xF8, 0, 63, 255, PART, TOTAL - PART)
struct.pack_into('<IHHIHH', bs, 36, FATSZ, 0, 0, 2, 1, 6)
bs[82:90] = b'FAT32   '; bs[510] = 0x55; bs[511] = 0xAA
disk[PART * SEC:(PART + 1) * SEC] = bs
# MBR
mbr = bytearray(SEC)
mbr[446 + 4] = 0x0C
struct.pack_into('<II', mbr, 446 + 8, PART, TOTAL - PART)
mbr[510] = 0x55; mbr[511] = 0xAA
disk[0:SEC] = mbr

os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'disk.hex'), 'w') as f:
    f.write('\n'.join('%02x' % b for b in disk) + '\n')
with open(os.path.join(out, 'expect.hex'), 'w') as f:
    for k in range(4):
        px = bmps[k][2]
        for y in range(H):
            for x in range(W):
                r, g, b = px[y][x]
                f.write('%06x %08x\n' % (k * SLOT + y * W + x, (r << 24) | (g << 16) | (b << 8)))
print('disk sectors', TOTAL, 'data_lba', data_lba, 'bmp first clusters', [b[0] for b in bmps], 'slot', SLOT)
