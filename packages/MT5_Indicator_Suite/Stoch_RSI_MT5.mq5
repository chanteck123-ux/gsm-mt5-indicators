//+------------------------------------------------------------------+
//|                                             Stoch_RSI_MT5.mq5     |
//| Original MQL5 implementation of Stochastic RSI.                  |
//| Uses MT5 iRSI, then stochastic normalization and SMA smoothing.   |
//| This is not a claim of point-for-point TradingView equivalence.   |
//| No orders, alerts, external libraries, or future-bar references.  |
//+------------------------------------------------------------------+
#property copyright "Original MQL5 implementation, 2026"
#property version   "1.00"
#property description "Stoch RSI: MT5 RSI -> stochastic -> SMA K -> SMA D. Current chart timeframe."
#property description "The live bar changes with price. A flat RSI range is defined as raw Stoch RSI = 0."
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   2
#property indicator_minimum 0.0
#property indicator_maximum 100.0
#property indicator_level1 20.0
#property indicator_level2 50.0
#property indicator_level3 80.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

#property indicator_label1 "Stoch RSI K"
#property indicator_type1  DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2
#property indicator_label2 "Stoch RSI D"
#property indicator_type2  DRAW_LINE
#property indicator_color2 clrOrange
#property indicator_style2 STYLE_SOLID
#property indicator_width2 2

input int InpRsiPeriod   = 14; // RSI 周期（收盘价，至少 1）
input int InpStochPeriod = 14; // RSI 高低范围回看周期（至少 1）
input int InpKSmoothing  = 3;  // K 线 SMA 平滑周期（至少 1）
input int InpDSmoothing  = 3;  // D 线 SMA 平滑周期（至少 1）

// Public iCustom/CopyBuffer contract: buffer 0 = K; buffer 1 = D.
// Buffer 2 is internal raw Stoch RSI, not a trading-signal contract.
double KBuffer[];
double DBuffer[];
double RawBuffer[];
double RsiValues[];

int      RsiHandle = INVALID_HANDLE;
int      RawBegin  = 0;
int      KBegin    = 0;
int      DBegin    = 0;
datetime FirstBarTime = 0;
int      PreviousRsiBars = 0;
bool     DataFailureLogged = false;

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRsiPeriod < 1 || InpStochPeriod < 1 ||
      InpKSmoothing < 1 || InpDSmoothing < 1)
     {
      Print("Stoch_RSI_MT5: all periods must be at least 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Use a wider type before converting offsets to integer indexes.
   const long last_begin = (long)InpRsiPeriod + InpStochPeriod - 1 +
                           InpKSmoothing - 1 + InpDSmoothing - 1;
   if(last_begin > 2147483646)
     {
      Print("Stoch_RSI_MT5: combined periods exceed the supported index range.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   RawBegin = InpRsiPeriod + InpStochPeriod - 1;
   KBegin   = RawBegin + InpKSmoothing - 1;
   DBegin   = KBegin + InpDSmoothing - 1;

   if(!SetIndexBuffer(0,KBuffer,INDICATOR_DATA) ||
      !SetIndexBuffer(1,DBuffer,INDICATOR_DATA) ||
      !SetIndexBuffer(2,RawBuffer,INDICATOR_CALCULATIONS))
      return(INIT_FAILED);

   // Index zero is the oldest loaded chart bar, consistently everywhere.
   ArraySetAsSeries(KBuffer,false);
   ArraySetAsSeries(DBuffer,false);
   ArraySetAsSeries(RawBuffer,false);
   ArraySetAsSeries(RsiValues,false);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,KBegin);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,DBegin);
   IndicatorSetInteger(INDICATOR_DIGITS,2);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Stoch RSI (%d,%d,%d,%d)",
                                   InpRsiPeriod,InpStochPeriod,
                                   InpKSmoothing,InpDSmoothing));

   ResetLastError();
   RsiHandle = iRSI(_Symbol,_Period,InpRsiPeriod,PRICE_CLOSE);
   if(RsiHandle == INVALID_HANDLE)
     {
      PrintFormat("Stoch_RSI_MT5: iRSI handle creation failed, error %d.",GetLastError());
      return(INIT_FAILED);
     }
   FirstBarTime = 0;
   PreviousRsiBars = 0;
   DataFailureLogged = false;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Do not leave unwritten values looking like valid zeros            |
//+------------------------------------------------------------------+
void ClearBuffersFrom(const int start,const int total)
  {
   for(int i=start; i<total; ++i)
     {
      KBuffer[i] = EMPTY_VALUE;
      DBuffer[i] = EMPTY_VALUE;
      RawBuffer[i] = EMPTY_VALUE;
     }
  }

//+------------------------------------------------------------------+
//| Log a temporary data problem once; the next Calculate retries it  |
//+------------------------------------------------------------------+
void ReportDataFailure(const string context)
  {
   if(!DataFailureLogged)
     {
      PrintFormat("Stoch_RSI_MT5: %s; waiting for data and retrying. Error %d.",
                  context,GetLastError());
      DataFailureLogged = true;
     }
  }

//+------------------------------------------------------------------+
//| Calculate                                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total <= 0)
      return(0);
   ArraySetAsSeries(time,false);

   ResetLastError();
   const int rsi_bars = BarsCalculated(RsiHandle);
   // MT5 sets prev_calculated=0 after history changes. The oldest-bar
   // check also handles a fixed-size chart window shifting forward.
   const bool rebuild = prev_calculated <= 0 || prev_calculated > rates_total ||
                        FirstBarTime != time[0] ||
                        (PreviousRsiBars > 0 && rsi_bars < PreviousRsiBars) ||
                        (PreviousRsiBars > 0 &&
                         rsi_bars - PreviousRsiBars > rates_total - prev_calculated);
   const int start = rebuild ? 0 : prev_calculated - 1;
   ClearBuffersFrom(start,rates_total);

   // MT5 iRSI's first usable RSI is at index InpRsiPeriod. Before a
   // full stochastic window exists all values deliberately stay empty.
   if(rates_total <= RawBegin)
     {
      FirstBarTime = time[0];
      PreviousRsiBars = rsi_bars;
      return(rates_total);
     }

   if(rsi_bars < rates_total)
     {
      ReportDataFailure("RSI history is not yet fully calculated");
      return(0);
     }

   const int first_raw = (start > RawBegin) ? start : RawBegin;
   const int first_rsi = first_raw - InpStochPeriod + 1;
   const int copy_count = rates_total - first_rsi;
   // CopyBuffer stores oldest data first in physical memory. A small
   // temporary array avoids partial-copy alignment of indicator buffers.
   ResetLastError();
   const int copied = CopyBuffer(RsiHandle,0,0,copy_count,RsiValues);
   if(copied != copy_count)
     {
      ReportDataFailure("CopyBuffer did not return all requested RSI values");
      return(0); // Full retry next event; no permanent stale-data flag.
     }

   for(int r=0; r<copy_count; ++r)
     {
      if(RsiValues[r] == EMPTY_VALUE || !MathIsValidNumber(RsiValues[r]))
        {
         ReportDataFailure("RSI contains an unavailable value");
         return(0);
        }
     }

   // Every window ends at i. It never reads a newer/future bar.
   for(int i=first_raw; i<rates_total && !IsStopped(); ++i)
     {
      const int current_rsi = i - first_rsi;
      double lowest = RsiValues[current_rsi];
      double highest = lowest;
      for(int j=current_rsi-InpStochPeriod+1; j<current_rsi; ++j)
        {
         if(RsiValues[j] < lowest)
            lowest = RsiValues[j];
         if(RsiValues[j] > highest)
            highest = RsiValues[j];
        }
      const double range = highest - lowest;
      // Explicit convention: a perfectly flat RSI range yields zero.
      // This avoids division by zero; other platforms may use another rule.
      RawBuffer[i] = (range > 0.0) ?
                     100.0 * (RsiValues[current_rsi] - lowest) / range : 0.0;
      RawBuffer[i] = MathMax(0.0,MathMin(100.0,RawBuffer[i]));

      if(i >= KBegin)
        {
         double sum_k = 0.0;
         for(int j=i-InpKSmoothing+1; j<=i; ++j)
            sum_k += RawBuffer[j];
         KBuffer[i] = sum_k / InpKSmoothing;
        }
      if(i >= DBegin)
        {
         double sum_d = 0.0;
         for(int j=i-InpDSmoothing+1; j<=i; ++j)
            sum_d += KBuffer[j];
         DBuffer[i] = sum_d / InpDSmoothing;
        }
     }
   if(IsStopped())
      return(0);

   FirstBarTime = time[0];
   PreviousRsiBars = rsi_bars;
   DataFailureLogged = false;
   // Includes the current bar, so a tick recalculates that live value.
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Release owned indicator resources                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(RsiHandle != INVALID_HANDLE)
     {
      IndicatorRelease(RsiHandle);
      RsiHandle = INVALID_HANDLE;
     }
  }
//+------------------------------------------------------------------+
