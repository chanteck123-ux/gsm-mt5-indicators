# 黄金EA指标研究：分工、数据口径与增量贡献

保存日期：2026-09-27（Asia/Kuala_Lumpur）。来源：用户本次提供的指标研究说明，要求“保存指标GitHub”；文中引用占位符已换成本次核对的原始来源。

**采用研究方向，不把文章默认参数直接设成黄金EA交易标准。** EMA只是趋势型候选的一个研究起点，不是所有策略的统一基础。先明确每套策略的用途、机会位置、触发／确认／失效条件，再分配指标职责，验证其是否改善扣除成本后的实际结果。

本次为研究资料保存：`RESEARCH_GUIDANCE_SAVED / NOT_IMPLEMENTED / NOT_BACKTESTED`。没有增加指标产品、修改现有MQ5／EX5或默认参数、接入EA、编译、回测、晋级Champion或更改实盘。以下接入与测试是后续已授权研发的执行要求，不代表本次已完成。

## 1. 分清计算定义、经验参数与风险偏好

| 类型 | 例子 | 处理方式 |
|---|---|---|
| 计算定义 | SMA／EMA、MACD信号线、ADX平滑方法、RSI计算 | 核对实际源码、初始化、输入、缓冲区、单位与时间语义；不同版本分别命名 |
| 经验参数 | ADX 25／20、RSI 70／30、均线50／200 | 作为候选值，不能直接认定适合黄金M5或最赚钱 |
| 风险偏好／项目政策 | 回撤、资金储备、每单与组合风险预算 | 依据用户目标及当前项目授权登记，不由指标值决定 |

ADX常见25／20解释与RSI常见70／30解释属于技术分析惯例。RSI在强趋势中可持续处于超买或超卖区，不能见阈值就机械反向开单。这些解释未验证本项目收益。[Fidelity ADX](https://www.fidelity.com/viewpoints/active-investor/average-directional-index-ADX)、[Fidelity RSI](https://www.fidelity.com/learning-center/trading-investing/technical-analysis/technical-indicator-guide/RSI)

200期是否属于长期，要连同周期、交易时段和实际K线时间判断；M5的200根与D1的200根不是同一时间尺度。保存参数时同时保存品种、周期、报价来源和预热方式，不能只写“200”。

## 2. 同名MACD、同为12／26／9，不保证相同信号

| 实现／参考 | 默认主线 | 默认信号线 | 接入注意 |
|---|---|---|---|
| Fidelity介绍的常见定义 | EMA12 − EMA26 | MACD的EMA9 | 参数相同不等于MT5内置定义相同 |
| MT5官方内置MACD | EMA12 − EMA26 | MACD的SMA9 | 核对实际平台、缓冲区和采样时点 |
| 本库CM_MACD_Ult_MTF_MT5 | EMA12 − EMA26 | SMA9 | 高周期映射使用完成值，事件另按接口确认 |
| 本库ZeroLag_MACD_MT5 | 默认DEMA12 − DEMA26 | 默认EMA9 | 自定义模式可改变算法；名称不保证没有延迟 |

前两项定义分别见[Fidelity MACD](https://www.fidelity.com/learning-center/trading-investing/technical-analysis/technical-indicator-guide/macd)与[MT5 MACD](https://www.metatrader5.com/en/terminal/help/indicators/oscillators/macd)。后两项已核对本库[MACD比较说明](../packages/MT5_Indicator_Suite/MACD_比较说明.md)、[CM源码](../packages/MT5_Indicator_Suite/CM_MACD_Ult_MTF_MT5.mq5)和[ZeroLag源码](../packages/MT5_Indicator_Suite/ZeroLag_MACD_MT5.mq5)，读取基准提交为`de12c127a7f8ab7522a3126f99be508ba16c4750`；本次未重跑历史指标验证。

接口不能混用：CM的MACD／Signal／Hist为buffer 0／2／3，ZeroLag为0／1／2。还要核对均线种子、输入价格、历史起点、周期映射、已收盘／未收盘K线、`BarsCalculated`、`CopyBuffer`实际返回数和`EMPTY_VALUE`。只对齐指标名及参数，不能宣称交叉时刻或交易结果等价。

## 3. 黄金成交量：先确认数据代表什么

MT5的`MqlRates`分别提供`tick_volume`和`real_volume`；先检查具体券商、具体品种、具体历史区间的可用数据，不能默认两者相同。[MqlRates官方定义](https://www.mql5.com/en/docs/constants/structures/mqlrates)

只有Tick量时，将研究结果明确命名为Tick量版本。用它计算OBV不能解释为全球黄金真实资金流；以Tick次数加权的均价也不等于按真实成交量计算的VWAP。即使有Real Volume，也须说明来源及覆盖市场，不能自动推广为全球黄金成交量。

本库[VFI接口](../packages/GSM_ATR_VFI/VFI_规则与缓冲区说明.md)及[源码](../packages/GSM_ATR_VFI/MQL5/Indicators/GSM/Volume_Flow_Indicator_MT5.mq5)默认Tick量，选择Real后不会悄悄回退；缺量／零均量按既有接口处理，不伪造有效信号。[Volume Profile源码](../packages/MT5_Indicator_Suite/Volume_Profile_MT5.mq5)也区分两种量，其当前区间快照不能回填成历史POC；历史研究须另验证决策时刻可得的数据与重算方法。

OBV与VWAP在本说明中是研究举例，不表示它们已加入本库13项成品清单或接入EA。以后采用时先检查平台内置能力、可复用实现、计算窗口／锚点及数据定义。

## 4. 指标不能替代独立风险控制

ATR提供价格波动尺度，可辅助设计止损或追踪距离，但它不是账户货币损失，也不自动限制账户亏损。OBV／VWAP不承担账户级风险上限。布林带可用于位置、突破或形态研究；触碰上轨本身不是卖出信号，触碰下轨本身不是买入信号。[Bollinger原作者规则](https://www.bollingerbands.com/bollinger-band-rules)

风险计算要把入场、初始止损、合约、手数、费用、保证金和组合风险连接起来。在线性合约且相关费用近似随手数成比例的假设下：

```text
初步手数 = 本次允许损失预算（账户货币）
         / [每1手从计划入场到初始止损的预计损失（账户货币）
            + 每1手尚未包含的费用及额外滑点预留（账户货币）]
```

USD账户可统一用USD；非USD账户须先换成同一账户货币，不能混除。`OrderCalcProfit`按方向、实际品种、指定手数及入场／止损价格估算账户货币损益，须检查调用成功及输出；它不替代佣金、隔夜费和执行压力核算。[OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit)

1手只是归一基准；若实际合约不允许直接用1手查询，选择有效参考手数并在适用的线性假设下归一。手续费阶梯、最低收费或非线性结构应按候选实际手数重新计算，不能机械套上述比例。按实际最小手数、步长、最大量及保证金条件选合法手数后，再核对预算和组合风险；向上凑到最小手数不能继续声称未增加风险。无可行手数时登记约束，研究有依据的调整。

已经体现在实际／所用假设买卖成交价中的点差不再扣第二遍。滑点已计入预估平仓价时，避免再次加入同一项预留；尚未包含的费用另列。预期未来触发保本不能抵扣入场时的初始风险；风险预算也不能保证跳空、滑点或执行失败下的实际损失不超出。

比较ATR退出前后，固定同轮基础风险并重新核对手数及实际敞口，区分退出改善和风险增加。当前用户Scalping SOP按既有权限保护；确认NON_USER策略在已授权研究中可自主优化，不因指标模块而绕过策略归属与项目风险限制。已有仓位保护不能因新入场过滤而跳过。

## 5. 两项研究的结论与外推边界

| 来源 | 本次核对到的内容 | 对黄金EA的合理用途与限制 |
|---|---|---|
| Hutchinson等（2022），Technical trading rule profitability in currencies: It’s all about momentum | 摘要报告其货币规则组合的平均Sharpe从样本内0.66降至样本外0.06，样本外回报未承受适度成本 | 提醒检查成本、时变有效性和选择偏差；不能推出所有技术指标EA必亏 |
| Hurst、Ooi、Pedersen（2017），A Century of Evidence on Trend-Following Investing | 使用跨市场组合，等权结合1、3、12个月时间序列动量，每月再平衡 | 支持趋势跟随作为研究方向；不证明黄金M5某个EMA／MACD参数有效 |

来源：[Hutchinson等原论文（大学库PDF）](https://repository.adu.ac.ae/bitstreams/30d15095-739e-4967-a33f-7233bf0644df/download)、[AQR原论文PDF](https://www.aqr.com/-/media/AQR/Documents/Insights/Journal-Article/AQR-JPM-Fall-2017.pdf)。本次核对摘要和相关方法段，没有复现论文数据或试验；二者市场、周期、组合及成本模型不同，不构成互相否定或本EA盈利证据。

## 6. 指标搭配必须检验新增条件的贡献

先按每套策略登记用途／适用行情、价格／结构位置、触发／确认／失效，再选参数与指标。不默认EMA、MACD、ADX、RSI、布林带全部同时同意。相关信息可能重复，也可能在特定时间尺度与逻辑位置提供额外价值；不凭同源或数量直接判无用／更优。Bollinger的组合规则提醒避免直接重复的信息，本项目用对照验证实际贡献。[原作者组合规则](https://www.bollingerbands.com/bollinger-band-rules)

| 候选变化 | 需要回答的问题 | 对照设计 |
|---|---|---|
| 加ADX强度条件 | 拦掉哪些亏损机会，又错过哪些盈利机会？时点是否过迟？ | 保留原基线，对比开／关及少量预登记参数，记录每个拒绝原因 |
| 加MACD确认 | 提供新信息，还是重复均线条件？不同公式的影响是什么？ | 基线、单项、明确交互组合与移除组件对照；核对时间和公式 |
| ATR止损／追踪 | 是退出位置更合理，还是承担更多风险才赚更多？ | 同基础风险、明确退出规则与实际手数，单列退出及风险因素 |
| 加VFI／OBV／VWAP类量价条件 | 数据有效吗？增量信息依赖Tick量还是真实量？ | 先固定数据口径和锚点，再测试策略贡献；未实现工具不能冒充已有产品 |

这些是待验证假设，不要求组件先单独盈利才能研究有明确交互理由的小组合。被过滤机会的后续盈亏只能按冻结的模拟执行规则作反事实分析，不能写成实际成交收益，也不能把事后赢家／输家标签输入当时的信号。

已授权开发中执行：登记假设、基线、变量、试验预算和比较条件 → 核对指标接口与时序 → 实际接入EA候选 → 编译受影响源码 → 新回测 → 比较并归因 → 调整／替换／淘汰 → 再测试。参数单独变化可复用已核验EX5，但需对应新配置和报告。只显示指标或写研究报告不能作为EA开发完成。

用相同资金、行情区间、合约、基础风险及成本条件，比较净利润USD、最大权益回撤金额、最大相对权益回撤%、PF、完整交易数及成本；提款场景另看剩余权益、保证金、实际交易机会与持续运作。最大金额回撤和最大相对回撤分别记录。评分沿用所选EA计划，不给指标名称、数量或共振数加分；参考[当前中文EA计划](https://github.com/chanteck123-ux/TX-AI---EA-GOLD-Trading/blob/main/FINAL_CHAMPION_ITERATION_SYSTEM_CN.md)的§11与§13.8–§13.10，其他项目按自己的授权条件。

保留成功和失败的全部试验、候选ID／运行ID、EA与指标源码／EX5哈希、配置、编译日志和报告。反复用于调整的时段标为已使用，冻结后另做成本／延迟压力及未用于选择的验证。DSR是研究多次试验选择偏差与非正态收益的辅助工具，依赖输入和假设，不保证未来盈利。[DSR原论文](https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf)

每轮结论必须说清：多赚或少赚多少USD、回撤如何变化、成本如何变化、改善是否来自增加风险，以及提款后能否按规则继续运作。证据不足写明缺口，继续有依据的研究，保留当前条件下已验证的最佳版本与恢复点。

## 7. 仓库接口与保存范围

入口：[指标清单](../indicator_manifest.json) → [根README接口说明](../README.md) → 各package的源码、buffer文档和历史验证报告。正式指标仍为原13项；本说明未选择“最佳搭配”，未将经验参数改成源码默认值。

资料核对与保存仅证明定义、来源、链接和文件版本已整理。现有编译／指标行为证据保持其原日期和范围；新增EA收益、真实Tick回测、成本压力和样本外表现仍须在后续授权研发中实际验证。
