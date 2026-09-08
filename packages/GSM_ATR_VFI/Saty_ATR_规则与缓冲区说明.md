# Saty ATR Levels MT5

原作者为 **Saty Mahajan（Copyright © 2022）**，原文件特别感谢 Gabriel Viana。本实现依据你提供的完整 Pine v5 源码移植，保留原作者署名。它是图表指标，不下单、不修改 EA 或 SOP。

## 安装与默认设置

把 `MQL5/Indicators/GSM/Saty_ATR_Levels_MT5.mq5` 和已实际编译的同名 `.ex5` 放进 MT5 数据文件夹的对应目录，在导航器刷新后拖到图表。需要重新编译时，用 MetaEditor 打开 `.mq5` 并按 F7。

默认 Day、ATRLength=14、TriggerPercentage=0.236、上一完整源周期收盘价与 ATR、图表 EMA 8/21/34、中间线开启、扩展线关闭、中文面板开启。改变绘图开关不会改变公开缓冲区。

| 模式枚举 | 显示模式 | 源周期 |
|---:|---|---|
| 0 | Day | MT5 D1 |
| 1 | Multiday | MT5 W1 |
| 2 | Swing | MT5 MN1 |
| 3 | Position | 日历季度：1–3、4–6、7–9、10–12 月 |
| 4 | Long-term | 日历年：1–12 月 |

季度和年度使用完整连续的 MN1 数据聚合 OHLC，再对聚合后的周期计算 ATR，不能拿 3 倍月 ATR 或 12 倍月 ATR 代替。月份与年度边界按经纪商时间解释。原文件头提到 Keltner，但实际选项和计算代码没有 Keltner 模式，因此本版没有自行添加它。

Day 不接受高于 D1 的图表；Multiday 不接受高于 W1 的图表。月、季、年模式不接受 W1 图表，因为单根周线可能跨越日历边界，只有周线 OHLC 无法还原边界前后各自的实时范围。这些模式可用日线、兼容的日内周期或月线图表。

## ATR、锚点与时间对齐

本实现独立计算 Wilder RMA：首个 ATR 是连续 ATRLength 个有效 TR 的算术平均；之后 `ATR = (前 ATR × (ATRLength−1) + 当前 TR) / ATRLength`。TR 是本期高低差、最高价与前收盘价差绝对值、最低价与前收盘价差绝对值中的最大值；首个可用 TR 没有前收盘时使用高低差。TradingView 说明默认 ATR 平滑为 RMA。[TradingView ATR 官方说明](https://www.tradingview.com/support/solutions/43000501823-average-true-range-atr/)

未使用 MT5 `iATR` 代替这条公式。本机随 MT5 提供的 `Examples/ATR.mq5` 使用 TR 滚动窗口更新，算法与此处的 RMA 不同。比较指标时必须使用相同算法与相同历史起点。

默认 `UseCurrentClose=false`：图表某根柱属于源周期 P 时，锚价与 ATR 都取 P−1 已完成的源周期。P 本身的最终高、低、收盘不得参与当时锚点。完整 14 周期 RMA 才能输出 ATR；例如年度默认参数需要至少 14 个完整年度的源数据，再在下一年度引用它。

`UseCurrentClose=true`：锚价取该图表柱的收盘/最新价；发展中的 ATR 使用截至该图表柱已经出现的同一源周期最高/最低价和上一完整周期收盘、ATR 计算。当前柱 0 会随报价变化，已收盘图表柱不会读取随后柱的价格。

范围 `Range` 同样只累计截至当时已出现的图表 OHLC。第一个图表周期如果从源周期中途开始，不能推测此前的高低点：该段 Range、Range/ATR% 为空，当前模式的 ATR 与相应水平线也为空。进入下一完整覆盖的周期后恢复。若 M1 缓存明确显示最早源柱只覆盖了其中一段，该源柱不纳入 RMA 的完整周期种子；季度/年缺月份时也会中断并重新预热。

异常历史中，缺完整季度/年度，或上一聚合周期缺月时，不把较早的收盘价伪装成上一完整周期收盘。只有相邻且完整的上一周期才能参与 TR 的跨周期差价；恢复后的首个完整周期按新数据段处理，TR 从该周期高低差重新起算并重新预热 RMA。这是明确的缺失数据处理规则，不能恢复不存在的报价。

原 Pine 使用 `lookahead_on` 读取未移位的当前高低点；打开当前收盘选项后，也这样读取当前源周期收盘和 ATR。这种历史读取会提前获得源周期的最终值。本移植按当时已知数据构造发展值，因此这些历史图形刻意不照搬未来值。默认上一周期锚点的逻辑保留。[TradingView 多周期数据与 lookahead 说明](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/)

补载更早历史、修复数据缺口、更换算法参数或经纪商数据源会正常重算 RMA 与 EMA。不能把输入数据改变后的重算与读取未来柱混为一谈。

## 水平线和面板

水平线均为 `锚价 ± ATR × 系数`：

`触发距离（默认0.236）、0.382、0.5、0.618、0.786、1、1.236、1.382、1.5、1.618、1.786、2、2.236、2.618、3`。

源代码中 2.382、2.5、2.786 的绘图被注释掉，本版没有额外画出它们。

- 中间线开关控制 0.382、0.5、0.786、1.382、1.5、1.786。
- 扩展线开关控制所有大于 1 ATR 的实际绘图线。
- 0.236 触发线、0.618、1 ATR 与锚价线保留显示。
- 面板 Range/ATR% ≤70 为绿，≥90 为红，其余为橙；ATR 为 0 时不计算百分比。
- EMA 趋势：价格≥EMA8≥EMA21≥EMA34 为偏多，反向为偏空，其余为中性；全部相等时依原源码优先归入偏多。
- Calls/Puts 或 Long/Short 是原源码的参考标签，不是订单或买卖信号；ATR 衡量波动距离，EMA 面板仅提供方向参考。

MT5 原生线缓冲区使用连接相邻柱的折线；源周期边界的连接外观与 Pine `stepline` 不完全相同。原 Pine 线条 40% 透明度也未转成 MT5 线色透明度。数值、级别和开关逻辑独立保留。MT5 使用经纪商报价时段；没有伪造 TradingView `session.extended` 数据，也不承诺跨平台报价完全一致。

## 固定公开缓冲区

0–40 均为 `INDICATOR_DATA`，可通过 `CopyBuffer` 读取。41–42 为内部范围缓存，不是公开接口。全部输出与图表柱对齐，`shift=0` 是未收盘柱，`shift=1` 为最近已收盘柱。它们是数值/环境状态，不是 ADX 那种 0/1 事件接口。

| 缓冲区 | 内容 |
|---:|---|
| 0 | 锚价 AnchorClose；同时绘制中心线 |
| 1 | 源周期 ATR，Wilder RMA |
| 2 | 截至该图表柱的本周期已知范围 |
| 3 | 范围／ATR ×100；ATR=0 或范围不完整时为空 |
| 4 | 图表 EMA 趋势：+1 偏多、−1 偏空、0 中性 |
| 5 / 6 / 7 | 图表 EMA8 / EMA21 / EMA34，周期可调 |
| 8 | 当前源周期开始时间，datetime 转 double |
| 9 | 锚点所属源周期开始时间 |
| 10 | 范围覆盖完整标志：1=完整覆盖至当时，0=首次周期只覆盖一部分；未映射到源周期则为空 |
| 11 / 12 | 下／上触发线，默认 ±0.236 ATR |
| 13 / 14 | −／+0.382 ATR |
| 15 / 16 | −／+0.5 ATR |
| 17 / 18 | −／+0.618 ATR |
| 19 / 20 | −／+0.786 ATR |
| 21 / 22 | −／+1 ATR |
| 23 / 24 | −／+1.236 ATR |
| 25 / 26 | −／+1.382 ATR |
| 27 / 28 | −／+1.5 ATR |
| 29 / 30 | −／+1.618 ATR |
| 31 / 32 | −／+1.786 ATR |
| 33 / 34 | −／+2 ATR |
| 35 / 36 | −／+2.236 ATR |
| 37 / 38 | −／+2.618 ATR |
| 39 / 40 | −／+3 ATR |

未预热、不足历史、源周期不完整、无效数据时，相应缓冲区为 `EMPTY_VALUE`，不是零。真实 ATR=0 可以有效存在，此时上下线与锚价重合，百分比保持为空。

无交易功能的读取片段：

```cpp
int handle = iCustom(_Symbol, _Period, "GSM\\Saty_ATR_Levels_MT5");
// 等待后在正常事件函数中读取，勿在每个 tick 重建句柄。
double atr[], upper[];
if(handle != INVALID_HANDLE && BarsCalculated(handle) > 1 &&
   CopyBuffer(handle, 1, 1, 1, atr) == 1 &&
   CopyBuffer(handle, 12, 1, 1, upper) == 1 &&
   atr[0] != EMPTY_VALUE && upper[0] != EMPTY_VALUE &&
   MathIsValidNumber(atr[0]) && MathIsValidNumber(upper[0]))
  Print("已收盘 ATR=", atr[0], "，上触发参考=", upper[0]);
// 释放阶段：IndicatorRelease(handle);
```

省略全部自定义参数会使用默认值。显式传参需严格按源码声明次序，本机目标 MT5 的两个 `input group` 占字符串位置：首组在 TradingType 前，第二组在 ShowAllFibonacciLevels 前。默认 `iCustom` 无须填这些位置；修改部分参数时可参考交付的实际验证脚本，不能把省略组字符串后产生的错位当成指标参数。

## 验证边界

生产与验证脚本已实际完成 MetaEditor 编译；对应编译日志随交付保存。运行检查结果以原始 `Saty_ATR_validation_results.txt` 与 `Saty_ATR_validation_values.csv` 为准，不由本文推断通过。

原生测试脚本使用独立生成的日内/日数据和 192 个月的数据，比较锚点、RMA、全部水平线、月/季/年日历边界、当前发展模式、前缀/未来扰动、显示开关、首个不完整周期，以及实际 MT5 模板和图表。MT5 与 TradingView 的同品种同报价逐笔对照、真实交易收益和参数优化结论不属于这份合成数据验证。
