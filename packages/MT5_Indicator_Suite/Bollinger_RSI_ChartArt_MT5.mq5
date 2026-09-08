// Original concept: ChartArt, "Bollinger + RSI, Double Strategy" v1.1 (2015).
// Ported from the supplied Pine v2 source as an INDICATOR, not an order simulator.
// Arrows mark closed-bar simultaneous conditions; they are NOT strategy fills.
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots 9
#property indicator_label1 "BB SMA Basis"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrAqua
#property indicator_label2 "BB Upper"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrSilver
#property indicator_label3 "BB Lower"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrSilver
#property indicator_label4 "BB Fill Upper;BB Fill Lower"
#property indicator_type4 DRAW_FILLING
#property indicator_color4 C'35,45,60'
#property indicator_label5 "RSI + BB Buy Condition (closed)"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrLime
#property indicator_width5 2
#property indicator_label6 "RSI + BB Sell Condition (closed)"
#property indicator_type6 DRAW_ARROW
#property indicator_color6 clrRed
#property indicator_width6 2
#property indicator_label7 "Trend Open;Trend High;Trend Low;Trend Close"
#property indicator_type7 DRAW_COLOR_CANDLES
#property indicator_color7 clrGreen,clrRed
#property indicator_label8 "RSI (Wilder)"
#property indicator_type8 DRAW_NONE
#property indicator_label9 "Source Trend Condition (+1/-1/0)"
#property indicator_type9 DRAW_NONE

input group "计算参数（原始默认值：200 / 2 / 6 / 50）"
input int InpBBPeriod=200;       // 布林带 SMA 周期
input double InpBBDeviation=2.0; // 布林带倍数（总体标准差）
input int InpRSIPeriod=6;        // RSI 周期（Wilder 平滑）
input double InpRSILevel=50.0;   // RSI 多空交叉阈值
input group "显示（箭头是条件提示，不是成交记录）"
input bool InpShowFill=true;          // 显示带内填充（MT5 不透明颜色）
input color InpFillColor=C'35,45,60';  // 带内填充色
input bool InpShowArrows=true;        // 显示收盘确认双交叉箭头
input double InpArrowOffsetPoints=10; // 箭头距K线的最小点数
input bool InpEnableBarColor=true;    // 按原源码条件叠加红绿K线
input bool InpEnableBackground=true;  // 按原源码条件显示背景条
input int InpBackgroundBars=500;      // 最多显示最近多少根K线背景（1 至 5000）
input color InpBullBackground=C'22,55,32'; // 多头背景条色
input color InpBearBackground=C'60,25,25'; // 空头背景条色

double Basis[],Upper[],Lower[],FillU[],FillL[],BuyArrow[],SellArrow[];
double CandleO[],CandleH[],CandleL[],CandleC[],CandleColor[],RSI[],Trend[],Gain[],Loss[];
string BackgroundPrefix;
datetime BackgroundTimes[];
datetime BackgroundEnds[];
int BackgroundDirections[];
int LastCount=-1;
double LastLiveTrend=EMPTY_VALUE;

void DrawBackground()
{
   if(!InpEnableBackground) return;
   double ymin=0,ymax=0;
   if(!ChartGetDouble(0,CHART_PRICE_MIN,0,ymin) || !ChartGetDouble(0,CHART_PRICE_MAX,0,ymax) || ymax<=ymin) return;
   // Each rectangle spans the current visible main-chart price scale.
   for(int j=0;j<ArraySize(BackgroundTimes);j++)
   {
      const string name=BackgroundPrefix+IntegerToString((long)BackgroundTimes[j]);
      if(ObjectFind(0,name)<0)
      {
         if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,BackgroundTimes[j],ymin,BackgroundEnds[j],ymax)) continue;
         ObjectSetInteger(0,name,OBJPROP_FILL,true);
         ObjectSetInteger(0,name,OBJPROP_BACK,true);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
         ObjectSetString(0,name,OBJPROP_TOOLTIP,"ChartArt 原始背景条件（不等于买卖箭头）");
      }
      ObjectSetInteger(0,name,OBJPROP_COLOR,BackgroundDirections[j]>0 ? InpBullBackground : InpBearBackground);
      ObjectMove(0,name,0,BackgroundTimes[j],ymin);
      ObjectMove(0,name,1,BackgroundEnds[j],ymax);
   }
}

void RebuildBackground(const int count,const datetime &time[])
{
   ObjectsDeleteAll(0,BackgroundPrefix);
   ArrayResize(BackgroundTimes,0); ArrayResize(BackgroundEnds,0); ArrayResize(BackgroundDirections,0);
   if(!InpEnableBackground) return;
   const int begin=MathMax(0,count-InpBackgroundBars);
   for(int i=begin;i<count;i++)
   {
      if(Trend[i]==EMPTY_VALUE || Trend[i]==0) continue;
      const int j=ArraySize(BackgroundTimes);
      ArrayResize(BackgroundTimes,j+1); ArrayResize(BackgroundEnds,j+1); ArrayResize(BackgroundDirections,j+1);
      BackgroundTimes[j]=time[i];
      BackgroundEnds[j]=(i+1<count ? time[i+1] : time[i]+PeriodSeconds(_Period));
      BackgroundDirections[j]=(Trend[i]>0 ? 1 : -1);
   }
   DrawBackground();
}

int OnInit()
{
   if(InpBBPeriod<1 || InpBBPeriod>100000 || InpRSIPeriod<1 || InpRSIPeriod>100000 ||
      !MathIsValidNumber(InpBBDeviation) || InpBBDeviation<=0 || InpBBDeviation>50 ||
      !MathIsValidNumber(InpRSILevel) || InpRSILevel<=0 || InpRSILevel>=100 ||
      !MathIsValidNumber(InpArrowOffsetPoints) || InpArrowOffsetPoints<0 || InpArrowOffsetPoints>100000 ||
      InpBackgroundBars<1 || InpBackgroundBars>5000)
   {
      Print("BB+RSI: 周期 1..100000；倍数 (0,50]；RSI阈值 (0,100)；箭头距离 0..100000；背景根数 1..5000。");
      PrintFormat("BB+RSI actual inputs: BBPeriod=%d BBDeviation=%.17g RSIPeriod=%d RSILevel=%.17g ShowFill=%d FillColor=%d ShowArrows=%d ArrowOffsetPoints=%.17g BarColor=%d Background=%d BackgroundBars=%d BullBackground=%d BearBackground=%d",
                  InpBBPeriod,InpBBDeviation,InpRSIPeriod,InpRSILevel,InpShowFill,(int)InpFillColor,
                  InpShowArrows,InpArrowOffsetPoints,InpEnableBarColor,InpEnableBackground,InpBackgroundBars,
                  (int)InpBullBackground,(int)InpBearBackground);
      return INIT_PARAMETERS_INCORRECT;
   }
   SetIndexBuffer(0,Basis,INDICATOR_DATA); SetIndexBuffer(1,Upper,INDICATOR_DATA); SetIndexBuffer(2,Lower,INDICATOR_DATA);
   SetIndexBuffer(3,FillU,INDICATOR_DATA); SetIndexBuffer(4,FillL,INDICATOR_DATA);
   SetIndexBuffer(5,BuyArrow,INDICATOR_DATA); SetIndexBuffer(6,SellArrow,INDICATOR_DATA);
   SetIndexBuffer(7,CandleO,INDICATOR_DATA); SetIndexBuffer(8,CandleH,INDICATOR_DATA);
   SetIndexBuffer(9,CandleL,INDICATOR_DATA); SetIndexBuffer(10,CandleC,INDICATOR_DATA); SetIndexBuffer(11,CandleColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(12,RSI,INDICATOR_DATA); SetIndexBuffer(13,Trend,INDICATOR_DATA);
   SetIndexBuffer(14,Gain,INDICATOR_CALCULATIONS); SetIndexBuffer(15,Loss,INDICATOR_CALCULATIONS);
   for(int p=0;p<9;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   for(int p=0;p<4;p++) PlotIndexSetInteger(p,PLOT_DRAW_BEGIN,InpBBPeriod-1);
   PlotIndexSetInteger(4,PLOT_ARROW,233); PlotIndexSetInteger(5,PLOT_ARROW,234);
   PlotIndexSetInteger(4,PLOT_DRAW_BEGIN,MathMax(InpBBPeriod,InpRSIPeriod+1));
   PlotIndexSetInteger(5,PLOT_DRAW_BEGIN,MathMax(InpBBPeriod,InpRSIPeriod+1));
   PlotIndexSetInteger(7,PLOT_DRAW_BEGIN,InpRSIPeriod);
   PlotIndexSetInteger(3,PLOT_LINE_COLOR,InpFillColor);
   IndicatorSetString(INDICATOR_SHORTNAME,"ChartArt BB+RSI (closed conditions)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   BackgroundPrefix="CA_BBR_"+IntegerToString(ChartID())+"_"+IntegerToString((long)GetMicrosecondCount())+"_";
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(StringLen(BackgroundPrefix)>0) ObjectsDeleteAll(0,BackgroundPrefix);
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE) DrawBackground();
}

void WindowMoments(const int end,const int period,const double &close[],double &mean,double &m2)
{
   mean=0; m2=0;
   int n=0;
   for(int j=end-period+1;j<=end;j++)
   {
      n++;
      const double delta=close[j]-mean;
      mean+=delta/n;
      m2+=delta*(close[j]-mean);
   }
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   const int start=(prev_calculated>0 && prev_calculated<=rates_total ? prev_calculated-1 : 0);
   for(int i=start;i<rates_total;i++)
   {
      Basis[i]=Upper[i]=Lower[i]=FillU[i]=FillL[i]=EMPTY_VALUE;
      BuyArrow[i]=SellArrow[i]=EMPTY_VALUE;
      CandleO[i]=CandleH[i]=CandleL[i]=CandleC[i]=EMPTY_VALUE; CandleColor[i]=0;
      Trend[i]=EMPTY_VALUE;
      RSI[i]=EMPTY_VALUE;
      if(i<InpRSIPeriod) {Gain[i]=Loss[i]=0; continue;}
      if(i==InpRSIPeriod)
      {
         double up=0,down=0;
         for(int j=1;j<=InpRSIPeriod;j++)
         {
            const double delta=close[j]-close[j-1];
            up+=MathMax(delta,0.0); down+=MathMax(-delta,0.0);
         }
         Gain[i]=up/InpRSIPeriod; Loss[i]=down/InpRSIPeriod;
      }
      else
      {
         const double delta=close[i]-close[i-1];
         Gain[i]=(Gain[i-1]*(InpRSIPeriod-1)+MathMax(delta,0.0))/InpRSIPeriod;
         Loss[i]=(Loss[i-1]*(InpRSIPeriod-1)+MathMax(-delta,0.0))/InpRSIPeriod;
      }
      // Flat input has no directional strength: deterministic neutral RSI=50.
      RSI[i]=(Loss[i]==0 ? (Gain[i]==0 ? 50.0 : 100.0) : 100.0-100.0/(1.0+Gain[i]/Loss[i]));
   }
   const int begin=MathMax(start,InpBBPeriod-1);
   double mean=0,m2=0;
   if(begin<rates_total) WindowMoments(begin,InpBBPeriod,close,mean,m2);
   for(int i=begin;i<rates_total;i++)
   {
      if(i>begin)
      {
         if((i-begin)%512==0) WindowMoments(i,InpBBPeriod,close,mean,m2);
         else
         {
            const double old=close[i-InpBBPeriod],value=close[i],old_mean=mean;
            mean+=(value-old)/InpBBPeriod;
            m2+=(value-old)*(value-mean+old-old_mean);
            if(m2<0) WindowMoments(i,InpBBPeriod,close,mean,m2);
         }
      }
      const double dev=InpBBDeviation*MathSqrt(MathMax(m2/InpBBPeriod,0.0));
      Basis[i]=mean; Upper[i]=mean+dev; Lower[i]=mean-dev;
      if(InpShowFill) {FillU[i]=Upper[i]; FillL[i]=Lower[i];}
   }
   for(int i=MathMax(start,1);i<rates_total;i++)
   {
      if(Basis[i]==EMPTY_VALUE || Basis[i-1]==EMPTY_VALUE) continue;
      Trend[i]=0;
      // Preserve source literally: RSIoverBought / RSIoverSold are constant 50
      // used as truthy values; this candle/background condition does NOT test RSI.
      // SMA[i]-SMA[i-1]=(close[i]-close[i-period])/period exactly.
      // Compare incoming/outgoing prices to preserve strict equal-window behavior
      // without inventing a direction from floating-point summation/rebasing noise.
      const bool basis_falling=(close[i]<close[i-InpBBPeriod]);
      const bool basis_rising=(close[i]>close[i-InpBBPeriod]);
      const bool bear=(close[i-1]>Upper[i] && close[i]<Upper[i] && basis_falling);
      const bool bull=(close[i-1]<Lower[i] && close[i]>Lower[i] && basis_rising);
      if(bear) Trend[i]=-1; else if(bull) Trend[i]=1;
      if(InpEnableBarColor && Trend[i]!=0)
      {
         CandleO[i]=open[i]; CandleH[i]=high[i]; CandleL[i]=low[i]; CandleC[i]=close[i];
         CandleColor[i]=(Trend[i]>0 ? 0 : 1);
      }
      if(!InpShowArrows || i==rates_total-1 || RSI[i]==EMPTY_VALUE || RSI[i-1]==EMPTY_VALUE) continue;
      const bool buy=(RSI[i]>InpRSILevel && RSI[i-1]<=InpRSILevel && close[i]>Lower[i] && close[i-1]<=Lower[i-1]);
      const bool sell=(RSI[i]<InpRSILevel && RSI[i-1]>=InpRSILevel && close[i]<Upper[i] && close[i-1]>=Upper[i-1]);
      const double offset=MathMax(InpArrowOffsetPoints*_Point,(high[i]-low[i])*0.25);
      if(buy) BuyArrow[i]=low[i]-offset;
      if(sell) SellArrow[i]=high[i]+offset;
   }
   if(prev_calculated==0 || LastCount!=rates_total || LastLiveTrend!=Trend[rates_total-1])
   {
      RebuildBackground(rates_total,time);
      LastCount=rates_total; LastLiveTrend=Trend[rates_total-1];
   }
   return rates_total;
}
