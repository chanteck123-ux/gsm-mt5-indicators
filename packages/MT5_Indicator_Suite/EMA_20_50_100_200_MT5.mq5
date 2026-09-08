// Port of the supplied TradingView "EMA 20/50/100/200" indicator.
// Indicator only: no trading, files, network calls, or future-bar references.
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 4
#property indicator_label1 "EMA 20"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrRed
#property indicator_label2 "EMA 50"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrOrange
#property indicator_label3 "EMA 100"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrAqua
#property indicator_label4 "EMA 200"
#property indicator_type4 DRAW_LINE

input group "EMA 参数（收盘价；当前K线实时更新）"
input int InpPeriod1=20;       // EMA 1 周期
input int InpPeriod2=50;       // EMA 2 周期
input int InpPeriod3=100;      // EMA 3 周期
input int InpPeriod4=200;      // EMA 4 周期
input bool InpShow1=true;     // 显示 EMA 1（红）
input bool InpShow2=true;     // 显示 EMA 2（橙）
input bool InpShow3=true;     // 显示 EMA 3（青）
input bool InpShow4=true;     // 显示 EMA 4（蓝）

double E1[],E2[],E3[],E4[],R1[],R2[],R3[],R4[];

int OnInit()
{
   if(InpPeriod1<1 || InpPeriod1>100000 || InpPeriod2<1 || InpPeriod2>100000 ||
      InpPeriod3<1 || InpPeriod3>100000 || InpPeriod4<1 || InpPeriod4>100000)
   {
      Print("EMA: 周期必须介于 1 和 100000。");
      return INIT_PARAMETERS_INCORRECT;
   }
   SetIndexBuffer(0,E1,INDICATOR_DATA); SetIndexBuffer(1,E2,INDICATOR_DATA);
   SetIndexBuffer(2,E3,INDICATOR_DATA); SetIndexBuffer(3,E4,INDICATOR_DATA);
   SetIndexBuffer(4,R1,INDICATOR_CALCULATIONS); SetIndexBuffer(5,R2,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,R3,INDICATOR_CALCULATIONS); SetIndexBuffer(7,R4,INDICATOR_CALCULATIONS);
   int periods[4]={InpPeriod1,InpPeriod2,InpPeriod3,InpPeriod4};
   for(int p=0;p<4;p++)
   {
      PlotIndexSetInteger(p,PLOT_DRAW_BEGIN,periods[p]-1);
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetString(p,PLOT_LABEL,"EMA "+IntegerToString(periods[p]));
   }
   IndicatorSetString(INDICATOR_SHORTNAME,"EMA 4 (close)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

void CalculateEMA(const int count,const int start,const int period,const bool show,
                  const double &prices[],double &raw[],double &display[])
{
   const double alpha=2.0/(period+1.0);
   for(int i=start;i<count;i++)
   {
      // First available close seeds the EMA. No future samples enter the recurrence.
      raw[i]=(i==0 ? prices[i] : alpha*prices[i]+(1.0-alpha)*raw[i-1]);
      display[i]=(show && i>=period-1 ? raw[i] : EMPTY_VALUE);
   }
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(close,false);
   const int start=(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated-1 : 0);
   CalculateEMA(rates_total,start,InpPeriod1,InpShow1,close,R1,E1);
   CalculateEMA(rates_total,start,InpPeriod2,InpShow2,close,R2,E2);
   CalculateEMA(rates_total,start,InpPeriod3,InpShow3,close,R3,E3);
   CalculateEMA(rates_total,start,InpPeriod4,InpShow4,close,R4,E4);
   return rates_total;
}
