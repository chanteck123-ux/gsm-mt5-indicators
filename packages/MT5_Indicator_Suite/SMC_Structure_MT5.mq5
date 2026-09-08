// This work is licensed under Attribution-NonCommercial-ShareAlike 4.0 International
// (CC BY-NC-SA 4.0) https://creativecommons.org/licenses/by-nc-sa/4.0/
// Original Smart Money Concepts Pine Script: (c) LuxAlgo.
// MQL5 adaptation from the complete user-supplied smc.txt, 2026-09-08.
// Changes: closed-bar confirmation, safe higher-timeframe mapping, bounded objects,
// public causal buffers, suppression of inverted parsed OB candidates, no lookahead.
// This adaptation is not affiliated with LuxAlgo. No order placement.
#property copyright "© LuxAlgo; MQL5 closed-bar adaptation under CC BY-NC-SA 4.0"
#property link "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version "2.00"
#property description "SMC source adaptation: leg pivots, BOS/CHoCH, parsed OB, EQ, confirmed MTF FVG."
#property indicator_chart_window
#property indicator_buffers 40
#property indicator_plots 36
#property indicator_label1 "InternalBiasData"
#property indicator_type1 DRAW_NONE
#property indicator_label2 "SwingBiasData"
#property indicator_type2 DRAW_NONE
#property indicator_label3 "InternalEvent"
#property indicator_type3 DRAW_NONE
#property indicator_label4 "SwingEvent"
#property indicator_type4 DRAW_NONE
#property indicator_label5 "SwingHighData"
#property indicator_type5 DRAW_NONE
#property indicator_label6 "SwingLowData"
#property indicator_type6 DRAW_NONE
#property indicator_label7 "BullOBUpper"
#property indicator_type7 DRAW_NONE
#property indicator_label8 "BullOBLower"
#property indicator_type8 DRAW_NONE
#property indicator_label9 "BearOBUpper"
#property indicator_type9 DRAW_NONE
#property indicator_label10 "BearOBLower"
#property indicator_type10 DRAW_NONE
#property indicator_label11 "BullFVGUpper"
#property indicator_type11 DRAW_NONE
#property indicator_label12 "BullFVGLower"
#property indicator_type12 DRAW_NONE
#property indicator_label13 "BearFVGUpper"
#property indicator_type13 DRAW_NONE
#property indicator_label14 "BearFVGLower"
#property indicator_type14 DRAW_NONE
#property indicator_label15 "RegionEvent"
#property indicator_type15 DRAW_NONE
#property indicator_label16 "ATRData"
#property indicator_type16 DRAW_NONE
#property indicator_label17 "OBCount"
#property indicator_type17 DRAW_NONE
#property indicator_label18 "FVGCount"
#property indicator_type18 DRAW_NONE
#property indicator_label19 "InternalHighData"
#property indicator_type19 DRAW_NONE
#property indicator_label20 "InternalLowData"
#property indicator_type20 DRAW_NONE
#property indicator_label21 "TrailingHighData"
#property indicator_type21 DRAW_NONE
#property indicator_label22 "TrailingLowData"
#property indicator_type22 DRAW_NONE
#property indicator_label23 "EquilibriumData"
#property indicator_type23 DRAW_NONE
#property indicator_label24 "PremiumLowerData"
#property indicator_type24 DRAW_NONE
#property indicator_label25 "DiscountUpperData"
#property indicator_type25 DRAW_NONE
#property indicator_label26 "PriorDayHigh"
#property indicator_type26 DRAW_NONE
#property indicator_label27 "PriorDayLow"
#property indicator_type27 DRAW_NONE
#property indicator_label28 "PriorWeekHigh"
#property indicator_type28 DRAW_NONE
#property indicator_label29 "PriorWeekLow"
#property indicator_type29 DRAW_NONE
#property indicator_label30 "PriorMonthHigh"
#property indicator_type30 DRAW_NONE
#property indicator_label31 "PriorMonthLow"
#property indicator_type31 DRAW_NONE
#property indicator_label32 "FVGSourceClosedTime"
#property indicator_type32 DRAW_NONE
#property indicator_label33 "InternalOBCount"
#property indicator_type33 DRAW_NONE
#property indicator_label34 "SwingOBCount"
#property indicator_type34 DRAW_NONE
#property indicator_label35 "SourceAlertMask"
#property indicator_type35 DRAW_NONE
#property indicator_label36 "SMC Open;SMC High;SMC Low;SMC Close"
#property indicator_type36 DRAW_COLOR_CANDLES
#property indicator_color36 clrSeaGreen,clrIndianRed

enum ENUM_SMC_OB_FILTER { SMC_ATR=0, SMC_CUMULATIVE_RANGE=1 };
enum ENUM_SMC_MITIGATION { SMC_HIGH_LOW=0, SMC_CLOSE=1 };
enum ENUM_SMC_STRUCTURE_FILTER { SMC_ALL=0, SMC_BOS_ONLY=1, SMC_CHOCH_ONLY=2 };
input int InpInternalLength=5;                      // Source internal leg length
input int InpSwingLength=50;                        // Source swing leg length
input int InpEqualLength=3;                         // EQ leg confirmation bars
input double InpEqualThreshold=0.10;                // Strict threshold * ATR(200)
input ENUM_SMC_OB_FILTER InpOBFilter=SMC_ATR;        // Parsed extrema volatility filter
input ENUM_SMC_MITIGATION InpOBMitigation=SMC_HIGH_LOW;// Source OB invalidation input
input bool InpConfluenceFilter=false;               // Preserve source expression as written
input bool InpShowInternal=true;
input bool InpShowSwing=true;
input ENUM_SMC_STRUCTURE_FILTER InpInternalBullFilter=SMC_ALL;
input ENUM_SMC_STRUCTURE_FILTER InpInternalBearFilter=SMC_ALL;
input ENUM_SMC_STRUCTURE_FILTER InpSwingBullFilter=SMC_ALL;
input ENUM_SMC_STRUCTURE_FILTER InpSwingBearFilter=SMC_ALL;
input bool InpShowInternalOB=true;
input bool InpShowSwingOB=false;
input int InpInternalOBVisible=5;                   // Latest valid internal blocks shown
input int InpSwingOBVisible=5;                      // Latest valid swing blocks shown
input bool InpShowEqual=true;
input bool InpShowFVG=false;
input bool InpFVGAutoThreshold=true;
input ENUM_TIMEFRAMES InpFVGTimeframe=PERIOD_CURRENT;// Current or higher only
input int InpFVGExtendBars=1;                       // Additional chart bars after source-width box
input bool InpShowStrongWeak=true;
input bool InpShowPremiumDiscount=false;
input bool InpShowDaily=false;
input bool InpShowWeekly=false;
input bool InpShowMonthly=false;
input bool InpShowPivotLabels=false;
input bool InpColorCandles=false;                   // Closed candles use pre-break internal bias
input bool InpPresentMode=false;                    // Latest mark for each source call category
input bool InpMonochrome=false;
input bool InpDrawObjects=true;                     // False for numerical iCustom callers
input bool InpFillZones=false;                      // Native MT5 solid fill; off avoids obscuring candles
input bool InpShowZoneLabels=true;
input int InpLookbackBars=3000;                     // Structure replay range on initialization
input int InpMaxOBStored=100;                       // Per internal/swing class (source default 100)
input int InpMaxFVGStored=50;
input int InpMaxMarks=120;
input color InpBullColor=C'8,153,129';
input color InpBearColor=C'242,54,69';
input color InpInternalBullOBColor=C'49,121,245';
input color InpInternalBearOBColor=C'247,124,128';
input color InpSwingBullOBColor=C'24,72,204';
input color InpSwingBearOBColor=C'178,40,51';
input color InpBullFVGColor=C'0,185,90';
input color InpBearFVGColor=C'220,45,70';
input color InpLevelsColor=C'33,87,243';
input ENUM_LINE_STYLE InpLevelsStyle=STYLE_SOLID;

double InternalBiasData[];
double SwingBiasData[];
double InternalEvent[];
double SwingEvent[];
double SwingHighData[];
double SwingLowData[];
double BullOBUpper[];
double BullOBLower[];
double BearOBUpper[];
double BearOBLower[];
double BullFVGUpper[];
double BullFVGLower[];
double BearFVGUpper[];
double BearFVGLower[];
double RegionEvent[];
double ATRData[];
double OBCount[];
double FVGCount[];
double InternalHighData[];
double InternalLowData[];
double TrailingHighData[];
double TrailingLowData[];
double EquilibriumData[];
double PremiumLowerData[];
double DiscountUpperData[];
double PriorDayHigh[];
double PriorDayLow[];
double PriorWeekHigh[];
double PriorWeekLow[];
double PriorMonthHigh[];
double PriorMonthLow[];
double FVGSourceClosedTime[];
double InternalOBCount[];
double SwingOBCount[];
double SourceAlertMask[];
double CandleOpen[];
double CandleHigh[];
double CandleLow[];
double CandleClose[];
double CandleColor[];
double CalcATR[],CumulativeTR[],ParsedHigh[],ParsedLow[],FVGThreshold[];
int FVGIndex[];
MqlRates FVGFrame[],DayFrame[],WeekFrame[],MonthFrame[];
ENUM_TIMEFRAMES FVGPeriod;

struct Pivot { double price,previous; int index; datetime origin,known; bool valid,broken; };
struct Region
{
   int id,side,kind; // 1 internal OB, 2 swing OB, 3 FVG
   double upper,lower,mitigation;
   datetime origin,known,draw_end;
   bool touched;
};
struct Mark
{
   int id,side,category;
   bool line,swing;
   double price;
   datetime start,finish,origin;
   string label;
};
Pivot IH,IL,SH,SL,EH,EL;
Region Regions[];
Mark Marks[];
int InternalLeg=0,SwingLeg=0,EqualLeg=0,InternalBias=0,SwingBias=0,Serial=0;
int LastClosedIndex=-1;
datetime LastClosedTime=0,LastFVGKnown=0,TrailingKnown=0;
double TrailingTop=EMPTY_VALUE,TrailingBottom=EMPTY_VALUE;
datetime TopKnown=0,BottomKnown=0;
string Prefix="";
long ObjectsChart=-1;
ulong LastHistoryNotice=0;

color BullColor() { return InpMonochrome ? C'178,181,190' : InpBullColor; }
color BearColor() { return InpMonochrome ? C'93,96,107' : InpBearColor; }
bool Valid(const double x) { return x!=EMPTY_VALUE && MathIsValidNumber(x); }
void OwnChart()
{
   if(!InpDrawObjects) return;
   long now=ChartID();
   if(ObjectsChart!=now)
   {
      if(ObjectsChart>=0) ObjectsDeleteAll(ObjectsChart,Prefix);
      ObjectsChart=now;
   }
   ObjectCreate(0,Prefix+"OWNER",OBJ_LABEL,0,0,0);
   ObjectSetString(0,Prefix+"OWNER",OBJPROP_TEXT,"");
   ObjectSetInteger(0,Prefix+"OWNER",OBJPROP_HIDDEN,true);
}
void DropRegion(const int index)
{
   if(InpDrawObjects)
   {
      string n=Prefix+"R"+IntegerToString(Regions[index].id);
      ObjectDelete(0,n); ObjectDelete(0,n+"M"); ObjectDelete(0,n+"T");
   }
   for(int i=index;i<ArraySize(Regions)-1;i++) Regions[i]=Regions[i+1];
   ArrayResize(Regions,ArraySize(Regions)-1);
}
bool AddRegion(const int side,const int kind,const double lower,const double upper,
               const double mitigation,const datetime known,const datetime origin,const datetime draw_end)
{
   // Source can select an inverted high-volatility parsed candle. Do not silently
   // normalize it into a different OB. This adaptation suppresses that candidate.
   if(!Valid(lower) || !Valid(upper) || upper<=lower) return false;
   int count=0;
   for(int i=0;i<ArraySize(Regions);i++) if(Regions[i].kind==kind) count++;
   int cap=(kind==3 ? InpMaxFVGStored : InpMaxOBStored);
   if(count>=cap)
      for(int i=0;i<ArraySize(Regions);i++) if(Regions[i].kind==kind) { DropRegion(i); break; }
   int n=ArraySize(Regions);
   ArrayResize(Regions,n+1); ZeroMemory(Regions[n]);
   Regions[n].id=++Serial; Regions[n].side=side; Regions[n].kind=kind;
   Regions[n].lower=lower; Regions[n].upper=upper; Regions[n].mitigation=mitigation;
   Regions[n].known=known; Regions[n].origin=origin; Regions[n].draw_end=draw_end;
   return true;
}
void DropMark(const int index)
{
   string n=Prefix+"M"+IntegerToString(Marks[index].id);
   if(InpDrawObjects) { ObjectDelete(0,n); ObjectDelete(0,n+"T"); }
   for(int i=index;i<ArraySize(Marks)-1;i++) Marks[i]=Marks[i+1];
   ArrayResize(Marks,ArraySize(Marks)-1);
}
void AddMark(const string label,const int side,const double price,const datetime start,
             const datetime finish,const datetime origin,const bool line,const bool swing,const int category)
{
   if(!InpDrawObjects) return;
   if(InpPresentMode)
      for(int i=ArraySize(Marks)-1;i>=0;i--) if(Marks[i].category==category) DropMark(i);
   int n=ArraySize(Marks);
   ArrayResize(Marks,n+1);
   Marks[n].id=++Serial; Marks[n].side=side; Marks[n].price=price;
   Marks[n].start=start; Marks[n].finish=finish; Marks[n].origin=origin;
   Marks[n].line=line; Marks[n].swing=swing; Marks[n].label=label; Marks[n].category=category;
   while(ArraySize(Marks)>InpMaxMarks) DropMark(0);
}

int ClosedIndex(MqlRates &frame[],const datetime known)
{
   // The frame containing known is open; only its predecessor is usable.
   int lo=0,hi=ArraySize(frame)-1,found=-1;
   while(lo<=hi)
   {
      int mid=(lo+hi)/2;
      if(frame[mid].time<=known) { found=mid; lo=mid+1; } else hi=mid-1;
   }
   return found-1;
}
int ChartIndex(const datetime &time[],const int last,const datetime at)
{
   int lo=0,hi=last,found=-1;
   while(lo<=hi)
   {
      int mid=(lo+hi)/2;
      if(time[mid]<=at) { found=mid; lo=mid+1; } else hi=mid-1;
   }
   return found;
}
bool FrameReady(const ENUM_TIMEFRAMES tf,const datetime from,const datetime until,MqlRates &frame[])
{
   ArraySetAsSeries(frame,false);
   datetime wanted=from-(datetime)(3*PeriodSeconds(tf));
   datetime first_available=(datetime)SeriesInfoInteger(_Symbol,tf,SERIES_FIRSTDATE);
   if(first_available>0 && wanted<first_available) wanted=first_available;
   ResetLastError();
   int copied=CopyRates(_Symbol,tf,wanted,until,frame);
   int error=GetLastError();
   bool synchronized=(bool)SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED);
   bool ready=(copied>0 && synchronized);
   if(!ready && GetTickCount64()-LastHistoryNotice>=5000)
   {
      LastHistoryNotice=GetTickCount64();
      PrintFormat("SMC history pending symbol=%s tf=%s from=%s until=%s copied=%d synchronized=%d error=%d first=%s",
                  _Symbol,EnumToString(tf),TimeToString(wanted,TIME_DATE|TIME_MINUTES),TimeToString(until,TIME_DATE|TIME_MINUTES),
                  copied,synchronized,error,TimeToString(first_available,TIME_DATE|TIME_MINUTES));
   }
   return ready;
}
bool PrepareFrames(const datetime &time[],const int last)
{
   datetime first=time[0],until=time[last+1];
   bool ready=true;
   // Start every enabled history request even when an earlier frame is pending.
   // A single synchronized bar is a valid history; missing prior levels stay empty.
   if(InpShowFVG && FVGPeriod!=_Period)
      if(!FrameReady(FVGPeriod,first,until,FVGFrame)) ready=false;
   if(InpShowDaily && PeriodSeconds(_Period)<=PeriodSeconds(PERIOD_D1))
      if(!FrameReady(PERIOD_D1,first,until,DayFrame)) ready=false;
   if(InpShowWeekly && PeriodSeconds(_Period)<=PeriodSeconds(PERIOD_W1))
      if(!FrameReady(PERIOD_W1,first,until,WeekFrame)) ready=false;
   if(InpShowMonthly && PeriodSeconds(_Period)<=PeriodSeconds(PERIOD_MN1))
      if(!FrameReady(PERIOD_MN1,first,until,MonthFrame)) ready=false;
   return ready;
}
void PrepareFVG(const int rates_total,const datetime &time[],const double &open[],const double &close[])
{
   ArrayResize(FVGIndex,rates_total); ArrayInitialize(FVGIndex,-1);
   ArrayResize(FVGThreshold,rates_total); ArrayInitialize(FVGThreshold,EMPTY_VALUE);
   if(!InpShowFVG) return;
   double cumulative=0;
   int previous=-999;
   for(int b=0;b<rates_total-1;b++)
   {
      int s=(FVGPeriod==_Period ? b : ClosedIndex(FVGFrame,time[b+1]));
      if(s==previous || s<1) { previous=s; continue; }
      previous=s;
      double middle_open=(FVGPeriod==_Period ? open[s-1] : FVGFrame[s-1].open);
      double middle_close=(FVGPeriod==_Period ? close[s-1] : FVGFrame[s-1].close);
      if(middle_open==0) continue;
      double delta=(middle_close-middle_open)/(middle_open*100.0); // Preserve source scale.
      cumulative+=MathAbs(delta);
      datetime source_open=(FVGPeriod==_Period ? time[s] : FVGFrame[s].time);
      int source_chart_index=ChartIndex(time,b,source_open);
      if(source_chart_index<=0 && InpFVGAutoThreshold) continue;
      FVGIndex[b]=s;
      // Source divides by CHART bar_index at the original third-bar opening.
      // Detection is delayed until that third source bar has closed.
      FVGThreshold[b]=(InpFVGAutoThreshold ? 2.0*cumulative/source_chart_index : 0.0);
   }
}

int LegChange(const int b,const int length,int &leg,const double &high[],const double &low[])
{
   if(b<length) return 0;
   int p=b-length,old=leg;
   bool new_high=true,new_low=true;
   for(int i=p+1;i<=b;i++)
   {
      if(high[p]<=high[i]) new_high=false;
      if(low[p]>=low[i]) new_low=false;
   }
   if(new_high) leg=0; else if(new_low) leg=1; // Exact source high-branch priority.
   return leg-old;
}
void SetPivot(Pivot &pivot,const int p,const double price,const datetime known,const datetime &time[])
{
   pivot.previous=(pivot.valid ? pivot.price : EMPTY_VALUE);
   pivot.price=price; pivot.index=p; pivot.origin=time[p]; pivot.known=known;
   pivot.valid=true; pivot.broken=false;
}
int Confirm(const int b,const int length,const int layer,int &leg,Pivot &ph,Pivot &pl,
            int &alerts,const datetime &time[],const double &high[],const double &low[])
{
   int change=LegChange(b,length,leg,high,low);
   if(change==0) return 0;
   int p=b-length,flags=0;
   datetime known=time[b+1];
   if(change==1)
   {
      if(layer==2 && pl.valid && Valid(CalcATR[b]) && MathAbs(pl.price-low[p])<InpEqualThreshold*CalcATR[b])
      {
         flags|=8192; alerts|=8192;
         AddMark("EQL",1,low[p],known,known,time[p],false,true,21);
      }
      SetPivot(pl,p,low[p],known,time);
      if(layer==1)
      {
         TrailingBottom=pl.price; BottomKnown=known; TrailingKnown=known;
         if(InpShowPivotLabels) AddMark(Valid(pl.previous) && pl.price<pl.previous ? "LL" : "HL",1,pl.price,known,known,time[p],false,true,30);
      }
   }
   else
   {
      if(layer==2 && ph.valid && Valid(CalcATR[b]) && MathAbs(ph.price-high[p])<InpEqualThreshold*CalcATR[b])
      {
         flags|=4096; alerts|=4096;
         AddMark("EQH",-1,high[p],known,known,time[p],false,true,20);
      }
      SetPivot(ph,p,high[p],known,time);
      if(layer==1)
      {
         TrailingTop=ph.price; TopKnown=known; TrailingKnown=known;
         if(InpShowPivotLabels) AddMark(Valid(ph.previous) && ph.price>ph.previous ? "HH" : "LH",-1,ph.price,known,known,time[p],false,true,31);
      }
   }
   return flags;
}
int StoreOB(const int b,const bool swing,const int side,const Pivot &p,const datetime &time[])
{
   if((swing && !InpShowSwingOB) || (!swing && !InpShowInternalOB) || p.index>=b) return 0;
   int chosen=p.index;
   // First max/min wins on ties; the breakout bar is excluded as in slice(start,end).
   for(int j=p.index+1;j<b;j++)
      if((side<0 && ParsedHigh[j]>ParsedHigh[chosen]) || (side>0 && ParsedLow[j]<ParsedLow[chosen])) chosen=j;
   double upper=ParsedHigh[chosen],lower=ParsedLow[chosen];
   if(AddRegion(side,swing ? 2 : 1,lower,upper,side>0 ? lower : upper,time[b+1],time[chosen],0)) return side>0 ? 1 : 2;
   return 0;
}
bool FilterAllows(const ENUM_SMC_STRUCTURE_FILTER f,const int event)
{
   return f==SMC_ALL || (f==SMC_BOS_ONLY && MathAbs(event)==1) || (f==SMC_CHOCH_ONLY && MathAbs(event)==2);
}
int Breaks(const int b,const bool swing,Pivot &ph,Pivot &pl,const double previous_high,const double previous_low,
           int &bias,int &flags,int &alerts,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
{
   int event=0;
   bool bullish=true,bearish=true;
   if(!swing && InpConfluenceFilter)
   {
      double upper=high[b]-MathMax(close[b],open[b]);
      double source_other=MathMin(close[b],open[b]-low[b]); // Exact source parentheses.
      bullish=upper>source_other; bearish=upper<source_other;
   }
   bool extra_up=(swing || (SH.valid && ph.valid && ph.price!=SH.price && bullish));
   bool extra_down=(swing || (SL.valid && pl.valid && pl.price!=SL.price && bearish));
   if(ph.valid && !ph.broken && Valid(previous_high) && close[b]>ph.price && close[b-1]<=previous_high && extra_up)
   {
      event=(bias<0 ? 2 : 1); bias=1; ph.broken=true;
      alerts|=(1<<((swing ? 4 : 0)+(event==2 ? 2 : 0)));
      bool shown=(swing ? InpShowSwing : InpShowInternal);
      ENUM_SMC_STRUCTURE_FILTER filter=(swing ? InpSwingBullFilter : InpInternalBullFilter);
      if(shown && FilterAllows(filter,event)) AddMark((swing ? "s " : "i ")+(event==2 ? "CHoCH" : "BOS"),1,ph.price,ph.known,time[b+1],ph.origin,true,swing,swing ? 12 : 10);
      flags|=StoreOB(b,swing,1,ph,time);
   }
   // Keep source's second independent branch, including its order of bias updates.
   if(pl.valid && !pl.broken && Valid(previous_low) && close[b]<pl.price && close[b-1]>=previous_low && extra_down)
   {
      event=(bias>0 ? -2 : -1); bias=-1; pl.broken=true;
      alerts|=(1<<((swing ? 4 : 0)+(event==-2 ? 3 : 1)));
      bool shown=(swing ? InpShowSwing : InpShowInternal);
      ENUM_SMC_STRUCTURE_FILTER filter=(swing ? InpSwingBearFilter : InpInternalBearFilter);
      if(shown && FilterAllows(filter,event)) AddMark((swing ? "s " : "i ")+(event==-2 ? "CHoCH" : "BOS"),-1,pl.price,pl.known,time[b+1],pl.origin,true,swing,swing ? 13 : 11);
      flags|=StoreOB(b,swing,-1,pl,time);
   }
   return event;
}
int Mitigate(const int b,const bool fvg,int &alerts,const datetime &time[],const double &high[],const double &low[],const double &close[])
{
   int flags=0;
   // Reverse deletion avoids skipping adjacent invalid entries, a source loop edge case.
   for(int i=ArraySize(Regions)-1;i>=0;i--)
   {
      if((Regions[i].kind==3)!=fvg) continue;
      double source=(fvg || InpOBMitigation==SMC_HIGH_LOW ? (Regions[i].side>0 ? low[b] : high[b]) : close[b]);
      bool invalid=(Regions[i].side>0 ? source<Regions[i].mitigation : source>Regions[i].mitigation);
      int offset=(fvg ? 2 : 0)+(Regions[i].side>0 ? 0 : 1);
      if(invalid)
      {
         flags|=(1<<(8+offset));
         if(!fvg) alerts|=(1<<(8+(Regions[i].kind==2 ? 2 : 0)+(Regions[i].side>0 ? 0 : 1)));
         DropRegion(i);
      }
      else if(!Regions[i].touched && time[b]>=Regions[i].known && high[b]>=Regions[i].lower && low[b]<=Regions[i].upper)
      {
         Regions[i].touched=true; flags|=(1<<(4+offset)); // Additional informational buffer; no source alert.
      }
   }
   return flags;
}
int DetectFVG(const int b,int &alerts,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
{
   if(!InpShowFVG || FVGIndex[b]<2 || !Valid(FVGThreshold[b])) return 0;
   int s=FVGIndex[b];
   double middle_open,middle_close,current_high,current_low,two_high,two_low;
   datetime origin,source_closed;
   if(FVGPeriod==_Period)
   {
      middle_open=open[s-1]; middle_close=close[s-1]; current_high=high[s]; current_low=low[s];
      two_high=high[s-2]; two_low=low[s-2]; origin=time[s]; source_closed=time[s+1];
   }
   else
   {
      middle_open=FVGFrame[s-1].open; middle_close=FVGFrame[s-1].close;
      current_high=FVGFrame[s].high; current_low=FVGFrame[s].low;
      two_high=FVGFrame[s-2].high; two_low=FVGFrame[s-2].low;
      origin=FVGFrame[s].time; source_closed=FVGFrame[s+1].time;
   }
   LastFVGKnown=source_closed;
   if(middle_open==0 || source_closed>time[b+1]) return 0;
   double delta=(middle_close-middle_open)/(middle_open*100.0);
   datetime known=time[b+1],end=known+PeriodSeconds(FVGPeriod)+InpFVGExtendBars*PeriodSeconds(_Period);
   if(current_low>two_high && middle_close>two_high && delta>FVGThreshold[b])
      if(AddRegion(1,3,two_high,current_low,two_high,known,origin,end)) { alerts|=16384; return 4; }
   if(current_high<two_low && middle_close<two_low && -delta>FVGThreshold[b])
      // Normalize DISPLAY bounds only. Preserve source bearish deletion threshold
      // currentHigh (near edge), which is asymmetric with bullish far-edge removal.
      if(AddRegion(-1,3,current_high,two_low,current_high,known,origin,end)) { alerts|=32768; return 8; }
   return 0;
}
void PriorLevels(const int b,const bool enabled,MqlRates &frame[],double &upper[],double &lower[],const datetime known)
{
   upper[b]=lower[b]=EMPTY_VALUE;
   if(!enabled) return;
   int s=ClosedIndex(frame,known);
   if(s>=0) { upper[b]=frame[s].high; lower[b]=frame[s].low; }
}
void WriteState(const int b,const double price,const int ie,const int se,const int flags,const int alerts,const datetime known)
{
   InternalBiasData[b]=InternalBias; SwingBiasData[b]=SwingBias;
   InternalEvent[b]=ie; SwingEvent[b]=se; RegionEvent[b]=flags; SourceAlertMask[b]=alerts;
   SwingHighData[b]=(SH.valid ? SH.price : EMPTY_VALUE); SwingLowData[b]=(SL.valid ? SL.price : EMPTY_VALUE);
   InternalHighData[b]=(IH.valid ? IH.price : EMPTY_VALUE); InternalLowData[b]=(IL.valid ? IL.price : EMPTY_VALUE);
   ATRData[b]=CalcATR[b]; TrailingHighData[b]=TrailingTop; TrailingLowData[b]=TrailingBottom;
   EquilibriumData[b]=PremiumLowerData[b]=DiscountUpperData[b]=EMPTY_VALUE;
   if(Valid(TrailingTop) && Valid(TrailingBottom) && TrailingTop>TrailingBottom)
   {
      EquilibriumData[b]=(TrailingTop+TrailingBottom)/2;
      PremiumLowerData[b]=0.95*TrailingTop+0.05*TrailingBottom;
      DiscountUpperData[b]=0.95*TrailingBottom+0.05*TrailingTop;
   }
   BullOBUpper[b]=BullOBLower[b]=BearOBUpper[b]=BearOBLower[b]=EMPTY_VALUE;
   BullFVGUpper[b]=BullFVGLower[b]=BearFVGUpper[b]=BearFVGLower[b]=EMPTY_VALUE;
   InternalOBCount[b]=SwingOBCount[b]=OBCount[b]=FVGCount[b]=0;
   FVGSourceClosedTime[b]=(LastFVGKnown>0 ? (double)LastFVGKnown : EMPTY_VALUE);
   double distance[4]={DBL_MAX,DBL_MAX,DBL_MAX,DBL_MAX};
   for(int i=0;i<ArraySize(Regions);i++)
   {
      Region r=Regions[i];
      if(r.kind==3) FVGCount[b]++;
      else { OBCount[b]++; if(r.kind==1) InternalOBCount[b]++; else SwingOBCount[b]++; }
      int slot=(r.kind==3 ? 2 : 0)+(r.side>0 ? 0 : 1);
      if((r.side>0 && r.lower>price) || (r.side<0 && r.upper<price)) continue;
      double d=(r.side>0 ? MathMax(0,price-r.upper) : MathMax(0,r.lower-price));
      if(d>distance[slot]) continue;
      distance[slot]=d;
      if(slot==0) { BullOBUpper[b]=r.upper; BullOBLower[b]=r.lower; }
      if(slot==1) { BearOBUpper[b]=r.upper; BearOBLower[b]=r.lower; }
      if(slot==2) { BullFVGUpper[b]=r.upper; BullFVGLower[b]=r.lower; }
      if(slot==3) { BearFVGUpper[b]=r.upper; BearFVGLower[b]=r.lower; }
   }
   PriorLevels(b,InpShowDaily,DayFrame,PriorDayHigh,PriorDayLow,known);
   PriorLevels(b,InpShowWeekly,WeekFrame,PriorWeekHigh,PriorWeekLow,known);
   PriorLevels(b,InpShowMonthly,MonthFrame,PriorMonthHigh,PriorMonthLow,known);
}

void Configure(const string n,const color c)
{
   ObjectSetInteger(0,n,OBJPROP_COLOR,c); ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
}
void Text(const string n,const string label,const datetime at,const double price,const color c,const int size=8,const bool above=true)
{
   ObjectCreate(0,n,OBJ_TEXT,0,at,price); ObjectMove(0,n,0,at,price); Configure(n,c);
   ObjectSetString(0,n,OBJPROP_TEXT,label); ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,above ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
}
void Line(const string n,const datetime from,const datetime to,const double price,const color c,const ENUM_LINE_STYLE style=STYLE_SOLID)
{
   ObjectCreate(0,n,OBJ_TREND,0,from,price,to,price); ObjectMove(0,n,0,from,price); ObjectMove(0,n,1,to,price);
   Configure(n,c); ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
}
void Box(const string n,const datetime from,const datetime to,const double upper,const double lower,const color c)
{
   ObjectCreate(0,n,OBJ_RECTANGLE,0,from,upper,to,lower); ObjectMove(0,n,0,from,upper); ObjectMove(0,n,1,to,lower);
   Configure(n,c); ObjectSetInteger(0,n,OBJPROP_FILL,InpFillZones); ObjectSetInteger(0,n,OBJPROP_BACK,true);
}
void FixedLevel(const string key,const string label,const double value,const datetime known,const datetime end)
{
   if(!Valid(value)) return;
   Line(Prefix+key,known,end,value,InpLevelsColor,InpLevelsStyle);
   Text(Prefix+key+"T",label,end,value,InpLevelsColor);
}
void Draw(const int b,const datetime known)
{
   if(!InpDrawObjects) return;
   OwnChart();
   datetime horizon=known+20*PeriodSeconds(_Period);
   int shown_i=0,shown_s=0;
   for(int i=ArraySize(Regions)-1;i>=0;i--)
   {
      Region r=Regions[i];
      string n=Prefix+"R"+IntegerToString(r.id);
      bool show=true;
      if(r.kind==1) { shown_i++; show=shown_i<=InpInternalOBVisible; }
      if(r.kind==2) { shown_s++; show=shown_s<=InpSwingOBVisible; }
      if(!show) { ObjectDelete(0,n); ObjectDelete(0,n+"M"); ObjectDelete(0,n+"T"); continue; }
      color c;
      if(InpMonochrome) c=(r.side>0 ? BullColor() : BearColor());
      else if(r.kind==1) c=(r.side>0 ? InpInternalBullOBColor : InpInternalBearOBColor);
      else if(r.kind==2) c=(r.side>0 ? InpSwingBullOBColor : InpSwingBearOBColor);
      else c=(r.side>0 ? InpBullFVGColor : InpBearFVGColor);
      datetime end=(r.kind==3 ? r.draw_end : horizon);
      Box(n,r.known,end,r.upper,r.lower,c);
      if(r.kind==3) Line(n+"M",r.known,end,(r.upper+r.lower)/2,c,STYLE_DOT);
      string label=(r.side>0 ? "+ " : "- ")+(r.kind==1 ? "iOB" : (r.kind==2 ? "sOB" : "FVG"));
      ObjectSetString(0,n,OBJPROP_TOOLTIP,label+"\nKnown "+TimeToString(r.known)+"\nOrigin "+TimeToString(r.origin)+"\nMitigation "+DoubleToString(r.mitigation,_Digits));
      if(InpShowZoneLabels) Text(n+"T",label,r.known,r.upper,c);
   }
   for(int i=0;i<ArraySize(Marks);i++)
   {
      Mark m=Marks[i]; string n=Prefix+"M"+IntegerToString(m.id); color c=(m.side>0 ? BullColor() : BearColor());
      if(m.line) Line(n,m.start,m.finish,m.price,c,m.swing ? STYLE_SOLID : STYLE_DASH);
      Text(n+"T",m.label,m.finish,m.price,c,m.swing ? 9 : 8,m.side>0);
      ObjectSetString(0,n+"T",OBJPROP_TOOLTIP,m.label+"\nConfirmed "+TimeToString(m.finish)+"\nOrigin "+TimeToString(m.origin));
   }
   if(InpShowStrongWeak)
   {
      if(Valid(TrailingTop))
      {
         Line(Prefix+"TH",TopKnown,horizon,TrailingTop,BearColor());
         Text(Prefix+"THT",SwingBias<0 ? "Strong High" : "Weak High",horizon,TrailingTop,BearColor());
      }
      if(Valid(TrailingBottom))
      {
         Line(Prefix+"TL",BottomKnown,horizon,TrailingBottom,BullColor());
         Text(Prefix+"TLT",SwingBias>0 ? "Strong Low" : "Weak Low",horizon,TrailingBottom,BullColor(),8,false);
      }
   }
   if(InpShowPremiumDiscount && Valid(EquilibriumData[b]))
   {
      // Current snapshot only: start at this snapshot's confirmation, never backdate
      // current range geometry to an old pivot.
      Box(Prefix+"PR",known,horizon,TrailingTop,PremiumLowerData[b],BearColor());
      Text(Prefix+"PRT","Premium",horizon,TrailingTop,BearColor());
      Box(Prefix+"DI",known,horizon,DiscountUpperData[b],TrailingBottom,BullColor());
      Text(Prefix+"DIT","Discount",horizon,TrailingBottom,BullColor(),8,false);
      Box(Prefix+"EQ",known,horizon,0.525*TrailingTop+0.475*TrailingBottom,0.525*TrailingBottom+0.475*TrailingTop,clrGray);
      Text(Prefix+"EQT","Equilibrium",horizon,EquilibriumData[b],clrGray);
   }
   if(InpShowDaily) { FixedLevel("PDH","PDH",PriorDayHigh[b],known,horizon); FixedLevel("PDL","PDL",PriorDayLow[b],known,horizon); }
   if(InpShowWeekly) { FixedLevel("PWH","PWH",PriorWeekHigh[b],known,horizon); FixedLevel("PWL","PWL",PriorWeekLow[b],known,horizon); }
   if(InpShowMonthly) { FixedLevel("PMH","PMH",PriorMonthHigh[b],known,horizon); FixedLevel("PML","PML",PriorMonthLow[b],known,horizon); }
   ChartRedraw(0);
}

int OnInit()
{
   FVGPeriod=(InpFVGTimeframe==PERIOD_CURRENT ? _Period : InpFVGTimeframe);
   PrintFormat("SMC source init symbol=%s chart=%s internal=%d swing=%d FVG=%d FVGTF=%s D=%d W=%d M=%d draw=%d OBfilter=%d mitigation=%d",
               _Symbol,EnumToString(_Period),InpInternalLength,InpSwingLength,InpShowFVG,EnumToString(FVGPeriod),
               InpShowDaily,InpShowWeekly,InpShowMonthly,InpDrawObjects,(int)InpOBFilter,(int)InpOBMitigation);
   if(InpInternalLength<1 || InpInternalLength>500 || InpSwingLength<10 || InpSwingLength>1000 ||
      InpEqualLength<1 || InpEqualLength>500 || !MathIsValidNumber(InpEqualThreshold) || InpEqualThreshold<0 || InpEqualThreshold>0.5 ||
      InpInternalOBVisible<1 || InpInternalOBVisible>20 || InpSwingOBVisible<1 || InpSwingOBVisible>20 ||
      InpFVGExtendBars<0 || InpFVGExtendBars>100 || InpLookbackBars<200 || InpLookbackBars>100000 ||
      InpMaxOBStored<1 || InpMaxOBStored>100 || InpMaxFVGStored<1 || InpMaxFVGStored>200 || InpMaxMarks<1 || InpMaxMarks>500 ||
      (InpShowFVG && PeriodSeconds(FVGPeriod)<PeriodSeconds(_Period))) return INIT_PARAMETERS_INCORRECT;
   Prefix="SMCL_"+StringFormat("%I64d_%I64u_",ChartID(),GetMicrosecondCount());
   while(InpDrawObjects && ObjectFind(0,Prefix+"OWNER")>=0) Prefix="SMCL_"+StringFormat("%I64d_%I64u_",ChartID(),GetMicrosecondCount());
   OwnChart();
   SetIndexBuffer(0,InternalBiasData,INDICATOR_DATA); ArraySetAsSeries(InternalBiasData,false);
   SetIndexBuffer(1,SwingBiasData,INDICATOR_DATA); ArraySetAsSeries(SwingBiasData,false);
   SetIndexBuffer(2,InternalEvent,INDICATOR_DATA); ArraySetAsSeries(InternalEvent,false);
   SetIndexBuffer(3,SwingEvent,INDICATOR_DATA); ArraySetAsSeries(SwingEvent,false);
   SetIndexBuffer(4,SwingHighData,INDICATOR_DATA); ArraySetAsSeries(SwingHighData,false);
   SetIndexBuffer(5,SwingLowData,INDICATOR_DATA); ArraySetAsSeries(SwingLowData,false);
   SetIndexBuffer(6,BullOBUpper,INDICATOR_DATA); ArraySetAsSeries(BullOBUpper,false);
   SetIndexBuffer(7,BullOBLower,INDICATOR_DATA); ArraySetAsSeries(BullOBLower,false);
   SetIndexBuffer(8,BearOBUpper,INDICATOR_DATA); ArraySetAsSeries(BearOBUpper,false);
   SetIndexBuffer(9,BearOBLower,INDICATOR_DATA); ArraySetAsSeries(BearOBLower,false);
   SetIndexBuffer(10,BullFVGUpper,INDICATOR_DATA); ArraySetAsSeries(BullFVGUpper,false);
   SetIndexBuffer(11,BullFVGLower,INDICATOR_DATA); ArraySetAsSeries(BullFVGLower,false);
   SetIndexBuffer(12,BearFVGUpper,INDICATOR_DATA); ArraySetAsSeries(BearFVGUpper,false);
   SetIndexBuffer(13,BearFVGLower,INDICATOR_DATA); ArraySetAsSeries(BearFVGLower,false);
   SetIndexBuffer(14,RegionEvent,INDICATOR_DATA); ArraySetAsSeries(RegionEvent,false);
   SetIndexBuffer(15,ATRData,INDICATOR_DATA); ArraySetAsSeries(ATRData,false);
   SetIndexBuffer(16,OBCount,INDICATOR_DATA); ArraySetAsSeries(OBCount,false);
   SetIndexBuffer(17,FVGCount,INDICATOR_DATA); ArraySetAsSeries(FVGCount,false);
   SetIndexBuffer(18,InternalHighData,INDICATOR_DATA); ArraySetAsSeries(InternalHighData,false);
   SetIndexBuffer(19,InternalLowData,INDICATOR_DATA); ArraySetAsSeries(InternalLowData,false);
   SetIndexBuffer(20,TrailingHighData,INDICATOR_DATA); ArraySetAsSeries(TrailingHighData,false);
   SetIndexBuffer(21,TrailingLowData,INDICATOR_DATA); ArraySetAsSeries(TrailingLowData,false);
   SetIndexBuffer(22,EquilibriumData,INDICATOR_DATA); ArraySetAsSeries(EquilibriumData,false);
   SetIndexBuffer(23,PremiumLowerData,INDICATOR_DATA); ArraySetAsSeries(PremiumLowerData,false);
   SetIndexBuffer(24,DiscountUpperData,INDICATOR_DATA); ArraySetAsSeries(DiscountUpperData,false);
   SetIndexBuffer(25,PriorDayHigh,INDICATOR_DATA); ArraySetAsSeries(PriorDayHigh,false);
   SetIndexBuffer(26,PriorDayLow,INDICATOR_DATA); ArraySetAsSeries(PriorDayLow,false);
   SetIndexBuffer(27,PriorWeekHigh,INDICATOR_DATA); ArraySetAsSeries(PriorWeekHigh,false);
   SetIndexBuffer(28,PriorWeekLow,INDICATOR_DATA); ArraySetAsSeries(PriorWeekLow,false);
   SetIndexBuffer(29,PriorMonthHigh,INDICATOR_DATA); ArraySetAsSeries(PriorMonthHigh,false);
   SetIndexBuffer(30,PriorMonthLow,INDICATOR_DATA); ArraySetAsSeries(PriorMonthLow,false);
   SetIndexBuffer(31,FVGSourceClosedTime,INDICATOR_DATA); ArraySetAsSeries(FVGSourceClosedTime,false);
   SetIndexBuffer(32,InternalOBCount,INDICATOR_DATA); ArraySetAsSeries(InternalOBCount,false);
   SetIndexBuffer(33,SwingOBCount,INDICATOR_DATA); ArraySetAsSeries(SwingOBCount,false);
   SetIndexBuffer(34,SourceAlertMask,INDICATOR_DATA); ArraySetAsSeries(SourceAlertMask,false);
   SetIndexBuffer(35,CandleOpen,INDICATOR_DATA); ArraySetAsSeries(CandleOpen,false);
   SetIndexBuffer(36,CandleHigh,INDICATOR_DATA); ArraySetAsSeries(CandleHigh,false);
   SetIndexBuffer(37,CandleLow,INDICATOR_DATA); ArraySetAsSeries(CandleLow,false);
   SetIndexBuffer(38,CandleClose,INDICATOR_DATA); ArraySetAsSeries(CandleClose,false);
   SetIndexBuffer(39,CandleColor,INDICATOR_COLOR_INDEX); ArraySetAsSeries(CandleColor,false);
   for(int i=0;i<36;i++) PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(35,PLOT_LINE_COLOR,0,BullColor()); PlotIndexSetInteger(35,PLOT_LINE_COLOR,1,BearColor());
   IndicatorSetString(INDICATOR_SHORTNAME,"SMC LuxAlgo Source (Closed Bars)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(InpDrawObjects && Prefix!="")
   {
      ObjectsDeleteAll(0,Prefix);
      if(ObjectsChart>=0 && ObjectsChart!=ChartID()) ObjectsDeleteAll(ObjectsChart,Prefix);
      ChartRedraw(0);
   }
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false); ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   if(rates_total<3) return 0;
   int last=rates_total-2;
   bool reset=(prev_calculated==0 || prev_calculated>rates_total || LastClosedIndex<0 || LastClosedIndex>last || time[LastClosedIndex]!=LastClosedTime);
   int start=(reset ? MathMax(1,rates_total-1-InpLookbackBars) : LastClosedIndex+1);
   if(start<=last)
   {
      if(!PrepareFrames(time,last)) return prev_calculated;
      int old=ArraySize(CalcATR),calc_start=(reset ? 0 : MathMax(0,old-1));
      ArrayResize(CalcATR,rates_total); ArrayResize(CumulativeTR,rates_total); ArrayResize(ParsedHigh,rates_total); ArrayResize(ParsedLow,rates_total);
      for(int i=calc_start;i<rates_total;i++)
      {
         double tr=(i==0 ? high[i]-low[i] : MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1]))));
         CumulativeTR[i]=(i==0 ? 0 : CumulativeTR[i-1]+tr); // ta.tr starts at first usable previous close.
         if(i<199) CalcATR[i]=EMPTY_VALUE;
         else if(i==199)
         {
            // ta.atr(200) uses RMA(ta.tr(true)); first TR is high-low.
            CalcATR[i]=(CumulativeTR[i]+high[0]-low[0])/200.0;
         }
         else CalcATR[i]=(CalcATR[i-1]*199.0+tr)/200.0;
         double vol=(InpOBFilter==SMC_ATR ? CalcATR[i] : (i>0 ? CumulativeTR[i]/i : EMPTY_VALUE));
         bool wide=Valid(vol) && high[i]-low[i]>=2.0*vol;
         ParsedHigh[i]=(wide ? low[i] : high[i]); ParsedLow[i]=(wide ? high[i] : low[i]);
      }
      PrepareFVG(rates_total,time,open,close);
   }
   if(reset)
   {
      if(InpDrawObjects) { ObjectsDeleteAll(0,Prefix); OwnChart(); }
      ArrayResize(Regions,0); ArrayResize(Marks,0); Serial=0;
      ZeroMemory(IH); ZeroMemory(IL); ZeroMemory(SH); ZeroMemory(SL); ZeroMemory(EH); ZeroMemory(EL);
      InternalLeg=SwingLeg=EqualLeg=0; InternalBias=SwingBias=0;
      TrailingTop=TrailingBottom=EMPTY_VALUE; TopKnown=BottomKnown=TrailingKnown=LastFVGKnown=0;
      ArrayInitialize(InternalBiasData,EMPTY_VALUE);
      ArrayInitialize(SwingBiasData,EMPTY_VALUE);
      ArrayInitialize(InternalEvent,EMPTY_VALUE);
      ArrayInitialize(SwingEvent,EMPTY_VALUE);
      ArrayInitialize(SwingHighData,EMPTY_VALUE);
      ArrayInitialize(SwingLowData,EMPTY_VALUE);
      ArrayInitialize(BullOBUpper,EMPTY_VALUE);
      ArrayInitialize(BullOBLower,EMPTY_VALUE);
      ArrayInitialize(BearOBUpper,EMPTY_VALUE);
      ArrayInitialize(BearOBLower,EMPTY_VALUE);
      ArrayInitialize(BullFVGUpper,EMPTY_VALUE);
      ArrayInitialize(BullFVGLower,EMPTY_VALUE);
      ArrayInitialize(BearFVGUpper,EMPTY_VALUE);
      ArrayInitialize(BearFVGLower,EMPTY_VALUE);
      ArrayInitialize(RegionEvent,EMPTY_VALUE);
      ArrayInitialize(ATRData,EMPTY_VALUE);
      ArrayInitialize(OBCount,EMPTY_VALUE);
      ArrayInitialize(FVGCount,EMPTY_VALUE);
      ArrayInitialize(InternalHighData,EMPTY_VALUE);
      ArrayInitialize(InternalLowData,EMPTY_VALUE);
      ArrayInitialize(TrailingHighData,EMPTY_VALUE);
      ArrayInitialize(TrailingLowData,EMPTY_VALUE);
      ArrayInitialize(EquilibriumData,EMPTY_VALUE);
      ArrayInitialize(PremiumLowerData,EMPTY_VALUE);
      ArrayInitialize(DiscountUpperData,EMPTY_VALUE);
      ArrayInitialize(PriorDayHigh,EMPTY_VALUE);
      ArrayInitialize(PriorDayLow,EMPTY_VALUE);
      ArrayInitialize(PriorWeekHigh,EMPTY_VALUE);
      ArrayInitialize(PriorWeekLow,EMPTY_VALUE);
      ArrayInitialize(PriorMonthHigh,EMPTY_VALUE);
      ArrayInitialize(PriorMonthLow,EMPTY_VALUE);
      ArrayInitialize(FVGSourceClosedTime,EMPTY_VALUE);
      ArrayInitialize(InternalOBCount,EMPTY_VALUE);
      ArrayInitialize(SwingOBCount,EMPTY_VALUE);
      ArrayInitialize(SourceAlertMask,EMPTY_VALUE);
      ArrayInitialize(CandleOpen,EMPTY_VALUE);
      ArrayInitialize(CandleHigh,EMPTY_VALUE);
      ArrayInitialize(CandleLow,EMPTY_VALUE);
      ArrayInitialize(CandleClose,EMPTY_VALUE);
      ArrayInitialize(CandleColor,EMPTY_VALUE);
   }
   for(int b=start;b<=last;b++)
   {
      int alerts=0,flags=0;
      CandleOpen[b]=CandleHigh[b]=CandleLow[b]=CandleClose[b]=EMPTY_VALUE; CandleColor[b]=0;
      if(InpColorCandles)
      {
         CandleOpen[b]=open[b]; CandleHigh[b]=high[b]; CandleLow[b]=low[b]; CandleClose[b]=close[b];
         CandleColor[b]=(InternalBias==1 ? 0 : 1); // Source colors before processing current break.
      }
      if(InpShowStrongWeak || InpShowPremiumDiscount)
      {
         if(Valid(TrailingTop) && high[b]>=TrailingTop) { TrailingTop=high[b]; TopKnown=time[b+1]; }
         if(Valid(TrailingBottom) && low[b]<=TrailingBottom) { TrailingBottom=low[b]; BottomKnown=time[b+1]; }
      }
      if(InpShowFVG) flags|=Mitigate(b,true,alerts,time,high,low,close);
      double prev_ih=(IH.valid ? IH.price : EMPTY_VALUE),prev_il=(IL.valid ? IL.price : EMPTY_VALUE);
      double prev_sh=(SH.valid ? SH.price : EMPTY_VALUE),prev_sl=(SL.valid ? SL.price : EMPTY_VALUE);
      flags|=Confirm(b,InpSwingLength,1,SwingLeg,SH,SL,alerts,time,high,low);
      flags|=Confirm(b,InpInternalLength,0,InternalLeg,IH,IL,alerts,time,high,low);
      if(InpShowEqual) flags|=Confirm(b,InpEqualLength,2,EqualLeg,EH,EL,alerts,time,high,low);
      int ie=0,se=0;
      if(InpShowInternal || InpShowInternalOB || InpColorCandles) ie=Breaks(b,false,IH,IL,prev_ih,prev_il,InternalBias,flags,alerts,time,open,high,low,close);
      if(InpShowSwing || InpShowSwingOB || InpShowStrongWeak) se=Breaks(b,true,SH,SL,prev_sh,prev_sl,SwingBias,flags,alerts,time,open,high,low,close);
      if(InpShowInternalOB || InpShowSwingOB) flags|=Mitigate(b,false,alerts,time,high,low,close);
      flags|=DetectFVG(b,alerts,time,open,high,low,close);
      WriteState(b,close[b],ie,se,flags,alerts,time[b+1]);
   }
   int current=last+1;
   InternalBiasData[current]=InternalBiasData[last];
   SwingBiasData[current]=SwingBiasData[last];
   InternalEvent[current]=0;
   SwingEvent[current]=0;
   SwingHighData[current]=SwingHighData[last];
   SwingLowData[current]=SwingLowData[last];
   BullOBUpper[current]=BullOBUpper[last];
   BullOBLower[current]=BullOBLower[last];
   BearOBUpper[current]=BearOBUpper[last];
   BearOBLower[current]=BearOBLower[last];
   BullFVGUpper[current]=BullFVGUpper[last];
   BullFVGLower[current]=BullFVGLower[last];
   BearFVGUpper[current]=BearFVGUpper[last];
   BearFVGLower[current]=BearFVGLower[last];
   RegionEvent[current]=0;
   ATRData[current]=ATRData[last];
   OBCount[current]=OBCount[last];
   FVGCount[current]=FVGCount[last];
   InternalHighData[current]=InternalHighData[last];
   InternalLowData[current]=InternalLowData[last];
   TrailingHighData[current]=TrailingHighData[last];
   TrailingLowData[current]=TrailingLowData[last];
   EquilibriumData[current]=EquilibriumData[last];
   PremiumLowerData[current]=PremiumLowerData[last];
   DiscountUpperData[current]=DiscountUpperData[last];
   PriorDayHigh[current]=PriorDayHigh[last];
   PriorDayLow[current]=PriorDayLow[last];
   PriorWeekHigh[current]=PriorWeekHigh[last];
   PriorWeekLow[current]=PriorWeekLow[last];
   PriorMonthHigh[current]=PriorMonthHigh[last];
   PriorMonthLow[current]=PriorMonthLow[last];
   FVGSourceClosedTime[current]=FVGSourceClosedTime[last];
   InternalOBCount[current]=InternalOBCount[last];
   SwingOBCount[current]=SwingOBCount[last];
   SourceAlertMask[current]=0;
   CandleOpen[current]=CandleHigh[current]=CandleLow[current]=CandleClose[current]=EMPTY_VALUE; CandleColor[current]=0;
   LastClosedIndex=last; LastClosedTime=time[last];
   if(start<=last) Draw(last,time[current]);
   return rates_total;
}
