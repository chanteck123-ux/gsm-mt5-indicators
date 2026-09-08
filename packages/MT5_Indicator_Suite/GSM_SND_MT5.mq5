// Original MQL5 implementation informed by the user-supplied TX/GSM
// Supply & Demand Handbook, pages 3-9. No handbook images are embedded.
// Numeric recognition thresholds and invalidation are engineering choices,
// not thresholds stated by the handbook. See snd_notes / Chinese guide.
// Closed-bar detections become available at the NEXT actual bar opening.
// No trading, pending orders, network calls, notifications, or account access.
#property copyright "MQL5 implementation for user; concept reference: TX/GSM S&D Handbook"
#property version "1.00"
#property description "Long Wick / Base Break / Impulsive origin zones; first visit only."
#property description "30 pt uses configurable price per pt; 0 means this symbol's MT5 point."
#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots 16
#property indicator_label1 "Fresh demand low"
#property indicator_type1 DRAW_NONE
#property indicator_label2 "Fresh demand high"
#property indicator_type2 DRAW_NONE
#property indicator_label3 "Fresh supply low"
#property indicator_type3 DRAW_NONE
#property indicator_label4 "Fresh supply high"
#property indicator_type4 DRAW_NONE
#property indicator_label5 "Demand reference"
#property indicator_type5 DRAW_NONE
#property indicator_label6 "Supply reference"
#property indicator_type6 DRAW_NONE
#property indicator_label7 "Demand formations"
#property indicator_type7 DRAW_NONE
#property indicator_label8 "Supply formations"
#property indicator_type8 DRAW_NONE
#property indicator_label9 "Demand first touches"
#property indicator_type9 DRAW_NONE
#property indicator_label10 "Supply first touches"
#property indicator_type10 DRAW_NONE
#property indicator_label11 "Demand later retouches"
#property indicator_type11 DRAW_NONE
#property indicator_label12 "Supply later retouches"
#property indicator_type12 DRAW_NONE
#property indicator_label13 "Demand invalidations"
#property indicator_type13 DRAW_NONE
#property indicator_label14 "Supply invalidations"
#property indicator_type14 DRAW_NONE
#property indicator_label15 "Demand first-visit reference touches"
#property indicator_type15 DRAW_NONE
#property indicator_label16 "Supply first-visit reference touches"
#property indicator_type16 DRAW_NONE

input bool InpEnableLongWick=true;
input bool InpEnableBaseBreak=true;
input bool InpEnableImpulsive=true;
input double InpPointSize=0.0;              // 每个教材pt的价格差；0=MT5 point，未确认等同教材单位
input double InpWideZonePoints=30.0;        // >此宽度用50%中位参考（教材30pt）
input int InpATRPeriod=14;                  // 工程识别波动基准
input double InpWickMinRangeFraction=0.60;  // 长影占K线振幅最小比例，工程默认
input double InpWickMinBodyRatio=2.0;       // 长影/实体最小比例，工程默认
input double InpWickMinATR=0.50;            // 长影最小ATR倍数，工程默认
input double InpWickZoneFraction=1.0;       // 从影线末端取多少比例画区；1=完整影线
input int InpBaseMinBars=2;                 // 基底最少K线，工程默认
input int InpBaseMaxBars=6;                 // 基底最多K线，工程默认
input double InpBaseMaxBarATR=0.80;         // 单根基底振幅上限
input double InpBaseMaxWidthATR=1.20;       // 整个基底宽度上限
input double InpBaseMaxBodyFraction=0.50;   // 基底实体/振幅上限
input double InpBreakMinBodyATR=0.80;       // 突破实体最小ATR
input double InpBreakBufferATR=0.05;        // 收盘突破基底的最小ATR距离
input int InpImpulseBars=3;                 // 同向推动根数，工程默认
input double InpImpulseMinMoveATR=2.0;      // 推动净位移最小ATR
input double InpImpulseMinBodyFraction=0.60;// 每根推动实体/振幅下限
input double InpDepartureATR=0.05;          // 离开近端才开始等首次回踩
input bool InpInvalidationByClose=true;     // 工程失效：收盘越远端；false=影线越远端
input double InpInvalidationBufferPoints=0.0;
input int InpMaxAgeBars=2000;               // 区域最大存活K线数，工程管理
input int InpMaxStoredZones=200;            // 状态存储上限；满时先淘汰旧失效区
input int InpMaxDrawnZones=40;              // 图形区域上限
input int InpInitialHistoryBars=10000;      // 初次识别的最近历史范围
input bool InpDrawObjects=true;            // false供iCustom纯数值使用
input bool InpShowUsed=true;
input bool InpShowInvalid=true;
input int InpExtendBars=20;
input int InpStatusY=42;
input color InpDemandColor=clrSeaGreen;
input color InpSupplyColor=clrIndianRed;
input color InpUsedColor=clrDimGray;

// Buffers 0..5: nearest fresh zone snapshot after the indexed candle CLOSE.
// Buffers 6..15: event COUNTS on closed candles (can be >1; never signed netting).
// All events are zero on the live candle. 14/15 only fire within the first
// contiguous visit, once per zone, at its boundary/midpoint reference.
double DLow[],DHigh[],SLow[],SHigh[],DRef[],SRef[];
double DNew[],SNew[],DFirst[],SFirst[],DRetouch[],SRetouch[],DInvalid[],SInvalid[],DReferenceHit[],SReferenceHit[];
double TrueRange[],ATR[];

struct SNDZone
  {
   long id;
   int direction;          // +1 demand, -1 supply
   int kinds;              // 1 wick, 2 base, 4 impulse
   int state;              // -1 waiting departure, 0 fresh, 1 used, 2 invalid, 3 expired
   int created_bar,touches;
   double low,high,reference,departure;
   datetime origin,available,ended;
   bool inside,first_visit,reference_seen;
  };
SNDZone Zones[];
long NextID=1;
int LastProcessed=-1,ScanStart=0;
int ImpulseRunDirection=0,ImpulseRunStart=-1;
bool ImpulseRunEmitted=false;
datetime FirstHistoryTime=0,LastProcessedTime=0;
double Unit=0;
string Prefix="";

bool Valid(const double x) {return(x!=EMPTY_VALUE && MathIsValidNumber(x));}
string UnitText()
  {
   if(Unit<1e-8) return(StringFormat("%.8g",Unit));
   string result=DoubleToString(Unit,8);
   while(StringLen(result)>1 && StringSubstr(result,StringLen(result)-1)=="0") result=StringSubstr(result,0,StringLen(result)-1);
   if(StringSubstr(result,StringLen(result)-1)==".")result=StringSubstr(result,0,StringLen(result)-1);
   return(result);
  }
double Body(const int i,const double &open[],const double &close[]) {return(MathAbs(close[i]-open[i]));}
string KindName(const int kinds)
  {
   string result="";
   if((kinds&1)!=0) result="Wick";
   if((kinds&2)!=0) result+=(result=="" ? "" : "+")+"Base";
   if((kinds&4)!=0) result+=(result=="" ? "" : "+")+"Impulse";
   return(result);
  }
void ClearBar(const int i)
  {
   DLow[i]=EMPTY_VALUE;DHigh[i]=EMPTY_VALUE;SLow[i]=EMPTY_VALUE;SHigh[i]=EMPTY_VALUE;
   DRef[i]=EMPTY_VALUE;SRef[i]=EMPTY_VALUE;
   DNew[i]=0;SNew[i]=0;DFirst[i]=0;SFirst[i]=0;DRetouch[i]=0;SRetouch[i]=0;
   DInvalid[i]=0;SInvalid[i]=0;DReferenceHit[i]=0;SReferenceHit[i]=0;
  }
string ZoneName(const long id) {return(Prefix+"Z"+IntegerToString(id));}
void DeleteZoneObjects(const long id)
  {
   if(!InpDrawObjects) return;
   string stem=ZoneName(id);
   ObjectDelete(0,stem);ObjectDelete(0,stem+"_T");ObjectDelete(0,stem+"_R");
  }
void DeleteOwned()
  {
   if(InpDrawObjects && Prefix!="") ObjectsDeleteAll(0,Prefix);
  }
void RemoveZone(const int index)
  {
   DeleteZoneObjects(Zones[index].id);
   int n=ArraySize(Zones);
   for(int i=index+1;i<n;i++) Zones[i-1]=Zones[i];
   ArrayResize(Zones,n-1);
  }
void Snapshot(const int bar,const double price)
  {
   double demand_distance=DBL_MAX,supply_distance=DBL_MAX;
   for(int z=0;z<ArraySize(Zones);z++)
     {
      if(Zones[z].state!=0) continue;
      if(Zones[z].direction>0)
        {
         double distance=MathAbs(price-Zones[z].high);
         if(distance<demand_distance)
           {demand_distance=distance;DLow[bar]=Zones[z].low;DHigh[bar]=Zones[z].high;DRef[bar]=Zones[z].reference;}
        }
      else
        {
         double distance=MathAbs(price-Zones[z].low);
         if(distance<supply_distance)
           {supply_distance=distance;SLow[bar]=Zones[z].low;SHigh[bar]=Zones[z].high;SRef[bar]=Zones[z].reference;}
        }
     }
  }
void AddZone(const int dir,const int kind,const double lo,const double hi,
             const int origin,const int bar,const datetime &time[],const double price,const double atr)
  {
   if(!Valid(lo) || !Valid(hi) || hi-lo<_Point*0.1) return;
   // Exact same-bar geometry is one zone with combined pattern evidence.
   // Existing zones never have their old geometry revised by later patterns.
   for(int z=ArraySize(Zones)-1;z>=0;z--)
      if(Zones[z].created_bar==bar && Zones[z].direction==dir &&
         MathAbs(Zones[z].low-lo)<_Point*0.01 && MathAbs(Zones[z].high-hi)<_Point*0.01)
        {Zones[z].kinds|=kind;return;}
   if(ArraySize(Zones)>=InpMaxStoredZones)
     {
      int discard=0;
      for(int z=0;z<ArraySize(Zones);z++) if(Zones[z].state>=2) {discard=z;break;}
      RemoveZone(discard);
     }
   int n=ArraySize(Zones);ArrayResize(Zones,n+1);
   Zones[n].id=NextID++;Zones[n].direction=dir;Zones[n].kinds=kind;
   Zones[n].low=lo;Zones[n].high=hi;
   Zones[n].reference=(hi-lo>InpWideZonePoints*Unit) ? (hi+lo)/2.0 : (dir>0 ? hi : lo);
   Zones[n].departure=InpDepartureATR*atr;
   bool departed=(dir>0) ? price>hi+Zones[n].departure : price<lo-Zones[n].departure;
   Zones[n].state=departed ? 0 : -1;
   Zones[n].created_bar=bar;Zones[n].touches=0;
   Zones[n].origin=time[origin];Zones[n].available=time[bar+1];Zones[n].ended=0;
   Zones[n].inside=false;Zones[n].first_visit=false;Zones[n].reference_seen=false;
   if(dir>0) DNew[bar]++;else SNew[bar]++;
  }
void UpdateZones(const int bar,const datetime &time[],const double &high[],const double &low[],const double &close[])
  {
   for(int z=0;z<ArraySize(Zones);z++)
     {
      if(Zones[z].state>=2) continue;
      int dir=Zones[z].direction;
      double buffer=InpInvalidationBufferPoints*Unit;
      bool invalid=(dir>0) ? (InpInvalidationByClose ? close[bar] : low[bar])<Zones[z].low-buffer
                           : (InpInvalidationByClose ? close[bar] : high[bar])>Zones[z].high+buffer;
      // Invalidation wins if the same OHLC candle could touch and break the
      // zone. The intrabar path is unknown; do not invent a valid first entry.
      if(invalid)
        {
         Zones[z].state=2;Zones[z].ended=time[bar+1];Zones[z].first_visit=false;
         if(dir>0) DInvalid[bar]++;else SInvalid[bar]++;
         continue;
        }
      if(bar-Zones[z].created_bar>InpMaxAgeBars)
        {Zones[z].state=3;Zones[z].ended=time[bar+1];Zones[z].first_visit=false;continue;}
      if(Zones[z].state==-1)
        {
         bool departed=(dir>0) ? close[bar]>Zones[z].high+Zones[z].departure
                               : close[bar]<Zones[z].low-Zones[z].departure;
         if(departed) Zones[z].state=0;
         continue; // A departure candle is never its own retest.
        }
      bool overlap=(high[bar]>=Zones[z].low && low[bar]<=Zones[z].high);
      if(overlap && !Zones[z].inside)
        {
         Zones[z].touches++;
         if(Zones[z].touches==1)
           {
            Zones[z].state=1;Zones[z].first_visit=true;
            if(dir>0) DFirst[bar]++;else SFirst[bar]++;
           }
         else
           {Zones[z].first_visit=false;if(dir>0) DRetouch[bar]++;else SRetouch[bar]++;}
        }
      if(!overlap) Zones[z].first_visit=false;
      if(overlap && Zones[z].first_visit && !Zones[z].reference_seen &&
         low[bar]<=Zones[z].reference && high[bar]>=Zones[z].reference)
        {
         Zones[z].reference_seen=true;
         if(dir>0) DReferenceHit[bar]++;else SReferenceHit[bar]++;
        }
      // A visit ends when a closed candle exits the zone. A later candle
      // returning after that close is a new visit, even if both candles' wicks
      // overlap. Intrabar exit/re-entry within one candle cannot be counted.
      Zones[z].inside=(close[bar]>=Zones[z].low && close[bar]<=Zones[z].high);
      if(!Zones[z].inside) Zones[z].first_visit=false;
     }
  }
void Detect(const int i,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(i<1 || !Valid(ATR[i-1]) || ATR[i-1]<=0) return;
   double atr=ATR[i-1],range=high[i]-low[i],body=Body(i,open,close);
   if(InpEnableLongWick && range>0)
     {
      double upper=high[i]-MathMax(open[i],close[i]);
      double lower=MathMin(open[i],close[i])-low[i];
      double required=InpWickMinBodyRatio*MathMax(body,_Point);
      if(upper>=range*InpWickMinRangeFraction && upper>=required && upper>=atr*InpWickMinATR)
         AddZone(-1,1,high[i]-upper*InpWickZoneFraction,high[i],i,i,time,close[i],atr);
      if(lower>=range*InpWickMinRangeFraction && lower>=required && lower>=atr*InpWickMinATR)
         AddZone(1,1,low[i],low[i]+lower*InpWickZoneFraction,i,i,time,close[i],atr);
     }
   if(InpEnableBaseBreak && i>=InpBaseMinBars && body>=atr*InpBreakMinBodyATR)
     {
      int count=0,origin=i;double blo=DBL_MAX,bhi=-DBL_MAX;
      for(int b=i-1;b>=0 && count<InpBaseMaxBars;b--)
        {
         double br=high[b]-low[b];
         if(br<=0 || br>atr*InpBaseMaxBarATR || Body(b,open,close)>br*InpBaseMaxBodyFraction) break;
         double nextlo=MathMin(blo,low[b]),nexthi=MathMax(bhi,high[b]);
         if(nexthi-nextlo>atr*InpBaseMaxWidthATR) break;
         blo=nextlo;bhi=nexthi;count++;origin=b;
        }
      if(count>=InpBaseMinBars)
        {
         if(close[i]>open[i] && close[i]>bhi+atr*InpBreakBufferATR) AddZone(1,2,blo,bhi,origin,i,time,close[i],atr);
         if(close[i]<open[i] && close[i]<blo-atr*InpBreakBufferATR) AddZone(-1,2,blo,bhi,origin,i,time,close[i],atr);
        }
     }
   if(InpEnableImpulsive)
     {
      int dir=(close[i]>open[i]) ? 1 : (close[i]<open[i] ? -1 : 0);
      bool strong=(dir!=0 && range>0 && body>=range*InpImpulseMinBodyFraction);
      if(!strong)
        {ImpulseRunDirection=0;ImpulseRunStart=-1;ImpulseRunEmitted=false;}
      else
        {
         if(dir!=ImpulseRunDirection || (dir>0 && close[i]<=close[i-1]) || (dir<0 && close[i]>=close[i-1]))
           {ImpulseRunDirection=dir;ImpulseRunStart=i;ImpulseRunEmitted=false;}
         int origin=ImpulseRunStart-1;
         if(!ImpulseRunEmitted && i-ImpulseRunStart+1>=InpImpulseBars && origin>=0 && Valid(ATR[origin]) &&
            dir*(close[i]-open[ImpulseRunStart])>=InpImpulseMinMoveATR*ATR[origin])
           {
            AddZone(dir,4,low[origin],high[origin],origin,i,time,close[i],ATR[origin]);
            ImpulseRunEmitted=true;
           }
        }
     }
  }

void DrawZone(const int z,const datetime right)
  {
   string name=ZoneName(Zones[z].id),label=name+"_T",ref=name+"_R";
   datetime finish=(Zones[z].ended>0) ? Zones[z].ended : right;
   color shade=(Zones[z].direction>0) ? InpDemandColor : InpSupplyColor;
   if(Zones[z].state!=0) shade=InpUsedColor;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,Zones[z].available,Zones[z].low,finish,Zones[z].high);
   ObjectMove(0,name,0,Zones[z].available,Zones[z].low);ObjectMove(0,name,1,finish,Zones[z].high);
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,Zones[z].state==0 ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   string state=(Zones[z].state==-1) ? "Wait departure" : (Zones[z].state==0 ? "Fresh" :
                 (Zones[z].state==2 ? "Invalid" : (Zones[z].state==3 ? "Expired" :
                 (Zones[z].touches==1 ? "First touch / used" : "Retouch / used"))));
   string text=(Zones[z].direction>0 ? "D " : "S ")+KindName(Zones[z].kinds)+" | "+state;
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text+" | origin "+TimeToString(Zones[z].origin)+
                   " | available "+TimeToString(Zones[z].available)+" | touches "+IntegerToString(Zones[z].touches));
   if(ObjectFind(0,label)<0) ObjectCreate(0,label,OBJ_TEXT,0,Zones[z].available,Zones[z].high);
   ObjectMove(0,label,0,Zones[z].available,Zones[z].high);
   ObjectSetString(0,label,OBJPROP_TEXT,text);ObjectSetInteger(0,label,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,label,OBJPROP_FONTSIZE,8);ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,label,OBJPROP_HIDDEN,true);
   if(Zones[z].state==0 || (Zones[z].state==1 && Zones[z].first_visit))
     {
      if(ObjectFind(0,ref)<0) ObjectCreate(0,ref,OBJ_TREND,0,Zones[z].available,Zones[z].reference,finish,Zones[z].reference);
      ObjectMove(0,ref,0,Zones[z].available,Zones[z].reference);ObjectMove(0,ref,1,finish,Zones[z].reference);
      ObjectSetInteger(0,ref,OBJPROP_COLOR,clrGoldenrod);ObjectSetInteger(0,ref,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,ref,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,ref,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,ref,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,ref,OBJPROP_HIDDEN,true);
      ObjectSetString(0,ref,OBJPROP_TOOLTIP,"First-visit reference (not an order): "+DoubleToString(Zones[z].reference,_Digits));
     }
   else ObjectDelete(0,ref);
  }
void DrawAll(const datetime latest)
  {
   if(!InpDrawObjects) return;
   int drawn=0,demand=0,supply=0;
   datetime right=latest+(datetime)(PeriodSeconds((ENUM_TIMEFRAMES)_Period)*InpExtendBars);
   for(int z=ArraySize(Zones)-1;z>=0;z--)
     {
      if(Zones[z].state==0) {if(Zones[z].direction>0)demand++;else supply++;}
      bool show=(drawn<InpMaxDrawnZones && (Zones[z].state!=1 || InpShowUsed) && (Zones[z].state<2 || InpShowInvalid));
      if(show) {DrawZone(z,right);drawn++;} else DeleteZoneObjects(Zones[z].id);
     }
   string status=Prefix+"STATUS";
   if(ObjectFind(0,status)<0) ObjectCreate(0,status,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,status,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,status,OBJPROP_XDISTANCE,10);ObjectSetInteger(0,status,OBJPROP_YDISTANCE,InpStatusY);
   ObjectSetInteger(0,status,OBJPROP_COLOR,clrSilver);ObjectSetInteger(0,status,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,status,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,status,OBJPROP_HIDDEN,true);
   ObjectSetString(0,status,OBJPROP_TEXT,StringFormat("GSM S&D | fresh D:%d S:%d | first visit only | 1 pt=%s%s",
                   demand,supply,UnitText(),InpPointSize==0 ? " (MT5 point; handbook unit unset)" : ""));
  }

int OnInit()
  {
   if(InpPointSize<0 || !MathIsValidNumber(InpPointSize) || InpWideZonePoints<=0 ||
      InpATRPeriod<2 || InpATRPeriod>1000 || InpWickMinRangeFraction<=0 || InpWickMinRangeFraction>1 ||
      InpWickMinBodyRatio<0 || InpWickMinATR<0 || InpWickZoneFraction<=0 || InpWickZoneFraction>1 ||
      InpBaseMinBars<1 || InpBaseMaxBars<InpBaseMinBars || InpBaseMaxBars>100 ||
      InpBaseMaxBarATR<=0 || InpBaseMaxWidthATR<=0 || InpBaseMaxBodyFraction<0 || InpBaseMaxBodyFraction>1 ||
      InpBreakMinBodyATR<0 || InpBreakBufferATR<0 || InpImpulseBars<1 || InpImpulseBars>100 ||
      InpImpulseMinMoveATR<=0 || InpImpulseMinBodyFraction<=0 || InpImpulseMinBodyFraction>1 ||
      InpDepartureATR<0 || InpInvalidationBufferPoints<0 || InpMaxAgeBars<1 || InpMaxAgeBars>100000 ||
      InpMaxStoredZones<1 || InpMaxStoredZones>1000 || InpMaxDrawnZones<1 || InpMaxDrawnZones>InpMaxStoredZones ||
      InpInitialHistoryBars<100 || InpInitialHistoryBars>1000000 || InpExtendBars<1 || InpExtendBars>500 || InpStatusY<0)
      return(INIT_PARAMETERS_INCORRECT);
   Unit=(InpPointSize>0) ? InpPointSize : SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(Unit<=0) return(INIT_FAILED);
   SetIndexBuffer(0,DLow,INDICATOR_DATA);SetIndexBuffer(1,DHigh,INDICATOR_DATA);
   SetIndexBuffer(2,SLow,INDICATOR_DATA);SetIndexBuffer(3,SHigh,INDICATOR_DATA);
   SetIndexBuffer(4,DRef,INDICATOR_DATA);SetIndexBuffer(5,SRef,INDICATOR_DATA);
   SetIndexBuffer(6,DNew,INDICATOR_DATA);SetIndexBuffer(7,SNew,INDICATOR_DATA);
   SetIndexBuffer(8,DFirst,INDICATOR_DATA);SetIndexBuffer(9,SFirst,INDICATOR_DATA);
   SetIndexBuffer(10,DRetouch,INDICATOR_DATA);SetIndexBuffer(11,SRetouch,INDICATOR_DATA);
   SetIndexBuffer(12,DInvalid,INDICATOR_DATA);SetIndexBuffer(13,SInvalid,INDICATOR_DATA);
   SetIndexBuffer(14,DReferenceHit,INDICATOR_DATA);SetIndexBuffer(15,SReferenceHit,INDICATOR_DATA);
   SetIndexBuffer(16,TrueRange,INDICATOR_CALCULATIONS);SetIndexBuffer(17,ATR,INDICATOR_CALCULATIONS);
   for(int p=0;p<16;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"GSM S&D (confirmed zones)");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   Prefix=StringFormat("GSD_%I64d_%I64u_%I64u_",ChartID(),GetTickCount64(),GetMicrosecondCount());
   if(InpDrawObjects)
     {
      string seed=Prefix;int suffix=0;
      while(ObjectFind(0,Prefix+"OWNER")>=0) Prefix=seed+IntegerToString(++suffix)+"_";
      if(!ObjectCreate(0,Prefix+"OWNER",OBJ_LABEL,0,0,0)) return(INIT_FAILED);
      ObjectSetString(0,Prefix+"OWNER",OBJPROP_TEXT,"");ObjectSetInteger(0,Prefix+"OWNER",OBJPROP_HIDDEN,true);
     }
   LastProcessed=-1;FirstHistoryTime=0;LastProcessedTime=0;NextID=1;ArrayResize(Zones,0);
   return(INIT_SUCCEEDED);
  }
int OnCalculate(const int total,const int prev,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(total<2) return(0);
   ArraySetAsSeries(time,false);ArraySetAsSeries(open,false);ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);ArraySetAsSeries(close,false);
   bool reset=(prev<=0 || prev>total || FirstHistoryTime!=time[0] || LastProcessed>=total-1 ||
               (LastProcessed>=0 && LastProcessedTime!=time[LastProcessed]));
   if(reset)
     {
      for(int z=0;z<ArraySize(Zones);z++) DeleteZoneObjects(Zones[z].id);
      ArrayResize(Zones,0);NextID=1;LastProcessed=-1;
      ImpulseRunDirection=0;ImpulseRunStart=-1;ImpulseRunEmitted=false;
      ScanStart=(int)MathMax(InpATRPeriod,total-1-InpInitialHistoryBars);
      for(int i=0;i<total;i++) {ClearBar(i);TrueRange[i]=EMPTY_VALUE;ATR[i]=EMPTY_VALUE;}
     }
   bool updated=false;
   for(int i=LastProcessed+1;i<total-1;i++)
     {
      ClearBar(i);
      TrueRange[i]=(i==0) ? high[i]-low[i] :
                    MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
      if(i<InpATRPeriod-1) ATR[i]=EMPTY_VALUE;
      else if(i==InpATRPeriod-1)
        {double sum=0;for(int j=0;j<=i;j++)sum+=TrueRange[j];ATR[i]=sum/InpATRPeriod;}
      else ATR[i]=(ATR[i-1]*(InpATRPeriod-1)+TrueRange[i])/InpATRPeriod;
      if(i>=ScanStart) {UpdateZones(i,time,high,low,close);Detect(i,time,open,high,low,close);Snapshot(i,close[i]);}
      LastProcessed=i;LastProcessedTime=time[i];updated=true;
     }
   ClearBar(total-1);Snapshot(total-1,close[total-2]);
   FirstHistoryTime=time[0];
   if(updated || reset) DrawAll(time[total-1]);
   return(total);
  }
void OnDeinit(const int reason) {DeleteOwned();}
