


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				1000000000/100000000
// 原为 /2**(`ROW_WIDTH)（64ms 内 2048 次），但芯片要求 4096 次/64ms，且 IP 只在读写空闲时插入刷新会被推迟；
// 实测图片放久了出现固定位置噪点（弱单元掉电荷），改为 8192 次/64ms（每 7.8us 一次，留 2 倍余量）
`define   SELF_REFRESH_INTERVAL			64000000/`SDR_CLK_PERIOD/8192

