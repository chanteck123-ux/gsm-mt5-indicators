// MQL5 port of the CM_MacD_Ult_MTF logic supplied by the user.
// Original Pine indicator: ChrisMoody, updated 2014-04-10.
// Cross-dot idea credited in that source to TheLark.
// Higher timeframes deliberately use only the previous confirmed source bar.
#property copyright "Original concept: ChrisMoody; MQL5 port prepared for user"
#property version   "1.00"
#property description "EMA MACD / SMA signal, four-state histogram and cross dots."
#property description "Higher timeframe values become available at the next source bar."
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   5
#property indicator_label1  "MACD"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime,clrRed
#property indicator_width1  3
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_width2  2
#property indicator_label3  "Histogram"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrAqua,clrBlue,clrRed,clrMaroon,clrYellow,clrGray
#property indicator_width3  3
#property indicator_label4  "Cross dot"
#property indicator_type4   DRAW_COLOR_ARROW
#property indicator_color4  clrLime,clrRed
#property indicator_width4  3
#property indicator_label5  "Cross direction"
#property indicator_type5   DRAW_NONE
#property indicator_level1  0.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_SOLID

input bool            InpUseCurrentTimeframe=true;     // 使用当前图表周期
input ENUM_TIMEFRAMES InpCustomTimeframe=PERIOD_H1;     // 自选周期（限当前或更高）
input int             InpFastLength=12;                // 快速 EMA 周期
input int             InpSlowLength=26;                // 慢速 EMA 周期
input int             InpSignalLength=9;               // 信号 SMA 周期
input bool            InpShowMACDAndSignal=true;        // 显示 MACD 和信号线
input bool            InpShowCrossDots=true;            // 显示交叉圆点（独立开关）
input bool            InpShowHistogram=true;            // 显示柱状图
input bool            InpMACDColorChange=true;          // MACD 按相对信号线位置变色
input bool            InpHistogramFourColors=true;      // 柱状图四色（不变时黄色）
input bool            InpCrossOnClosedBar=true;         // 交叉圆点仅在图表柱收盘后确认
input int             InpMaxChartBars=10000;            // 最多计算最近图表柱数

// Public data buffers: 0 MACD, 2 Signal, 3 Histogram, 5 Dots,
// 7 Cross direction (+1 up, -1 down, 0 no confirmed cross).
// Color-index buffers: 1, 4, 6. Hidden plots retain their data buffers.
double MACD[],MACDColor[],Signal[],Histogram[],HistogramColor[];
double CrossDot[],CrossColor[],CrossDirection[];
double SourceMACD[],SourceSignal[];
datetime SourceTime[];
int MACDHandle=INVALID_HANDLE;
ENUM_TIMEFRAMES SourcePeriod;
int LastSourceBars=0;
int LastChartBars=0;
datetime FirstChartTime=0;
string LastDataWait="";

void ReportDataWait(const string stage,const int copied,const int required)
  {
   if(LastDataWait!=stage)
     {
      PrintFormat("CM MACD [%s]: waiting for %s (%d/%d), error %d; will retry on new data.",
                  EnumToString(SourcePeriod),stage,copied,required,GetLastError());
      LastDataWait=stage;
     }
  }

bool ValidValue(const double value)
  {
   return(value!=EMPTY_VALUE && MathIsValidNumber(value));
  }

void ClearBar(const int bar)
  {
   MACD[bar]=EMPTY_VALUE;
   Signal[bar]=EMPTY_VALUE;
   Histogram[bar]=EMPTY_VALUE;
   CrossDot[bar]=EMPTY_VALUE;
   CrossDirection[bar]=EMPTY_VALUE;
   MACDColor[bar]=0;
   HistogramColor[bar]=4;
   CrossColor[bar]=0;
  }

int OnInit()
  {
   if(InpFastLength<1 || InpSlowLength<1 || InpSignalLength<1 ||
      InpFastLength>=InpSlowLength || InpMaxChartBars<100 ||
      InpFastLength>100000 || InpSlowLength>100000 || InpSignalLength>100000)
     {
      Print("CM MACD: periods must be 1..100000, fast < slow; MaxChartBars >= 100.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   SourcePeriod=InpUseCurrentTimeframe ? (ENUM_TIMEFRAMES)_Period : InpCustomTimeframe;
   if(SourcePeriod==PERIOD_CURRENT)
      SourcePeriod=(ENUM_TIMEFRAMES)_Period;
   if(PeriodSeconds(SourcePeriod)<PeriodSeconds((ENUM_TIMEFRAMES)_Period))
     {
      Print("CM MACD: select the chart timeframe or a higher timeframe. Lower timeframe aggregation is not supported.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   SetIndexBuffer(0,MACD,INDICATOR_DATA);
   SetIndexBuffer(1,MACDColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,Signal,INDICATOR_DATA);
   SetIndexBuffer(3,Histogram,INDICATOR_DATA);
   SetIndexBuffer(4,HistogramColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5,CrossDot,INDICATOR_DATA);
   SetIndexBuffer(6,CrossColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(7,CrossDirection,INDICATOR_DATA);
   ArraySetAsSeries(MACD,false);
   ArraySetAsSeries(MACDColor,false);
   ArraySetAsSeries(Signal,false);
   ArraySetAsSeries(Histogram,false);
   ArraySetAsSeries(HistogramColor,false);
   ArraySetAsSeries(CrossDot,false);
   ArraySetAsSeries(CrossColor,false);
   ArraySetAsSeries(CrossDirection,false);
   for(int plot=0;plot<5;plot++)
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(3,PLOT_ARROW,108); // Filled Wingdings circle.
   PlotIndexSetInteger(4,PLOT_SHOW_DATA,false);
   if(!InpShowMACDAndSignal)
     {
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,0,clrNONE);
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,1,clrNONE);
      PlotIndexSetInteger(1,PLOT_LINE_COLOR,clrNONE);
     }
   else
      PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpMACDColorChange ? clrYellow : clrLime);
   if(!InpShowHistogram)
      for(int color_index=0;color_index<6;color_index++)
         PlotIndexSetInteger(2,PLOT_LINE_COLOR,color_index,clrNONE);
   if(!InpShowCrossDots)
     {
      PlotIndexSetInteger(3,PLOT_LINE_COLOR,0,clrNONE);
      PlotIndexSetInteger(3,PLOT_LINE_COLOR,1,clrNONE);
     }
   string mode=(SourcePeriod==(ENUM_TIMEFRAMES)_Period) ? "current TF" : "confirmed HTF";
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("CM MACD (%d,%d,%d) %s [%s]",
                      InpFastLength,InpSlowLength,InpSignalLength,EnumToString(SourcePeriod),mode));
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits+2);
   MACDHandle=iMACD(_Symbol,SourcePeriod,InpFastLength,InpSlowLength,InpSignalLength,PRICE_CLOSE);
   if(MACDHandle==INVALID_HANDLE)
     {
      PrintFormat("CM MACD: iMACD creation failed, error %d",GetLastError());
      return(INIT_FAILED);
     }
   LastSourceBars=0;
   LastChartBars=0;
   FirstChartTime=0;
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   ArraySetAsSeries(time,false);
   if(rates_total<2)
      return(0);
   bool reset=(prev_calculated<=0 || prev_calculated>rates_total ||
               LastChartBars>rates_total || FirstChartTime!=time[0]);
   if(reset)
     {
      ArrayInitialize(MACD,EMPTY_VALUE);
      ArrayInitialize(Signal,EMPTY_VALUE);
      ArrayInitialize(Histogram,EMPTY_VALUE);
      ArrayInitialize(CrossDot,EMPTY_VALUE);
      ArrayInitialize(CrossDirection,EMPTY_VALUE);
      ArrayInitialize(MACDColor,0);
      ArrayInitialize(HistogramColor,4);
      ArrayInitialize(CrossColor,0);
     }
   int available=BarsCalculated(MACDHandle);
   int warmup=InpSlowLength+InpSignalLength-2;
   if(available<=warmup)
     {
      ReportDataWait("source calculation",available,warmup+1);
      return(0);
     }
   int first=(int)MathMax(0,rates_total-InpMaxChartBars);
   int oldest_shift=iBarShift(_Symbol,SourcePeriod,time[first],false);
   // Extra source bars cover both the confirmed HTF offset and the preceding
   // chart value used by the original script's outHist[1] comparison.
   // If source history is shorter than chart history, still draw its valid
   // suffix; the per-bar timestamp/warmup checks leave the early area empty.
   int count=(oldest_shift<0) ? available : (int)MathMin(available,oldest_shift+4);
   if(count<2)
      return(0);
   int copied_time=CopyTime(_Symbol,SourcePeriod,0,count,SourceTime);
   if(copied_time!=count)
     {ReportDataWait("source times",copied_time,count);return(0);}
   int copied_main=CopyBuffer(MACDHandle,0,0,count,SourceMACD);
   if(copied_main!=count)
     {ReportDataWait("MACD values",copied_main,count);return(0);}
   int copied_signal=CopyBuffer(MACDHandle,1,0,count,SourceSignal);
   if(copied_signal!=count)
     {ReportDataWait("signal values",copied_signal,count);return(0);}
   bool full=(reset || available!=LastSourceBars || rates_total!=LastChartBars);
   int start=full ? first : (int)MathMax(first,prev_calculated-2);
   if(first>0)
     {
      int previous_first=(int)MathMax(0,LastChartBars-InpMaxChartBars);
      for(int old=previous_first;old<first;old++)
         ClearBar(old);
     }
   bool higher=(SourcePeriod!=(ENUM_TIMEFRAMES)_Period);
   int source_index=0;
   for(int bar=start;bar<rates_total;bar++)
     {
      ClearBar(bar);
      while(source_index+1<count && SourceTime[source_index+1]<=time[bar])
         source_index++;
      if(time[bar]<SourceTime[0])
         continue;
      int index=source_index-(higher ? 1 : 0);
      if(index<0 || available-count+index<warmup)
         continue;
      double main_value=SourceMACD[index];
      double signal_value=SourceSignal[index];
      if(!ValidValue(main_value) || !ValidValue(signal_value))
         continue;
      MACD[bar]=main_value;
      Signal[bar]=signal_value;
      Histogram[bar]=main_value-signal_value;
      MACDColor[bar]=(InpMACDColorChange && main_value>=signal_value) ? 0 : 1;
      CrossColor[bar]=MACDColor[bar];
      CrossDirection[bar]=0;
      HistogramColor[bar]=InpHistogramFourColors ? 4 : 5;
      if(bar>0 && ValidValue(Histogram[bar-1]))
        {
         double previous=Histogram[bar-1];
         double current=Histogram[bar];
         if(InpHistogramFourColors)
           {
            if(current>0 && current>previous) HistogramColor[bar]=0;
            else if(current>0 && current<previous) HistogramColor[bar]=1;
            else if(current<=0 && current<previous) HistogramColor[bar]=2;
            else if(current<=0 && current>previous) HistogramColor[bar]=3;
           }
         bool cross_up=(current>0 && previous<=0);
         bool cross_down=(current<0 && previous>=0);
         if((!InpCrossOnClosedBar || bar<rates_total-1) && (cross_up || cross_down))
           {
            CrossDot[bar]=signal_value;
            CrossDirection[bar]=cross_up ? 1 : -1;
           }
        }
     }
   LastSourceBars=available;
   LastChartBars=rates_total;
   FirstChartTime=time[0];
   LastDataWait="";
   return(rates_total);
  }

void OnDeinit(const int reason)
  {
   if(MACDHandle!=INVALID_HANDLE)
      IndicatorRelease(MACDHandle);
   MACDHandle=INVALID_HANDLE;
  }
