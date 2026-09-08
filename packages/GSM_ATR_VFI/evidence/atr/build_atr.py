from pathlib import Path
root=Path(r'C:\Users\A\Documents\Codex\2026-09-08\created-by-user-chrismoody-updated-4')
target=root/'outputs/GSM_ATR_VFI/MQL5/Indicators/GSM/Saty_ATR_Levels_MT5.mq5'
target.parent.mkdir(parents=True,exist_ok=True)
code=r'''// Saty ATR Levels - MetaTrader 5 source adaptation.
// Original: Copyright (C) 2022 Saty Mahajan. Special thanks to Gabriel Viana.
// Original supplied Pine v5 source retained in the delivery reference files.
// Independent chart indicator, no orders or account APIs. Not a trading system.
#property strict
#property version "1.00"
#property copyright "Original concept/source (C) 2022 Saty Mahajan; MT5 adaptation 2026"
#property indicator_chart_window
#property indicator_buffers 43
#property indicator_plots 41

enum SATYTradingMode { DAY=0, MULTIDAY=1, SWING=2, POSITION=3, LONG_TERM=4 };
input group "一、周期与计算"
input SATYTradingMode TradingType=DAY; // Day日、Multiday周、Swing月、Position季度、Long-term年
input bool UseOptionsLabels=true;     // Calls/Puts 标签；关闭后为 Long/Short（均非下单指令）
input int ATRLength=14;               // Wilder RMA 的周期数
input double TriggerPercentage=0.236; // 上下触发参考距离／ATR
input bool UseCurrentClose=false;    // 当前发展中的收盘价与ATR；未收盘可变化
input int FastEMA=8;                 // 图表周期快 EMA
input int PivotEMA=21;               // 图表周期中 EMA
input int SlowEMA=34;                // 图表周期慢 EMA
input group "二、绘图与面板"
input bool ShowAllFibonacciLevels=true; // 显示中间斐波那契线；不影响缓冲区
input bool ShowExtensions=false;        // 显示 1ATR 以外扩展；不影响缓冲区
input int LevelSize=2;                  // 线宽 1～5
input bool ShowInfo=true;               // 中文状态面板
input color PreviousCloseColor=clrWhite;
input color LowerTriggerColor=clrYellow;
input color UpperTriggerColor=clrAqua;
input color KeyTargetColor=clrSilver;
input color ATRTargetColor=clrWhite;
input color IntermediateTargetColor=clrGray;
input ENUM_BASE_CORNER PanelCorner=CORNER_RIGHT_UPPER;
input int PanelX=16;
input int PanelY=22;
input int PanelFontSize=10;

struct OutputBuffer {double v[];};
OutputBuffer Data[41];
double RunHigh[],RunLow[];
struct SourcePeriod
  {
   datetime time;
   double open,high,low,close,tr,rma,seed_sum;
   int months,seed_count,last_month;
   bool complete,close_known;
  };
SourcePeriod Source[];
MqlRates PreviousRaw[];
string Prefix="",ShortName="",Unavailable="数据准备中";
datetime LastChartTime=0;
bool SourceReady=false,LastDataReady=false;
ulong LastErrorLog=0;
const double Ratios[15]={0.236,0.382,0.5,0.618,0.786,1.0,1.236,1.382,1.5,1.618,1.786,2.0,2.236,2.618,3.0};

bool Valid(const double value){return value!=EMPTY_VALUE && MathIsValidNumber(value);}
void LogError(const string text)
  {ulong now=GetTickCount64();if(LastErrorLog==0||now-LastErrorLog>=5000){Print("Saty ATR：",text);LastErrorLog=now;}}
string ModeText()
  {if(TradingType==DAY)return "Day / D1";if(TradingType==MULTIDAY)return "Multiday / W1";if(TradingType==SWING)return "Swing / MN1";if(TradingType==POSITION)return "Position / 日历季度";return "Long-term / 日历年";}
ENUM_TIMEFRAMES BaseTF()
  {if(TradingType==DAY)return PERIOD_D1;if(TradingType==MULTIDAY)return PERIOD_W1;return PERIOD_MN1;}
int MonthNumber(const datetime t)
  {MqlDateTime d;TimeToStruct(t,d);return d.year*12+d.mon-1;}
datetime CalendarStart(const datetime t)
  {
   MqlDateTime d;TimeToStruct(t,d);d.day=1;d.hour=0;d.min=0;d.sec=0;
   if(TradingType==POSITION)d.mon=((d.mon-1)/3)*3+1;
   else if(TradingType==LONG_TERM)d.mon=1;
   return StructToTime(d);
  }
datetime PeriodEnd(const datetime start)
  {
   if(TradingType==DAY)return start+86400;
   if(TradingType==MULTIDAY)return start+7*86400;
   MqlDateTime d;TimeToStruct(start,d);int add=TradingType==SWING?1:TradingType==POSITION?3:12;
   int m=d.year*12+d.mon-1+add;d.year=m/12;d.mon=m%12+1;d.day=1;d.hour=0;d.min=0;d.sec=0;return StructToTime(d);
  }
bool PriorAdjacent(const int p)
  {return p>0 && (TradingType<POSITION || PeriodEnd(Source[p-1].time)==Source[p].time);}

bool LoadSource(bool &history_changed)
  {
   const ENUM_TIMEFRAMES tf=BaseTF();int count=Bars(_Symbol,tf);history_changed=false;
   if(count<1)
     {MqlRates probe[];CopyRates(_Symbol,tf,0,MathMin(5000,(ATRLength+2)*(TradingType==POSITION?3:TradingType==LONG_TERM?12:1)),probe);Unavailable="源周期历史尚未准备好";return false;}
   MqlRates raw[];ArraySetAsSeries(raw,false);
   int copied=CopyRates(_Symbol,tf,0,count,raw);
   if(copied!=count){Unavailable=StringFormat("源周期历史未完整复制（%d/%d）",copied,count);return false;}
   int old_count=ArraySize(PreviousRaw);
   if(count!=old_count)history_changed=true;
   else for(int i=0;i<count-1;i++)
      if(raw[i].time!=PreviousRaw[i].time || raw[i].open!=PreviousRaw[i].open || raw[i].high!=PreviousRaw[i].high ||
         raw[i].low!=PreviousRaw[i].low || raw[i].close!=PreviousRaw[i].close){history_changed=true;break;}
   ArrayCopy(PreviousRaw,raw);
   ArrayResize(Source,count);int source_count=0;
   const bool calendar=(TradingType==POSITION || TradingType==LONG_TERM);
   const int needed=(TradingType==POSITION?3:12);
   datetime first_m1=(datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
   bool first_raw_complete=true;
   if(first_m1>raw[0].time)
     {
      datetime raw_end=0;
      if(tf==PERIOD_D1)raw_end=raw[0].time+86400;
      else if(tf==PERIOD_W1)raw_end=raw[0].time+7*86400;
      else{MqlDateTime d;TimeToStruct(raw[0].time,d);d.day=1;d.hour=0;d.min=0;d.sec=0;if(++d.mon>12){d.mon=1;d.year++;}raw_end=StructToTime(d);}
      if(first_m1<raw_end)first_raw_complete=false;
     }
   for(int i=0;i<count;i++)
     {
      if(!MathIsValidNumber(raw[i].open)||!MathIsValidNumber(raw[i].high)||!MathIsValidNumber(raw[i].low)||
         !MathIsValidNumber(raw[i].close)||raw[i].high<raw[i].low){Unavailable="源周期 OHLC 无效";return false;}
      datetime key=calendar?CalendarStart(raw[i].time):raw[i].time;
      int n=source_count,month=MonthNumber(raw[i].time);
      if(n==0 || Source[n-1].time!=key)
        {
         source_count++;ZeroMemory(Source[n]);Source[n].time=key;
         Source[n].open=raw[i].open;Source[n].high=raw[i].high;Source[n].low=raw[i].low;Source[n].close=raw[i].close;
         Source[n].months=1;Source[n].last_month=month;
         Source[n].complete=(!calendar || month==MonthNumber(key)) && (i!=0 || first_raw_complete);
        }
      else
        {
         int k=n-1;Source[k].high=MathMax(Source[k].high,raw[i].high);Source[k].low=MathMin(Source[k].low,raw[i].low);Source[k].close=raw[i].close;
         if(month!=Source[k].last_month+1)Source[k].complete=false;
         Source[k].months++;Source[k].last_month=month;
        }
     }
   ArrayResize(Source,source_count);
   for(int p=0;p<ArraySize(Source);p++)
     {
      if(calendar && Source[p].months!=needed)Source[p].complete=false;
      Source[p].close_known=!calendar || Source[p].last_month==MonthNumber(Source[p].time)+needed-1;
      Source[p].tr=Source[p].high-Source[p].low;
      if(PriorAdjacent(p)&&Source[p-1].complete&&Source[p-1].close_known)Source[p].tr=MathMax(Source[p].tr,MathMax(MathAbs(Source[p].high-Source[p-1].close),MathAbs(Source[p].low-Source[p-1].close)));
      Source[p].rma=EMPTY_VALUE;Source[p].seed_sum=0;Source[p].seed_count=0;
      if(!Source[p].complete)continue;
      bool contiguous=true;
      if(calendar && p>0)contiguous=MonthNumber(Source[p].time)-MonthNumber(Source[p-1].time)==needed;
      if(p>0 && contiguous && Valid(Source[p-1].rma))
        {Source[p].rma=(Source[p-1].rma*(ATRLength-1)+Source[p].tr)/ATRLength;Source[p].seed_count=ATRLength;}
      else
        {
         if(p>0&&contiguous){Source[p].seed_sum=Source[p-1].seed_sum;Source[p].seed_count=Source[p-1].seed_count;}
         Source[p].seed_sum+=Source[p].tr;Source[p].seed_count++;
         if(Source[p].seed_count==ATRLength)Source[p].rma=Source[p].seed_sum/ATRLength;
        }
     }
   return ArraySize(Source)>0;
  }

int MapSource(const datetime when)
  {
   int lo=0,hi=ArraySize(Source)-1,found=-1;
   while(lo<=hi){int mid=(lo+hi)/2;if(Source[mid].time<=when){found=mid;lo=mid+1;}else hi=mid-1;}
   if(found<0)return -1;
   // Do not carry the last cached source period across a missing next period.
   if(when>=PeriodEnd(Source[found].time))return -1;
   return found;
  }
void EmptyAt(const int i){for(int b=0;b<41;b++)Data[b].v[i]=EMPTY_VALUE;RunHigh[i]=EMPTY_VALUE;RunLow[i]=EMPTY_VALUE;}
double DevelopingATR(const int p,const double high,const double low)
  {
   double tr=high-low;if(PriorAdjacent(p)&&Source[p-1].complete&&Source[p-1].close_known)tr=MathMax(tr,MathMax(MathAbs(high-Source[p-1].close),MathAbs(low-Source[p-1].close)));
   if(PriorAdjacent(p) && Valid(Source[p-1].rma))return (Source[p-1].rma*(ATRLength-1)+tr)/ATRLength;
   int previous=(PriorAdjacent(p)?Source[p-1].seed_count:0);double sum=(PriorAdjacent(p)?Source[p-1].seed_sum:0);
   return previous+1==ATRLength?(sum+tr)/ATRLength:EMPTY_VALUE;
  }

void BuildBar(const int i,const datetime &time[],const double &high[],const double &low[],const double &close[])
  {
   EmptyAt(i);
   if(!MathIsValidNumber(close[i])||!MathIsValidNumber(high[i])||!MathIsValidNumber(low[i])||high[i]<low[i])return;
   int lengths[3];lengths[0]=FastEMA;lengths[1]=PivotEMA;lengths[2]=SlowEMA;
   for(int e=0;e<3;e++)
     {double alpha=2.0/(lengths[e]+1.0);Data[5+e].v[i]=(i>0&&Valid(Data[5+e].v[i-1]))?Data[5+e].v[i-1]+alpha*(close[i]-Data[5+e].v[i-1]):close[i];}
   bool bull=close[i]>=Data[5].v[i]&&Data[5].v[i]>=Data[6].v[i]&&Data[6].v[i]>=Data[7].v[i];
   bool bear=close[i]<=Data[5].v[i]&&Data[5].v[i]<=Data[6].v[i]&&Data[6].v[i]<=Data[7].v[i];
   Data[4].v[i]=bull?1:bear?-1:0; // Pine gives bullish precedence when all equal.
   int p=MapSource(time[i]);if(p<0)return;
   Data[8].v[i]=(double)Source[p].time;
   bool continued=i>0&&Data[8].v[i-1]==Data[8].v[i]&&Valid(RunHigh[i-1])&&Valid(RunLow[i-1]);
   RunHigh[i]=continued?MathMax(RunHigh[i-1],high[i]):high[i];RunLow[i]=continued?MathMin(RunLow[i-1],low[i]):low[i];
   bool complete=continued?Data[10].v[i-1]==1:((i>0&&time[i-1]<Source[p].time)||time[i]==Source[p].time);
   Data[10].v[i]=complete?1:0;
   if(complete)Data[2].v[i]=RunHigh[i]-RunLow[i];
   double anchor=EMPTY_VALUE,atr=EMPTY_VALUE;
   if(UseCurrentClose)
     {anchor=close[i];if(complete)atr=DevelopingATR(p,RunHigh[i],RunLow[i]);Data[9].v[i]=(double)Source[p].time;}
   else if(PriorAdjacent(p) && Source[p-1].complete)
     {anchor=Source[p-1].close;atr=Source[p-1].rma;Data[9].v[i]=(double)Source[p-1].time;}
   Data[0].v[i]=anchor;Data[1].v[i]=atr;
   if(complete && Valid(atr) && atr>0)Data[3].v[i]=Data[2].v[i]/atr*100.0;
   if(!Valid(anchor)||!Valid(atr))return;
   for(int r=0;r<15;r++)
     {double factor=r==0?TriggerPercentage:Ratios[r];Data[11+2*r].v[i]=anchor-factor*atr;Data[12+2*r].v[i]=anchor+factor*atr;}
  }

bool VisibleRatio(const int r)
  {
   if(r>=6 && !ShowExtensions)return false;
   bool intermediate=(r==1||r==2||r==4||r==7||r==8||r==10);
   return !intermediate||ShowAllFibonacciLevels;
  }
color RatioColor(const int r,const bool upper)
  {if(r==0)return upper?UpperTriggerColor:LowerTriggerColor;if(r==5||r==11||r==14)return ATRTargetColor;if(r==1||r==2||r==4||r==7||r==8||r==10)return IntermediateTargetColor;return KeyTargetColor;}
long Sequence()
  {
   string key="SATY_ATR_MT5_INSTANCE_SEQ";GlobalVariableTemp(key);
   for(int n=0;n<100;n++){double old=GlobalVariableGet(key);if(GlobalVariableSetOnCondition(key,old+1,old))return(long)(old+1);}
   return -1;
  }
void PanelLine(const int row,const string text,const color background)
  {
   string box=Prefix+"R"+IntegerToString(row),label=Prefix+"T"+IntegerToString(row);
   if(ObjectFind(0,box)<0)ObjectCreate(0,box,OBJ_RECTANGLE_LABEL,0,0,0);
   if(ObjectFind(0,label)<0)ObjectCreate(0,label,OBJ_LABEL,0,0,0);
   int height=PanelFontSize+13;bool right=PanelCorner==CORNER_RIGHT_UPPER||PanelCorner==CORNER_RIGHT_LOWER;
   bool bottom=PanelCorner==CORNER_LEFT_LOWER||PanelCorner==CORNER_RIGHT_LOWER;
   int chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0),chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int width=MathMax(120,MathMin(PanelFontSize*56,chart_width-2*PanelX));
   int left=right?MathMax(0,chart_width-PanelX-width):PanelX,top=bottom?MathMax(0,chart_height-PanelY-5*height):PanelY;
   // Rectangle labels use a fixed upper-left anchor; convert the requested
   // corner into physical upper-left coordinates before placing both objects.
   ObjectSetInteger(0,box,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,box,OBJPROP_XDISTANCE,left);
   ObjectSetInteger(0,box,OBJPROP_YDISTANCE,top+row*height);ObjectSetInteger(0,box,OBJPROP_XSIZE,width);ObjectSetInteger(0,box,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,box,OBJPROP_BGCOLOR,background);ObjectSetInteger(0,box,OBJPROP_COLOR,clrDimGray);ObjectSetInteger(0,box,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,label,OBJPROP_XDISTANCE,left+6);ObjectSetInteger(0,label,OBJPROP_YDISTANCE,top+row*height+4);
   ObjectSetInteger(0,label,OBJPROP_FONTSIZE,PanelFontSize);ObjectSetString(0,label,OBJPROP_FONT,"Microsoft YaHei");ObjectSetInteger(0,label,OBJPROP_COLOR,clrWhite);
   ObjectSetString(0,label,OBJPROP_TEXT,text);ObjectSetString(0,label,OBJPROP_TOOLTIP,text);
   ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,box,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,label,OBJPROP_HIDDEN,true);ObjectSetInteger(0,box,OBJPROP_HIDDEN,true);
  }
void RenderPanel()
  {
   if(!ShowInfo || ChartWindowFind(0,ShortName)<0)return;int i=ArraySize(Data[0].v)-1;bool valid=LastDataReady&&i>=0&&Valid(Data[0].v[i])&&Valid(Data[1].v[i]);
   string title="Saty ATR Levels | "+ModeText();color trend=clrDarkOrange;
   if(i>=0&&Valid(Data[4].v[i]))trend=Data[4].v[i]>0?clrForestGreen:Data[4].v[i]<0?clrFireBrick:clrDarkOrange;
   PanelLine(0,title,trend);
   if(!valid)
     {PanelLine(1,Unavailable,clrDimGray);PanelLine(2,"等待完整源周期与 RMA 预热",clrDimGray);PanelLine(3,"默认使用上一完整周期锚点",clrDimGray);}
   else
     {
      bool range_ok=Valid(Data[3].v[i]);color c=range_ok?(Data[3].v[i]<=70?clrForestGreen:Data[3].v[i]>=90?clrFireBrick:clrDarkOrange):clrDimGray;
      string range=range_ok?StringFormat("已知 Range %.2f = %.1f%% ATR（%.2f）",Data[2].v[i],Data[3].v[i],Data[1].v[i]):StringFormat("ATR %.2f；本周期范围不完整或 ATR 为零",Data[1].v[i]);
      PanelLine(1,range,c);
      PanelLine(2,StringFormat("%s > %.*f | +1 ATR %.*f",UseOptionsLabels?"Calls":"Long",_Digits,Data[12].v[i],_Digits,Data[22].v[i]),clrTeal);
      PanelLine(3,StringFormat("%s < %.*f | -1 ATR %.*f",UseOptionsLabels?"Puts":"Short",_Digits,Data[11].v[i],_Digits,Data[21].v[i]),clrDarkGoldenrod);
     }
   PanelLine(4,UseCurrentClose?"当前发展值会变化；仅环境参考，不自动交易":"上一完整周期锚点；仅环境参考，不自动交易",clrBlack);
  }

int OnInit()
  {
   if((int)TradingType<0||(int)TradingType>4||ATRLength<1||ATRLength>10000||FastEMA<1||PivotEMA<1||SlowEMA<1||
      FastEMA>100000||PivotEMA>100000||SlowEMA>100000||!MathIsValidNumber(TriggerPercentage)||TriggerPercentage<0||
      LevelSize<1||LevelSize>5||PanelX<0||PanelY<0||PanelFontSize<7||PanelFontSize>24)
     {Print("Saty ATR 初始化失败：周期、触发距离或绘图参数无效。");return INIT_PARAMETERS_INCORRECT;}
   if((TradingType==DAY&&PeriodSeconds(_Period)>PeriodSeconds(PERIOD_D1)) ||
      (TradingType==MULTIDAY&&PeriodSeconds(_Period)>PeriodSeconds(PERIOD_W1)) ||
      (TradingType>=SWING&&_Period==PERIOD_W1))
     {Print("Saty ATR 初始化失败：图表周期过高，或W1蜡烛跨越日历月/季度/年边界；请用兼容周期。");return INIT_PARAMETERS_INCORRECT;}
   string labels[11]={"AnchorClose","SourceATR_RMA","KnownPeriodRange","RangePercentATR","EMA_Trend","EMA_Fast","EMA_Pivot","EMA_Slow","SourcePeriodStart","AnchorPeriodStart","RangeComplete"};
   for(int b=0;b<41;b++)
     {
      SetIndexBuffer(b,Data[b].v,INDICATOR_DATA);ArraySetAsSeries(Data[b].v,false);
      PlotIndexSetInteger(b,PLOT_DRAW_TYPE,DRAW_NONE);PlotIndexSetInteger(b,PLOT_SHOW_DATA,true);PlotIndexSetDouble(b,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      if(b<11)PlotIndexSetString(b,PLOT_LABEL,labels[b]);
     }
   SetIndexBuffer(41,RunHigh,INDICATOR_CALCULATIONS);SetIndexBuffer(42,RunLow,INDICATOR_CALCULATIONS);ArraySetAsSeries(RunHigh,false);ArraySetAsSeries(RunLow,false);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_LINE);PlotIndexSetInteger(0,PLOT_LINE_COLOR,PreviousCloseColor);PlotIndexSetInteger(0,PLOT_LINE_WIDTH,LevelSize);
   for(int r=0;r<15;r++)for(int side=0;side<2;side++)
     {
      int b=11+2*r+side;PlotIndexSetInteger(b,PLOT_DRAW_TYPE,VisibleRatio(r)?DRAW_LINE:DRAW_NONE);
      PlotIndexSetInteger(b,PLOT_LINE_COLOR,RatioColor(r,side==1));PlotIndexSetInteger(b,PLOT_LINE_WIDTH,LevelSize);
      PlotIndexSetString(b,PLOT_LABEL,r==0?(side==0?"LowerTrigger":"UpperTrigger"):StringFormat("%s%.3f_ATR",side==0?"-":"+",Ratios[r]));
     }
   long id=Sequence();if(id<1)return INIT_FAILED;
   Prefix="SATY_ATR_"+IntegerToString(ChartID())+"_"+IntegerToString(id)+"_";
   ShortName=StringFormat("Saty ATR [%d / RMA%d #%I64d]",(int)TradingType,ATRLength,id);
   IndicatorSetString(INDICATOR_SHORTNAME,ShortName);IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   if(ShowInfo)EventSetTimer(1);
   PrintFormat("SATY_ATR_INIT | symbol=%s chart=%s mode=%d RMA=%d current=%s prefix=%s",_Symbol,EnumToString(_Period),(int)TradingType,ATRLength,UseCurrentClose?"true":"false",Prefix);
   return INIT_SUCCEEDED;
  }
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<1)return 0;ArraySetAsSeries(time,false);ArraySetAsSeries(high,false);ArraySetAsSeries(low,false);ArraySetAsSeries(close,false);
   bool full=prev_calculated<=0||prev_calculated>rates_total,changed=false;
   if(full||!SourceReady||time[rates_total-1]!=LastChartTime)
     {
      SourceReady=LoadSource(changed);
      if(!SourceReady)
        {int first=full?0:MathMax(0,rates_total-2);for(int i=first;i<rates_total;i++)EmptyAt(i);LastDataReady=false;LogError(Unavailable);RenderPanel();return full?0:prev_calculated;}
      if(changed)full=true;
     }
   int begin=full?0:MathMax(0,prev_calculated-1);
   for(int i=begin;i<rates_total;i++)BuildBar(i,time,high,low,close);
   LastChartTime=time[rates_total-1];LastDataReady=Valid(Data[0].v[rates_total-1])&&Valid(Data[1].v[rates_total-1]);
   Unavailable=LastDataReady?"":"源周期不足、RMA 尚未预热或本周期范围不完整";RenderPanel();return rates_total;
  }
void OnTimer(){RenderPanel();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){if(id==CHARTEVENT_CHART_CHANGE)RenderPanel();}
void OnDeinit(const int reason){EventKillTimer();if(Prefix!="")ObjectsDeleteAll(0,Prefix,-1,-1);ChartRedraw(0);}
'''
target.write_text(code,encoding='utf-8-sig')
print(target)
