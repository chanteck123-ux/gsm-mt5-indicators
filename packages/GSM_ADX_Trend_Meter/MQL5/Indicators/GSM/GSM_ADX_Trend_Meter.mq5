// GSM ADX 趋势强弱测量器 v1.00
// Independent indicator. No order, account, DLL or external-service API.
// Specification: CODEX_GSM_ADX_Trend_Meter_MT5_v1.0.md (2026-09-08).
// Pine ADX/DI formula adapted from "ADX and DI for v4", © BeikabuOyaji.
// This Source Code Form is subject to the terms of Mozilla Public License 2.0:
// https://mozilla.org/MPL/2.0/ . Original attribution is retained below.
#property strict
#property version "1.00"
#property description "ADX 与 DMI 环境提示；收盘确认；不自动交易。"
#property indicator_separate_window
#property indicator_height 320
#property indicator_minimum 0
#property indicator_buffers 20
#property indicator_plots 15
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_type3 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_color2 clrLimeGreen
#property indicator_color3 clrTomato
#property indicator_width1 2
#property indicator_width2 1
#property indicator_width3 1

enum GSMADXMethod { WILDER=0, MT5_STANDARD=1, PINE_ADX_DI=2 };
input group "一、算法与事件定义"
input GSMADXMethod ADXMethod=WILDER;          // 算法：Wilder／普通 ADX／Pine ADX and DI
input int ADXPeriod=14;                       // ADX 周期（本指标最小为 2）
input double LevelWeak=20.0;                  // 弱势参考线
input double LevelTrend=25.0;                 // 趋势参考线
input double LevelStrong=40.0;                // 很强趋势参考线
input double SlopeEpsilon=0.0;                // ADX 变化容差（指标数值）
input int ConfirmBars=2;                      // 连续站稳的收盘根数
input int RiseComparisons=3;                  // 连续增强的相邻比较次数
input int LowADXBars=10;                      // 持续低 ADX 的收盘根数
input int DICrossLookback=10;                 // DI 缠绕的相邻比较次数
input int DICrossMinCount=3;                  // 缠绕至少原始交叉次数
input bool UseMinADXForDICross=false;         // DI 交叉额外启用最低 ADX 门槛
input double MinADXForDICross=25.0;           // DI 交叉最低 ADX（仅开启时过滤）
input group "二、显示与中文面板"
input bool ShowPanel=true;                   // 显示中文面板
input bool ShowDILines=true;                 // 显示 DI 曲线（不影响缓冲区）
input bool PanelLivePreview=false;           // 实时预览：未收盘数值会变化
input bool ShowSignalMarkers=true;          // 标注已确认事件
input int MaxMarkerBars=500;                 // 标记历史范围（不限制缓冲区）
input color ADXColor=clrDodgerBlue;           // ADX 颜色
input color PlusDIColor=clrLimeGreen;         // +DI 颜色
input color MinusDIColor=clrTomato;           // -DI 颜色
input int ADXWidth=2;                        // ADX 线宽 1～5
input int PlusDIWidth=1;                     // +DI 线宽 1～5
input int MinusDIWidth=1;                    // -DI 线宽 1～5
input color LevelColor=clrSlateGray;         // 参考线颜色
input ENUM_LINE_STYLE LevelStyle=STYLE_DOT;  // 参考线样式
input int LevelWidth=1;                      // 参考线线宽 1～5
input ENUM_BASE_CORNER PanelCorner=CORNER_LEFT_UPPER; // 面板位置
input int PanelX=12;                        // 面板横向距离（像素）
input int PanelY=14;                        // 面板纵向距离（像素）
input int PanelFontSize=10;                 // 面板字号 7～24
input string PanelFont="Microsoft YaHei";  // 中文字体
input color PanelTextColor=clrGainsboro;     // 面板文字颜色
input color PanelBackground=clrBlack;       // 面板背景颜色
input group "三、提醒（默认总开关关闭）"
input bool EnableAlerts=false;             // 提醒总开关
input bool EnablePopup=true;               // 弹窗（需总开关）
input bool EnableSound=false;              // 声音（需总开关）
input bool EnablePush=false;               // 手机推送（需主动配置终端通知）
input string SoundFile="alert.wav";       // 终端 Sounds 文件夹中的声音
input bool AlertCrossWeak=true;            // 提醒：ADX 上穿弱势线
input bool AlertCrossTrend=true;           // 提醒：ADX 上穿趋势线
input bool AlertBull=true;                 // 提醒：偏多 DI 交叉增强
input bool AlertBear=true;                 // 提醒：偏空 DI 交叉增强
input bool AlertHighTurnDown=true;         // 提醒：高位转弱
input bool AlertTrendConfirmed=true;       // 提醒：连续站稳趋势线
input bool AlertRising=true;               // 提醒：连续增强
input bool AlertLongLow=true;              // 提醒：持续低 ADX
input bool AlertChoppy=true;               // 提醒：低 ADX 与 DI 缠绕

// GSM_RULES_BEGIN
// All arrays use series indexing. Their caller masks each raw line's warm-up.
// Each result is checked independently; no short-circuit hides missing history.
struct GSMRuleSettings
  {
   double weak,trend,strong,epsilon,min_di_adx;
   int confirm_bars,rise_comparisons,low_bars,cross_lookback,cross_min;
   bool use_min_di_adx;
  };
bool GSMValidValue(const double value)
  { return(value!=EMPTY_VALUE && MathIsValidNumber(value)); }
bool GSMValidRange(const double &v[],const int from,const int length,const int count)
  {
   if(from<0 || length<1 || count<0 || from>=count || length>count-from || count>ArraySize(v)) return(false);
   for(int i=from;i<from+length;i++) if(!GSMValidValue(v[i])) return(false);
   return(true);
  }
bool GSMAbove(const double &a[],const int s,const GSMRuleSettings &cfg)
  { for(int j=0;j<cfg.confirm_bars;j++) if(a[s+j]<cfg.trend) return(false); return(true); }
bool GSMRising(const double &a[],const int s,const GSMRuleSettings &cfg)
  { for(int j=0;j<cfg.rise_comparisons;j++) if(a[s+j]-a[s+j+1]<=cfg.epsilon) return(false); return(true); }
bool GSMLow(const double &a[],const int s,const GSMRuleSettings &cfg)
  { for(int j=0;j<cfg.low_bars;j++) if(a[s+j]>=cfg.weak) return(false); return(true); }
int GSMCrossCount(const double &p[],const double &m[],const int s,const int comparisons)
  {
   int total=0;
   for(int j=0;j<comparisons;j++)
     if((p[s+j]>m[s+j] && p[s+j+1]<=m[s+j+1]) ||
        (m[s+j]>p[s+j] && m[s+j+1]<=p[s+j+1])) total++;
   return(total);
  }
void GSMEvaluateRules(const double &a[],const double &p[],const double &m[],const int s,const int count,
                      const GSMRuleSettings &cfg,double &out[])
  {
   ArrayResize(out,12);
   ArrayInitialize(out,EMPTY_VALUE);
   if(s<1 || count<=s || cfg.confirm_bars<1 || cfg.rise_comparisons<1 || cfg.low_bars<1 ||
      cfg.cross_lookback<1 || cfg.confirm_bars>=2147483646 || cfg.rise_comparisons>=2147483645 ||
      cfg.low_bars>=2147483646 || cfg.cross_lookback>=2147483645) return;
   if(GSMValidRange(a,s,1,count))
      out[0]=(a[s]<cfg.weak ? 0.0 : a[s]<cfg.trend ? 1.0 : a[s]<=cfg.strong ? 2.0 : 3.0);
   if(GSMValidRange(p,s,1,count) && GSMValidRange(m,s,1,count))
      out[1]=(p[s]>m[s] ? 1.0 : p[s]<m[s] ? -1.0 : 0.0);
   if(GSMValidRange(a,s,2,count))
     {
      double delta=a[s]-a[s+1];
      out[2]=(delta>cfg.epsilon ? 1.0 : delta< -cfg.epsilon ? -1.0 : 0.0);
      out[3]=(a[s]>cfg.weak && a[s+1]<=cfg.weak ? 1.0 : 0.0);
      out[4]=(a[s]>cfg.trend && a[s+1]<=cfg.trend ? 1.0 : 0.0);
      if(GSMValidRange(p,s,2,count) && GSMValidRange(m,s,2,count))
        {
         bool allowed=(delta>cfg.epsilon && (!cfg.use_min_di_adx || a[s]>=cfg.min_di_adx));
         out[5]=(allowed && p[s]>m[s] && p[s+1]<=m[s+1] ? 1.0 : 0.0);
         out[6]=(allowed && m[s]>p[s] && m[s+1]<=p[s+1] ? 1.0 : 0.0);
        }
     }
   if(GSMValidRange(a,s,3,count))
      out[7]=(a[s+1]>cfg.strong && a[s]-a[s+1]< -cfg.epsilon && a[s+1]-a[s+2]>= -cfg.epsilon ? 1.0 : 0.0);
   if(GSMValidRange(a,s,cfg.confirm_bars+1,count))
      out[8]=(GSMAbove(a,s,cfg) && !GSMAbove(a,s+1,cfg) ? 1.0 : 0.0);
   if(GSMValidRange(a,s,cfg.rise_comparisons+2,count))
      out[9]=(GSMRising(a,s,cfg) && !GSMRising(a,s+1,cfg) ? 1.0 : 0.0);
   if(GSMValidRange(a,s,cfg.low_bars+1,count))
      out[10]=(GSMLow(a,s,cfg) && !GSMLow(a,s+1,cfg) ? 1.0 : 0.0);
   if(GSMValidRange(a,s,2,count) && GSMValidRange(p,s,cfg.cross_lookback+2,count) &&
      GSMValidRange(m,s,cfg.cross_lookback+2,count))
     {
      bool current=(a[s]<cfg.weak && GSMCrossCount(p,m,s,cfg.cross_lookback)>=cfg.cross_min);
      bool prior=(a[s+1]<cfg.weak && GSMCrossCount(p,m,s+1,cfg.cross_lookback)>=cfg.cross_min);
      out[11]=(current && !prior ? 1.0 : 0.0);
     }
  }
// GSM_RULES_END

double B0[],B1[],B2[],B3[],B4[],B5[],B6[],B7[],B8[],B9[],B10[],B11[],B12[],B13[],B14[];
double T0[],T1[],T2[];
// Internal caches only. Public EA contract remains buffers 0..14.
double PineTR[],PineDMPlus[],PineDMMinus[],PineDX[],PineSMASum[];
GSMRuleSettings g_rules;
int g_handle=INVALID_HANDLE,g_window=-1,g_last_total=0,g_source_total=0;
int g_adx_begin=0,g_di_begin=0;
datetime g_oldest_time=0,g_current_time=0,g_processed_time=0,g_latest_event_time=0,g_marker_time=0;
bool g_need_rebuild=true,g_silent_baseline=true,g_data_ready=false,g_was_connected=false;
string g_prefix="",g_short_name="",g_latest_events="暂无已确认事件",g_unavailable="数据准备中";
ulong g_last_error_ms=0;
int g_latest_low_count=0;

void LogProblem(const string message)
  {
   ulong now=GetTickCount64();
   if(g_last_error_ms==0 || now-g_last_error_ms>=10000)
     { Print("GSM ADX：",message); g_last_error_ms=now; }
  }
string PeriodText()
  { string value=EnumToString(_Period); StringReplace(value,"PERIOD_",""); return(value); }
string MethodText()
  { return(ADXMethod==WILDER ? "ADX Wilder" : ADXMethod==MT5_STANDARD ? "MT5 普通 ADX" : "Pine ADX and DI"); }
bool InputError(const string detail)
  { Print("GSM ADX 初始化失败：",detail); return(false); }
bool ValidateInputs()
  {
   if(ADXMethod!=WILDER && ADXMethod!=MT5_STANDARD && ADXMethod!=PINE_ADX_DI) return(InputError("算法枚举无效。"));
   // Bound only arithmetic, never silently substitute a period or event window.
   if(ADXPeriod<2 || ADXPeriod>1073741822) return(InputError("ADX 周期必须为 2～1073741822；过大的周期可能因平台资源限制无法创建。"));
   if(!GSMValidValue(LevelWeak) || !GSMValidValue(LevelTrend) || !GSMValidValue(LevelStrong) ||
      !(0<LevelWeak && LevelWeak<LevelTrend && LevelTrend<LevelStrong && LevelStrong<100))
      return(InputError("阈值必须满足 0 < 弱势线 < 趋势线 < 很强线 < 100。"));
   if(!GSMValidValue(SlopeEpsilon) || SlopeEpsilon<0) return(InputError("ADX 变化容差必须为有限非负数。"));
   if(ConfirmBars<1 || ConfirmBars>2147483645 || RiseComparisons<1 || RiseComparisons>2147483644 ||
      LowADXBars<1 || LowADXBars>2147483645 || DICrossLookback<1 || DICrossLookback>2147483644)
      return(InputError("根数与比较窗口必须为合法正整数，并留出进入状态的额外回看空间。"));
   if(DICrossMinCount<1 || DICrossMinCount>DICrossLookback) return(InputError("DI 最少交叉次数必须在 1 与比较窗口之间。"));
   if(!GSMValidValue(MinADXForDICross) || MinADXForDICross<0 || MinADXForDICross>100)
      return(InputError("DI 最低 ADX 必须在 0～100 之间。"));
   if(MaxMarkerBars<1) return(InputError("历史标记范围必须为正整数。"));
   if(ADXWidth<1 || ADXWidth>5 || PlusDIWidth<1 || PlusDIWidth>5 || MinusDIWidth<1 || MinusDIWidth>5 || LevelWidth<1 || LevelWidth>5)
      return(InputError("曲线及参考线宽度必须在 1～5 之间。"));
   if(PanelFontSize<7 || PanelFontSize>24 || PanelX<0 || PanelY<0 || StringLen(PanelFont)==0)
      return(InputError("面板字号须为 7～24，位置不得为负，字体不能为空。"));
   if(PanelCorner<CORNER_LEFT_UPPER || PanelCorner>CORNER_RIGHT_LOWER)
      return(InputError("面板角落枚举无效。"));
   if(LevelStyle<STYLE_SOLID || LevelStyle>STYLE_DASHDOTDOT) return(InputError("参考线样式无效。"));
   if(EnableSound && StringLen(SoundFile)==0) return(InputError("开启声音时，声音文件名不能为空。"));
   return(true);
  }
void ConfigureRules()
  {
   g_rules.weak=LevelWeak; g_rules.trend=LevelTrend; g_rules.strong=LevelStrong; g_rules.epsilon=SlopeEpsilon;
   g_rules.min_di_adx=MinADXForDICross; g_rules.confirm_bars=ConfirmBars; g_rules.rise_comparisons=RiseComparisons;
   g_rules.low_bars=LowADXBars; g_rules.cross_lookback=DICrossLookback; g_rules.cross_min=DICrossMinCount;
   g_rules.use_min_di_adx=UseMinADXForDICross;
  }
long AllocateInstanceSequence()
  {
   // GetMicrosecondCount starts at each MQL program's start, so it is not a
   // terminal-wide identity. Use an atomic session counter instead.
   string name="GSM_ADX_INSTANCE_SEQUENCE_v1";
   if(!GlobalVariableCheck(name) && !GlobalVariableTemp(name) && !GlobalVariableCheck(name)) return(0);
   for(int attempt=0;attempt<64;attempt++)
     {
      double previous=GlobalVariableGet(name);
      if(!MathIsValidNumber(previous) || previous<0 || previous>=9007199254740990.0) return(0);
      if(GlobalVariableSetOnCondition(name,previous+1.0,previous)) return((long)(previous+1.0));
     }
   return(0);
  }
void WriteRules(const int s,const double &v[])
  {
   B3[s]=v[0]; B4[s]=v[1]; B5[s]=v[2]; B6[s]=v[3]; B7[s]=v[4]; B8[s]=v[5];
   B9[s]=v[6]; B10[s]=v[7]; B11[s]=v[8]; B12[s]=v[9]; B13[s]=v[10]; B14[s]=v[11];
  }
void ClearConfirmed(const int s)
  {
   B3[s]=EMPTY_VALUE; B4[s]=EMPTY_VALUE; B5[s]=EMPTY_VALUE; B6[s]=EMPTY_VALUE; B7[s]=EMPTY_VALUE;
   B8[s]=EMPTY_VALUE; B9[s]=EMPTY_VALUE; B10[s]=EMPTY_VALUE; B11[s]=EMPTY_VALUE; B12[s]=EMPTY_VALUE;
   B13[s]=EMPTY_VALUE; B14[s]=EMPTY_VALUE;
  }
void ClearRange(const int count)
  {
   int stop=MathMin(count,ArraySize(B0));
   for(int s=0;s<stop;s++) { B0[s]=EMPTY_VALUE; B1[s]=EMPTY_VALUE; B2[s]=EMPTY_VALUE; ClearConfirmed(s); }
  }
// Pine formula port: © BeikabuOyaji, "ADX and DI for v4", MPL-2.0.
// nz(x) replaces unavailable x with zero, including first-bar prior OHLC.
double PineNZ(const double value)
  { return(GSMValidValue(value) ? value : 0.0); }
void PinePushDX(const double value,double &ring[],int &count,int &head,double &sum)
  {
   if(!GSMValidValue(value)) return;
   int capacity=ArraySize(ring);
   if(capacity<1) return;
   if(count<capacity) { ring[count]=value; sum+=value; count++; }
   else { sum-=ring[head]; ring[head]=value; sum+=value; head=(head+1)%capacity; }
  }
bool CalculatePine(const int total,const int requested,const bool full,
                   const double &high[],const double &low[],const double &close[])
  {
   int start=requested-1,capacity=MathMin(ADXPeriod,total);
   double ring[];
   if(ArrayResize(ring,capacity)!=capacity) { LogProblem("Pine DX 有效样本窗口分配失败。"); return(false); }
   int count=0,head=0; double sum=0.0;
   if(full)
     {
      ArrayInitialize(PineTR,EMPTY_VALUE); ArrayInitialize(PineDMPlus,EMPTY_VALUE);
      ArrayInitialize(PineDMMinus,EMPTY_VALUE); ArrayInitialize(PineDX,EMPTY_VALUE);
      ArrayInitialize(PineSMASum,0.0);
     }
   else
     {
      // Restore the N most recent valid DX samples strictly older than the first
      // recalculated bar; the unfinished bar's prior tick must not seed itself.
      for(int s=start+1;s<total && count<capacity;s++)
         if(GSMValidValue(PineDX[s])) { ring[count]=PineDX[s]; count++; }
      for(int i=0;i<count/2;i++) { double swap=ring[i]; ring[i]=ring[count-1-i]; ring[count-1-i]=swap; }
      // Reuse the same historical arithmetic accumulator as full chronological
      // calculation; re-summing only this window can introduce epsilon=0 event
      // differences through floating-point rounding after a refresh.
      if(start+1<total && GSMValidValue(PineSMASum[start+1])) sum=PineSMASum[start+1];
      else for(int i=0;i<count;i++) sum+=ring[i];
     }
   for(int s=start;s>=0;s--)
     {
      B0[s]=EMPTY_VALUE; B1[s]=EMPTY_VALUE; B2[s]=EMPTY_VALUE; PineDX[s]=EMPTY_VALUE;
      bool has_prior=(s+1<total);
      double prior_close=(has_prior ? PineNZ(close[s+1]) : 0.0);
      double prior_high=(has_prior ? PineNZ(high[s+1]) : 0.0);
      double prior_low=(has_prior ? PineNZ(low[s+1]) : 0.0);
      if(GSMValidValue(high[s]) && GSMValidValue(low[s]))
        {
         double tr=MathMax(MathMax(high[s]-low[s],MathAbs(high[s]-prior_close)),MathAbs(low[s]-prior_close));
         double up=high[s]-prior_high,down=prior_low-low[s];
         double dm_plus=(up>down ? MathMax(up,0.0) : 0.0);
         double dm_minus=(down>up ? MathMax(down,0.0) : 0.0);
         double prev_tr=(has_prior ? PineNZ(PineTR[s+1]) : 0.0);
         double prev_plus=(has_prior ? PineNZ(PineDMPlus[s+1]) : 0.0);
         double prev_minus=(has_prior ? PineNZ(PineDMMinus[s+1]) : 0.0);
         PineTR[s]=prev_tr-(prev_tr/ADXPeriod)+tr;
         PineDMPlus[s]=prev_plus-(prev_plus/ADXPeriod)+dm_plus;
         PineDMMinus[s]=prev_minus-(prev_minus/ADXPeriod)+dm_minus;
         if(GSMValidValue(PineTR[s]) && PineTR[s]!=0.0 && GSMValidValue(PineDMPlus[s]) && GSMValidValue(PineDMMinus[s]))
           {
            B1[s]=PineDMPlus[s]/PineTR[s]*100.0;
            B2[s]=PineDMMinus[s]/PineTR[s]*100.0;
            if(!GSMValidValue(B1[s])) B1[s]=EMPTY_VALUE;
            if(!GSMValidValue(B2[s])) B2[s]=EMPTY_VALUE;
            if(GSMValidValue(B1[s]) && GSMValidValue(B2[s]) && B1[s]+B2[s]!=0.0)
               PineDX[s]=MathAbs(B1[s]-B2[s])/(B1[s]+B2[s])*100.0;
           }
        }
      else { PineTR[s]=EMPTY_VALUE; PineDMPlus[s]=EMPTY_VALUE; PineDMMinus[s]=EMPTY_VALUE; }
      // Pine sma ignores na: a missing DX does not enter or evict from the queue.
      // Once N valid samples exist, even a current na retains their SMA.
      PinePushDX(PineDX[s],ring,count,head,sum);
      PineSMASum[s]=sum;
      if(count==ADXPeriod) B0[s]=sum/ADXPeriod;
      if(!GSMValidValue(B0[s])) B0[s]=EMPTY_VALUE;
     }
   return(true);
  }
double EventAt(const int event_index,const int s)
  {
   switch(event_index)
     {
      case 0:return(B6[s]); case 1:return(B7[s]); case 2:return(B8[s]); case 3:return(B9[s]);
      case 4:return(B10[s]); case 5:return(B11[s]); case 6:return(B12[s]); case 7:return(B13[s]);
      case 8:return(B14[s]);
     }
   return(EMPTY_VALUE);
  }
bool EventEnabled(const int event_index)
  {
   switch(event_index)
     {
      case 0:return(AlertCrossWeak); case 1:return(AlertCrossTrend); case 2:return(AlertBull); case 3:return(AlertBear);
      case 4:return(AlertHighTurnDown); case 5:return(AlertTrendConfirmed); case 6:return(AlertRising);
      case 7:return(AlertLongLow); case 8:return(AlertChoppy);
     }
   return(false);
  }
string EventText(const int event_index,const double adx)
  {
   switch(event_index)
     {
      case 0:return(StringFormat("ADX 上穿 %g，关注趋势形成",LevelWeak));
      case 1:return(StringFormat("ADX 上穿 %g，强度提升",LevelTrend));
      case 2:return("偏多 DI 交叉，趋势强度增强"+(adx<LevelWeak ? "（强度仍低，尚未形成明显趋势）" : ""));
      case 3:return("偏空 DI 交叉，趋势强度增强"+(adx<LevelWeak ? "（强度仍低，尚未形成明显趋势）" : ""));
      case 4:return("ADX 高位转弱，检查持仓保护");
      case 5:return(StringFormat("ADX 连续 %d 根站稳 %g",ConfirmBars,LevelTrend));
      case 6:return(StringFormat("ADX 连续 %d 次比较增强",RiseComparisons));
      case 7:return(StringFormat("趋势偏弱持续 %d 根",LowADXBars));
      case 8:return("低 ADX + DI 反复交叉，震荡风险较高");
     }
   return("");
  }
string EventList(const int s,const bool alerts_only=false)
  {
   string result="";
   for(int e=0;e<9;e++) if(EventAt(e,s)==1.0 && (!alerts_only || EventEnabled(e)))
     { if(result!="") result+="；"; result+=EventText(e,B0[s]); }
   return(result);
  }
bool ClosedReady(const int s)
  {
   if(s<1 || s>=ArraySize(B0) || !GSMValidValue(B0[s]) || !GSMValidValue(B1[s]) || !GSMValidValue(B2[s]) ||
      !GSMValidValue(B3[s]) || !GSMValidValue(B4[s]) || !GSMValidValue(B5[s])) return(false);
   for(int e=0;e<9;e++) if(!GSMValidValue(EventAt(e,s))) return(false);
   return(true);
  }

// A terminal-wide cooperative rate limiter shared by every GSM ADX instance.
// Reserve attempts (including failed requests); never queue old notifications.
bool ReservePushSlot()
  {
   string lock_name="GSM_ADX_PUSH_LOCK_v1";
   GlobalVariableTemp(lock_name);
   double prior=GlobalVariableGet(lock_name),now_seconds=(double)TimeLocal();
   if(prior>now_seconds || !GlobalVariableSetOnCondition(lock_name,now_seconds+10.0,prior))
     { LogProblem("手机推送未发送：共享限流锁忙；不补发旧消息。"); return(false); }
   double now=(double)GetTickCount64(),oldest=DBL_MAX;
   int count=0,slot=0;
   for(int k=0;k<10;k++)
     {
      string name="GSM_ADX_PUSH_SLOT_v1_"+IntegerToString(k);
      GlobalVariableTemp(name);
      double stamp=GlobalVariableGet(name);
      if(stamp>0 && now>=stamp && now-stamp<60000.0) count++;
      if(stamp>0 && now>=stamp && now-stamp<600.0)
        { GlobalVariableSet(lock_name,0.0); LogProblem("手机推送未发送：至少间隔 600 毫秒；不补发旧消息。"); return(false); }
      if(stamp<oldest || stamp>now) { oldest=stamp; slot=k; }
     }
   if(count>=10)
     { GlobalVariableSet(lock_name,0.0); LogProblem("手机推送未发送：每分钟最多 10 次；不补发旧消息。"); return(false); }
   GlobalVariableSet("GSM_ADX_PUSH_SLOT_v1_"+IntegerToString(slot),now);
   GlobalVariableSet(lock_name,0.0);
   return(true);
  }
void DeliverAlerts(const datetime bar_time,const string events,const int s)
  {
   if(!EnableAlerts || events=="") return;
   string message=StringFormat("GSM ADX | %s %s | %s | ADX %.2f，+DI %.2f，-DI %.2f | 信号K线 %s",
      _Symbol,PeriodText(),events,B0[s],B1[s],B2[s],TimeToString(bar_time,TIME_DATE|TIME_MINUTES));
   Print("GSM_ADX_ALERT_CONFIRMED | ",message);
   if(MQLInfoInteger(MQL_TESTER))
     { Print("GSM ADX：测试器只记录已确认提醒；不验证弹窗、声音或手机送达。"); return; }
   if(EnablePopup) Alert(message);
   if(EnableSound && !PlaySound(SoundFile)) LogProblem(StringFormat("声音播放失败，错误 %d，文件 %s。",GetLastError(),SoundFile));
   if(EnablePush)
     {
      if(!TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
        { LogProblem("手机推送未发送：请先在终端选项中开启并配置通知。"); return; }
      if(!ReservePushSlot()) return;
      // Official SendNotification limit is 255 characters. Keep the bar identity.
      string suffix=StringFormat(" | ADX %.2f +DI %.2f -DI %.2f | K线 %s",B0[s],B1[s],B2[s],TimeToString(bar_time,TIME_DATE|TIME_MINUTES));
      string prefix="GSM ADX | "+_Symbol+" "+PeriodText()+" | ";
      int available=255-StringLen(prefix)-StringLen(suffix);
      string body=events;
      if(StringLen(body)>available) body=StringSubstr(body,0,MathMax(0,available-1))+"…";
      ResetLastError();
      if(!SendNotification(prefix+body+suffix)) LogProblem(StringFormat("手机推送调用失败，错误 %d；该事件不重复提交。",GetLastError()));
      else Print("GSM ADX：终端已接受推送请求；不等于手机已送达。");
     }
  }

void EnsureWindow()
  { g_window=ChartWindowFind(0,g_short_name); }
void ObjectCommon(const string name)
  {
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }
void PanelGeometry(int &x,int &y,int &width,int &height)
  {
   int window_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,g_window);
   int window_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,g_window);
   width=MathMax(100,MathMin(window_width-2*PanelX,PanelFontSize*53));
   height=(PanelFontSize+9)*11+16;
   bool right=(PanelCorner==CORNER_RIGHT_UPPER || PanelCorner==CORNER_RIGHT_LOWER);
   bool bottom=(PanelCorner==CORNER_LEFT_LOWER || PanelCorner==CORNER_RIGHT_LOWER);
   x=MathMax(0,right ? window_width-PanelX-width : PanelX);
   y=MathMax(0,bottom ? window_height-PanelY-height : PanelY);
  }
void PutPanelLine(const int row,const string text,const color text_color)
  {
   string name=g_prefix+"P"+IntegerToString(row);
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_LABEL,g_window,0,0)) return;
   int x,y,width,height; PanelGeometry(x,y,width,height);
   int line_height=PanelFontSize+9;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x+9);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+8+row*line_height);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,PanelFontSize);
   ObjectSetString(0,name,OBJPROP_FONT,PanelFont);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,2);
   ObjectCommon(name);
  }
string MarketText(const double state)
  {
   if(state==0) return("趋势偏弱／震荡倾向"); if(state==1) return("趋势形成中");
   if(state==2) return("趋势较明显"); if(state==3) return("趋势很强"); return("数据准备中");
  }
void RenderPanel()
  {
   if(!ShowPanel) return;
   EnsureWindow(); if(g_window<1) return;
   string name=g_prefix+"PB";
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,g_window,0,0)) return;
   int x,y,width,height; PanelGeometry(x,y,width,height);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,PanelBackground);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,1); ObjectCommon(name);
   string lines[11];
   lines[0]="GSM ADX 趋势强弱测量器";
   lines[1]="品种："+_Symbol+"    周期："+PeriodText();
   lines[2]=StringFormat("算法：%s    参数：%d",MethodText(),ADXPeriod);
   lines[3]=(PanelLivePreview ? "数据：未收盘，数值会变化（正式信号仍收盘确认）" : "数据：最近已收盘K线");
   int s=(PanelLivePreview ? 0 : 1);
   bool valid=(g_data_ready && s<ArraySize(B0) && GSMValidValue(B0[s]) && GSMValidValue(B1[s]) && GSMValidValue(B2[s]));
   if(!valid)
     {
      lines[4]="ADX／DI："+g_unavailable;
      lines[5]="市场环境：数据准备中／数据暂不可用"; lines[6]="趋势变化：等待有效数据";
      lines[7]="方向参考：等待有效数据"; lines[8]="最新事件：等待当前数据确认"; lines[9]="状态：预热或数据获取未完成";
     }
   else
     {
      double market=(B0[s]<LevelWeak ? 0 : B0[s]<LevelTrend ? 1 : B0[s]<=LevelStrong ? 2 : 3);
      string slope="数据准备中";
      if(s+1<ArraySize(B0) && GSMValidValue(B0[s+1]))
        { double delta=B0[s]-B0[s+1]; slope=(delta>SlopeEpsilon ? "增强" : delta< -SlopeEpsilon ? "减弱" : "基本走平"); }
      string direction=(B1[s]>B2[s] ? "偏多" : B1[s]<B2[s] ? "偏空" : "方向均衡");
      if(B1[s]!=B2[s] && B0[s]<LevelWeak) direction+="，但趋势强度不足";
      lines[4]=StringFormat("ADX：%.2f    +DI：%.2f    -DI：%.2f",B0[s],B1[s],B2[s]);
      lines[5]="市场环境："+MarketText(market); lines[6]="趋势变化："+slope; lines[7]="方向参考："+direction;
      string short_event=g_latest_events;
      if(StringLen(short_event)>27) short_event=StringSubstr(short_event,0,26)+"…";
      lines[8]="最新已确认事件："+short_event;
      if(!ClosedReady(1)) lines[9]="状态：部分正式事件仍在等待回看窗口";
      else if(g_latest_low_count>=LowADXBars) lines[9]=StringFormat("状态：趋势偏弱已持续 %d 根（已收盘）",g_latest_low_count);
      else lines[9]=(g_latest_event_time>0 ? "事件K线："+TimeToString(g_latest_event_time,TIME_DATE|TIME_MINUTES) : "状态：已完成数据确认");
     }
   lines[10]="说明：环境提示，不是自动买卖指令";
   for(int row=0;row<11;row++) PutPanelLine(row,lines[row],row==0 ? clrLightSkyBlue : PanelTextColor);
   ObjectSetString(0,g_prefix+"P8",OBJPROP_TOOLTIP,g_latest_events);
  }
void SyncMarker(const int s,const datetime bar_time)
  {
   string name=g_prefix+"E"+IntegerToString((long)bar_time),events=EventList(s);
   if(events=="" || !GSMValidValue(B0[s])) { ObjectDelete(0,name); return; }
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_ARROW,g_window,bar_time,B0[s])) return;
   ObjectMove(0,name,0,bar_time,B0[s]);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,159);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   color c=(B10[s]==1 ? clrOrange : B8[s]==1 ? clrLimeGreen : B9[s]==1 ? clrTomato : clrGold);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,TimeToString(bar_time,TIME_DATE|TIME_MINUTES)+" | "+events);
   ObjectCommon(name);
  }
void UpdateMarkers(const datetime &time[],const int total,const bool full,const int closed_updates)
  {
   if(!ShowSignalMarkers) return;
   EnsureWindow(); if(g_window<1 || total<2) return;
   int horizon=MathMin(MaxMarkerBars,total-1);
   bool redraw=(full || g_marker_time==0);
   int count=(redraw ? horizon : MathMin(horizon,closed_updates));
   for(int s=count;s>=1;s--) SyncMarker(s,time[s]);
   if(redraw || g_marker_time!=time[0])
     {
      datetime cutoff=time[horizon];
      string prefix=g_prefix+"E";
      for(int j=ObjectsTotal(0,g_window,-1)-1;j>=0;j--)
        {
         string name=ObjectName(0,j,g_window,-1);
         if(StringFind(name,prefix)==0)
           {
            datetime when=(datetime)StringToInteger(StringSubstr(name,StringLen(prefix)));
            int s=iBarShift(_Symbol,_Period,when,true);
            if(when<cutoff || s<1 || s>horizon || EventList(s)=="") ObjectDelete(0,name);
           }
        }
      g_marker_time=time[0];
     }
  }
void RefreshLatestEvent(const datetime &time[],const int total,const bool full,const int closed_updates)
  {
   if(full) { g_latest_events="暂无已确认事件"; g_latest_event_time=0; }
   int count=(full ? total-1 : closed_updates);
   for(int s=1;s<=count;s++)
     {
      string events=EventList(s);
      if(events!="") { g_latest_events=events; g_latest_event_time=time[s]; break; }
     }
   // Called only after initial build or new bars, never for every ordinary tick.
   g_latest_low_count=0;
   for(int s=1;s<total && GSMValidValue(B0[s]) && B0[s]<LevelWeak;s++) g_latest_low_count++;
  }

int OnInit()
  {
   if(!ValidateInputs()) return(INIT_PARAMETERS_INCORRECT);
   ConfigureRules();
   SetIndexBuffer(0,B0,INDICATOR_DATA); SetIndexBuffer(1,B1,INDICATOR_DATA); SetIndexBuffer(2,B2,INDICATOR_DATA);
   SetIndexBuffer(3,B3,INDICATOR_DATA); SetIndexBuffer(4,B4,INDICATOR_DATA); SetIndexBuffer(5,B5,INDICATOR_DATA);
   SetIndexBuffer(6,B6,INDICATOR_DATA); SetIndexBuffer(7,B7,INDICATOR_DATA); SetIndexBuffer(8,B8,INDICATOR_DATA);
   SetIndexBuffer(9,B9,INDICATOR_DATA); SetIndexBuffer(10,B10,INDICATOR_DATA); SetIndexBuffer(11,B11,INDICATOR_DATA);
   SetIndexBuffer(12,B12,INDICATOR_DATA); SetIndexBuffer(13,B13,INDICATOR_DATA); SetIndexBuffer(14,B14,INDICATOR_DATA);
   SetIndexBuffer(15,PineTR,INDICATOR_CALCULATIONS); SetIndexBuffer(16,PineDMPlus,INDICATOR_CALCULATIONS);
   SetIndexBuffer(17,PineDMMinus,INDICATOR_CALCULATIONS); SetIndexBuffer(18,PineDX,INDICATOR_CALCULATIONS);
   SetIndexBuffer(19,PineSMASum,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(B0,true); ArraySetAsSeries(B1,true); ArraySetAsSeries(B2,true); ArraySetAsSeries(B3,true);
   ArraySetAsSeries(B4,true); ArraySetAsSeries(B5,true); ArraySetAsSeries(B6,true); ArraySetAsSeries(B7,true);
   ArraySetAsSeries(B8,true); ArraySetAsSeries(B9,true); ArraySetAsSeries(B10,true); ArraySetAsSeries(B11,true);
   ArraySetAsSeries(B12,true); ArraySetAsSeries(B13,true); ArraySetAsSeries(B14,true);
   ArraySetAsSeries(T0,true); ArraySetAsSeries(T1,true); ArraySetAsSeries(T2,true);
   ArraySetAsSeries(PineTR,true); ArraySetAsSeries(PineDMPlus,true); ArraySetAsSeries(PineDMMinus,true); ArraySetAsSeries(PineDX,true);
   ArraySetAsSeries(PineSMASum,true);
   string labels[15]={"ADX","PlusDI","MinusDI","MarketState","DirectionState","SlopeState","CrossWeakEvent","CrossTrendEvent",
      "BullEvent","BearEvent","HighTurnDownEvent","TrendConfirmedEvent","RisingEntryEvent","LongLowEntryEvent","ChoppyEntryEvent"};
   for(int k=0;k<15;k++)
     {
      PlotIndexSetString(k,PLOT_LABEL,labels[k]); PlotIndexSetDouble(k,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(k,PLOT_DRAW_TYPE,k<3 ? DRAW_LINE : DRAW_NONE);
      PlotIndexSetInteger(k,PLOT_SHOW_DATA,true);
     }
   // MetaQuotes installed Examples: ADXW.mq5 and ADX.mq5 PLOT_DRAW_BEGIN.
   g_adx_begin=(ADXMethod==PINE_ADX_DI ? ADXPeriod-1 : 2*ADXPeriod);
   g_di_begin=(ADXMethod==PINE_ADX_DI ? 0 : ADXMethod==WILDER ? ADXPeriod+1 : ADXPeriod);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,g_adx_begin);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,g_di_begin); PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,g_di_begin);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,ADXColor); PlotIndexSetInteger(1,PLOT_LINE_COLOR,PlusDIColor); PlotIndexSetInteger(2,PLOT_LINE_COLOR,MinusDIColor);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,ADXWidth); PlotIndexSetInteger(1,PLOT_LINE_WIDTH,PlusDIWidth); PlotIndexSetInteger(2,PLOT_LINE_WIDTH,MinusDIWidth);
   PlotIndexSetInteger(1,PLOT_DRAW_TYPE,ShowDILines ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2,PLOT_DRAW_TYPE,ShowDILines ? DRAW_LINE : DRAW_NONE);
   IndicatorSetInteger(INDICATOR_DIGITS,2); IndicatorSetInteger(INDICATOR_LEVELS,3);
   double levels[3]; levels[0]=LevelWeak; levels[1]=LevelTrend; levels[2]=LevelStrong;
   for(int k=0;k<3;k++)
     {
      IndicatorSetDouble(INDICATOR_LEVELVALUE,k,levels[k]); IndicatorSetInteger(INDICATOR_LEVELCOLOR,k,LevelColor);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE,k,LevelStyle); IndicatorSetInteger(INDICATOR_LEVELWIDTH,k,LevelWidth);
      IndicatorSetString(INDICATOR_LEVELTEXT,k,StringFormat("%g",levels[k]));
     }
   long sequence=AllocateInstanceSequence();
   if(sequence<=0) { Print("GSM ADX 初始化失败：无法分配独立实例编号。"); return(INIT_FAILED); }
   string id=IntegerToString(ChartID())+"_"+IntegerToString(sequence);
   g_prefix="GSM_ADX_"+id+"_";
   // Keep the user-visible name below 63 characters for native templates.
   g_short_name=StringFormat("GSM ADX 趋势强弱测量器 [%s %d #%I64d]",MethodText(),ADXPeriod,sequence);
   IndicatorSetString(INDICATOR_SHORTNAME,g_short_name);
   ResetLastError();
   if(ADXMethod!=PINE_ADX_DI)
     {
      g_handle=(ADXMethod==WILDER ? iADXWilder(_Symbol,_Period,ADXPeriod) : iADX(_Symbol,_Period,ADXPeriod));
      if(g_handle==INVALID_HANDLE) { PrintFormat("GSM ADX 初始化失败：内置指标句柄创建失败，%s %s 参数 %d，错误 %d。",_Symbol,PeriodText(),ADXPeriod,GetLastError()); return(INIT_FAILED); }
     }
   g_was_connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   // Timer only refreshes presentation after chart layout changes. It does not
   // calculate or publish data; dependent iCustom indicators need quote events.
   if(ShowPanel || ShowSignalMarkers) EventSetTimer(1);
   PrintFormat("GSM_ADX_INIT | %s %s | method=%d period=%d | ADX_begin=%d DI_begin=%d | alerts=%s | instance=%s",
      _Symbol,PeriodText(),(int)ADXMethod,ADXPeriod,g_adx_begin,g_di_begin,(EnableAlerts ? "true" : "false"),g_prefix);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<1) return(0);
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(high,true); ArraySetAsSeries(low,true); ArraySetAsSeries(close,true);
   bool new_bar=(g_current_time!=0 && time[0]!=g_current_time);
   bool native_reset=(prev_calculated==0 || prev_calculated>rates_total ||
                      (g_oldest_time!=0 && time[rates_total-1]!=g_oldest_time && !new_bar));
   if(native_reset) { g_silent_baseline=true; g_need_rebuild=true; g_marker_time=0; }
   bool full=(g_need_rebuild || prev_calculated==0 || rates_total>prev_calculated+1 || rates_total<g_last_total);
   int requested=(full ? rates_total : MathMin(rates_total,(new_bar ? 2 : 1)));
   int calculated=(ADXMethod==PINE_ADX_DI ? rates_total : BarsCalculated(g_handle));
   if(calculated<rates_total)
     {
      ClearRange(full ? rates_total : MathMin(rates_total,MathMax(2,requested)));
      g_need_rebuild=true; g_data_ready=false; g_unavailable="底层数据准备中";
      LogProblem(StringFormat("底层数据准备中：BarsCalculated=%d，当前历史=%d。",calculated,rates_total));
      RenderPanel(); return(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated : 0);
     }
   bool latest_raw_invalid=false;
   if(ADXMethod==PINE_ADX_DI)
     {
      if(full) ClearRange(rates_total);
      if(!CalculatePine(rates_total,requested,full,high,low,close))
        {
         ClearRange(full ? rates_total : MathMin(rates_total,MathMax(2,requested)));
         g_need_rebuild=true; g_data_ready=false; g_unavailable="Pine 数据计算暂不可用";
         RenderPanel(); return(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated : 0);
        }
     }
   else
     {
   // Copy all three into temporary buffers, then validate the entire transaction.
   // CopyBuffer writes oldest first physically; AS_SERIES accesses newest at 0.
   int n0=CopyBuffer(g_handle,0,0,requested,T0);
   int n1=CopyBuffer(g_handle,1,0,requested,T1);
   int n2=CopyBuffer(g_handle,2,0,requested,T2);
   if(n0!=requested || n1!=requested || n2!=requested)
     {
      ClearRange(full ? rates_total : MathMin(rates_total,MathMax(2,requested)));
      g_need_rebuild=true; g_data_ready=false; g_unavailable="数据暂不可用（等待完整批次）";
      LogProblem(StringFormat("三线批次未发布：请求=%d，实际=%d/%d/%d，错误=%d。",requested,n0,n1,n2,GetLastError()));
      RenderPanel(); return(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated : 0);
     }
   if(full) ClearRange(rates_total);
   g_source_total=calculated;
   for(int s=requested-1;s>=0;s--)
     {
      int chronological=calculated-1-s;
      if(s<=1 && (!GSMValidValue(T0[s]) || !GSMValidValue(T1[s]) || !GSMValidValue(T2[s]))) latest_raw_invalid=true;
      B0[s]=(chronological>=g_adx_begin && GSMValidValue(T0[s]) ? T0[s] : EMPTY_VALUE);
      B1[s]=(chronological>=g_di_begin && GSMValidValue(T1[s]) ? T1[s] : EMPTY_VALUE);
      B2[s]=(chronological>=g_di_begin && GSMValidValue(T2[s]) ? T2[s] : EMPTY_VALUE);
     }
     }
   int updates=(full ? rates_total-1 : new_bar ? 1 : 0);
   double rules[];
   for(int s=updates;s>=1;s--) { GSMEvaluateRules(B0,B1,B2,s,rates_total,g_rules,rules); WriteRules(s,rules); }
   ClearConfirmed(0);
   g_data_ready=(rates_total>1 && GSMValidValue(B0[1]) && GSMValidValue(B1[1]) && GSMValidValue(B2[1]));
   g_unavailable=(g_data_ready ? "" : "预热数据不足");
   if(full || new_bar) RefreshLatestEvent(time,rates_total,full,updates);
   UpdateMarkers(time,rates_total,full,updates);
   bool connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   // Connection changes never trigger a historical loop: only latest closed bar.
   if(rates_total>1 && ClosedReady(1))
     {
      if(g_silent_baseline)
        { g_processed_time=time[1]; g_silent_baseline=false; }
      else if(time[1]>g_processed_time)
        {
         // Do not consume a bar while disconnected; successful recovery processes
         // only its newest confirmed bar. Local custom-symbol fixtures remain usable.
         bool custom=(bool)SymbolInfoInteger(_Symbol,SYMBOL_CUSTOM);
         if(connected || custom || MQLInfoInteger(MQL_TESTER) || !EnableAlerts)
           { DeliverAlerts(time[1],EventList(1,true),1); g_processed_time=time[1]; }
        }
     }
   g_was_connected=connected;
   // A complete CopyBuffer transaction can still contain unavailable values.
   // Retry the closed bar after that transient condition; never consume it early.
   g_need_rebuild=latest_raw_invalid; g_last_total=rates_total; g_oldest_time=time[rates_total-1]; g_current_time=time[0];
   RenderPanel();
   return(rates_total);
  }
void OnTimer()
  {
   // No copies or recalculation: presentation only. Find the actual indicator
   // subwindow; an unattached iCustom handle must not draw on its caller's chart.
   RenderPanel();
   if(ShowSignalMarkers && g_data_ready && g_marker_time==0 && ArraySize(B0)>1)
     {
      datetime times[]; ArraySetAsSeries(times,true);
      int total=ArraySize(B0);
      if(CopyTime(_Symbol,_Period,0,total,times)==total) UpdateMarkers(times,total,true,total-1);
     }
  }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  { if(id==CHARTEVENT_CHART_CHANGE) RenderPanel(); }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_handle!=INVALID_HANDLE) { IndicatorRelease(g_handle); g_handle=INVALID_HANDLE; }
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix,-1,-1);
   ChartRedraw(0);
  }
