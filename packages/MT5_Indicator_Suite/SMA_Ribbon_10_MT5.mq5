// Port of the user's supplied TradingView "Simple Moving Averages".
// Ten independent SMA sources; line color ALWAYS compares chart close with that SMA.
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 20
#property indicator_plots 10
#property indicator_label1 "SMA 1"
#property indicator_type1 DRAW_COLOR_LINE
#property indicator_color1 clrBlue,clrOrange
#property indicator_label2 "SMA 2"
#property indicator_type2 DRAW_COLOR_LINE
#property indicator_color2 clrBlue,clrOrange
#property indicator_width2 2
#property indicator_label3 "SMA 3"
#property indicator_type3 DRAW_COLOR_LINE
#property indicator_color3 clrBlue,clrOrange
#property indicator_label4 "SMA 4"
#property indicator_type4 DRAW_COLOR_LINE
#property indicator_color4 clrBlue,clrOrange
#property indicator_label5 "SMA 5"
#property indicator_type5 DRAW_COLOR_LINE
#property indicator_color5 clrBlue,clrOrange
#property indicator_width5 4
#property indicator_label6 "SMA 6"
#property indicator_type6 DRAW_COLOR_LINE
#property indicator_color6 clrGreen,clrRed
#property indicator_label7 "SMA 7"
#property indicator_type7 DRAW_COLOR_LINE
#property indicator_color7 clrGreen,clrRed
#property indicator_width7 2
#property indicator_label8 "SMA 8"
#property indicator_type8 DRAW_COLOR_LINE
#property indicator_color8 clrGreen,clrRed
#property indicator_label9 "SMA 9"
#property indicator_type9 DRAW_COLOR_LINE
#property indicator_color9 clrGreen,clrRed
#property indicator_label10 "SMA 10"
#property indicator_type10 DRAW_COLOR_LINE
#property indicator_color10 clrGreen,clrRed
#property indicator_width10 4

input group "SMA 1 至 5：收盘价在均线上方/相等为蓝色，否则橙色"
input int InpPeriod1=20; // SMA 1 周期
input ENUM_APPLIED_PRICE InpPrice1=PRICE_CLOSE; // SMA 1 计算价格
input bool InpShow1=true; // 显示 SMA 1
input int InpPeriod2=50; // SMA 2 周期
input ENUM_APPLIED_PRICE InpPrice2=PRICE_CLOSE; // SMA 2 计算价格
input bool InpShow2=true; // 显示 SMA 2
input int InpPeriod3=100; // SMA 3 周期
input ENUM_APPLIED_PRICE InpPrice3=PRICE_CLOSE; // SMA 3 计算价格
input bool InpShow3=true; // 显示 SMA 3
input int InpPeriod4=150; // SMA 4 周期
input ENUM_APPLIED_PRICE InpPrice4=PRICE_CLOSE; // SMA 4 计算价格
input bool InpShow4=true; // 显示 SMA 4
input int InpPeriod5=200; // SMA 5 周期
input ENUM_APPLIED_PRICE InpPrice5=PRICE_CLOSE; // SMA 5 计算价格
input bool InpShow5=true; // 显示 SMA 5
input group "SMA 6 至 10：收盘价在均线上方/相等为绿色，否则红色"
input int InpPeriod6=250; // SMA 6 周期
input ENUM_APPLIED_PRICE InpPrice6=PRICE_CLOSE; // SMA 6 计算价格
input bool InpShow6=true; // 显示 SMA 6
input int InpPeriod7=300; // SMA 7 周期
input ENUM_APPLIED_PRICE InpPrice7=PRICE_CLOSE; // SMA 7 计算价格
input bool InpShow7=true; // 显示 SMA 7
input int InpPeriod8=400; // SMA 8 周期
input ENUM_APPLIED_PRICE InpPrice8=PRICE_CLOSE; // SMA 8 计算价格
input bool InpShow8=true; // 显示 SMA 8
input int InpPeriod9=500; // SMA 9 周期
input ENUM_APPLIED_PRICE InpPrice9=PRICE_CLOSE; // SMA 9 计算价格
input bool InpShow9=true; // 显示 SMA 9
input int InpPeriod10=600; // SMA 10 周期
input ENUM_APPLIED_PRICE InpPrice10=PRICE_CLOSE; // SMA 10 计算价格
input bool InpShow10=true; // 显示 SMA 10

double S1[],C1[],S2[],C2[],S3[],C3[],S4[],C4[],S5[],C5[];
double S6[],C6[],S7[],C7[],S8[],C8[],S9[],C9[],S10[],C10[];

int OnInit()
{
   int periods[10]={InpPeriod1,InpPeriod2,InpPeriod3,InpPeriod4,InpPeriod5,InpPeriod6,InpPeriod7,InpPeriod8,InpPeriod9,InpPeriod10};
   ENUM_APPLIED_PRICE prices[10]={InpPrice1,InpPrice2,InpPrice3,InpPrice4,InpPrice5,InpPrice6,InpPrice7,InpPrice8,InpPrice9,InpPrice10};
   for(int p=0;p<10;p++)
   {
      if(periods[p]<1 || periods[p]>100000 || (int)prices[p]<(int)PRICE_CLOSE || (int)prices[p]>(int)PRICE_WEIGHTED)
      {
         Print("SMA ",p+1,": 周期必须为 1 至 100000，价格类型必须为 MT5 标准价格。");
         return INIT_PARAMETERS_INCORRECT;
      }
      PlotIndexSetInteger(p,PLOT_DRAW_BEGIN,periods[p]-1);
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetString(p,PLOT_LABEL,"SMA "+IntegerToString(periods[p]));
   }
   SetIndexBuffer(0,S1,INDICATOR_DATA); SetIndexBuffer(1,C1,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,S2,INDICATOR_DATA); SetIndexBuffer(3,C2,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4,S3,INDICATOR_DATA); SetIndexBuffer(5,C3,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6,S4,INDICATOR_DATA); SetIndexBuffer(7,C4,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8,S5,INDICATOR_DATA); SetIndexBuffer(9,C5,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(10,S6,INDICATOR_DATA); SetIndexBuffer(11,C6,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(12,S7,INDICATOR_DATA); SetIndexBuffer(13,C7,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(14,S8,INDICATOR_DATA); SetIndexBuffer(15,C8,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(16,S9,INDICATOR_DATA); SetIndexBuffer(17,C9,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(18,S10,INDICATOR_DATA); SetIndexBuffer(19,C10,INDICATOR_COLOR_INDEX);
   IndicatorSetString(INDICATOR_SHORTNAME,"SMA Ribbon 10 (TV)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

double PriceAt(const int i,const ENUM_APPLIED_PRICE source,const double &open[],const double &high[],const double &low[],const double &close[])
{
   switch(source)
   {
      case PRICE_OPEN: return open[i];
      case PRICE_HIGH: return high[i];
      case PRICE_LOW: return low[i];
      case PRICE_MEDIAN: return (high[i]+low[i])/2.0;
      case PRICE_TYPICAL: return (high[i]+low[i]+close[i])/3.0;
      case PRICE_WEIGHTED: return (high[i]+low[i]+2.0*close[i])/4.0;
      default: return close[i];
   }
}

void CalculateSMA(const int count,const int start,const int period,const ENUM_APPLIED_PRICE source,const bool show,
                  const double &open[],const double &high[],const double &low[],const double &close[],double &line[],double &colors[])
{
   for(int i=start;i<count && i<period-1;i++) {line[i]=EMPTY_VALUE; colors[i]=0;}
   const int begin=MathMax(start,period-1);
   if(begin>=count) return;
   double sum=0;
   for(int j=begin-period+1;j<=begin;j++) sum+=PriceAt(j,source,open,high,low,close);
   for(int i=begin;i<count;i++)
   {
      if(i>begin) sum+=PriceAt(i,source,open,high,low,close)-PriceAt(i-period,source,open,high,low,close);
      const double ma=sum/period;
      line[i]=(show ? ma : EMPTY_VALUE);
      colors[i]=(close[i]>=ma ? 0 : 1);
   }
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(open,false); ArraySetAsSeries(high,false); ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   const int start=(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated-1 : 0);
   CalculateSMA(rates_total,start,InpPeriod1,InpPrice1,InpShow1,open,high,low,close,S1,C1);
   CalculateSMA(rates_total,start,InpPeriod2,InpPrice2,InpShow2,open,high,low,close,S2,C2);
   CalculateSMA(rates_total,start,InpPeriod3,InpPrice3,InpShow3,open,high,low,close,S3,C3);
   CalculateSMA(rates_total,start,InpPeriod4,InpPrice4,InpShow4,open,high,low,close,S4,C4);
   CalculateSMA(rates_total,start,InpPeriod5,InpPrice5,InpShow5,open,high,low,close,S5,C5);
   CalculateSMA(rates_total,start,InpPeriod6,InpPrice6,InpShow6,open,high,low,close,S6,C6);
   CalculateSMA(rates_total,start,InpPeriod7,InpPrice7,InpShow7,open,high,low,close,S7,C7);
   CalculateSMA(rates_total,start,InpPeriod8,InpPrice8,InpShow8,open,high,low,close,S8,C8);
   CalculateSMA(rates_total,start,InpPeriod9,InpPrice9,InpShow9,open,high,low,close,S9,C9);
   CalculateSMA(rates_total,start,InpPeriod10,InpPrice10,InpShow10,open,high,low,close,S10,C10);
   return rates_total;
}
