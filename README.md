# GSM MT5 指标库

13 个独立 MT5 指标，提供完整 `.mq5`、实际编译的 `.ex5`、中文说明、EA 缓冲区接口及真实验证证据。保存于私有仓库，供后续 EA 开发和测试使用。没有加入自动交易规则，没有修改现有 EA 或 SOP。

## 安装

1. 电脑端 MT5：**文件 → 打开数据文件夹 → MQL5 → Indicators**，新建 `GSM` 文件夹。
2. 把 `packages/MT5_Indicator_Suite` 顶层的 10 对 `.mq5/.ex5` 复制进去。
3. 把另外两个 package 的 `MQL5/Indicators/GSM` 内共 3 对指标复制到同一 `GSM` 文件夹。
4. MT5 导航器「指标」右键刷新，展开 GSM 后拖入图表。不需要为这些指标开启算法交易或 DLL。

最终应有 **13 个指标 EX5 和 13 份对应源码**。`evidence` 下的测试副本和验证脚本不属于正式指标，不要一起拖入 Indicators。脚本读取示例需要时单独放到 `MQL5/Scripts`。本次使用隔离终端验证，尚未把套装安装到你的原交易终端。

旧 10 指标包保留原有目录和说明；本总包统一建议安装到 `Indicators/GSM`，因此旧文档示例中的裸指标名在本安装方式下须加 `GSM\\` 前缀。默认调用例如：

```cpp
int handle = iCustom(_Symbol, _Period, "GSM\\GSM_ADX_Trend_Meter");
```

## 指标与说明

| 指标文件名（省略扩展名） | 内容 | 中文说明 |
|---|---|---|
| Bollinger_RSI_ChartArt_MT5 | 布林带、RSI 同根交叉提示 | [使用说明](packages/MT5_Indicator_Suite/使用说明.md) |
| SMA_Ribbon_10_MT5 | 10 条 SMA 和方向配色 | [使用说明](packages/MT5_Indicator_Suite/使用说明.md) |
| EMA_20_50_100_200_MT5 | 20/50/100/200 EMA | [使用说明](packages/MT5_Indicator_Suite/使用说明.md) |
| ZeroLag_MACD_MT5 | 默认 DEMA MACD、EMA 信号线 | [MACD 比较](packages/MT5_Indicator_Suite/MACD_比较说明.md) |
| CM_MACD_Ult_MTF_MT5 | CM 多周期 MACD、SMA 信号线、四色柱 | [MACD 比较](packages/MT5_Indicator_Suite/MACD_比较说明.md) |
| Stoch_RSI_MT5 | 14/14/3/3 随机 RSI | [使用说明](packages/MT5_Indicator_Suite/使用说明.md) |
| SMC_Structure_MT5 | 最新完整 SMC 源码移植及确认调整 | [SMC 接口](packages/MT5_Indicator_Suite/SMC_规则与数据接口.md) |
| Volume_Profile_MT5 | 价格层活动权重、POC、价值区 | [使用说明](packages/MT5_Indicator_Suite/使用说明.md) |
| GSM_SNR_MT5 | GSM 支撑阻力、角色互换与反应 | [SNR 接口](packages/MT5_Indicator_Suite/SNR_规则与数据接口.md) |
| GSM_SND_MT5 | GSM 供需区、首次回踩与参考价 | [SND 接口](packages/MT5_Indicator_Suite/SND_规则与数据接口.md) |
| GSM_ADX_Trend_Meter | ADX/+DI/-DI、中文强弱面板、确认事件 | [ADX 使用说明](packages/GSM_ADX_Trend_Meter/README_GSM_ADX_ZH.md) |
| Saty_ATR_Levels_MT5 | 日／周／月／季／年 ATR 水平及状态面板 | [ATR 接口](packages/GSM_ATR_VFI/Saty_ATR_规则与缓冲区说明.md) |
| Volume_Flow_Indicator_MT5 | LazyBear VFI、EMA 信号和可选差值柱 | [VFI 接口](packages/GSM_ATR_VFI/VFI_规则与缓冲区说明.md) |

ZeroLag 和 CM MACD 都保留，尚未根据黄金交易收益选出胜者。它们的默认公式不同，已完成的指标行为比较不代表策略胜率比较。

## 供 EA 开发读取

文件与安装路径由 [indicator_manifest.json](indicator_manifest.json) 固定。正式输出按各自说明读取，不能从中文面板或当前图形对象反推过去信号。

| 指标 | 主要 buffer 编号 | 使用边界 |
|---|---|---|
| ADX | 0/1/2 三曲线；3/4/5 强度、方向、斜率；6～14 九个事件 | [完整 15 buffer 及参数顺序](packages/GSM_ADX_Trend_Meter/GSM_ADX_BUFFER_MAP.md)；3～14 的 shift 0 固定 EMPTY |
| ATR | 0 锚价、1 ATR、2 已知范围、3 百分比、4 趋势、5～7 EMA、8～10 时间／完整标志、11～40 水平线 | 41 个公开接口；默认上一完整源周期 |
| VFI | 0 VFI、1 EMA、2 差值；3～9 诊断中间值 | 10 个公开接口；默认 Tick Volume，Real 不自动回退 |
| CM MACD | 0 MACD、2 Signal、3 Hist、5 圆点价、7 交叉方向 | 收盘事件读 shift 1，高周期只映射完成值 |
| ZeroLag MACD | 0 MACD、1 Signal、2 Hist、4 交叉方向 | 与 CM 信号线算法不同 |
| Stoch RSI | 0 K、1 D | 当前柱可以变化 |
| BB/RSI | 0/1/2 中上轨下轨；5/6 箭头；12 RSI；13 颜色方向 | 箭头是条件提示，不是成交记录 |
| SMA / EMA | SMA 偶数 0～18；EMA 0～3 | 隐藏显示后对应 buffer 可能为空，详见各说明 |
| Volume Profile | 0/1/2 POC/VAH/VAL；3～6 权重／量／占比／样本 | **仅 shift 0 当前区间快照**，不能当历史 POC 回测 |
| SNR / SND / SMC | 各自规则文档完整列表 | SNR 位掩码、SND 事件个数和 SMC 状态不能混用 |

通用读取要求：句柄只在初始化创建；检查 `BarsCalculated`、每个 `CopyBuffer` 实际返回数量、`EMPTY_VALUE` 和有限数值。通常读 shift 1，并核对读取前后最近已收盘柱时间一致，避免换柱时混合两根数据。有效 0 不等于缺失；不要将 EMPTY 转成 0。显示开关的接口语义按各指标文档，不统一假设。

ADX、ATR 以及部分旧指标包含 `input group`，目标编译环境的位置参数中分组占字符串槽；省略全部参数使用默认值最稳妥，自定义时按源码及实际测试脚本传入。未来 EA 应锁定指标版本、源码／EX5 哈希、算法、参数和历史起点。

**SND 教材“30 pt”的价格单位仍未获得确认。** 当前 `InpPointSize=0` 代表经纪商 MT5 point；正式策略采用前必须确定教材单位，不能把报价小数位直接当教材单位。

## 真实验证与尚未完成项目

全部 13 个正式指标实际编译为 0 errors、0 warnings。按模块查阅原始日志和中文报告：

- [原 10 指标：121 组检查](packages/MT5_Indicator_Suite/验证结果.md)，包含同一未改 CM／Stoch RSI 成品的此前 20 组验证。
- [ADX 三算法、真实 GOLD/EURUSD 数值及工程测试](packages/GSM_ADX_Trend_Meter/GSM_ADX_TEST_REPORT.md)。Wilder 和普通 ADX 各自对照内置来源，真实行情共 15000 个三线数值最大误差 0。
- [ATR 实际测试](packages/GSM_ATR_VFI/Saty_ATR_测试报告.md)。
- [VFI：18 组、72927 断言、0 失败](packages/GSM_ATR_VFI/VFI_测试报告.md)。

指标验证没有交易模型，因此 Net Profit、PF、Max Equity DD、Trades、Win Rate、真实 Tick 策略回测、延迟／滑点压力和样本外收益均 **未测试**。ADX 实机弹窗／声音／手机送达与真实断线恢复 **未测试**。TradingView 与同一真实报价逐点配对 **未测试**。更多数据边界见各报告，不把局部通过写成“全部场景通过”。

## 源码与版权

原始文本／PDF 在各包 `source_reference` 中，用作用户提供的参考资料。保留 ChrisMoody、BeikabuOyaji、Saty Mahajan、LazyBear、ChartArt、LuxAlgo 等原作者署名以及已有许可。ZeroLag／Volume Profile／Pine ADX 引用的源文件注明 MPL 2.0；SMC 源文件注明 CC BY-NC-SA 4.0；其他资料的权利归相应作者。此私有仓库不为全部文件另行授予统一开源许可，私有保存也不改变原许可条件。

哈希清单用于核对源码、编译成品和证据版本。仓库不包含 MT5 登录配置、密码、账户数据库、终端缓存或完整网络日志。
