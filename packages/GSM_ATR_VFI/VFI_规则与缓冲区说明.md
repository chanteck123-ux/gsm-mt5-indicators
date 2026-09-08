# Volume Flow Indicator [LazyBear] — MT5

本指标根据你提供的 `Volume Flow Indicator.txt` 编写，保留 LazyBear 署名。它是独立副窗口指标，不下单，不修改 EA 或 SOP，不调用 DLL、外部服务或通知接口。

## 安装与默认值

将 `MQL5/Indicators/GSM/Volume_Flow_Indicator_MT5.mq5` 和实际编译生成的同名 `.ex5` 复制到 MT5 **文件 → 打开数据文件夹 → MQL5 → Indicators → GSM**。刷新导航器后，把 `Volume_Flow_Indicator_MT5` 拖到图表。

默认显示绿色 VFI、橙色 EMA 信号线和零轴；差值柱默认关闭，与原文相同。`ShowHistogram=true` 后显示灰色 `VFI-EMA` 柱。三个显示开关只控制绘图，不改变公开缓冲区。

| 参数 | 默认 | 含义 |
|---|---:|---|
| VFILength | 130 | 流量求和窗口和成交量均值窗口 |
| Coefficient | 0.2 | 价格波动过滤系数 |
| MaxVolumeCoefficient | 2.5 | 当前成交量最大值为前均量的此倍数 |
| SignalLength | 5 | VFI 的 EMA 信号线周期 |
| SmoothVFI | false | 开启后对原始 VFI 再做 SMA(3) |
| VolumeMode | VFI_TICK_VOLUME / 0 | 默认使用 MT5 Tick Volume |
| ShowVFILine / ShowSignalLine | true / true | 显示两条线 |
| ShowHistogram | false | 显示差值柱 |

另提供三条图形的颜色参数。VFI 和信号周期允许 1～1000000；两个系数必须为有限非负数。无效参数会给出中文初始化错误，不会偷偷改回默认值。

**成交量口径：**默认 Tick Volume 是当前 MT5 数据源的报价次数。可选 `VFI_REAL_VOLUME / 1` 使用平台提供的 Real Volume；没有实际成交量时，不会退回 Tick Volume。两种成交量不是同一概念，MT5 与 TradingView 的供应商及成交量数据也可能不同，因此不能承诺两平台曲线逐点一致。图表指标名称会显示 `Tick量` 或 `Real量`。

## 与附件对应的公式

以下按时间从旧到新计算，`i` 表示当前计算位置，`L=VFILength`：

1. `typical = (high + low + close) / 3`。
2. `inter[i] = log(typical[i]) - log(typical[i-1])`。
3. `vinter = inter 最近 30 项的总体标准差`，分母为 30。
4. `cutoff = Coefficient × vinter × close[i]`。
5. `vave = volume[i-L ... i-1] 的 SMA`，明确排除本根成交量。
6. `vc = min(volume[i], vave × MaxVolumeCoefficient)`。
7. 价格变化严格大于 `cutoff` 时流量为 `+vc`；严格小于 `-cutoff` 时为 `-vc`；其余为 0。恰好等于门槛时仍为 0。
8. `rawVFI = 最近 L 项流量之和 / 当前 vave`。
9. `SmoothVFI=false` 时 VFI 为 rawVFI；开启时 VFI 为 rawVFI 的 SMA(3)。
10. 信号线为 VFI 的 EMA，`alpha=2/(SignalLength+1)`，从第一个有效 VFI 值开始初始化。差值柱为 `VFI-EMA`。

例如前均量 100、截量倍数 2.5、本根量 1000，则本根计入的最大量为 250；本根量 1000 不会同时抬高用于自己截量的前均量。

## 数据边界和历史行为

普通连续有效数据中，原始 VFI 最早可用的旧序索引为 `max(L,30)+L-1`；开启 SMA(3) 后再增加 2 根。默认 L=130 时索引为 259，也就是至少第 260 根数据才能有当前 VFI；要读取第一根已经收盘的有效 VFI，需要再出现下一根。EMA 从首个有效 VFI 初始化，不额外伪造一段零值。

所有公开输出按自身所需历史分别检查。典型价格不大于 0、非有限数值或回看窗口中有不可用值时，相关输出为 `EMPTY_VALUE`。前均量为 0 时无法做除法，VFI、Signal、Histogram 输出 `EMPTY_VALUE`；辅助缓冲区中的前均量 0、截量 0、有效零流量仍保留为真实数值，方便诊断。价格不动但成交量有效时，VFI、Signal、Histogram 可以都等于 0，这不是无效数据。

无效 VFI 期间，公开 Signal 和 Histogram 保持 EMPTY；内部保留最后一个有效 EMA 状态，数据恢复后从该状态继续。此处以及要求完整连续窗口的检查，是处理异常数据的明确工程边界；不承诺与旧版 Pine 对所有 `na` 缺口的隐式处理完全相同。

未收盘位置 0 随新报价变化。供正式策略判断时读取已收盘位置 1；本指标没有单独输出买卖事件。固定参数、固定历史起点和相同已收盘数据下，之后的价格与成交量不参与更早输出的计算。平台补载或修正历史、可用历史起点变化、参数改变时会完整重建，这与使用未来数据不同。

## 公开缓冲区

下列 10 个缓冲区均绑定为 `INDICATOR_DATA`；0～2 可绘图，3～9 不绘图。内部 10～12 为计算存储，不属于对外接口。

| 编号 | 名称 | 内容及单位 |
|---:|---|---|
| 0 | VFI | 最终 VFI，无量纲 |
| 1 | EMA of VFI | VFI 的 EMA 信号线，无量纲 |
| 2 | VFI minus EMA | VFI 与信号线差值，无量纲；柱图关闭也可读取 |
| 3 | SignedFlow | 过滤、截量后的有符号流量，使用所选成交量口径 |
| 4 | PriceCutoff | 价格变化门槛，价格单位 |
| 5 | PriorAverageVolume | 前 L 根成交量均值，排除本根 |
| 6 | CappedVolume | 本根截量后的非负成交量 |
| 7 | UnsmoothedVFI | 未加 SMA(3) 的原始 VFI |
| 8 | LogReturn | 典型价格相邻对数变化 |
| 9 | PopulationVolatility30 | 30 项对数变化的总体标准差 |

`iCustom(_Symbol,_Period,"GSM\\Volume_Flow_Indicator_MT5")` 使用默认设置。若传自定义参数，顺序与源码 `input` 一致：长度、过滤系数、截量倍数、EMA 周期、SMA3 开关、成交量枚举、显示 VFI、显示信号、显示柱、VFI 颜色、信号颜色、柱颜色。不存在分组占位参数。

读取时先检查句柄与 `BarsCalculated()`，再检查每次 `CopyBuffer()` 的实际复制数量和 `EMPTY_VALUE`。随包的 `MQL5/Scripts/VFI_Buffer_Read.mq5` 是无交易功能的读取示例，只读取最近已收盘位置 1，不据此开平仓。

## 验证证据的范围

原生编译日志、运行结果、独立 Python 参考数据及真实 MT5 截图由主交付测试报告汇总。Python 参考使用 `math.fsum` 与 `statistics.pstdev`，分别计算 13 组固定 OHLC／Tick Volume／Real Volume 数据；另有手算截量、严格门槛、无效值、有效零值、逐根增量及未来扰动检查。

这些检查验证实现、缓冲区和历史行为，不构成黄金交易盈利、胜率改善或 TradingView 逐点一致性的证明。未实际运行的项目应在主测试报告中标为“未测试”。
