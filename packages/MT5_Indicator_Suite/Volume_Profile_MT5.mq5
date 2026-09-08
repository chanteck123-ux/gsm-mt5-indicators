// Port of the supplied Pine Volume Profile by kv4coins.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. https://mozilla.org/MPL/2.0/  Original copyright: kv4coins.
// MQL5 adaptations: explicit tick/real volume, actual visible-bar range,
// safe empty ranges, pixel-anchored rendering, and latest-snapshot buffers.
// Source weighting is preserved: a candle's FULL volume is credited to
// EVERY sampled price level in [low, high). These are repeated activity
// weights, not a conserved trade-volume-at-price reconstruction.
#property copyright "Original Pine: kv4coins; MQL5 adaptation for user"
#property version "1.00"
#property description "Volume Profile - source-compatible repeated level weights."
#property description "Tick volume by default. Snapshot only; not historical signals."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots 7
#property indicator_label1 "Snapshot POC"
#property indicator_type1 DRAW_NONE
#property indicator_label2 "Snapshot VAH"
#property indicator_type2 DRAW_NONE
#property indicator_label3 "Snapshot VAL"
#property indicator_type3 DRAW_NONE
#property indicator_label4 "Sum of repeated level weights"
#property indicator_type4 DRAW_NONE
#property indicator_label5 "Selected input volume"
#property indicator_type5 DRAW_NONE
#property indicator_label6 "Actual VA percent"
#property indicator_type6 DRAW_NONE
#property indicator_label7 "Profile sample bars"
#property indicator_type7 DRAW_NONE

enum VP_FILTER { VP_BOTH=0,VP_BULLISH=1,VP_BEARISH=2 };
enum VP_VOLUME { VP_TICK_VOLUME=0,VP_REAL_VOLUME=1 };
input bool InpUseVisibleRange=false;       // 使用真正可见的图表K线范围
input int InpLookbackDepth=200;            // 固定回看根数 10..3000
input int InpRows=200;                     // 价格层数 10..490
input int InpBarThickness=1;               // 横条像素厚度 1..30
input int InpLengthMultiplier=20;          // 横条长度倍率 1..50
input int InpRightMarginPixels=70;         // 距图表右侧像素 0..400
input VP_FILTER InpVolumeFilter=VP_BOTH;   // 两种/阳线/阴线成交量
input VP_VOLUME InpVolumeSource=VP_TICK_VOLUME; // Tick量或真实成交量；不混用
input bool InpShowPOC=true;                // 显示POC线
input bool InpShowValueArea=true;          // 显示价值区域
input int InpValueAreaPercent=68;          // 价值区域目标 5..95%
input bool InpShowVALines=true;            // 显示VAH与VAL
input color InpBarColor=clrDimGray;
input color InpPOCColor=clrRed;
input color InpVAColor=clrDodgerBlue;
input int InpLevelLineWidth=1;             // POC/VA线宽 1..5
input bool InpDrawObjects=true;            // 绘图；iCustom数值测试可关闭

// Only the latest chart bar holds this snapshot. Earlier buffers are EMPTY.
// 0 POC, 1 VAH, 2 VAL, 3 total level weights, 4 input volume,
// 5 achieved VA percentage (the source can stop at a zero gap), 6 bar count.
double PocBuffer[],VahBuffer[],ValBuffer[],WeightBuffer[],InputBuffer[],VaPercentBuffer[],CountBuffer[];
double Weights[];
double LowestPrice=0,PriceStep=0,MaxWeight=0,TotalWeight=0,InputVolume=0;
double SnapshotPOC=EMPTY_VALUE,SnapshotVAH=EMPTY_VALUE,SnapshotVAL=EMPTY_VALUE;
double ActualVAPercent=0;
int POCIndex=0,VAFirst=0,VALast=0,SampleCount=0;
datetime RangeFirst=0,RangeLast=0;
string ObjectPrefix="";
bool ProfileReady=false;
bool VisibleDataPending=false;

void ClearSnapshot()
  {
   ArrayInitialize(PocBuffer,EMPTY_VALUE);ArrayInitialize(VahBuffer,EMPTY_VALUE);
   ArrayInitialize(ValBuffer,EMPTY_VALUE);ArrayInitialize(WeightBuffer,EMPTY_VALUE);
   ArrayInitialize(InputBuffer,EMPTY_VALUE);ArrayInitialize(VaPercentBuffer,EMPTY_VALUE);
   ArrayInitialize(CountBuffer,EMPTY_VALUE);
  }

void PublishSnapshot()
  {
   ClearSnapshot();
   int i=ArraySize(PocBuffer)-1;
   if(i<0) return;
   CountBuffer[i]=SampleCount;
   WeightBuffer[i]=TotalWeight;
   InputBuffer[i]=InputVolume;
   if(!ProfileReady) return;
   PocBuffer[i]=SnapshotPOC;VahBuffer[i]=SnapshotVAH;ValBuffer[i]=SnapshotVAL;
   VaPercentBuffer[i]=ActualVAPercent;
  }

void DeleteDrawings(const bool include_owner=true)
  {
   if(StringLen(ObjectPrefix)==0) return;
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
     {
      string name=ObjectName(0,i);
      if(StringFind(name,ObjectPrefix)==0 && (include_owner || name!=ObjectPrefix+"OWNER"))
         ObjectDelete(0,name);
     }
  }

bool CalculateProfile(const MqlRates &selected[])
  {
   SampleCount=ArraySize(selected);
   ProfileReady=false;TotalWeight=0;InputVolume=0;MaxWeight=0;
   SnapshotPOC=EMPTY_VALUE;SnapshotVAH=EMPTY_VALUE;SnapshotVAL=EMPTY_VALUE;
   if(SampleCount<2) return(false);
   RangeFirst=selected[0].time;RangeLast=selected[SampleCount-1].time;
   double highest=selected[0].high;
   LowestPrice=selected[0].low;
   for(int i=1;i<SampleCount;i++)
     {highest=MathMax(highest,selected[i].high);LowestPrice=MathMin(LowestPrice,selected[i].low);}
   PriceStep=(highest-LowestPrice)/(InpRows-1);
   ArrayResize(Weights,InpRows);ArrayInitialize(Weights,0.0);
   for(int i=0;i<SampleCount;i++)
     {
      bool bullish=selected[i].close>=selected[i].open;
      if(InpVolumeFilter==VP_BULLISH && !bullish) continue;
      if(InpVolumeFilter==VP_BEARISH && bullish) continue;
      double vol=(double)(InpVolumeSource==VP_TICK_VOLUME ? selected[i].tick_volume : selected[i].real_volume);
      if(vol>0) InputVolume+=vol;
     }
   if(PriceStep<=0.0) return(false);
   // A range-add difference array exactly implements the source's full-volume
   // level touches without a nested candles x rows accumulation loop.
   double differences[];ArrayResize(differences,InpRows+1);ArrayInitialize(differences,0.0);
   for(int i=0;i<SampleCount;i++)
     {
      bool bullish=selected[i].close>=selected[i].open;
      if(InpVolumeFilter==VP_BULLISH && !bullish) continue;
      if(InpVolumeFilter==VP_BEARISH && bullish) continue;
      double vol=(double)(InpVolumeSource==VP_TICK_VOLUME ? selected[i].tick_volume : selected[i].real_volume);
      if(vol<=0) continue;
      int first=(int)MathMax(0,MathMin(InpRows-1,MathCeil((selected[i].low-LowestPrice)/PriceStep)));
      int last=(int)MathMax(-1,MathMin(InpRows-1,MathCeil((selected[i].high-LowestPrice)/PriceStep)-1));
      // Resolve floating rounding at exact boundaries using source predicates.
      while(first>0 && LowestPrice+PriceStep*(first-1)>=selected[i].low) first--;
      while(first<InpRows && LowestPrice+PriceStep*first<selected[i].low) first++;
      while(last>=0 && LowestPrice+PriceStep*last>=selected[i].high) last--;
      while(last+1<InpRows && LowestPrice+PriceStep*(last+1)<selected[i].high) last++;
      if(first<=last && first<InpRows && last>=0)
        {differences[first]+=vol;differences[last+1]-=vol;}
     }
   double running=0;
   POCIndex=0;
   for(int row=0;row<InpRows;row++)
     {
      running+=differences[row];Weights[row]=MathMax(0.0,running);
      TotalWeight+=Weights[row];
      if(Weights[row]>MaxWeight) {MaxWeight=Weights[row];POCIndex=row;}
     }
   if(MaxWeight<=0 || TotalWeight<=0) return(false);
   VAFirst=POCIndex;VALast=POCIndex;
   double va_sum=MaxWeight,target=TotalWeight*InpValueAreaPercent/100.0;
   while(va_sum<target)
     {
      double up=(VALast<InpRows-1) ? Weights[VALast+1] : 0;
      double down=(VAFirst>0) ? Weights[VAFirst-1] : 0;
      if(up==0 && down==0) break;
      if(up>=down && VALast<InpRows-1) {VALast++;va_sum+=up;}
      else if(VAFirst>0) {VAFirst--;va_sum+=down;}
      else break;
     }
   SnapshotPOC=LowestPrice+PriceStep*POCIndex;
   SnapshotVAH=LowestPrice+PriceStep*VALast;
   SnapshotVAL=LowestPrice+PriceStep*VAFirst;
   ActualVAPercent=100.0*va_sum/TotalWeight;
   ProfileReady=true;
   return(true);
  }

void PixelBar(const string name,const int x,const int y,const int width,const int height,const color shade)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,shade);ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
  }

void DrawLevel(const string suffix,const double price,const color shade,const bool enabled)
  {
   string name=ObjectPrefix+suffix;
   if(!enabled || !ProfileReady) {ObjectDelete(0,name);return;}
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,RangeFirst,price,RangeLast,price);
   ObjectMove(0,name,0,RangeFirst,price);ObjectMove(0,name,1,RangeLast,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);ObjectSetInteger(0,name,OBJPROP_WIDTH,InpLevelLineWidth);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,suffix+" "+DoubleToString(price,_Digits));
  }

void DrawProfile()
  {
   if(!InpDrawObjects) return;
   if(!ProfileReady) DeleteDrawings(false);
   string label=ObjectPrefix+"STATUS";
   if(ObjectFind(0,label)<0) ObjectCreate(0,label,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,label,OBJPROP_XDISTANCE,InpRightMarginPixels+8);
   ObjectSetInteger(0,label,OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,label,OBJPROP_COLOR,clrSilver);ObjectSetInteger(0,label,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,label,OBJPROP_HIDDEN,true);
   string unit=(InpVolumeSource==VP_TICK_VOLUME) ? "Tick" : "Real";
   string status=ProfileReady ? StringFormat("VP %s | repeated weights | %d bars | VA %.1f%%",unit,SampleCount,ActualVAPercent)
                             : (VisibleDataPending ? "VP | waiting for visible history" : StringFormat("VP %s | no usable range/volume",unit));
   ObjectSetString(0,label,OBJPROP_TEXT,status);
   if(!ProfileReady) return;
   int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int visible=(int)MathMax(1,ChartGetInteger(0,CHART_VISIBLE_BARS,0));
   int right=(int)MathMax(30,width-InpRightMarginPixels-55);
   double pixels_per_bar=(double)width/visible;
   int maximum_width=(int)MathMax(20,MathMin(width*0.45,SampleCount*InpLengthMultiplier/100.0*pixels_per_bar));
   maximum_width=(int)MathMin(right,maximum_width);
   int first_visible=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
   int middle_shift=(int)MathMax(0,first_visible-visible/2);
   datetime anchor=iTime(_Symbol,_Period,middle_shift);
   for(int row=0;row<InpRows;row++)
     {
      string name=ObjectPrefix+"ROW_"+IntegerToString(row);
      int px=0,py=0;
      int len=(int)MathRound(maximum_width*Weights[row]/MaxWeight);
      double level=LowestPrice+PriceStep*row;
      if(len<1 || !ChartTimePriceToXY(0,0,anchor,level,px,py) || py<0 || py>=height)
        {ObjectDelete(0,name);continue;}
      color shade=(row==POCIndex) ? InpPOCColor : InpBarColor;
      if(InpShowValueArea && row>=VAFirst && row<=VALast && row!=POCIndex) shade=InpVAColor;
      PixelBar(name,(int)MathMax(0,right-len),(int)MathMax(0,py-InpBarThickness/2),len,InpBarThickness,shade);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,DoubleToString(level,_Digits)+" | weight "+DoubleToString(Weights[row],0));
     }
   DrawLevel("POC",SnapshotPOC,InpPOCColor,InpShowPOC);
   DrawLevel("VAH",SnapshotVAH,InpVAColor,InpShowValueArea && InpShowVALines);
   DrawLevel("VAL",SnapshotVAL,InpVAColor,InpShowValueArea && InpShowVALines);
  }

void SelectedRange(const int total,int &first,int &last)
  {
   last=total-1;first=(int)MathMax(0,total-InpLookbackDepth);
   if(InpUseVisibleRange)
     {
      int left=(int)ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0);
      int visible=(int)ChartGetInteger(0,CHART_VISIBLE_BARS,0);
      left=(int)MathMin(total-1,MathMax(0,left));
      int right=(int)MathMax(0,left-MathMax(1,visible)+1);
      first=total-1-left;last=total-1-right;
      first=(int)MathMax(first,last-2999);
     }
  }

int OnInit()
  {
   if(InpLookbackDepth<10 || InpLookbackDepth>3000 || InpRows<10 || InpRows>490 ||
      InpBarThickness<1 || InpBarThickness>30 || InpLengthMultiplier<1 || InpLengthMultiplier>50 ||
      InpRightMarginPixels<0 || InpRightMarginPixels>400 || InpValueAreaPercent<5 ||
      InpValueAreaPercent>95 || InpLevelLineWidth<1 || InpLevelLineWidth>5 ||
      InpVolumeFilter<VP_BOTH || InpVolumeFilter>VP_BEARISH ||
      InpVolumeSource<VP_TICK_VOLUME || InpVolumeSource>VP_REAL_VOLUME)
      return(INIT_PARAMETERS_INCORRECT);
   SetIndexBuffer(0,PocBuffer,INDICATOR_DATA);SetIndexBuffer(1,VahBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,ValBuffer,INDICATOR_DATA);SetIndexBuffer(3,WeightBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,InputBuffer,INDICATOR_DATA);SetIndexBuffer(5,VaPercentBuffer,INDICATOR_DATA);
   SetIndexBuffer(6,CountBuffer,INDICATOR_DATA);
   for(int plot=0;plot<7;plot++) PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Volume Profile (source weights)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   ObjectPrefix=StringFormat("VP_%I64d_%I64u_%I64u_",ChartID(),GetTickCount64(),GetMicrosecondCount());
   if(InpDrawObjects)
     {
      string base_prefix=ObjectPrefix;
      int instance=0;
      while(ObjectFind(0,ObjectPrefix+"OWNER")>=0)
         ObjectPrefix=base_prefix+IntegerToString(++instance)+"_";
      ObjectCreate(0,ObjectPrefix+"OWNER",OBJ_LABEL,0,0,0);
      ObjectSetString(0,ObjectPrefix+"OWNER",OBJPROP_TEXT,"");
      ObjectSetInteger(0,ObjectPrefix+"OWNER",OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,ObjectPrefix+"OWNER",OBJPROP_SELECTABLE,false);
     }
   if(InpUseVisibleRange) EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int total,const int prev,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],
                const long &ticks[],const long &volume[],const int &spread[])
  {
   if(total<2) return(0);
   ArraySetAsSeries(time,false);ArraySetAsSeries(open,false);ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);ArraySetAsSeries(close,false);ArraySetAsSeries(ticks,false);
   ArraySetAsSeries(volume,false);
   int first,last;SelectedRange(total,first,last);
   MqlRates selected[];ArrayResize(selected,last-first+1);
   for(int i=first;i<=last;i++)
     {
      int j=i-first;selected[j].time=time[i];selected[j].open=open[i];selected[j].high=high[i];
      selected[j].low=low[i];selected[j].close=close[i];selected[j].tick_volume=ticks[i];selected[j].real_volume=volume[i];
     }
   VisibleDataPending=false;CalculateProfile(selected);PublishSnapshot();DrawProfile();
   return(total);
  }

void RefreshVisibleHistory()
  {
   int total=Bars(_Symbol,_Period),first,last;
   if(total>=2)
     {
      SelectedRange(total,first,last);
      MqlRates selected[];
      if(CopyRates(_Symbol,_Period,total-1-last,last-first+1,selected)==last-first+1)
        {
         VisibleDataPending=false;CalculateProfile(selected);PublishSnapshot();DrawProfile();return;
        }
     }
   VisibleDataPending=true;ProfileReady=false;SampleCount=0;TotalWeight=0;InputVolume=0;
   PublishSnapshot();DrawProfile();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_CHART_CHANGE) return;
   if(InpUseVisibleRange) {RefreshVisibleHistory();return;}
   DrawProfile();
  }

void OnTimer() {if(InpUseVisibleRange && VisibleDataPending) RefreshVisibleHistory();}
void OnDeinit(const int reason) {EventKillTimer();DeleteDrawings();}
