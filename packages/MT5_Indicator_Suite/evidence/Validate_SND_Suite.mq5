// Synthetic S&D indicator checks only. No orders, accounts or external calls.
#property strict
#property version "1.00"
const int N=160;
string W="",B="",I="",P="";
int LogFile=INVALID_HANDLE,Groups=0,Failed=0;
ulong Started=0;
string HostNames[];
void Note(const string message) {Print(message);if(LogFile!=INVALID_HANDLE){FileWrite(LogFile,message);FileFlush(LogFile);}}
void Check(const string label,const bool pass)
  {Groups++;if(!pass)Failed++;Note((pass ? "PASS | " : "FAIL | ")+label);}
bool Same(const double a,const double b) {return((a==EMPTY_VALUE && b==EMPTY_VALUE) || (a!=EMPTY_VALUE && b!=EMPTY_VALUE && MathAbs(a-b)<1e-8));}
void Candle(MqlRates &r,const double o,const double h,const double l,const double c)
  {r.open=o;r.high=h;r.low=l;r.close=c;r.tick_volume=100;r.real_volume=0;r.spread=0;}
bool Create(const string sym,const int kind,const int count,MqlRates &r[])
  {
   bool custom=false;bool exists=SymbolExist(sym,custom);
   if((exists && !custom) || (!exists && !CustomSymbolCreate(sym,"CodexValidation"))) return(false);
   CustomSymbolSetInteger(sym,SYMBOL_DIGITS,2);CustomSymbolSetDouble(sym,SYMBOL_POINT,0.01);
   CustomSymbolSetInteger(sym,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
   ArrayResize(r,N);
   for(int n=0;n<N;n++){r[n].time=D'2026.03.02 00:00:00'+n*60;Candle(r[n],100,100.5,99.5,100);}
   if(kind==0)
     {
      Candle(r[30],100,104,99.5,99.8);
      Candle(r[31],99.8,99.9,98.8,99);
      Candle(r[32],99,100.5,98.8,100.2);
      Candle(r[33],100.2,100.3,98.8,99);
      Candle(r[34],99,102.5,98.8,101.8);
      Candle(r[35],101.8,105,101.5,104.5);
      Candle(r[60],100,100.5,96,100.2);
      Candle(r[61],100.2,100.6,100.1,100.4);
      Candle(r[62],100.4,100.5,99.7,99.8);
      Candle(r[63],99.8,101,99.7,100.8);
      Candle(r[64],100.8,101,97.5,98.2);
      Candle(r[65],98.2,98.5,95,95.5);
      // Late untouched examples for a readable preview; earlier assertions
      // and the prefix-append comparison concern bars <=65 and do not change.
      Candle(r[146],100,100.5,96,100.2);
      for(int k=147;k<N;k++)Candle(r[k],100.6,100.9,100.3,100.6);
      Candle(r[153],101,105,100.5,100.8);
     }
   if(kind==1)
     {
      Candle(r[40],100,100.1,99.9,100.04);Candle(r[41],100.04,100.1,99.9,100);
      Candle(r[42],100,102.1,99.9,102);
      Candle(r[80],100,100.1,99.9,100.04);Candle(r[81],100.04,100.1,99.9,100);
      Candle(r[82],100,100.1,97.9,98);
     }
   if(kind==2)
     {
      for(int k=0;k<4;k++) {double o=100+k;Candle(r[40+k],o,o+1.1,o-0.1,o+1);}
      for(int k=0;k<4;k++) {double o=100-k;Candle(r[80+k],o,o+0.1,o-1.1,o-1);}
     }
   ArrayResize(r,count);
   return(CustomRatesReplace(sym,r[0].time,r[count-1].time,r)==count && SymbolSelect(sym,true));
  }
int Handle(const string sym,const bool wick,const bool base,const bool impulse,const double point_size,
           const bool draw=false,const int maxdraw=8,const int label_y=42)
  {
   return(iCustom(sym,PERIOD_M1,"GSM_SND_MT5",wick,base,impulse,point_size,30.0,14,
                  0.60,2.0,0.50,1.0,2,6,0.80,1.20,0.50,0.80,0.05,3,2.0,0.60,0.05,
                  true,0.0,2000,200,maxdraw,10000,draw,true,true,20,label_y));
  }
bool Ready(const int h,const int n,const int timeout=12000)
  {
   double tmp[];ulong end=GetTickCount64()+(ulong)timeout;
   while(h!=INVALID_HANDLE && GetTickCount64()<end && !IsStopped())
     {
      int copied=CopyBuffer(h,0,0,1,tmp),calculated=BarsCalculated(h);
      if(calculated>n){Note(StringFormat("UNEXPECTED_HISTORY handle=%d expected=%d actual=%d",h,n,calculated));return(false);}
      if(copied==1 && calculated==n)return(true);
      Sleep(100);
     }
   return(false);
  }
bool Read(const int h,const int b,const int n,double &dst[])
  {ArraySetAsSeries(dst,false);return(CopyBuffer(h,b,0,n,dst)==n);}
double Value(const int h,const int b,const int n,const int index)
  {double data[];if(!Read(h,b,n,data))return(EMPTY_VALUE);return(data[index]);}
bool Event(const int h,const int b,const int bar,const double expected)
  {double actual=Value(h,b,N,bar);if(!Same(actual,expected))Note(StringFormat("DETAIL buffer=%d index=%d actual=%.12g expected=%.12g",b,bar,actual,expected));return(Same(actual,expected));}
int CountObjects(const long chart,const int type=-1)
  {
   int result=0;
   for(int j=0;j<ObjectsTotal(chart,0,-1);j++)
     {string name=ObjectName(chart,j,0,-1);if(StringFind(name,"GSD_")==0 && (type<0 || ObjectGetInteger(chart,name,OBJPROP_TYPE)==type))result++;}
   return(result);
  }
bool BothDrawn(const long chart)
  {
   int owners=0;
   for(int j=0;j<ObjectsTotal(chart,0,-1);j++)
     {
      string name=ObjectName(chart,j,0,-1);
      if(StringFind(name,"GSD_")!=0 || StringFind(name,"OWNER")<0)continue;
      owners++;string prefix=StringSubstr(name,0,StringLen(name)-5);int rectangles=0;
      for(int k=0;k<ObjectsTotal(chart,0,-1);k++)
        {string other=ObjectName(chart,k,0,-1);if(StringFind(other,prefix)==0 && ObjectGetInteger(chart,other,OBJPROP_TYPE)==OBJ_RECTANGLE)rectangles++;}
      if(rectangles==0)return(false);
     }
   return(owners==2);
  }
void CleanNewHost()
  {
   for(int j=ObjectsTotal(0,-1,-1)-1;j>=0;j--)
     {
      string name=ObjectName(0,j,-1,-1);if(StringFind(name,"GSD_")!=0)continue;
      bool old=false;for(int k=0;k<ArraySize(HostNames);k++)if(HostNames[k]==name){old=true;break;}
      if(!old)ObjectDelete(0,name);
     }
  }
void Visual(const int count)
  {
   long chart=ChartOpen(W,PERIOD_M1);
   if(chart<=0 || chart==ChartID()){Check("Own synthetic chart creation",false);return;}
   for(int j=ChartIndicatorsTotal(chart,0)-1;j>=0;j--)ChartIndicatorDelete(chart,0,ChartIndicatorName(chart,0,j));
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(chart,CHART_SCALE,5);ChartSetInteger(chart,CHART_SHIFT,true);ChartSetDouble(chart,CHART_SHIFT_SIZE,15);
   ChartSetInteger(chart,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
   ChartSetInteger(chart,CHART_COLOR_CHART_UP,clrSeaGreen);ChartSetInteger(chart,CHART_COLOR_CHART_DOWN,clrIndianRed);
   ChartSetInteger(chart,CHART_COLOR_CANDLE_BULL,clrSeaGreen);ChartSetInteger(chart,CHART_COLOR_CANDLE_BEAR,clrIndianRed);
   ChartSetString(chart,CHART_COMMENT,"SYNTHETIC S&D PATTERNS ONLY - NO TRADING RESULTS");
   int one=Handle(W,true,false,false,0.1,true,8,42),two=Handle(W,true,false,false,0.001,true,6,62);
   bool attached=Ready(one,count)&&Ready(two,count)&&ChartIndicatorAdd(chart,0,one)&&ChartIndicatorAdd(chart,0,two);
   ChartRedraw(chart);Sleep(400);
   if(attached && CountObjects(chart)==0)
     {
      string tpl="suite_snd_"+IntegerToString((long)Started)+".tpl";
      bool saved=ChartSaveTemplate(chart,tpl);
      for(int j=ChartIndicatorsTotal(chart,0)-1;j>=0;j--)ChartIndicatorDelete(chart,0,ChartIndicatorName(chart,0,j));
      IndicatorRelease(one);IndicatorRelease(two);one=INVALID_HANDLE;two=INVALID_HANDLE;Sleep(150);CleanNewHost();
      bool applied=saved&&ChartApplyTemplate(chart,tpl);
      ulong end=GetTickCount64()+12000;
      while(applied && GetTickCount64()<end && !BothDrawn(chart) && !IsStopped()){ChartRedraw(chart);Sleep(100);}
      Note(StringFormat("VISUAL template saved=%d applied=%d target_objects=%d",saved,applied,CountObjects(chart)));
     }
   int owners=0,rectangles=0;bool causal=true;
   for(int j=0;j<ObjectsTotal(chart,0,-1);j++)
     {
      string name=ObjectName(chart,j,0,-1);if(StringFind(name,"GSD_")!=0)continue;
      if(StringFind(name,"OWNER")>=0)owners++;
      if(ObjectGetInteger(chart,name,OBJPROP_TYPE)==OBJ_RECTANGLE)
        {
         rectangles++;
         datetime created=(datetime)ObjectGetInteger(chart,name,OBJPROP_TIME,0);
         if(created<D'2026.03.02 00:31:00')causal=false;
        }
     }
   Check("Two native chart instances own separate object prefixes and zone drawings",owners==2&&BothDrawn(chart));
   bool accurate_unit=false;
   for(int j=0;j<ObjectsTotal(chart,0,-1);j++)
     {string name=ObjectName(chart,j,0,-1);if(StringFind(name,"GSD_")==0 && StringFind(name,"STATUS")>=0 && StringFind(ObjectGetString(chart,name,OBJPROP_TEXT),"1 pt=0.001")>=0)accurate_unit=true;}
   Check("Sub-symbol-digit pt unit displayed accurately",accurate_unit);
   Check("Bounded drawings on target chart, causal rectangle left edges",rectangles>0&&rectangles<=14&&causal);
   ChartNavigate(chart,CHART_END,0);ChartRedraw(chart);Sleep(500);
   string shot="suite_snd_chart.png";if(FileIsExist(shot))FileDelete(shot);
   int width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS,0),height=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,0);
   bool requested=ChartScreenShot(chart,shot,width,height,ALIGN_RIGHT);
   for(int j=0;j<30&&!FileIsExist(shot);j++)Sleep(100);
   Check("Actual MT5 target-chart screenshot saved",requested&&FileIsExist(shot)&&rectangles>0);
   Note(StringFormat("VISUAL chart=%I64d owners=%d rectangles=%d canvas=%dx%d",chart,owners,rectangles,width,height));
   if(one!=INVALID_HANDLE)IndicatorRelease(one);if(two!=INVALID_HANDLE)IndicatorRelease(two);
   ChartClose(chart);Sleep(200);CleanNewHost();
  }
void OnStart()
  {
   Started=GetTickCount64();LogFile=FileOpen("suite_snd_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   // Each run owns new symbols. CustomRatesReplace on a shorter interval does
   // not remove bars/ticks appended by a previous run, so reusing P would hide
   // a stale bar behind a >= readiness test and offset every CopyBuffer read.
   string suffix=StringFormat("%I64u",Started);
   if(StringLen(suffix)>14)suffix=StringSubstr(suffix,StringLen(suffix)-14);
   W="CODEX_SND_W_"+suffix;B="CODEX_SND_B_"+suffix;I="CODEX_SND_I_"+suffix;P="CODEX_SND_P_"+suffix;
   int hn=ObjectsTotal(0,-1,-1);ArrayResize(HostNames,hn);for(int j=0;j<hn;j++)HostNames[j]=ObjectName(0,j,-1,-1);
   Note("GSM S&D synthetic fixture. Thresholds are engineering choices; this is not a strategy backtest.");
   Note("RUN_SYMBOLS "+W+" "+B+" "+I+" "+P);
   MqlRates rw[],rb[],ri[],rp[];
   bool setup=Create(W,0,N,rw)&&Create(B,1,N,rb)&&Create(I,2,N,ri)&&Create(P,0,31,rp);
   Check("Synthetic source data",setup);if(!setup)return;
   int hw=Handle(W,true,false,false,0.1),hnarrow=Handle(W,true,false,false,1.0),hb=Handle(B,false,true,false,0.1),hi=Handle(I,false,false,true,0.1),hp=Handle(P,true,false,false,0.1);
   bool ready=Ready(hw,N)&&Ready(hnarrow,N)&&Ready(hb,N)&&Ready(hi,N)&&Ready(hp,31);
   Check("Compiled indicator handles ready",ready);if(!ready)return;
   Check("Long upper wick creates supply only after candle close",Event(hw,7,29,0)&&Event(hw,7,30,1)&&Event(hw,6,30,0));
   Check("Upper-wick zone bounds and >30pt midpoint",Same(Value(hw,2,N,30),100)&&Same(Value(hw,3,N,30),104)&&Same(Value(hw,5,N,30),102));
   Check("Point-size override changes small-zone reference to proximal boundary",Same(Value(hnarrow,5,N,30),100));
   Check("Supply first visit recorded once; midpoint not reached",Event(hw,9,32,1)&&Event(hw,9,33,0)&&Event(hw,15,32,0)&&Event(hw,15,33,0));
   Check("Supply second visit is retouch; no renewed first or midpoint eligibility",Event(hw,11,34,1)&&Event(hw,9,34,0)&&Event(hw,15,34,0));
   Check("Narrow zone reference fires only during first visit",Event(hnarrow,15,32,1)&&Event(hnarrow,15,34,0));
   Check("Supply invalidation takes priority over same-bar touch",Event(hw,13,35,1)&&Event(hw,9,35,0)&&Event(hw,11,35,0));
   Check("Long lower wick creates demand and midpoint",Event(hw,6,60,1)&&Same(Value(hw,0,N,60),96)&&Same(Value(hw,1,N,60),100)&&Same(Value(hw,4,N,60),98));
   Check("Demand first, later retouch, invalidation lifecycle",Event(hw,8,62,1)&&Event(hw,10,64,1)&&Event(hw,14,64,0)&&Event(hw,12,65,1));
   Check("Bullish base break: prior base bounds, no pre-break formation",Event(hb,6,41,0)&&Event(hb,6,42,1)&&Same(Value(hb,0,N,42),99.9)&&Same(Value(hb,1,N,42),100.1));
   Check("Bearish base break creates supply",Event(hb,7,82,1)&&Same(Value(hb,2,N,82),99.9)&&Same(Value(hb,3,N,82),100.1));
   Check("Bullish impulse confirmed only after minimum run; origin bounds",Event(hi,6,41,0)&&Event(hi,6,42,1)&&Event(hi,6,43,0)&&Same(Value(hi,0,N,42),99.5)&&Same(Value(hi,1,N,42),100.5));
   Check("Bearish impulse creates one supply zone for continuing run",Event(hi,7,82,1)&&Event(hi,7,83,0));
   Check("Live forming long-wick candle has no event or future zone",Same(Value(hp,7,31,30),0)&&Value(hp,2,31,30)==EMPTY_VALUE);
   double before[16][31];bool copied=true;
   for(int b=0;b<16;b++){double a[];if(!Read(hp,b,31,a)){copied=false;break;}for(int j=0;j<31;j++)before[b][j]=a[j];}
   MqlTick quote[];ArrayResize(quote,1);ZeroMemory(quote[0]);quote[0].time=rp[30].time+61;
   quote[0].time_msc=(long)quote[0].time*1000;quote[0].bid=99;quote[0].ask=99;quote[0].last=99;quote[0].volume=1;
   quote[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   bool appended=(CustomTicksAdd(P,quote)==1)&&Ready(hp,32);
   bool stable=copied&&appended,same_full=appended;
   for(int b=0;b<16 && stable;b++)
     {
      double a[],f[];if(!Read(hp,b,32,a)||!Read(hw,b,N,f)){stable=false;same_full=false;break;}
      for(int j=0;j<30;j++)if(!Same(a[j],before[b][j]))stable=false;
      for(int j=0;j<=30;j++)if(!Same(a[j],f[j]))same_full=false;
     }
   Check("Incremental append preserves all previously closed buffers",stable);
   Check("First close reveals zone; incremental equals independent full-history instance",same_full&&Same(Value(hp,7,32,30),1));
   bool livezero=true;for(int b=6;b<16;b++)if(!Same(Value(hw,b,N,N-1),0))livezero=false;
   Check("All event buffers zero on current candle",livezero);
   int csv=FileOpen("suite_snd_events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(csv!=INVALID_HANDLE)
     {
      FileWrite(csv,"time","d_low","d_high","s_low","s_high","d_reference","s_reference","d_new","s_new","d_first","s_first","d_retouch","s_retouch","d_invalid","s_invalid","d_reference_hit","s_reference_hit");
      for(int j=25;j<=66;j++)FileWrite(csv,TimeToString(rw[j].time,TIME_DATE|TIME_MINUTES),Value(hw,0,N,j),Value(hw,1,N,j),Value(hw,2,N,j),Value(hw,3,N,j),Value(hw,4,N,j),Value(hw,5,N,j),Value(hw,6,N,j),Value(hw,7,N,j),Value(hw,8,N,j),Value(hw,9,N,j),Value(hw,10,N,j),Value(hw,11,N,j),Value(hw,12,N,j),Value(hw,13,N,j),Value(hw,14,N,j),Value(hw,15,N,j));
      FileClose(csv);
     }
   Visual(N);
   IndicatorRelease(hw);IndicatorRelease(hnarrow);IndicatorRelease(hb);IndicatorRelease(hi);IndicatorRelease(hp);
   Note(StringFormat("OVERALL=%s | groups=%d failed=%d elapsed_ms=%I64u",Failed==0 ? "PASS" : "FAIL",Groups,Failed,GetTickCount64()-Started));
   if(LogFile!=INVALID_HANDLE)FileClose(LogFile);
  }
