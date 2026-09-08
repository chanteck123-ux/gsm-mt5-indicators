// Rule interpretation of the user's GSM Support & Resistance Handbook, pp.3-9.
// This is an indicator, not an EA. Numeric thresholds below are engineering
// defaults: the handbook gives visual rules, not these numeric parameters.
// Confirmed bars only. Zone geometry freezes at its first candidate; a zone
// becomes visible only after a second separated, confirmed reaction.
#property strict
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 14
#property indicator_plots 14
#property indicator_label1 "Nearest support upper"
#property indicator_type1 DRAW_NONE
#property indicator_label2 "Nearest support lower"
#property indicator_type2 DRAW_NONE
#property indicator_label3 "Nearest resistance upper"
#property indicator_type3 DRAW_NONE
#property indicator_label4 "Nearest resistance lower"
#property indicator_type4 DRAW_NONE
#property indicator_label5 "Support confirmed reactions"
#property indicator_type5 DRAW_NONE
#property indicator_label6 "Resistance confirmed reactions"
#property indicator_type6 DRAW_NONE
#property indicator_label7 "Confirmed event mask"
#property indicator_type7 DRAW_NONE
#property indicator_label8 "Bull rejection condition (closed)"
#property indicator_type8 DRAW_ARROW
#property indicator_color8 clrLimeGreen
#property indicator_label9 "Bear rejection condition (closed)"
#property indicator_type9 DRAW_ARROW
#property indicator_color9 clrTomato
#property indicator_label10 "Wilder ATR"
#property indicator_type10 DRAW_NONE
#property indicator_label11 "Confirmed retained zones"
#property indicator_type11 DRAW_NONE
#property indicator_label12 "Support quality (1 good,0 choppy)"
#property indicator_type12 DRAW_NONE
#property indicator_label13 "Resistance quality (1 good,0 choppy)"
#property indicator_type13 DRAW_NONE
#property indicator_label14 "Arrival mask (1 support,2 resistance)"
#property indicator_type14 DRAW_NONE

input int InpPivotWing=3;              // 左右确认根数（量化默认）
input int InpATRPeriod=14;
input double InpZoneHalfWidthATR=0.15; // 区域半宽 / 首个触点 ATR
input double InpReactionATR=0.50;      // 明显反弹的最小收盘离区距离 / ATR
input int InpMinTouchSeparation=6;     // 两次初始触点最少间隔
input int InpMajorTouches=3;           // 主要区域的确认反应次数
input int InpBounceWaitBars=6;         // 回区后等待反弹的最多根数
input int InpChopLookback=20;          // 来回穿插评估窗口
input int InpBadCrossings=3;           // 两侧收盘来回穿越达到此次数为差区
input int InpMaxZoneAge=1500;          // 自初始候选起最多保留根数
input int InpLookbackBars=3000;
input int InpMaxZones=30;              // 含隐藏候选，限制图形和计算
input bool InpShowBadZones=false;     // 差区域默认隐藏（仍跟踪可恢复）
input bool InpShowMinorZones=true;
input bool InpFillZones=false;
input bool InpShowLabels=true;
input bool InpShowRejectionArrows=true;
input bool InpDrawObjects=true;       // iCustom纯数值使用可关闭
input color InpSupportColor=clrSeaGreen;
input color InpResistanceColor=clrCrimson;
input color InpBadColor=clrDimGray;
input int InpFalseReturnBars=3;        // 收盘突破后几根内关回原区视为假突破（0=仅同根影线）

double SU[],SL[],RU[],RL[],ST[],RT[],EV[],Bull[],Bear[],ATR[],Count[],SQ[],RQ[],Arrival[];
struct SRZone
  {
   int id,role,touches,created,last_pivot,activated,visit,flips,break_bar,break_from_role;
   double upper,lower,visit_atr;
   datetime known,role_since;
   bool active,armed,bad,stalled;
  };
SRZone Zones[];
string Prefix="";
int NextID=0,LastClosed=-1,LastTotal=0,ReplayStart=0;
datetime FirstTime=0,LastClosedTime=0,LastPaintTime=0;

bool Valid(const double v) {return v!=EMPTY_VALUE && MathIsValidNumber(v);}
void Empty(const int i)
  {
   SU[i]=SL[i]=RU[i]=RL[i]=ST[i]=RT[i]=SQ[i]=RQ[i]=EMPTY_VALUE;
   EV[i]=Count[i]=Arrival[i]=0;Bull[i]=Bear[i]=EMPTY_VALUE;
  }
void Drop(const int z)
  {
   for(int j=z+1;j<ArraySize(Zones);j++) Zones[j-1]=Zones[j];
   ArrayResize(Zones,ArraySize(Zones)-1);
  }
void Room()
  {
   if(ArraySize(Zones)<InpMaxZones) return;
   int target=0;
   for(int z=0;z<ArraySize(Zones);z++) if(!Zones[z].active) {target=z;break;}
   Drop(target);
  }
int Crossings(const SRZone &z,const int b,const double &close[])
  {
   int last=0,n=0;
   for(int i=MathMax(z.activated,b-InpChopLookback+1);i<=b;i++)
     {
      int side=close[i]>z.upper ? 1 : (close[i]<z.lower ? -1 : 0);
      if(side==0) continue;
      if(last!=0 && side!=last) n++;
      last=side;
     }
   return n;
  }
void Rejection(const int role,const int b,const double &high[],const double &low[])
  {
   if(!InpShowRejectionArrows) return;
   double offset=MathMax(10*_Point,ATR[b]*0.10);
   if(role>0) Bull[b]=low[b]-offset;else Bear[b]=high[b]+offset;
  }
void UpdateZones(const int b,const datetime &time[],const double &high[],const double &low[],const double &close[])
  {
   for(int z=ArraySize(Zones)-1;z>=0;z--)
     {
      if(b-Zones[z].created>InpMaxZoneAge) {Drop(z);continue;}
      if(!Zones[z].active)
        {
         if((Zones[z].role>0 && close[b]<Zones[z].lower) || (Zones[z].role<0 && close[b]>Zones[z].upper)) Drop(z);
         continue;
        }
      if(Zones[z].break_bar>=0 && b-Zones[z].break_bar>InpFalseReturnBars)
        {Zones[z].break_bar=-1;Zones[z].break_from_role=0;}
      bool recovered=false;
      if(Zones[z].break_bar>=0 && b>Zones[z].break_bar)
        {
         recovered=Zones[z].break_from_role>0 ? close[b]>=Zones[z].lower : close[b]<=Zones[z].upper;
         if(recovered)
           {
            // The handbook's quick close-back can span several candles and need
            // only reclaim the original distal boundary, not cross the full zone.
            Zones[z].role=Zones[z].break_from_role;Zones[z].role_since=time[b+1];Zones[z].flips++;
            Zones[z].visit=-1;Zones[z].armed=Zones[z].role>0 ? low[b]>Zones[z].upper : high[b]<Zones[z].lower;Zones[z].stalled=false;
            Zones[z].break_bar=-1;Zones[z].break_from_role=0;
           }
        }
      bool flip=!recovered && ((Zones[z].role>0 && close[b]<Zones[z].lower) || (Zones[z].role<0 && close[b]>Zones[z].upper));
      if(flip)
        {
         Zones[z].break_bar=b;Zones[z].break_from_role=Zones[z].role;
         Zones[z].role=-Zones[z].role;Zones[z].role_since=time[b+1];Zones[z].flips++;
         Zones[z].visit=-1;Zones[z].armed=true;Zones[z].stalled=false;
         EV[b]=(int)EV[b] | (Zones[z].role>0 ? 4 : 8);
        }
      Zones[z].bad=Zones[z].stalled || Crossings(Zones[z],b,close)>=InpBadCrossings;
      if(recovered)
        {
         EV[b]=(int)EV[b] | (Zones[z].role>0 ? 256 : 512);
         if(!Zones[z].bad) Rejection(Zones[z].role,b,high,low);
         // Historical close-break events stay intact. This close-back is not
         // also counted as a new visit or a second ordinary role-flip signal.
         continue;
        }
      if(flip) continue; // The breaking candle is not also a retest of its new role.
      const bool hit=high[b]>=Zones[z].lower && low[b]<=Zones[z].upper;
      if(Zones[z].armed && hit)
        {
         Zones[z].armed=false;Zones[z].visit=b;Zones[z].visit_atr=ATR[b-1];
         EV[b]=(int)EV[b] | (Zones[z].role>0 ? 16 : 32);
         if(!Zones[z].bad) Arrival[b]=(int)Arrival[b] | (Zones[z].role>0 ? 1 : 2);
        }
      bool fake=Zones[z].role>0 ? (low[b]<Zones[z].lower && close[b]>=Zones[z].lower && close[b-1]>=Zones[z].lower)
                                    : (high[b]>Zones[z].upper && close[b]<=Zones[z].upper && close[b-1]<=Zones[z].upper);
      if(fake)
        {
         EV[b]=(int)EV[b] | (Zones[z].role>0 ? 256 : 512);
         if(!Zones[z].bad) Rejection(Zones[z].role,b,high,low);
        }
      if(Zones[z].visit>=0)
        {
         const double distance=InpReactionATR*Zones[z].visit_atr;
         bool bounced=Zones[z].role>0 ? close[b]>=Zones[z].upper+distance : close[b]<=Zones[z].lower-distance;
         if(bounced && b-Zones[z].visit<=InpBounceWaitBars)
           {
            Zones[z].touches++;Zones[z].visit=-1;Zones[z].stalled=false;
            Zones[z].bad=Crossings(Zones[z],b,close)>=InpBadCrossings;
            EV[b]=(int)EV[b] | (Zones[z].role>0 ? 64 : 128);
            if(!Zones[z].bad) Rejection(Zones[z].role,b,high,low);
           }
         else if(b-Zones[z].visit>InpBounceWaitBars)
           {Zones[z].stalled=true;Zones[z].bad=true;Zones[z].visit=-1;}
        }
      // Leave the zone entirely before arming another visit. A continuous stay
      // inside a zone is one visit, never a sequence of artificial touches.
      if(!hit && Zones[z].visit<0)
        {
         bool away=Zones[z].role>0 ? low[b]>Zones[z].upper : high[b]<Zones[z].lower;
         if(away) Zones[z].armed=true;
        }
     }
  }
void PivotCandidate(const int role,const int p,const int b,const datetime &time[],const double &high[],const double &low[],const double &close[])
  {
   if(!Valid(ATR[p])) return;
   double price=role>0 ? low[p] : high[p];
   double half=MathMax(2*_Point,InpZoneHalfWidthATR*ATR[p]);
   double lower=price-half,upper=price+half;
   double best=close[p+1];
   for(int j=p+1;j<=b;j++) best=role>0 ? MathMax(best,close[j]) : MathMin(best,close[j]);
   if(role>0 ? best<upper+InpReactionATR*ATR[p] : best>lower-InpReactionATR*ATR[p]) return;
   if(role>0 ? close[b]<lower : close[b]>upper) return;
   int match=-1;double d=DBL_MAX;
   for(int z=0;z<ArraySize(Zones);z++)
     {
      if(Zones[z].role!=role || price<Zones[z].lower || price>Zones[z].upper) continue;
      if(Zones[z].active) return; // Already counted by the chronological visit state.
      double delta=MathAbs(price-0.5*(Zones[z].upper+Zones[z].lower));
      if(delta<d) {d=delta;match=z;}
     }
   if(match>=0)
     {
      if(p-Zones[match].last_pivot<InpMinTouchSeparation) return;
      Zones[match].last_pivot=p;Zones[match].touches++;
      Zones[match].active=true;Zones[match].activated=b;Zones[match].known=time[b+1];Zones[match].role_since=time[b+1];
      Zones[match].armed=role>0 ? low[b]>Zones[match].upper : high[b]<Zones[match].lower;
      EV[b]=(int)EV[b] | (role>0 ? 1 : 2);
      return;
     }
   Room();int n=ArraySize(Zones);ArrayResize(Zones,n+1);
   ZeroMemory(Zones[n]);Zones[n].id=++NextID;Zones[n].role=role;Zones[n].touches=1;
   Zones[n].created=b;Zones[n].last_pivot=p;Zones[n].activated=b;
   Zones[n].upper=upper;Zones[n].lower=lower;Zones[n].visit=-1;Zones[n].break_bar=-1;
  }
void Snapshot(const int b,const double price)
  {
   int si=-1,ri=-1;double sd=DBL_MAX,rd=DBL_MAX;int count=0;
   for(int z=0;z<ArraySize(Zones);z++)
     {
      if(!Zones[z].active) continue;count++;
      if((Zones[z].bad && !InpShowBadZones) || (Zones[z].touches<InpMajorTouches && !InpShowMinorZones)) continue;
      if(Zones[z].role>0 && Zones[z].lower<=price)
        {double d=MathMax(0,price-Zones[z].upper);if(d<=sd) {sd=d;si=z;}}
      if(Zones[z].role<0 && Zones[z].upper>=price)
        {double d=MathMax(0,Zones[z].lower-price);if(d<=rd) {rd=d;ri=z;}}
     }
   Count[b]=count;
   if(si>=0) {SU[b]=Zones[si].upper;SL[b]=Zones[si].lower;ST[b]=Zones[si].touches;SQ[b]=Zones[si].bad?0:1;}
   if(ri>=0) {RU[b]=Zones[ri].upper;RL[b]=Zones[ri].lower;RT[b]=Zones[ri].touches;RQ[b]=Zones[ri].bad?0:1;}
  }
void Paint(const datetime end)
  {
   if(!InpDrawObjects) return;
   // Only this instance's drawings are rebuilt; the owner marker is retained.
   for(int j=ObjectsTotal(0)-1;j>=0;j--)
     {string name=ObjectName(0,j);if(StringFind(name,Prefix)==0 && name!=Prefix+"OWNER") ObjectDelete(0,name);}
   for(int z=0;z<ArraySize(Zones);z++)
     {
      if(!Zones[z].active || (Zones[z].bad && !InpShowBadZones) || (Zones[z].touches<InpMajorTouches && !InpShowMinorZones)) continue;
      string name=Prefix+IntegerToString(Zones[z].id);
      color shade=Zones[z].bad ? InpBadColor : (Zones[z].role>0 ? InpSupportColor : InpResistanceColor);
      ObjectCreate(0,name,OBJ_RECTANGLE,0,Zones[z].role_since,Zones[z].upper,end,Zones[z].lower);
      ObjectSetInteger(0,name,OBJPROP_COLOR,shade);ObjectSetInteger(0,name,OBJPROP_FILL,InpFillZones);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,Zones[z].touches>=InpMajorTouches ? 2:1);
      ObjectSetInteger(0,name,OBJPROP_STYLE,Zones[z].bad ? STYLE_DOT:STYLE_SOLID);
      string label=StringFormat("%s %s | reactions %d%s%s",Zones[z].touches>=InpMajorTouches?"MAJOR":"MINOR",Zones[z].role>0?"SUPPORT":"RESISTANCE",Zones[z].touches,Zones[z].flips>0?" | FLIP":"",Zones[z].bad?" | CHOP":"");
      ObjectSetString(0,name,OBJPROP_TOOLTIP,label+" | confirmed zone; not a trade");
      if(InpShowLabels)
        {
         ObjectCreate(0,name+"T",OBJ_TEXT,0,end,Zones[z].role>0?Zones[z].upper:Zones[z].lower);
         ObjectSetString(0,name+"T",OBJPROP_TEXT,label);ObjectSetInteger(0,name+"T",OBJPROP_COLOR,shade);
         ObjectSetInteger(0,name+"T",OBJPROP_FONTSIZE,8);ObjectSetInteger(0,name+"T",OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
         ObjectSetInteger(0,name+"T",OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name+"T",OBJPROP_HIDDEN,true);
        }
     }
   ChartRedraw(0);
  }
int OnInit()
  {
   if(InpPivotWing<1 || InpPivotWing>100 || InpATRPeriod<1 || InpATRPeriod>500 ||
      !MathIsValidNumber(InpZoneHalfWidthATR) || InpZoneHalfWidthATR<=0 || InpZoneHalfWidthATR>5 ||
      !MathIsValidNumber(InpReactionATR) || InpReactionATR<=0 || InpReactionATR>20 ||
      InpMinTouchSeparation<1 || InpMinTouchSeparation>1000 || InpMajorTouches<2 || InpMajorTouches>100 ||
      InpBounceWaitBars<1 || InpBounceWaitBars>100 || InpChopLookback<2 || InpChopLookback>500 ||
      InpBadCrossings<1 || InpBadCrossings>100 || InpMaxZoneAge<20 || InpMaxZoneAge>100000 ||
      InpLookbackBars<100 || InpLookbackBars>100000 || InpMaxZones<2 || InpMaxZones>100 ||
      InpFalseReturnBars<0 || InpFalseReturnBars>100) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,SU,INDICATOR_DATA);SetIndexBuffer(1,SL,INDICATOR_DATA);SetIndexBuffer(2,RU,INDICATOR_DATA);SetIndexBuffer(3,RL,INDICATOR_DATA);
   SetIndexBuffer(4,ST,INDICATOR_DATA);SetIndexBuffer(5,RT,INDICATOR_DATA);SetIndexBuffer(6,EV,INDICATOR_DATA);
   SetIndexBuffer(7,Bull,INDICATOR_DATA);SetIndexBuffer(8,Bear,INDICATOR_DATA);SetIndexBuffer(9,ATR,INDICATOR_DATA);
   SetIndexBuffer(10,Count,INDICATOR_DATA);SetIndexBuffer(11,SQ,INDICATOR_DATA);SetIndexBuffer(12,RQ,INDICATOR_DATA);SetIndexBuffer(13,Arrival,INDICATOR_DATA);
   for(int p=0;p<14;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(7,PLOT_ARROW,233);PlotIndexSetInteger(8,PLOT_ARROW,234);
   IndicatorSetString(INDICATOR_SHORTNAME,"GSM SNR (confirmed zones)");IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   Prefix=StringFormat("GSNR_%I64d_%I64u_%I64u_",ChartID(),GetTickCount64(),GetMicrosecondCount());
   if(InpDrawObjects)
     {
      while(ObjectFind(0,Prefix+"OWNER")>=0) Prefix+="x";
      ObjectCreate(0,Prefix+"OWNER",OBJ_LABEL,0,0,0);ObjectSetString(0,Prefix+"OWNER",OBJPROP_TEXT,"");
      ObjectSetInteger(0,Prefix+"OWNER",OBJPROP_HIDDEN,true);
     }
   return INIT_SUCCEEDED;
  }
int OnCalculate(const int n,const int prev,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &ticks[],const long &volume[],const int &spread[])
  {
   if(n<InpATRPeriod+InpPivotWing*2+3) return 0;
   ArraySetAsSeries(time,false);ArraySetAsSeries(high,false);ArraySetAsSeries(low,false);ArraySetAsSeries(close,false);
   bool reset=prev==0 || n<LastTotal || time[0]!=FirstTime || LastClosed<0 || LastClosed>=n || time[LastClosed]!=LastClosedTime;
   if(reset)
     {
      ArrayResize(Zones,0);NextID=0;LastClosed=-1;FirstTime=time[0];ReplayStart=MathMax(InpATRPeriod+InpPivotWing,n-1-InpLookbackBars);
      for(int i=0;i<n;i++) {Empty(i);ATR[i]=EMPTY_VALUE;EV[i]=Count[i]=Arrival[i]=EMPTY_VALUE;}
     }
   int atr_start=reset ? InpATRPeriod:MathMax(InpATRPeriod,LastTotal-1);
   for(int i=atr_start;i<n;i++)
     {
      double tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
      if(i==InpATRPeriod)
        {
         double sum=0;for(int j=1;j<=i;j++) sum+=MathMax(high[j]-low[j],MathMax(MathAbs(high[j]-close[j-1]),MathAbs(low[j]-close[j-1])));
         ATR[i]=sum/InpATRPeriod;
        }
      else ATR[i]=(ATR[i-1]*(InpATRPeriod-1)+tr)/InpATRPeriod;
     }
   int start=reset?ReplayStart:LastClosed+1;
   for(int b=start;b<n-1;b++)
     {
      Empty(b);UpdateZones(b,time,high,low,close);
      int p=b-InpPivotWing;
      if(p>=MathMax(InpPivotWing,ReplayStart))
        {
         bool ph=true,pl=true;
         for(int j=p-InpPivotWing;j<=b;j++) if(j!=p) {if(high[j]>=high[p]) ph=false;if(low[j]<=low[p]) pl=false;}
         if(ph) PivotCandidate(-1,p,b,time,high,low,close);
         if(pl) PivotCandidate(1,p,b,time,high,low,close);
        }
      Snapshot(b,close[b]);LastClosed=b;LastClosedTime=time[b];
     }
   Empty(n-1);
   if(LastClosed>=0)
     {
      SU[n-1]=SU[n-2];SL[n-1]=SL[n-2];RU[n-1]=RU[n-2];RL[n-1]=RL[n-2];ST[n-1]=ST[n-2];RT[n-1]=RT[n-2];
      SQ[n-1]=SQ[n-2];RQ[n-1]=RQ[n-2];Count[n-1]=Count[n-2];ATR[n-1]=ATR[n-2];
     }
   LastTotal=n;
   if(reset || LastPaintTime!=time[n-1]) {Paint(time[n-1]);LastPaintTime=time[n-1];}
   return n;
  }
void OnDeinit(const int reason) {if(InpDrawObjects && StringLen(Prefix)>0) ObjectsDeleteAll(0,Prefix);}
