# SMC 源码移植：规则与数据接口

当前交付为 `SMC_Structure_MT5.mq5/.ex5`，标题 `SMC LuxAlgo Source (Closed Bars)`。本包交付的是依据本次完整源码制作的版本。

## 来源与许可

- 原作 **© LuxAlgo**，Smart Money Concepts；**CC BY-NC-SA 4.0**，<https://creativecommons.org/licenses/by-nc-sa/4.0/>。改写源码保留署名与该许可。
- 使用用户补齐的完整 `smc.txt`，848 行、51,136 字节，SHA256：`1802A78CC696206651C1700E92BD03ED4D873374943F4C7EC75BE94B7D5B5CF0`。
- 全文已读取，关键公式与先后顺序已另行审计；没有引用外部算法替代。它是**收盘安全的源码移植**，不声称与 TradingView 原图逐点相同，也不自动交易。

## 已实现的原规则

1. **leg pivot**：internal 默认 5，swing 默认 50。候选为 `b-length`，只比较其后 length 根，没有对称左侧窗口。候选高严格高于右侧最高则 leg=0，否则候选低严格低于右侧最低则 leg=1。初值 0，只在 leg 切换时确认 pivot；高低条件同时满足时高分支优先。
2. **BOS/CHoCH**：保留 crossover/crossunder 两根 K 对应各自当时 pivot 值的语义；同 pivot 不重复突破。初始/同向为 BOS，反向为 CHoCH。内部保留与同侧 swing 不等的条件；未确认 swing 的 na 不被错误当成允许。All/BOS/CHoCH 仅筛图形。
3. **Confluence** 默认关，开启时采用原文 `high-max(close,open)` 对 `min(close,open-low)`；没有擅自改成常见下影线公式。
4. **OB**：空头在 `[pivot.index,break.index)` 取 parsedHigh 最早最大，多头取 parsedLow 最早最小；不要求最后反向 K，break K 不参与。波动过滤为 Wilder ATR(200) 或 `累计TR/bar_index`；大波幅 `high-low>=2*volatility` 时 parsedHigh/parsedLow 对调。创建当根就按 wick 或 close 检查多下界/空上界严格穿越失效。内部和 swing 各储存最多 100 个，默认分别只画最新 5 个。
5. **EQH/EQL**：独立 source leg，默认 3 根，差值严格 `<0.1*确认时刻ATR(200)`。阈值 0 时不会触发。
6. **FVG** 默认关。保留三根条件、中间 K 的 `(close-open)/(open*100)`、累计绝对 delta 的自动阈值（除以图表 bar_index 再乘 2）。支持当前及更高周期；第三根目标周期 K 完整收盘才确认，按实际时间二分映射。低于图表周期的 FVG 输入不接受。
7. **Strong/Weak、Premium/Discount**：保留 trailing 扩展与 pivot 重置。Premium 为范围顶部 5%，Discount 为底部 5%，Equilibrium 为中间 5%；中线取上下端均值。
8. **前日/周/月高低**：只读取当时完整结束的上一周期；图表等于目标周期也取上一根。图表高于该级别则留空。
9. **显示**：Historical/Present、彩色/单色、双向结构筛选、internal/swing/OB/EQ/FVG/强弱/PD/DWM开关、数量、pivot标签、颜色蜡烛。颜色蜡烛仅已收盘 K，按该 K 处理突破前的 internal bias 着色，保留源顺序。

## 必须披露的移植差异

- **确认延迟**：移除源 FVG `lookahead_on` 对高周期 `high[0]/low[0]` 的前视；等第三根目标 K 收盘。所有图形从确认可得时间开始，不回画成 pivot/OB origin 当时就已知。FVG 盒子整体平移到确认时刻，显示宽度为一个目标周期加延伸的图表 K 数。
- **倒置 OB**：保留高波动对调与极值选择，但若最终选中倒置/零宽 parsed OB，则抑制该候选。没有静默 swap 成另一段区域。
- **熊 FVG 原失效非对称保留**：源熊 FVG 的 top=currentHigh、bottom=last2Low 数值倒置；这里仅规范绘图与上下界 buffers，删除仍按源 `high>currentHigh` 近边界，多 FVG 仍按远边界。没有暗改成对称远边界规则。
- **删除循环**：逆向删除所有失效项，修正源正向删除可能跳过相邻项的工程边界。
- **图形同步**：Strong/Weak 与 PD 在该根确认处理后画，原文在处理前画。PD 是最新已确认快照，从本次已知时间开始，不把最新几何回填到旧 pivot。EQ 使用确认时刻文字，不画跨越未确认过去的线。
- **资源**：默认初始化重放最近 3000 根，之后增量；每层 OB 最大100、FVG默认50、结构记录默认120。超限淘汰最旧项，历史 buffers 不因此清零。加载更多历史、重置 lookback 起点或换参数，可能改变初始化状态。
- **视觉**：MT5 字号、透明度、颜色参数合并等与 Pine 不同；默认填充关，避免遮 K。统一常用多空色与 D/W/M 线样式，不声称截图像素一致。
- **接口扩展**：首次触碰为额外观察位，不触发源码 alert、不改变删除规则。事件经 buffers 提供，没有移植弹窗/声音/推送配置。

## 源码显示门控也影响计算

- internal/swing pivot 无条件计算。
- internal break/bias 在 ShowInternal 或 ShowInternalOB 或 ColorCandles 开启时计算。
- swing break/bias 在 ShowSwing 或 ShowSwingOB 或 ShowStrongWeak 开启时计算。
- 对应 OB、EQ、FVG 开关控制其检测；Trailing 逐 K 扩展由 StrongWeak 或 PD 开启。
- 主题、Present、All/BOS/CHoCH、Fill、DrawObjects 只影响绘图。
- iCustom 推荐 `DrawObjects=false`。对象逐实例前缀 `SMCL_..._`，只删本实例。真实主图测试采用 native template 重建目标 chart 实例，不能把宿主图对象当作目标图成功。

## 输入契约（没有 input group）

```text
1 InternalLength=5        2 SwingLength=50         3 EqualLength=3
4 EqualThreshold=.1      5 OBFilter=0(ATR)        6 OBMitigation=0(HighLow)
7 Confluence=false       8 ShowInternal=true     9 ShowSwing=true
10 InternalBullFilter=0  11 InternalBearFilter=0  12 SwingBullFilter=0
13 SwingBearFilter=0     14 ShowInternalOB=true  15 ShowSwingOB=false
16 InternalOBVisible=5   17 SwingOBVisible=5     18 ShowEqual=true
19 ShowFVG=false         20 FVGAuto=true         21 FVGTimeframe=CURRENT
22 FVGExtendBars=1       23 StrongWeak=true      24 PremiumDiscount=false
25 Daily=false           26 Weekly=false         27 Monthly=false
28 PivotLabels=false     29 ColorCandles=false   30 PresentMode=false
31 Monochrome=false      32 DrawObjects=true     33 FillZones=false
34 ZoneLabels=true       35 LookbackBars=3000    36 MaxOBStored=100
37 MaxFVGStored=50        38 MaxMarks=120
```

39..47 为多空、内部/外部 OB、FVG、周期线颜色；48 为周期线样式。Filter：0 All，1 BOS，2 CHoCH；OBFilter 1 为累计 TR；Mitigation 1 为 Close。

```mql5
// 默认规则；只关闭图形。无组标题字符串占位。
int h=iCustom(_Symbol,_Period,"SMC_Structure_MT5",
  5,50,3,0.10,0,0,false,true,true,0,0,0,0,true,false,5,5,true,
  false,true,PERIOD_CURRENT,1,true,false,false,false,false,false,
  false,false,false,false,false,true,3000,100,50,120);
```

## 35 个公开 buffer（0-based）

| buffer | 含义 |
|---|---|
| 0 / 1 | internal / swing bias：+1 多，-1 空，0 未定 |
| 2 / 3 | internal / swing break：+1 多BOS、-1 空BOS、+2 多CHoCH、-2 空CHoCH、0无 |
| 4 / 5 | 最新确认 swing high / low |
| 6 / 7 | 最近有效多 OB 上/下界（合并 internal+swing 查询） |
| 8 / 9 | 最近有效空 OB 上/下界 |
| 10 / 11 | 最近有效多 FVG 上/下界 |
| 12 / 13 | 最近有效空 FVG 上/下界 |
| 14 | 区域事件 mask |
| 15 | Wilder ATR(200)，200根 TR 后有效 |
| 16 / 17 | 有效 OB / FVG 总数，含储存但未显示的 OB |
| 18 / 19 | 最新确认 internal high / low |
| 20 / 21 | trailing high / low |
| 22 | equilibrium 中线 |
| 23 / 24 | Premium 下界 / Discount 上界 |
| 25 / 26 | 前日高低 |
| 27 / 28 | 前周高低 |
| 29 / 30 | 前月高低 |
| 31 | 最近被 FVG 检测处理的目标 K 完成时间，datetime 转 double |
| 32 / 33 | 有效 internal / swing OB 数量 |
| 34 | 源码 alert mask |

额外 35..39 是颜色蜡烛 O/H/L/C/颜色索引，不是 EA 确认接口。

最近区域：多区下界<=当时close，取到上界的非负距离；空区上界>=close，取下界到close的非负距离。区内距离0，平局取更新区域；缺失为 EMPTY_VALUE。

**mask14**：1 新多OB，2 新空OB，4 新多FVG，8 新空FVG；16 首触多OB，32 首触空OB，64 首触多FVG，128 首触空FVG；256 失效多OB，512 失效空OB，1024 失效多FVG，2048 失效空FVG；4096 EQH，8192 EQL。

**mask34**：bit0 内部多BOS，bit1 内部空BOS，bit2 内部多CHoCH，bit3 内部空CHoCH；bit4..7 对应 swing；bit8 内部多OB失效，bit9 内部空OB失效，bit10 swing多OB失效，bit11 swing空OB失效；bit12 EQH，bit13 EQL，bit14 多FVG形成，bit15 空FVG形成。

EA 读 shift>=1；shift0 重复最新已收盘状态，2/3/14/34 四个事件 buffer 固定0。历史重放范围以前为空。若源双分支在极端同根均触发，简化 break buffer 保留最后执行方向，mask34 保留全部事件。

## 验证证据

实际 MetaEditor 编译日志：[指标编译日志](evidence/suite_structure_smc.log) 与 [测试编译日志](evidence/suite_structure_test_compile.log)，均 0 errors / 0 warnings。

最新测试脚本用每次独有的禁交易 custom symbols，先由 script 预热 M1/M5/D1，精确检查行情根数，然后创建指标；不允许用 Bars>=预期掩盖前轮残留。验证 35-buffer M1/M5 full/prefix/不同未来、源 leg 延迟/高分支优先/同腿抑制、前日边界、ATR种子、事件/边界/数量、current OHLC实际入库后的原 handle 和独立重算、增量追加、native chart对象及真实canvas截图。

最终运行 **12 组全部通过，0 组失败**。已目视核对目标图表的 BOS、CHoCH、OB、FVG 和区域绘制；截图有 177 个本实例对象。使用合成行情，不能证明盈利。

证据：[运行日志](evidence/suite_smc_results.txt)、[事件 CSV](evidence/suite_smc_events.csv)、[真实 MT5 图表](evidence/suite_smc_chart.png)、[测试源码](evidence/Validate_SMC_Suite.mq5)。

离线 `CustomRatesUpdate` 不是报价事件。测试在写入并预热后，以同一未收盘分钟内、毫秒时间递增且价格等于预期 close 的 `CustomTicksAdd` 报价驱动旧 handle 重算；每次验证 OHLC 没被改变，最多三次。旧 handle 必须恢复并通过全部历史比较，不能用新 handle 顶替。测试证明的是“历史写入后收到新报价的刷新”，不声称依赖型 iCustom 在无 tick 时会自动定时恢复；实际行情下一报价会触发重新计算。生产代码未加入无效的依赖指标 OnTimer 解法。

生产历史就绪条件为：对应 timeframe 的 CopyRates 至少返回 1 根，且 SERIES_SYNCHRONIZED 为真。只有 1 根 D1 也可以正常计算，只是不存在前日可用值时输出为空。所有启用 timeframe 都会发起请求后再汇总结果；任何待就绪项都不推进 LastClosedIndex。copied<0、copied=0 或未同步会进入限频等待日志，不把空缓存当作已准备完成。
