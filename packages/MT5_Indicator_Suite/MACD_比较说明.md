# 两款 MACD 的区别与 MT5 验证结果

你提供的 `macd.txt` 和 CM_MacD_Ult_MTF **默认计算公式不同，信号不会完全一样**。这次均已提供 MT5 版本；验证证明实现符合各自公式，不能据此判断哪款更赚钱。

## 1. 先看公式

| 项目 | ZeroLag_MACD_MT5（本次 macd.txt） | CM_MACD_Ult_MTF_MT5 |
|---|---|---|
| 默认主线 | DEMA(close,12) − DEMA(close,26) | EMA(close,12) − EMA(close,26) |
| 默认信号线 | EMA(MACD,9) | SMA(MACD,9) |
| 柱值 Hist | MACD − Signal | MACD − Signal |
| 自定义均线 | 振荡器和信号线可分别选 EMA、SMA、DEMA，共九种组合 | 固定 EMA 振荡器 + SMA 信号线 |

原作者 evaiinvesting 把辅助函数叫 `zlema()`，实际写的是：

```text
EMA1 = EMA(价格, N)
EMA2 = EMA(EMA1, N)
原 zlema() = EMA1 + (EMA1 − EMA2) = 2 × EMA1 − EMA2
```

这个公式通常称为 **DEMA**，本次保留原公式，并在 MT5 选项标清 DEMA。没有换成价格滞后补偿型 ZLEMA。[MT5 官方 DEMA 公式](https://www.metatrader5.com/en/terminal/help/indicators/trend_indicators/dema)

“Zero Lag” 是原名称，**不等于完全零延迟，也不保证每次交叉都比 CM 早**。两款默认差异同时来自主线均线和信号线平滑方式。

## 2. 颜色与交叉怎么读

| 显示 | ZeroLag MACD | CM MACD（默认开变色） |
|---|---|---|
| MACD 主线 | 固定蓝色 | MACD ≥ Signal 绿色，否则红色 |
| Signal 信号线 | 橙色 | 黄色 |
| 正侧柱 | Hist ≥ 0 且增加：深青；其余：浅青 | Hist > 0 且增加：青色；减少：蓝色 |
| 负侧柱 | Hist < 0 且增加：浅红；其余：红色 | Hist ≤ 0 且减少：红色；增加：栗红色 |
| 柱值等于前柱 | 非负侧浅青，负侧红色 | 黄色 |
| 交叉圆点 | 原源码没有圆点 | 有，默认收盘确认 |
| 本机提醒 | 可选，默认关闭，收盘确认 | 当前移植版没有 Alert |

两条线交叉等价于 **Hist 穿越零线**：

```text
上穿：前柱 Hist ≤ 0，当前 Hist > 0
下穿：前柱 Hist ≥ 0，当前 Hist < 0
```

本次源码的警报名叫 “Rising to falling / Falling to rising”，但实际判断的是上述穿零条件，不能把每次柱子由增变减都当成警报。

ZeroLag MT5 的 buffer 4 给出已收盘交叉：`+1` 上穿、`−1` 下穿、`0` 无交叉；当前与前一根 Hist 尚未同时有效时为 `EMPTY_VALUE`。预热完成后，当前未收盘柱方向保持 0，线和柱仍随报价变化。本机提醒不会补发加载图表前的历史信号。

## 3. 周期功能有区别

- **CM MT5**：支持当前或更高周期。选择高周期时，使用上一根已经收盘的高周期数据；默认交叉圆点再按图表柱收盘确认。这样会有等待时间，不应拿它与当前周期 ZeroLag 直接比较“谁更快”。
- **ZeroLag MT5**：本次移植按当前图表周期计算，需要其他周期时切换图表。
- **ZeroLag 原 Pine**：声明了 `timeframe=""`，默认当前周期，也能通过 TradingView 内置周期设置调整；并非原源码完全没有周期覆盖功能。

CM 旧 Pine 的 `security()` 行为与本次安全高周期映射不完全相同。当前实现避免提前引用尚未收盘的高周期结果，不承诺复现旧脚本可能存在的历史未来数据效果。[TradingView 官方周期与 lookahead 说明](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/)

## 4. 同一批数据实际比较

测试使用 **5000 根人工合成 M1 K 线**，两款均用当前 M1、Close、12/26/9。剔除最初 600 根以减小初始化影响，并排除最后一根未收盘柱，留下 **4399 根已收盘柱**。合成数据时间为 2026-01-05 10:00 至 2026-01-08 11:18，时间戳不代表该时段真实市场行情。

| 指标行为 | CM 默认 EMA/SMA | ZeroLag 默认 DEMA/EMA |
|---|---:|---:|
| 上穿零线次数 | 75 | 77 |
| 下穿零线次数 | 75 | 77 |
| 交叉总次数 | **150** | **154** |
| 每 1000 根柱的交叉次数 | 34.098659 | 35.007956 |

两款 Hist 符号不同的柱有 **1160 / 4399 根，即 26.369629%**。这里的“方向”只表示 Hist 在零线上、零线下或恰好为零，不表示行情涨跌预测是否正确。此次合成样本中 ZeroLag 多 4 次交叉；未测每次信号平均提前多少柱。

**这些次数不是交易次数，方向不同率不是胜率。** 本次没有开平仓、仓位和成本模型，因此没有 Net Profit、Equity DD、PF、交易胜率等策略绩效结论。

## 5. 数值是否做对了

最终 MT5 验证 **35 组全部通过，0 组失败**，覆盖默认及九种 Custom 公式、SMA 预热不足、长度 1、快慢周期反转、价格源、颜色、收盘交叉和最新报价更新时已收盘柱保持稳定。

另把 ZeroLag 设为 **Custom → Oscillator = EMA → Signal = SMA**，使它与 CM 使用同一公式。4399 根柱的 MACD、Signal、Hist 共 **13197 个数值**核对全部通过，最大绝对误差为 **5.68434188608 × 10⁻¹⁴**，属于浮点计算误差；可视为数值一致。比较容差是 10⁻⁸，并非宣称二进制逐位相同。

证据：[MT5 最终验证日志](evidence/suite_zl_results.txt)、[逐柱比较数据 CSV](evidence/suite_zl_comparison.csv)。报告中的行数、交叉次数、方向不同率和同公式最大误差另从 CSV 独立复核过。

源码：[ZeroLag MACD](ZeroLag_MACD_MT5.mq5)、[CM MACD](CM_MACD_Ult_MTF_MT5.mq5)。
