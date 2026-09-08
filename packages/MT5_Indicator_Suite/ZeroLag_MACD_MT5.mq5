// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Original Pine Script: Copyright (c) evaiinvesting.
// MQL5 translation prepared for the user, 2026-09-08.
// Source zlema() is 2*EMA(src)-EMA(EMA(src)), conventionally DEMA.
// The mathematical formula is preserved; this is not lag-adjusted-price ZLEMA.
#property copyright "Original Pine: evaiinvesting; MQL5 translation prepared for user"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.00"
#property description "Source-faithful DEMA oscillator + EMA signal, or Custom MA types."
#property description "Current chart timeframe. Buffer 4 contains confirmed closed-bar crosses."
#property indicator_separate_window
#property indicator_buffers 12
#property indicator_plots   4
#property indicator_label1  "MACD"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'255,109,0'
#property indicator_width2  2
#property indicator_label3  "Histogram"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  C'38,166,154',C'178,223,219',C'255,205,210',C'255,82,82'
#property indicator_width3  3
#property indicator_label4  "Closed cross direction"
#property indicator_type4   DRAW_NONE
#property indicator_level1  0.0
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_SOLID

enum ZLMACD_MODE
  {
   ZL_PRESET_DEMA_EMA=0, // Original preset: "ZLEMA osc + EMA signal" (= DEMA + EMA)
   ZL_CUSTOM=1          // Use the two Custom MA type inputs
  };
enum ZLMACD_MA_TYPE
  {
   ZL_EMA=0,  // EMA
   ZL_SMA=1,  // SMA
   ZL_DEMA=2  // 2*EMA - EMA(EMA), source calls this ZLEMA
  };

input ENUM_APPLIED_PRICE InpSource=PRICE_CLOSE;          // Price source
input int                InpFastLength=12;              // Fast length (1..100000)
input int                InpSlowLength=26;              // Slow length (1..100000)
input int                InpSignalLength=9;             // Signal length (1..100000)
input ZLMACD_MODE         InpMode=ZL_PRESET_DEMA_EMA;     // Original preset or Custom
input ZLMACD_MA_TYPE      InpCustomOscillator=ZL_EMA;     // Custom oscillator MA
input ZLMACD_MA_TYPE      InpCustomSignal=ZL_EMA;         // Custom signal MA
input bool               InpEnableLocalAlerts=false;    // Local terminal Alert on confirmed cross

// Public iCustom buffers (oldest -> newest internally):
// 0 MACD; 1 Signal; 2 Histogram; 3 Histogram color index (0..3);
// 4 Closed cross: +1 up, -1 down, 0 none/current bar after cross warmup;
// EMPTY_VALUE until both the current and preceding histogram values exist.
// Buffer 3 is an INDICATOR_COLOR_INDEX buffer; all other public buffers are data.
double MACD[],Signal[],Histogram[],HistogramColor[],ClosedCross[];
double SourcePrice[],FastState1[],FastState2[],SlowState1[],SlowState2[];
double SignalState1[],SignalState2[];
ZLMACD_MA_TYPE OscillatorType=ZL_DEMA;
ZLMACD_MA_TYPE SignalType=ZL_EMA;
datetime FirstBarTime=0,LastOpenTime=0;
int LastRatesTotal=0;

bool IsValue(const double value)
  {
   return(value!=EMPTY_VALUE && MathIsValidNumber(value));
  }

string TypeName(const ZLMACD_MA_TYPE ma_type)
  {
   if(ma_type==ZL_EMA) return("EMA");
   if(ma_type==ZL_SMA) return("SMA");
   return("DEMA");
  }

double AppliedPrice(const int bar,const double &open[],const double &high[],
                    const double &low[],const double &close[])
  {
   switch(InpSource)
     {
      case PRICE_OPEN:     return(open[bar]);
      case PRICE_HIGH:     return(high[bar]);
      case PRICE_LOW:      return(low[bar]);
      case PRICE_MEDIAN:   return((high[bar]+low[bar])/2.0);
      case PRICE_TYPICAL:  return((high[bar]+low[bar]+close[bar])/3.0);
      case PRICE_WEIGHTED: return((high[bar]+low[bar]+2.0*close[bar])/4.0);
      default:            return(close[bar]);
     }
  }

// EMA is seeded with the first valid input, matching the supplied Pine helper.
// SMA keeps a rolling sum, but never outputs partial-window averages.
// Recalculating a live bar derives state only from the preceding bar, so the
// same candle cannot be counted twice. No value after 'bar' is accessed.
double CalculateMA(const double &src[],const int bar,const int first,
                   const int length,const ZLMACD_MA_TYPE ma_type,
                   double &state1[],double &state2[])
  {
   if(bar<first || !IsValue(src[bar]))
     {
      state1[bar]=EMPTY_VALUE;
      state2[bar]=EMPTY_VALUE;
      return(EMPTY_VALUE);
     }
   double value=src[bar];
   if(ma_type==ZL_SMA)
     {
      double sum=(bar==first) ? value : state1[bar-1]+value;
      if(bar-first>=length)
         sum-=src[bar-length];
      state1[bar]=sum;
      state2[bar]=EMPTY_VALUE;
      if(bar-first+1<length)
         return(EMPTY_VALUE);
      return(sum/length);
     }
   double alpha=2.0/(length+1.0);
   state1[bar]=(bar==first) ? value : alpha*value+(1.0-alpha)*state1[bar-1];
   if(ma_type==ZL_EMA)
     {
      state2[bar]=EMPTY_VALUE;
      return(state1[bar]);
     }
   state2[bar]=(bar==first) ? state1[bar] :
               alpha*state1[bar]+(1.0-alpha)*state2[bar-1];
   return(2.0*state1[bar]-state2[bar]);
  }

int OnInit()
  {
   if(InpFastLength<1 || InpSlowLength<1 || InpSignalLength<1 ||
      InpFastLength>100000 || InpSlowLength>100000 || InpSignalLength>100000 ||
      InpMode<ZL_PRESET_DEMA_EMA || InpMode>ZL_CUSTOM ||
      InpCustomOscillator<ZL_EMA || InpCustomOscillator>ZL_DEMA ||
      InpCustomSignal<ZL_EMA || InpCustomSignal>ZL_DEMA ||
      InpSource<PRICE_CLOSE || InpSource>PRICE_WEIGHTED)
     {
      Print("ZeroLag MACD: invalid input. MA lengths must be 1..100000.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   OscillatorType=(InpMode==ZL_PRESET_DEMA_EMA) ? ZL_DEMA : InpCustomOscillator;
   SignalType=(InpMode==ZL_PRESET_DEMA_EMA) ? ZL_EMA : InpCustomSignal;
   SetIndexBuffer(0,MACD,INDICATOR_DATA);
   SetIndexBuffer(1,Signal,INDICATOR_DATA);
   SetIndexBuffer(2,Histogram,INDICATOR_DATA);
   SetIndexBuffer(3,HistogramColor,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4,ClosedCross,INDICATOR_DATA);
   SetIndexBuffer(5,SourcePrice,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,FastState1,INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,FastState2,INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,SlowState1,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,SlowState2,INDICATOR_CALCULATIONS);
   SetIndexBuffer(10,SignalState1,INDICATOR_CALCULATIONS);
   SetIndexBuffer(11,SignalState2,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(MACD,false);
   ArraySetAsSeries(Signal,false);
   ArraySetAsSeries(Histogram,false);
   ArraySetAsSeries(HistogramColor,false);
   ArraySetAsSeries(ClosedCross,false);
   ArraySetAsSeries(SourcePrice,false);
   ArraySetAsSeries(FastState1,false);
   ArraySetAsSeries(FastState2,false);
   ArraySetAsSeries(SlowState1,false);
   ArraySetAsSeries(SlowState2,false);
   ArraySetAsSeries(SignalState1,false);
   ArraySetAsSeries(SignalState2,false);
   int osc_first=(OscillatorType==ZL_SMA) ? (int)MathMax(InpFastLength,InpSlowLength)-1 : 0;
   int signal_first=osc_first+((SignalType==ZL_SMA) ? InpSignalLength-1 : 0);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,osc_first);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,signal_first);
   PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,signal_first);
   PlotIndexSetInteger(3,PLOT_DRAW_BEGIN,signal_first+1);
   for(int plot=0;plot<4;plot++)
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,(int)MathMin(10,_Digits+3));
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("ZLMACD (%d,%d,%d) %s/%s [current TF]",
                      InpFastLength,InpSlowLength,InpSignalLength,
                      TypeName(OscillatorType),TypeName(SignalType)));
   FirstBarTime=0;
   LastOpenTime=0;
   LastRatesTotal=0;
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<1) return(0);
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   bool reset=(prev_calculated<=0 || prev_calculated>rates_total ||
               LastRatesTotal>rates_total || FirstBarTime!=time[0]);
   int first=reset ? 0 : (int)MathMax(0,prev_calculated-1);
   // A new candle must also finalize the former live candle's event buffer.
   if(!reset && time[rates_total-1]!=LastOpenTime)
      first=(int)MathMax(0,MathMin(first,rates_total-2));
   int osc_first=(OscillatorType==ZL_SMA) ? (int)MathMax(InpFastLength,InpSlowLength)-1 : 0;
   for(int bar=first;bar<rates_total;bar++)
     {
      SourcePrice[bar]=AppliedPrice(bar,open,high,low,close);
      double fast=CalculateMA(SourcePrice,bar,0,InpFastLength,OscillatorType,FastState1,FastState2);
      double slow=CalculateMA(SourcePrice,bar,0,InpSlowLength,OscillatorType,SlowState1,SlowState2);
      MACD[bar]=(IsValue(fast) && IsValue(slow)) ? fast-slow : EMPTY_VALUE;
      Signal[bar]=CalculateMA(MACD,bar,osc_first,InpSignalLength,SignalType,SignalState1,SignalState2);
      Histogram[bar]=(IsValue(MACD[bar]) && IsValue(Signal[bar])) ? MACD[bar]-Signal[bar] : EMPTY_VALUE;
      HistogramColor[bar]=1;
      ClosedCross[bar]=EMPTY_VALUE;
      if(!IsValue(Histogram[bar])) continue;
      bool has_previous=(bar>0 && IsValue(Histogram[bar-1]));
      bool rising=(has_previous && Histogram[bar]>Histogram[bar-1]);
      HistogramColor[bar]=(Histogram[bar]>=0) ? (rising ? 0 : 1) : (rising ? 2 : 3);
      ClosedCross[bar]=has_previous ? 0 : EMPTY_VALUE;
      if(bar<rates_total-1 && has_previous)
        {
         if(Histogram[bar-1]<=0 && Histogram[bar]>0) ClosedCross[bar]=1;
         else if(Histogram[bar-1]>=0 && Histogram[bar]<0) ClosedCross[bar]=-1;
        }
     }
   if(InpEnableLocalAlerts && !reset && rates_total>=2 &&
      LastOpenTime!=0 && LastOpenTime!=time[rates_total-1])
     {
      int closed=rates_total-2;
      if(ClosedCross[closed]==1 || ClosedCross[closed]==-1)
         Alert(StringFormat("ZLMACD %s %s: histogram crossed %s zero at %s (closed bar).",
                            _Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),
                            ClosedCross[closed]>0 ? "above" : "below",
                            TimeToString(time[closed],TIME_DATE|TIME_MINUTES)));
     }
   FirstBarTime=time[0];
   LastOpenTime=time[rates_total-1];
   LastRatesTotal=rates_total;
   return(rates_total);
  }
