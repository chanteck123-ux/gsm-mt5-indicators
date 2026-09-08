# GSM ADX 趋势强弱测量器

这是电脑端 MT5 的独立副窗口指标，文件名 `GSM_ADX_Trend_Meter`。显示 ADX、+DI、-DI、中文状态面板及收盘确认事件，不自动交易，也不修改现有 EA 或 GSM SOP。

默认使用 **ADX Wilder，周期 14**。ADX 表示趋势强弱，方向另看 +DI 与 -DI；ADX 增强不代表价格上涨，ADX 减弱不代表价格下跌或反转。20、25、40 及各连续根数是本版本初始参考设置，没有据此证明黄金交易的胜率或盈利改善。

根据后来提供的 `ADX and DI.txt`，新增 **PINE_ADX_DI（2）** 算法选项，保留原始默认 Wilder。三个算法使用同一套中文面板和 15 个公开缓冲区，计算内核与初始化不同，不能互相要求数值相等。

| 算法 | 计算来源 | ADX 平滑与初始化 |
|---|---|---|
| WILDER（0，默认） | MT5 `iADXWilder` | 平台 Wilder 算法与初始化 |
| MT5_STANDARD（1） | MT5 `iADX` | 平台普通 ADX 算法与初始化 |
| PINE_ADX_DI（2） | 用户提供的 BeikabuOyaji Pine v4 源码移植 | TR/DM 从 0 递推平滑和，ADX 为最近 N 个有效 DX 的 SMA |

要使用新增源码算法，将 `ADXMethod` 改为 `PINE_ADX_DI`。原源码 `th=20` 对应本指标 `LevelWeak`；既有 25/40 参考线、面板和收盘确认功能仍保留。

## 安装与加载

1. 在电脑端 MT5 点击「文件 → 打开数据文件夹」。
2. 将本包 `MQL5/Indicators/GSM` 文件夹复制到该数据文件夹的 `MQL5/Indicators` 下。最终位置为 `MQL5/Indicators/GSM/GSM_ADX_Trend_Meter.ex5`；源码 `.mq5` 可以一起保留。
3. 在 MT5 导航器「指标」中右键刷新，展开 `GSM`，将 `GSM_ADX_Trend_Meter` 拖到目标图表。它按当前图表品种与周期计算，支持经纪商品种后缀，没有写死黄金名称。
4. 如需自行编译，在 MetaEditor 打开 `.mq5` 后按 F7，检查实际编译日志。不要把旧 EX5 或编译按钮已点击视为本次编译通过。
5. 若面板太高或挡住曲线，可拉高副窗口、改变面板角落、减小字号，或关闭面板。关闭面板、DI 线、标记和提醒都不改变可读取缓冲区。

本包实际编译与运行证据见 [真实测试报告](GSM_ADX_TEST_REPORT.md)。手机端 MT5 不能直接安装此桌面自定义指标；手机接收通知需要电脑终端持续运行并正确配置。

## 如何读图

默认蓝色 ADX、绿色 +DI、红色 -DI，参考线为 20/25/40；副窗口没有把纵轴最大值限制为 40 或 50。

| ADX 范围 | 面板含义 |
|---|---|
| ADX < 20 | 趋势偏弱／震荡倾向 |
| 20 ≤ ADX < 25 | 趋势形成中 |
| 25 ≤ ADX ≤ 40 | 趋势较明显 |
| ADX > 40 | 趋势很强 |

恰好等于 20 属于形成中；恰好 25、40 属于较明显。+DI > -DI 为偏多，+DI < -DI 为偏空，相等为方向均衡。ADX 较低时，面板会同时注明强度不足。

默认面板读取最近已收盘 K 线。启用 `PanelLivePreview` 后会明确显示「未收盘，数值会变化」，只改变临时显示；正式状态和事件仍只能读取已收盘位置。图上的事件圆点位于确认 K 线，不回移到此前高点；同根多个事件合并到该点的鼠标提示中，各事件缓冲区仍各自保留。面板的最新事件文字可能为适应宽度缩短，鼠标提示保留全文。

每次加载的短名包含算法、周期和实例编号，例如 `GSM ADX 趋势强弱测量器 [ADX Wilder 14 #12]`。编号用于区分同时加载的实例，重新加载或模板恢复后可以改变；EA 应读缓冲区，不应依赖图形对象名称或实例编号。

## 参数

下面的名称与源码一致。界面使用三组中文分组。周期最小值 2 是本指标的输入约束；不会按 M5、M15 等图表周期偷偷改参数。

| 参数 | 默认值 | 用途 |
|---|---|---|
| ADXMethod | WILDER（0） | Wilder、普通 ADX（1）或新增 Pine ADX and DI（2） |
| ADXPeriod | 14 | ADX/DMI 周期 |
| LevelWeak / LevelTrend / LevelStrong | 20 / 25 / 40 | 状态、事件及三条水平线共同使用 |
| SlopeEpsilon | 0 | ADX 变化容差，单位为指标数值 |
| ConfirmBars | 2 | 连续 ADX ≥ 趋势线的根数 |
| RiseComparisons | 3 | 连续 ADX 增强的相邻比较次数 |
| LowADXBars | 10 | 连续 ADX < 弱势线的根数 |
| DICrossLookback / DICrossMinCount | 10 / 3 | 缠绕统计窗口及最低原始交叉次数 |
| UseMinADXForDICross | false | 默认不额外要求 DI 交叉时 ADX ≥ 25 |
| MinADXForDICross | 25 | 仅上项开启时生效 |
| ShowPanel / ShowDILines | true / true | 显示面板和两条 DI 线 |
| PanelLivePreview | false | 未收盘临时显示，不改确认输出 |
| ShowSignalMarkers / MaxMarkerBars | true / 500 | 历史圆点及其范围，不限制缓冲区历史 |
| ADXColor / PlusDIColor / MinusDIColor | DodgerBlue / LimeGreen / Tomato | 三线颜色 |
| ADXWidth / PlusDIWidth / MinusDIWidth | 2 / 1 / 1 | 三线宽度，1～5 |
| LevelColor / LevelStyle / LevelWidth | SlateGray / STYLE_DOT / 1 | 水平线颜色、样式、宽度 |
| PanelCorner | CORNER_LEFT_UPPER | 左上、右上、左下或右下 |
| PanelX / PanelY | 12 / 14 | 距所选角落的像素距离 |
| PanelFontSize / PanelFont | 10 / Microsoft YaHei | 字号 7～24；中文字体 |
| PanelTextColor / PanelBackground | Gainsboro / Black | 面板文字及背景颜色 |
| EnableAlerts | false | 提醒总开关 |
| EnablePopup / EnableSound / EnablePush | true / false / false | 三个渠道都受总开关控制 |
| SoundFile | alert.wav | MT5 `Sounds` 目录下的声音文件 |
| AlertCrossWeak / AlertCrossTrend | true / true | 上穿弱势线／趋势线提醒 |
| AlertBull / AlertBear | true / true | 偏多／偏空 DI 交叉增强提醒 |
| AlertHighTurnDown / AlertTrendConfirmed | true / true | 高位转弱／连续站稳提醒 |
| AlertRising / AlertLongLow / AlertChoppy | true / true / true | 连续增强／持续低 ADX／低 ADX 与 DI 缠绕 |

输入必须满足 `0 < LevelWeak < LevelTrend < LevelStrong < 100`，容差为有限非负数，窗口和根数为合法正整数，交叉次数不能大于窗口。DI 最低 ADX 门槛为 0～100。无效输入会输出中文初始化错误并停止，不会悄悄换回默认值。为避免整数溢出，周期的代码上限为 1,073,741,822；窗口也保留额外索引空间。如此大的设置并不保证平台有足够历史或内存，句柄创建失败会明确报错。

## 事件含义

- ADX 上穿弱势线或趋势线：当前收盘 ADX 严格大于门槛，上一根小于等于门槛。19 → 26 可在同根同时触发两项。
- 连续站稳：连续 `ConfirmBars` 根 ADX ≥ 趋势线，只在首次进入时触发。
- 偏多／偏空交叉增强：DI 方向发生交叉，且 ADX 的相邻增量大于容差。ADX 下降时的 DI 交叉不满足本版增强事件。
- 连续增强：连续 `RiseComparisons` 次相邻差值大于容差，只在进入状态时触发。
- 高位转弱：上一根 ADX > 很强线，本根确认下降，前一段尚未明显下降。41、43、42 只在 42 那根确认，不提前放到 43。
- 持续低 ADX：连续低于弱势线，只在进入时触发。
- 低 ADX 与 DI 缠绕：使用原始 DI 交叉次数，不受 ADX 上升及可选最低 ADX 过滤影响，只在进入时触发。

精确公式、固定接口和读取示例见 [EA 缓冲区说明](GSM_ADX_BUFFER_MAP.md)。以上都是环境与方向提示，没有实现其他策略的「共振进场」。

## 提醒设置及边界

先将 `EnableAlerts=true`，再选择弹窗、声音或手机，并按需要关闭单项事件。手机推送还需在 MT5「工具 → 选项 → 通知」主动启用并配置 MetaQuotes ID。默认不会调用手机推送。

首次加载、改参数、切周期及全量历史重置只恢复标记，不补发旧提醒。正常新 K 线只处理最新有效已收盘位置；数据暂未准备好时不提前消费该 K 线，等待后续报价。断线恢复不循环补发离线期间每根事件。

同实例同根最多一次合并提醒。正文包含中文事件、品种、周期、ADX/+DI/-DI 和信号 K 线时间。总开关开启但三个外部渠道全部关闭时，只保留 `GSM_ADX_ALERT_CONFIRMED` 日志，可用于无外发通知的验证。

手机请求在本指标所有实例间共同限流：至少间隔 600 毫秒，每 60 秒最多 10 次；这个共享限制不控制其他无关 MQL 程序。被限流或失败的请求不会排队补发旧消息，并输出节流错误日志。手机消息受平台 255 字符限制，长事件列表可能缩短，但保留品种、周期、数值及 K 线时间。`SendNotification` 返回成功只表示终端接受请求，不代表手机已送达。

测试器内仅用缓冲区与日志核对提醒逻辑，不以弹窗、声音或推送送达作为通过依据。通知实机状态须单独查看 [测试报告](GSM_ADX_TEST_REPORT.md)。

## 数据准备与历史一致性

两个内置模式使用底层内置值；预热区间按当前 MetaQuotes 实现的绘图起点屏蔽：ADX 为从最早底层 K 线开始的零基索引 `2×周期`，Wilder DI 为 `周期+1`，普通 DI 为 `周期`。早期填充零被标为 `EMPTY_VALUE`，预热后的真实 0 不会被一律丢弃。不同状态分别检查所需数据；因此方向状态可能先于 ADX 强度状态有效。

Pine 模式保留原始 `nz(previous,0)`：最早一根 TR 与前收盘 0 比较，DM 与前高／前低 0 比较；因此不能擅自改成内置 ADX 的首根种子。每根平滑和按 `上一值－上一值/N＋本根值` 递推，DI=100×平滑 DM/平滑 TR，DX=100×|+DI−-DI|/(+DI+-DI)，ADX 是 DX 的 SMA。分母为 0 时使用 `EMPTY_VALUE`；分母有效而结果为 0 时保留真实 0。

Pine SMA 按最近 N 个有效 DX 计算，忽略 `na`，不把无效 DX 当 0。已有 N 个有效样本时，新的无效 DX 不挤出旧样本，ADX 可保持该有效窗口的平均值；未收集到 N 个有效 DX 前 ADX 为 `EMPTY_VALUE`。DI 最早可以在第一根有值，ADX 最早可以在第 N 根有值，不套用内置 2N 的起点。相关语义见 [TradingView 官方函数说明](https://www.tradingview.com/pine-script-docs/faq/functions/)。

进入状态比单个状态本身需要更多历史。例如默认连续增强状态需要 4 根 ADX，判断首次进入还要验证前一状态，因此确认事件共需要 5 根有效 ADX。每个缓冲区的边界详见接口文档。

数据复制不足、无效值或回看不足处为 `EMPTY_VALUE`；面板显示准备中或暂不可用，不把旧结论当当前值。普通 tick 只更新未收盘原始曲线；新 bar 计算新确认位置，历史补载或平台 `prev_calculated=0` 时安全重建。

相同参数和相同输入历史的已收盘事件只依赖该根及更早数据。平台补载更深历史、修正价格缺口或用户改参数会正常重算；这与事后读取未来数据、移动确认信号不同。测试时必须对齐算法、参数及历史起点，不能把三个算法之间的差异判为错误。Pine 模式尤其受首根种子影响：同品种同周期但可用历史起点不同，数值也可能不同。

## 包内文件与官方资料

- `MQL5/Indicators/GSM/GSM_ADX_Trend_Meter.mq5`：完整自包含源码。
- 同目录 `.ex5`：实际编译产物；具体编译器与哈希见测试报告及证据。
- `MQL5/Scripts/GSM_ADX_Compare.mq5`：无交易数值核对脚本。
- [GSM_ADX_BUFFER_MAP.md](GSM_ADX_BUFFER_MAP.md)：固定缓冲区、输入顺序与无交易读取示例。
- [GSM_ADX_TEST_REPORT.md](GSM_ADX_TEST_REPORT.md)：按通过／失败／未测试分项报告。

内置句柄和缓冲区：[iADXWilder](https://www.mql5.com/en/docs/indicators/iadxwilder)、[iADX](https://www.mql5.com/en/docs/indicators/iadx)。数据读取与重算：[CopyBuffer](https://www.mql5.com/en/docs/series/copybuffer)、[OnCalculate](https://www.mql5.com/en/docs/event_handlers/oncalculate)。通知约束：[Alert](https://www.mql5.com/en/docs/common/alert)、[SendNotification](https://www.mql5.com/en/docs/network/sendnotification)。

Pine 公式原作者为 **© BeikabuOyaji**，来源为用户提供的 `ADX and DI for v4`，许可证为 [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/)。交付源码保留原始署名及 MPL 2.0 声明。
