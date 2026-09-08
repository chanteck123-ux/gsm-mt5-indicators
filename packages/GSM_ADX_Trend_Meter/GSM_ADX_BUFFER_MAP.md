# GSM ADX — EA 缓冲区说明

固定接口为 15 个 `INDICATOR_DATA` 输出。除 0～2 外均使用 `DRAW_NONE`，外部程序可通过 `iCustom` + `CopyBuffer` 读取。关闭显示、面板、历史标记或提醒不改变接口数值。下方示例只读取并打印，不包含任何交易操作。

`ADXMethod` 支持 0=WILDER（默认）、1=MT5_STANDARD、2=PINE_ADX_DI。新增 Pine 模式没有移动任何输入位置或公开缓冲区；内部 15～19 为计算缓存，不属于承诺的外部接口，请勿依赖。

## 位置与无效值

时间序列位置 `0` 是当前未收盘 K 线，`1` 是最近已收盘 K 线。`CopyBuffer` 起始位置与返回数组的物理顺序是两件事；示例只复制一个值，避免方向歧义。批量复制时必须显式确定 AS_SERIES，不能猜先后。

0～2 号原始曲线可以在位置 0 随报价改变；**3～14 号位置 0 固定为 `EMPTY_VALUE`**。历史位置只使用它自己和更早数据，不使用位置更小的未来值。

`EMPTY_VALUE` 表示预热不足、必要回看不足或数据暂不可用，不等于事件未发生。仅在相应数据完整有效时，事件输出为 0 或 1。应先检查 `BarsCalculated`、复制实际返回数量，再检查 `EMPTY_VALUE` 和 `MathIsValidNumber`；不能只检查数值是否为 0。

## 固定映射

| 缓冲区 | 名称 | 有效已收盘值 |
|---:|---|---|
| 0 | ADX | 所选算法 ADX 数值 |
| 1 | PlusDI | 所选算法 +DI 数值 |
| 2 | MinusDI | 所选算法 -DI 数值 |
| 3 | MarketState | 0 弱；1 形成中；2 较明显；3 很强 |
| 4 | DirectionState | +1 偏多；-1 偏空；0 相等 |
| 5 | SlopeState | +1 增强；-1 减弱；0 容差内走平 |
| 6 | CrossWeakEvent | ADX 上穿弱势线，0/1 |
| 7 | CrossTrendEvent | ADX 上穿趋势线，0/1 |
| 8 | BullEvent | 偏多 DI 交叉且 ADX 增强，0/1 |
| 9 | BearEvent | 偏空 DI 交叉且 ADX 增强，0/1 |
| 10 | HighTurnDownEvent | 高位转弱确认，0/1 |
| 11 | TrendConfirmedEvent | 首次连续站稳趋势线，0/1 |
| 12 | RisingEntryEvent | 首次连续增强，0/1 |
| 13 | LongLowEntryEvent | 首次持续低 ADX，0/1 |
| 14 | ChoppyEntryEvent | 首次低 ADX 与 DI 缠绕，0/1 |

同根可同时有多个事件，例如 6=1 且 7=1；它们不是互斥枚举，不得只读取一个事件后覆盖其他项。ADX 高位转弱也不是强制平仓或反手指令。

## 精确定义

用 `A[s]`、`P[s]`、`M[s]` 分别表示 ADX、+DI、-DI，`s≥1`；`L/T/H` 为弱势／趋势／很强阈值，`E` 为容差，`D[s]=A[s]-A[s+1]`。

```text
MarketState: A<L → 0；L≤A<T → 1；T≤A≤H → 2；A>H → 3
DirectionState: P>M → +1；P<M → -1；P=M → 0
SlopeState: D>E → +1；D<-E → -1；其余 → 0

CrossWeak:  A[s]>L 且 A[s+1]≤L
CrossTrend: A[s]>T 且 A[s+1]≤T

DIBullCross: P[s]>M[s] 且 P[s+1]≤M[s+1]
DIBearCross: M[s]>P[s] 且 M[s+1]≤P[s+1]
Bull/Bear: 对应 DI 交叉 且 D[s]>E
  仅 UseMinADXForDICross=true 时再要求 A[s]≥MinADXForDICross

HighTurnDown:
  A[s+1]>H 且 D[s]<-E 且 A[s+1]-A[s+2]≥-E

AboveConfirmed(s): 从 s 起 ConfirmBars 根 A 均≥T
TrendConfirmedEvent: AboveConfirmed(s) 且非 AboveConfirmed(s+1)

Rising(s): j=0..RiseComparisons-1 的 A[s+j]-A[s+j+1] 均>E
RisingEntryEvent: Rising(s) 且非 Rising(s+1)

LongLow(s): 从 s 起 LowADXBars 根 A 均<L
LongLowEntryEvent: LongLow(s) 且非 LongLow(s+1)

RawCrossCount(s): 从 s 起 DICrossLookback 次相邻比较的原始 DI 交叉数
  每一对按 DIBullCross/DIBearCross 定义，最多计一次；不使用 ADX 过滤
Choppy(s): A[s]<L 且 RawCrossCount(s)≥DICrossMinCount
ChoppyEntryEvent: Choppy(s) 且非 Choppy(s+1)
```

进入事件在当前和前一状态的全部所需值有效后才有 0/1 输出；即使当前条件已经为 false，也不会跳过缺失的历史检查、用 0 冒充有效结果。

## 预热及必要历史

令 `N=ADXPeriod`。内置模式 `a0=2N`，`d0=N+1`（Wilder）或 `N`（普通）。这些是按当前 MetaQuotes 原生示例绘图起点确定的零基年代索引，从底层最早 K 线计数。内置模式按照底层 `BarsCalculated` 对齐，不会用「全部零无效」判断暖机。

Pine 模式的理论最早起点为 `a0=N−1`、`d0=0`；实际还需足够有效分母及 N 个有效 DX。其 SMA 忽略无效 DX，没有 N 个有效值时输出 EMPTY；已有 N 个时，新无效 DX 不挤出有效窗口。源码 `nz(previous,0)` 的首根种子也完整保留，不能按内置公式重设初值。

| 输出 | 最早可能有效的年代索引 |
|---|---|
| ADX、MarketState | a0 |
| PlusDI、MinusDI、DirectionState | d0 |
| SlopeState、CrossWeak、CrossTrend | a0+1 |
| Bull、Bear | max(a0+1, d0+1) |
| HighTurnDown | a0+2 |
| TrendConfirmedEvent | a0+ConfirmBars |
| RisingEntryEvent | a0+RiseComparisons+1 |
| LongLowEntryEvent | a0+LowADXBars |
| ChoppyEntryEvent | max(a0+1, d0+DICrossLookback+1) |

这些只是最低边界，还必须实际取得有限有效值，而且正式输出需要该根已经收盘。默认 Wilder、N=14 时，最长的低 ADX 进入事件最早位于年代索引 38；若它要成为最近已收盘位置 1，至少需 40 根总 K 线（包括当前未收盘根）。Pine、N=14 且无 DX 缺口时，该事件理论最早位于年代索引 23，作为位置 1 需要至少 25 根总 K 线。这只是数据有效边界，不表示事件一定发生，也不保证平滑初值影响已经消失。严谨的数值对照应使用更充分的预热并报告实际区间。

平台补载更深历史或修正价格缺口、变更算法或参数时可以正常重算。固定数据逐根回放的对照应保持同一历史起点，不能比较不同起点的平滑序列后宣称重绘。

## 最简单的无交易读取示例

将以下代码保存为独立脚本。默认 `iCustom` 不传可选输入，使用整套默认设置，不涉及中文分组的位置槽。脚本遇到数据准备中会退出；可以等图表数据加载后重运行，实际 EA 应在后续 tick 重试而不是先标记该 K 线已经处理。

```cpp
#property strict

void OnStart()
  {
   int handle=iCustom(_Symbol,_Period,"GSM\\GSM_ADX_Trend_Meter");
   if(handle==INVALID_HANDLE)
     { PrintFormat("创建 GSM ADX 失败，错误 %d",GetLastError()); return; }

   if(BarsCalculated(handle)<2)
     { Print("GSM ADX 数据准备中，请等待后重试。"); IndicatorRelease(handle); return; }

   datetime before=iTime(_Symbol,_Period,1);
   if(before<=0)
     { Print("信号 K 线时间未准备好。"); IndicatorRelease(handle); return; }

   double adx[1],market[1],bull[1],bear[1];
   int n0=CopyBuffer(handle,0,1,1,adx);
   int n3=CopyBuffer(handle,3,1,1,market);
   int n8=CopyBuffer(handle,8,1,1,bull);
   int n9=CopyBuffer(handle,9,1,1,bear);
   if(n0!=1 || n3!=1 || n8!=1 || n9!=1)
     { Print("GSM ADX 复制数量不足，等待后重试。"); IndicatorRelease(handle); return; }

   if(adx[0]==EMPTY_VALUE || market[0]==EMPTY_VALUE || bull[0]==EMPTY_VALUE || bear[0]==EMPTY_VALUE ||
      !MathIsValidNumber(adx[0]) || !MathIsValidNumber(market[0]) ||
      !MathIsValidNumber(bull[0]) || !MathIsValidNumber(bear[0]))
     { Print("GSM ADX 预热／回看不足或数据暂不可用。"); IndicatorRelease(handle); return; }

   datetime signal_bar=iTime(_Symbol,_Period,1);
   if(signal_bar<=0 || signal_bar!=before)
     { Print("读取期间发生换柱，请重新获取同一批数据。"); IndicatorRelease(handle); return; }
   PrintFormat("%s %s，收盘K线=%s，ADX=%.2f，环境=%.0f，偏多事件=%.0f，偏空事件=%.0f",
      _Symbol,EnumToString(_Period),TimeToString(signal_bar,TIME_DATE|TIME_MINUTES),
      adx[0],market[0],bull[0],bear[0]);
   IndicatorRelease(handle);
  }
```

`BarsCalculated(handle)≥2` 只代表有可查询位置，不代表所有输出已预热；后面的 EMPTY 检查不能删。实际长期运行的读取程序应在初始化阶段创建一次句柄，后续保留句柄读取，在释放阶段 `IndicatorRelease`，不要每个 tick 都创建新实例。

## 显式输入的完整顺序

`iCustom` 可选参数必须与实际编译输入顺序及类型一致。本版有三个 `input group`；目标终端的显式调用保留组标题的字符串位置槽，建议使用已交付比较脚本里的实际调用，并用 `IndicatorParameters` 核对。后部省略的参数使用默认值。不要在不同版本之间盲目复用位置参数。

以下编号从 `iCustom` 的指标路径之后的第一个可选参数开始，0 为起始位置；组槽传空字符串 `""`。

| 位置 | 参数 | 类型／默认值 |
|---:|---|---|
| 0 | 算法中文分组 | string / "" |
| 1 | ADXMethod | enum / 0=WILDER，1=MT5_STANDARD，2=PINE_ADX_DI |
| 2 | ADXPeriod | int / 14 |
| 3 | LevelWeak | double / 20 |
| 4 | LevelTrend | double / 25 |
| 5 | LevelStrong | double / 40 |
| 6 | SlopeEpsilon | double / 0 |
| 7 | ConfirmBars | int / 2 |
| 8 | RiseComparisons | int / 3 |
| 9 | LowADXBars | int / 10 |
| 10 | DICrossLookback | int / 10 |
| 11 | DICrossMinCount | int / 3 |
| 12 | UseMinADXForDICross | bool / false |
| 13 | MinADXForDICross | double / 25 |
| 14 | 显示中文分组 | string / "" |
| 15 | ShowPanel | bool / true |
| 16 | ShowDILines | bool / true |
| 17 | PanelLivePreview | bool / false |
| 18 | ShowSignalMarkers | bool / true |
| 19 | MaxMarkerBars | int / 500 |
| 20 | ADXColor | color / clrDodgerBlue |
| 21 | PlusDIColor | color / clrLimeGreen |
| 22 | MinusDIColor | color / clrTomato |
| 23 | ADXWidth | int / 2 |
| 24 | PlusDIWidth | int / 1 |
| 25 | MinusDIWidth | int / 1 |
| 26 | LevelColor | color / clrSlateGray |
| 27 | LevelStyle | enum / STYLE_DOT |
| 28 | LevelWidth | int / 1 |
| 29 | PanelCorner | enum / CORNER_LEFT_UPPER |
| 30 | PanelX | int / 12 |
| 31 | PanelY | int / 14 |
| 32 | PanelFontSize | int / 10 |
| 33 | PanelFont | string / Microsoft YaHei |
| 34 | PanelTextColor | color / clrGainsboro |
| 35 | PanelBackground | color / clrBlack |
| 36 | 提醒中文分组 | string / "" |
| 37 | EnableAlerts | bool / false |
| 38 | EnablePopup | bool / true |
| 39 | EnableSound | bool / false |
| 40 | EnablePush | bool / false |
| 41 | SoundFile | string / alert.wav |
| 42 | AlertCrossWeak | bool / true |
| 43 | AlertCrossTrend | bool / true |
| 44 | AlertBull | bool / true |
| 45 | AlertBear | bool / true |
| 46 | AlertHighTurnDown | bool / true |
| 47 | AlertTrendConfirmed | bool / true |
| 48 | AlertRising | bool / true |
| 49 | AlertLongLow | bool / true |
| 50 | AlertChoppy | bool / true |

无显示、默认规则的显式前缀示例（后部提醒仍默认关闭）：

```cpp
int handle=iCustom(_Symbol,_Period,"GSM\\GSM_ADX_Trend_Meter",
                   "",0,14,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
                   "",false,false,false,false,500);
```

这不是自动买卖信号接口承诺。EA 将来如何组合进出场、风险控制和交易成本，需要另行制定规则与测试；当前只提供可复核的环境、方向、强度变化和确认事件。
