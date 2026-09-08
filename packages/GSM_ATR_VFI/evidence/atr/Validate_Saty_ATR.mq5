#property strict
#property version "1.00"
// Synthetic price data and numerical oracle only. No orders or account APIs.
int Log=INVALID_HANDLE,Groups=0,Failures=0,CSV=INVALID_HANDLE;
string Tag="";const string PATH="GSM\\Saty_ATR_Levels_MT5";
struct Frame {double value[];};
struct Bar {datetime time;double high,low,close;};
const double Ratios[15]={0.236,0.382,0.5,0.618,0.786,1,1.236,1.382,1.5,1.618,1.786,2,2.236,2.618,3};
void Note(const string s){Print(s);if(Log!=INVALID_HANDLE){FileWriteString(Log,s+"\r\n");FileFlush(Log);}}
void Check(const string s,const bool pass,const string detail=""){Groups++;if(!pass)Failures++;Note((pass?"PASS|":"FAIL|")+s+"|"+detail);}
bool Same(const double a,const double b){return (a==EMPTY_VALUE||b==EMPTY_VALUE)?a==b:MathIsValidNumber(a)&&MathIsValidNumber(b)&&MathAbs(a-b)<=1e-8;}
string V(const double n){return n==EMPTY_VALUE?"EMPTY_VALUE":DoubleToString(n,15);}
bool SelectFixture(const string symbol,const string stage)
  {
   for(int retry=0;retry<4;retry++)
     {
      ResetLastError();if(SymbolSelect(symbol,true))return true;
      Note(StringFormat("SELECT_RETRY stage=%s symbol=%s attempt=%d error=%d",stage,symbol,retry+1,GetLastError()));Sleep(80);
     }
   return false;
  }
bool AddQuote(const string symbol,MqlTick &ticks[],const string stage)
  {
   for(int retry=0;retry<4;retry++)
     {
      if(!SelectFixture(symbol,stage))return false;
      ResetLastError();int added=CustomTicksAdd(symbol,ticks),error=GetLastError();
      if(added==ArraySize(ticks))return true;
      Note(StringFormat("QUOTE_RETRY stage=%s symbol=%s attempt=%d requested=%d added=%d error=%d",stage,symbol,retry+1,ArraySize(ticks),added,error));
      if(added>0 || error!=4302)return false;Sleep(80);
     }
   return false;
  }

bool Warm(const string symbol,const ENUM_TIMEFRAMES tf,const int expected=0)
  {
   if(!SelectFixture(symbol,"Warm"))return false;
   ulong until=GetTickCount64()+8000;MqlRates rows[];
   while(GetTickCount64()<until&&!IsStopped())
     {int total=Bars(symbol,tf);int request=expected>0?expected:MathMax(1,total);int copied=CopyRates(symbol,tf,0,request,rows);total=Bars(symbol,tf);if(total>0&&copied==request&&(expected==0||total==expected))return true;Sleep(50);}
   Note(StringFormat("WARM_FAIL %s %s bars=%d expected=%d err=%d",symbol,EnumToString(tf),Bars(symbol,tf),expected,GetLastError()));return false;
  }
bool Create(const string symbol,const MqlRates &rates[])
  {
   if(!CustomSymbolCreate(symbol,"SatyATRValidation"))return false;
   CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2);CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01);CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
   int n=ArraySize(rates);return CustomRatesReplace(symbol,rates[0].time,rates[n-1].time,rates)==n&&SymbolSelect(symbol,true)&&Warm(symbol,PERIOD_M1,n);
  }
int Profile(const string symbol,const ENUM_TIMEFRAMES tf,const int mode,const int length,const bool current,
            const bool all_levels,const bool extensions,const bool draw,const bool options=true)
  {
   for(int retry=0;retry<4;retry++)
     {
      if(!SelectFixture(symbol,"Handle"))return INVALID_HANDLE;
      ResetLastError();int h=iCustom(symbol,tf,PATH,"",mode,options,length,0.236,current,8,21,34,"",all_levels,extensions,2,draw),error=GetLastError();
      if(h!=INVALID_HANDLE)return h;
      Note(StringFormat("HANDLE_FAILURE symbol=%s tf=%s mode=%d length=%d current=%d attempt=%d error=%d",symbol,EnumToString(tf),mode,length,current,retry+1,error));
      if(error!=4302)return INVALID_HANDLE;Sleep(80);
     }
   return INVALID_HANDLE;
  }
int Handle(const string symbol,const ENUM_TIMEFRAMES tf,const int mode,const int length=14,const bool current=false,const bool hidden=false,const bool draw=false)
  {return Profile(symbol,tf,mode,length,current,!hidden,!hidden,draw);}
bool Ready(const int h,const int count)
  {
   ulong until=GetTickCount64()+8000;double p[];
   while(h!=INVALID_HANDLE&&GetTickCount64()<until&&!IsStopped())
     {if(CopyBuffer(h,0,0,1,p)==1&&BarsCalculated(h)==count)return true;Sleep(50);}
   Note(StringFormat("READY_FAIL h=%d bars=%d expected=%d err=%d",h,BarsCalculated(h),count,GetLastError()));return false;
  }
bool Snapshot(const int h,const int count,Frame &f[])
  {
   ArrayResize(f,41);for(int b=0;b<41;b++){ArraySetAsSeries(f[b].value,false);if(CopyBuffer(h,b,0,count,f[b].value)!=count)return false;}return true;
  }
bool Compare(const Frame &a[],const Frame &b[],const int bars,int &bad,long &values)
  {bad=0;values=0;if(ArraySize(a)!=41||ArraySize(b)!=41)return false;for(int j=0;j<41;j++)for(int i=0;i<bars;i++){values++;if(!Same(a[j].value[i],b[j].value[i])){if(bad<3)Note(StringFormat("DIFF b=%d i=%d a=%s b=%s",j,i,V(a[j].value[i]),V(b[j].value[i])));bad++;}}return bad==0;}
void Release(const int h){if(h!=INVALID_HANDLE)IndicatorRelease(h);}

void DailyFixture(MqlRates &rows[],Bar &days[])
  {
   ArrayResize(rows,144);ArrayResize(days,36);
   for(int d=0;d<36;d++)
     {
      days[d].time=D'2026.01.05 00:00:00'+d*86400;days[d].high=-DBL_MAX;days[d].low=DBL_MAX;
      for(int j=0;j<4;j++)
        {
         int k=d*4+j;ZeroMemory(rows[k]);rows[k].time=days[d].time+j*21600;
         rows[k].open=NormalizeDouble(100+0.6*d+3*MathSin(d/3.0)+0.2*j,2);
         rows[k].close=NormalizeDouble(rows[k].open+0.3*MathCos((d+j)/2.0),2);
         rows[k].high=NormalizeDouble(MathMax(rows[k].open,rows[k].close)+(j==3?5.0:0.3+j*0.2),2);
         rows[k].low=NormalizeDouble(MathMin(rows[k].open,rows[k].close)-(j==3?3.0:0.2+j*0.1),2);
         rows[k].tick_volume=100;days[d].high=MathMax(days[d].high,rows[k].high);days[d].low=MathMin(days[d].low,rows[k].low);days[d].close=rows[k].close;
        }
     }
  }
void RMA(const Bar &bars[],const int length,double &atr[])
  {
   int n=ArraySize(bars);ArrayResize(atr,n);ArrayInitialize(atr,EMPTY_VALUE);double sum=0;
   for(int k=0;k<n;k++)
     {
      double tr=bars[k].high-bars[k].low;if(k>0)tr=MathMax(tr,MathMax(MathAbs(bars[k].high-bars[k-1].close),MathAbs(bars[k].low-bars[k-1].close)));
      if(k<length){sum+=tr;if(k==length-1)atr[k]=sum/length;}
      else atr[k]=atr[k-1]+(tr-atr[k-1])/length; // Algebraically independent update ordering.
     }
  }
void CheckDayOracle(const Frame &f[],const MqlRates &rates[],const Bar &days[],const bool current)
  {
   double atr[];RMA(days,14,atr);int bad=0;long values=0;double ema[3]={0,0,0};int lengths[3]={8,21,34};
   for(int i=0;i<144;i++)
     {
      int d=i/4,j=i%4;double high=-DBL_MAX,low=DBL_MAX;
      for(int q=d*4;q<=i;q++){high=MathMax(high,rates[q].high);low=MathMin(low,rates[q].low);}
      double expected_atr=EMPTY_VALUE,anchor=current?rates[i].close:(d>0?days[d-1].close:EMPTY_VALUE);
      if(!current){if(d>0)expected_atr=atr[d-1];}
      else
        {
         double tr=high-low;if(d>0)tr=MathMax(tr,MathMax(MathAbs(high-days[d-1].close),MathAbs(low-days[d-1].close)));
         if(d>=14)expected_atr=atr[d-1]+(tr-atr[d-1])/14;
         else if(d==13)
           {double sum=tr;for(int p=0;p<13;p++){double t=days[p].high-days[p].low;if(p>0)t=MathMax(t,MathMax(MathAbs(days[p].high-days[p-1].close),MathAbs(days[p].low-days[p-1].close)));sum+=t;}expected_atr=sum/14;}
        }
      double expected[41];ArrayInitialize(expected,EMPTY_VALUE);expected[0]=anchor;expected[1]=expected_atr;expected[2]=high-low;
      if(expected_atr!=EMPTY_VALUE&&expected_atr>0)expected[3]=(high-low)/expected_atr*100;
      for(int e=0;e<3;e++){double alpha=2.0/(lengths[e]+1.0);ema[e]=i==0?rates[i].close:ema[e]+alpha*(rates[i].close-ema[e]);expected[5+e]=ema[e];}
      expected[4]=rates[i].close>=ema[0]&&ema[0]>=ema[1]&&ema[1]>=ema[2]?1:rates[i].close<=ema[0]&&ema[0]<=ema[1]&&ema[1]<=ema[2]?-1:0;
      expected[8]=(double)days[d].time;expected[9]=current?(double)days[d].time:(d>0?(double)days[d-1].time:EMPTY_VALUE);expected[10]=1;
      if(anchor!=EMPTY_VALUE&&expected_atr!=EMPTY_VALUE)for(int r=0;r<15;r++){expected[11+2*r]=anchor-Ratios[r]*expected_atr;expected[12+2*r]=anchor+Ratios[r]*expected_atr;}
      for(int b=0;b<41;b++)
        {
         values++;bool same=Same(f[b].value[i],expected[b]);if(!same){if(bad<5)Note(StringFormat("DAY_ORACLE current=%d b=%d bar=%d got=%s expected=%s",current,b,i,V(f[b].value[i]),V(expected[b])));bad++;}
         if(CSV!=INVALID_HANDLE)FileWrite(CSV,"DAY",current?"CURRENT":"PREVIOUS",TimeToString(rates[i].time,TIME_DATE|TIME_SECONDS),b,V(f[b].value[i]),V(expected[b]),same?"MATCH":"DIFFERENT");
        }
     }
   Check(current?"DAY_CURRENT_CAUSAL_ORACLE":"DAY_PREVIOUS_RMA_ORACLE",bad==0,StringFormat("values=%I64d failures=%d bars=144 source_days=36 RMA=14",values,bad));
  }

void NativeVisual(const string symbol,const int count)
  {
   if(!SelectFixture(symbol,"NativeVisual ChartOpen")){Check("NATIVE_CHART",false,"fixture selection failed");return;}
   long chart=0;
   for(int retry=0;retry<4;retry++)
     {
      SelectFixture(symbol,"NativeVisual ChartOpen retry");ResetLastError();chart=ChartOpen(symbol,PERIOD_M1);int error=GetLastError();
      if(chart>0)break;Note(StringFormat("CHART_OPEN_RETRY symbol=%s attempt=%d error=%d",symbol,retry+1,error));if(error!=4302)break;Sleep(80);
     }
   if(chart<=0||chart==ChartID()){Check("NATIVE_CHART",false);return;}
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=0;w--)for(int i=ChartIndicatorsTotal(chart,w)-1;i>=0;i--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,i));
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);ChartSetInteger(chart,CHART_SCALE,3);
   ChartSetString(chart,CHART_COMMENT,"SYNTHETIC DATA / SATY ATR LEVELS / NOT A STRATEGY BACKTEST");
   // Preserve source default: intermediate levels on, extensions off.
   int h=Profile(symbol,PERIOD_M1,0,14,false,true,false,true);
   bool attached=Ready(h,count)&&ChartIndicatorAdd(chart,0,h);ChartRedraw(chart);Sleep(200);
   bool saved=attached&&ChartSaveTemplate(chart,"Saty_ATR_validation.tpl");
   for(int i=ChartIndicatorsTotal(chart,0)-1;i>=0;i--)ChartIndicatorDelete(chart,0,ChartIndicatorName(chart,0,i));Release(h);
   bool applied=saved&&ChartApplyTemplate(chart,"Saty_ATR_validation.tpl");int own=0;
   ulong until=GetTickCount64()+10000;
   while(applied&&GetTickCount64()<until)
     {own=0;for(int i=0;i<ObjectsTotal(chart,0,-1);i++)if(StringFind(ObjectName(chart,i,0,-1),"SATY_ATR_")==0)own++;if(own>=10)break;ChartRedraw(chart);Sleep(100);}
   Check("NATIVE_PANEL",applied&&own>=10,StringFormat("saved=%d applied=%d own_objects=%d",saved,applied,own));
   string file="Saty_ATR_validation.png";if(FileIsExist(file))FileDelete(file);ChartRedraw(chart);Sleep(300);
   int width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS,0),height=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,0);
   bool shot=ChartScreenShot(chart,file,width,height,ALIGN_RIGHT);for(int i=0;i<30&&!FileIsExist(file);i++)Sleep(100);
   Check("NATIVE_SCREENSHOT",shot&&FileIsExist(file)&&own>=10,StringFormat("canvas=%dx%d",width,height));ChartClose(chart);
  }

void WeeklyOracle(const string symbol,const MqlRates &rates[])
  {
   bool warm=Warm(symbol,PERIOD_W1);MqlRates weekly[];ArraySetAsSeries(weekly,false);
   int weeks=Bars(symbol,PERIOD_W1);warm=warm&&weeks>=4&&CopyRates(symbol,PERIOD_W1,0,weeks,weekly)==weeks;
   int handle=warm?Handle(symbol,PERIOD_M1,1,3):INVALID_HANDLE;Frame f[];
   bool ready=warm&&Ready(handle,144)&&Snapshot(handle,144,f);int bad=0;long values=0;double a[];ArrayResize(a,weeks);ArrayInitialize(a,EMPTY_VALUE);
   bool first_complete=warm&&rates[0].time==weekly[0].time;double sum=0;int valid=0;
   if(ready)
     {
      for(int p=0;p<weeks;p++)
        {
         if(p==0&&!first_complete)continue;
         double tr=weekly[p].high-weekly[p].low;
         if(p>0&&(p>1||first_complete))tr=MathMax(tr,MathMax(MathAbs(weekly[p].high-weekly[p-1].close),MathAbs(weekly[p].low-weekly[p-1].close)));
         valid++;if(valid<=3){sum+=tr;if(valid==3)a[p]=sum/3;}else a[p]=a[p-1]+(tr-a[p-1])/3;
        }
      for(int i=0;i<144;i++)
        {
         int p=-1;for(int j=0;j<weeks;j++)if(weekly[j].time<=rates[i].time)p=j;
         bool previous=p>0&&(p>1||first_complete);
         double anchor=previous?weekly[p-1].close:EMPTY_VALUE,atr=previous?a[p-1]:EMPTY_VALUE;
         if(!Same(f[0].value[i],anchor)||!Same(f[1].value[i],atr))bad++;values+=2;
         for(int r=0;r<15;r++)
           {
            double lower=anchor==EMPTY_VALUE||atr==EMPTY_VALUE?EMPTY_VALUE:anchor-Ratios[r]*atr;
            double upper=anchor==EMPTY_VALUE||atr==EMPTY_VALUE?EMPTY_VALUE:anchor+Ratios[r]*atr;
            if(!Same(f[11+2*r].value[i],lower)||!Same(f[12+2*r].value[i],upper))bad++;values+=2;
           }
         if(CSV!=INVALID_HANDLE)FileWrite(CSV,"WEEKLY","PREVIOUS_RMA3",TimeToString(rates[i].time,TIME_DATE|TIME_SECONDS),1,V(f[1].value[i]),V(atr),Same(f[1].value[i],atr)?"MATCH":"DIFFERENT");
        }
     }
   Check("WEEKLY_RMA_AND_LEVELS",ready&&bad==0,StringFormat("source_weeks=%d first_complete=%d RMA=3 values=%I64d failures=%d",weeks,first_complete,values,bad));Release(handle);
  }

void CurrentTickCheck(const string symbol,const MqlRates &rates[],const int old_handle,const Frame &before[])
  {
   MqlRates bar=rates[143],update[];bar.high+=10;bar.low-=10;bar.close+=4;ArrayResize(update,1);update[0]=bar;
   bool written=SelectFixture(symbol,"CurrentTick history update")&&CustomRatesUpdate(symbol,update)==1&&Warm(symbol,PERIOD_M1,144)&&Warm(symbol,PERIOD_D1,36);
   MqlTick ticks[];ArrayResize(ticks,1);ZeroMemory(ticks[0]);ticks[0].time=bar.time+59;ticks[0].time_msc=(long)ticks[0].time*1000;
   ticks[0].bid=bar.close;ticks[0].ask=bar.close;ticks[0].last=bar.close;ticks[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   written=written&&AddQuote(symbol,ticks,"history update quote");Sleep(150);
   MqlRates observed[];written=written&&CopyRates(symbol,PERIOD_M1,bar.time,bar.time,observed)==1;
   if(written)written=Same(bar.open,observed[0].open)&&Same(bar.high,observed[0].high)&&Same(bar.low,observed[0].low)&&Same(bar.close,observed[0].close);
   int fresh=Handle(symbol,PERIOD_M1,0,14,true,true);Frame now[],oracle[];
   bool ready=written&&Ready(old_handle,144)&&Ready(fresh,144)&&Snapshot(old_handle,144,now)&&Snapshot(fresh,144,oracle);
   int bad=0;long values=0;bool old_stable=ready&&Compare(before,now,143,bad,values);
   Check("CURRENT_TICK_CLOSED_STABILITY",old_stable,StringFormat("closed_values=%I64d failures=%d OHLC_unchanged_by_pulse=%d",values,bad,written));
   bool same=ready&&Compare(now,oracle,144,bad,values);
   bool changed=ready&&!Same(before[1].value[143],now[1].value[143])&&!Same(before[0].value[143],now[0].value[143]);
   Check("CURRENT_TICK_OLD_HANDLE_VS_FRESH",same&&changed,StringFormat("values=%I64d failures=%d current_raw_actually_changed=%d history_write_before_quote=true",values,bad,changed));Release(fresh);
   // A second update is a quote only: no CustomRatesUpdate / Replace occurs.
   // This separately exercises the normal current-bar incremental path.
   MqlTick last;ZeroMemory(last);SymbolInfoTick(symbol,last);
   ticks[0].time_msc=MathMax((long)bar.time*1000+59001,last.time_msc+1);
   ticks[0].time=(datetime)(ticks[0].time_msc/1000);
   double price=bar.high+5;ticks[0].bid=price;ticks[0].ask=price;ticks[0].last=price;
   bool only_tick=ready&&ticks[0].time_msc<(long)(bar.time+60)*1000&&AddQuote(symbol,ticks,"pure incremental quote");Sleep(180);
   MqlRates tick_bar[];only_tick=only_tick&&CopyRates(symbol,PERIOD_M1,bar.time,bar.time,tick_bar)==1;
   if(only_tick)only_tick=Same(tick_bar[0].open,bar.open)&&Same(tick_bar[0].high,price)&&Same(tick_bar[0].low,bar.low)&&Same(tick_bar[0].close,price);
   // A never-used labels profile forces a separately initialized calculation.
   int tick_fresh=Profile(symbol,PERIOD_M1,0,14,true,false,false,false,false);
   Frame tick_now[],tick_oracle[];
   bool tick_ready=only_tick&&Ready(old_handle,144)&&Ready(tick_fresh,144)&&Snapshot(old_handle,144,tick_now)&&Snapshot(tick_fresh,144,tick_oracle);
   same=tick_ready&&Compare(now,tick_now,143,bad,values);
   Check("QUOTE_ONLY_CLOSED_STABILITY",same,StringFormat("values=%I64d failures=%d no_history_write=true observed_OHLC_correct=%d",values,bad,only_tick));
   same=tick_ready&&Compare(tick_now,tick_oracle,144,bad,values);
   changed=tick_ready&&!Same(now[0].value[143],tick_now[0].value[143])&&!Same(now[1].value[143],tick_now[1].value[143]);
   Check("QUOTE_ONLY_INCREMENTAL_VS_FRESH",same&&changed,StringFormat("values=%I64d failures=%d live_raw_actually_changed=%d",values,bad,changed));Release(tick_fresh);
  }

void DayTests()
  {
   MqlRates rates[];Bar days[];DailyFixture(rates,days);string full="SATY_D_"+Tag,prefix="SATY_P_"+Tag,future="SATY_U_"+Tag;
   bool fixture=Create(full,rates)&&Warm(full,PERIOD_D1,36);Check("DAY_FIXTURE",fixture);if(!fixture)return;
   int previous=Handle(full,PERIOD_M1,0),current=Handle(full,PERIOD_M1,0,14,true),hidden=Handle(full,PERIOD_M1,0,14,false,true);
   Frame pf[],cf[],hf[];bool ready=Ready(previous,144)&&Ready(current,144)&&Ready(hidden,144)&&Snapshot(previous,144,pf)&&Snapshot(current,144,cf)&&Snapshot(hidden,144,hf);
   Check("DAY_HANDLES",ready);if(!ready){Release(previous);Release(current);Release(hidden);return;}
   CheckDayOracle(pf,rates,days,false);CheckDayOracle(cf,rates,days,true);
   int bad=0;long checked=0;bool same=Compare(pf,hf,144,bad,checked);Check("DISPLAY_SWITCH_INVARIANCE",same,StringFormat("values=%I64d failures=%d",checked,bad));
   MqlRates part[];ArrayResize(part,79);for(int i=0;i<79;i++)part[i]=rates[i];
   bool prefix_ready=Create(prefix,part)&&Warm(prefix,PERIOD_D1,20);int hp=INVALID_HANDLE;Frame p[];
   if(prefix_ready){hp=Handle(prefix,PERIOD_M1,0,14,true);prefix_ready=Ready(hp,79)&&Snapshot(hp,79,p);}
   same=prefix_ready&&Compare(cf,p,79,bad,checked);Check("CURRENT_MODE_PREFIX_NO_FUTURE",same,StringFormat("values=%I64d failures=%d prefix_bars=79",checked,bad));
   MqlRates changed[];ArrayCopy(changed,rates);for(int i=79;i<144;i++){changed[i].open+=40;changed[i].high+=60;changed[i].low+=30;changed[i].close+=40;}
   bool future_ready=Create(future,changed)&&Warm(future,PERIOD_D1,36);int hu=INVALID_HANDLE;Frame u[];
   if(future_ready){hu=Handle(future,PERIOD_M1,0,14,true);future_ready=Ready(hu,144)&&Snapshot(hu,144,u);}
   same=future_ready&&Compare(cf,u,79,bad,checked);Check("CURRENT_MODE_FUTURE_PERTURBATION",same,StringFormat("values=%I64d failures=%d future_start=79",checked,bad));
   // Same source symbol with a chart starting mid-period is represented by a
   // partial-history custom fixture; its first day's range is deliberately unknown.
   string partial="SATY_H_"+Tag;MqlRates mid[];ArrayResize(mid,143);for(int i=0;i<143;i++)mid[i]=rates[i+1];
   bool mid_ready=Create(partial,mid)&&Warm(partial,PERIOD_D1,36);int hm=INVALID_HANDLE;Frame mf[];
   if(mid_ready){hm=Handle(partial,PERIOD_M1,0,14,true);mid_ready=Ready(hm,143)&&Snapshot(hm,143,mf);}
   bool absent=mid_ready;for(int i=0;i<3&&absent;i++)absent=mf[2].value[i]==EMPTY_VALUE&&mf[3].value[i]==EMPTY_VALUE&&mf[10].value[i]==0;
   Check("FIRST_PARTIAL_PERIOD_EMPTY_RANGE",absent);
   int invalid1=Handle(full,PERIOD_W1,0),invalid2=Handle(full,PERIOD_W1,2),invalid3=Handle(full,PERIOD_M1,0,0);
   // iCustom may return a handle before asynchronous OnInit has rejected it.
   // Do not CopyBuffer here: an invalid handle can spend a long time waiting
   // inside the terminal. Root also verifies the three Chinese init errors.
   Sleep(600);
   int invalid_handles[3];invalid_handles[0]=invalid1;invalid_handles[1]=invalid2;invalid_handles[2]=invalid3;
   bool rejected=true;
   for(int k=0;k<3;k++)
     {
      int calculated=invalid_handles[k]==INVALID_HANDLE?-1:BarsCalculated(invalid_handles[k]);
      Note(StringFormat("INVALID_INIT_OBSERVATION case=%d handle=%d calculated=%d Chinese_OnInit_error_required=true",k,invalid_handles[k],calculated));
      if(invalid_handles[k]!=INVALID_HANDLE&&calculated>0)rejected=false;
     }
   Check("INVALID_PERIOD_INPUTS",rejected,"asynchronous OnInit settled 600ms; correlate 3 Chinese init-failure log entries");
   Release(invalid1);Release(invalid2);Release(invalid3);
   WeeklyOracle(full,rates);CurrentTickCheck(full,rates,current,cf);NativeVisual(full,144);Release(previous);Release(current);Release(hidden);Release(hp);Release(hu);Release(hm);
  }

datetime MonthTime(const int month)
  {MqlDateTime d;ZeroMemory(d);d.year=2000+month/12;d.mon=month%12+1;d.day=1;return StructToTime(d);}
void CalendarTests()
  {
   const int months=192;MqlRates rows[];Bar monthly[];ArrayResize(rows,months*2);ArrayResize(monthly,months);
   for(int m=0;m<months;m++)
     {
      monthly[m].time=MonthTime(m);monthly[m].high=-DBL_MAX;monthly[m].low=DBL_MAX;
      for(int j=0;j<2;j++)
        {
         int k=m*2+j;ZeroMemory(rows[k]);rows[k].time=MonthTime(m)+j*14*86400;
         rows[k].open=NormalizeDouble(100+m*0.2+MathSin(m/3.0)*3+j,2);rows[k].close=rows[k].open+0.5;
         rows[k].high=rows[k].close+1+j;rows[k].low=rows[k].open-1-j;rows[k].tick_volume=100;
         monthly[m].high=MathMax(monthly[m].high,rows[k].high);monthly[m].low=MathMin(monthly[m].low,rows[k].low);monthly[m].close=rows[k].close;
        }
     }
   string symbol="SATY_C_"+Tag;bool fixture=Create(symbol,rows)&&Warm(symbol,PERIOD_MN1,months);Check("CALENDAR_FIXTURE",fixture,"192 months / 2000-2015 / 384 synthetic M1 bars");if(!fixture)return;
   for(int mode=2;mode<=4;mode++)
     {
      int block=mode==2?1:mode==3?3:12,count=months/block;Bar periods[];ArrayResize(periods,count);
      for(int p=0;p<count;p++)
        {
         periods[p].time=monthly[p*block].time;periods[p].high=-DBL_MAX;periods[p].low=DBL_MAX;
         for(int j=0;j<block;j++){periods[p].high=MathMax(periods[p].high,monthly[p*block+j].high);periods[p].low=MathMin(periods[p].low,monthly[p*block+j].low);periods[p].close=monthly[p*block+j].close;}
        }
      double atr[];RMA(periods,14,atr);int h=Handle(symbol,PERIOD_MN1,mode),hc=Handle(symbol,PERIOD_MN1,mode,14,true);Frame f[],c[];
      bool ready=Ready(h,months)&&Ready(hc,months)&&Snapshot(h,months,f)&&Snapshot(hc,months,c);int bad=0,current_bad=0;long values=0;
      if(ready)
        for(int m=0;m<months;m++)
          {
           int p=m/block;double previous=p>0?periods[p-1].close:EMPTY_VALUE,a=p>0?atr[p-1]:EMPTY_VALUE;
           double high=-DBL_MAX,low=DBL_MAX;for(int j=p*block;j<=m;j++){high=MathMax(high,monthly[j].high);low=MathMin(low,monthly[j].low);}
           double current_atr=EMPTY_VALUE,tr=high-low;if(p>0)tr=MathMax(tr,MathMax(MathAbs(high-periods[p-1].close),MathAbs(low-periods[p-1].close)));
           if(p>=14)current_atr=atr[p-1]+(tr-atr[p-1])/14;
           else if(p==13){double sum=tr;for(int k=0;k<13;k++){double t=periods[k].high-periods[k].low;if(k>0)t=MathMax(t,MathMax(MathAbs(periods[k].high-periods[k-1].close),MathAbs(periods[k].low-periods[k-1].close)));sum+=t;}current_atr=sum/14;}
           if(!Same(f[0].value[m],previous)||!Same(f[1].value[m],a)||f[8].value[m]!=(double)periods[p].time||!Same(f[2].value[m],high-low))bad++;
           if(!Same(c[0].value[m],monthly[m].close)||!Same(c[1].value[m],current_atr)||!Same(c[2].value[m],high-low))current_bad++;
           values+=7;
           for(int r=0;r<15;r++)
             {
              double lo=previous==EMPTY_VALUE||a==EMPTY_VALUE?EMPTY_VALUE:previous-Ratios[r]*a,hi=previous==EMPTY_VALUE||a==EMPTY_VALUE?EMPTY_VALUE:previous+Ratios[r]*a;
              if(!Same(f[11+2*r].value[m],lo)||!Same(f[12+2*r].value[m],hi))bad++;values+=2;
             }
           if(CSV!=INVALID_HANDLE)FileWrite(CSV,"CALENDAR",IntegerToString(mode),TimeToString(monthly[m].time,TIME_DATE),1,V(f[1].value[m]),V(a),Same(f[1].value[m],a)?"MATCH":"DIFFERENT");
          }
      Check("CALENDAR_PREVIOUS_ANCHORS",ready&&bad==0,StringFormat("mode=%d months_per_period=%d RMA=14 values=%I64d failures=%d",mode,block,values,bad));
      Check("CALENDAR_DEVELOPING_CURRENT",ready&&current_bad==0,StringFormat("mode=%d months_per_period=%d bars=%d failures=%d",mode,block,months,current_bad));
      Release(h);Release(hc);
     }
  }

void MissingCalendarTests()
  {
   for(int which=0;which<2;which++)
     {
      MqlRates rows[];ArrayResize(rows,0);int original_month[];ArrayResize(original_month,0);
      for(int m=0;m<18;m++)
        {
         if((which==0&&m>=3&&m<=5)||(which==1&&m==2))continue;
         int n=ArraySize(rows);ArrayResize(rows,n+1);ArrayResize(original_month,n+1);ZeroMemory(rows[n]);original_month[n]=m;
         rows[n].time=MonthTime(m);double base=m<(which==0?6:3)?100:200;
         rows[n].open=base+0.2;rows[n].high=base+1;rows[n].low=base;rows[n].close=base+0.5;rows[n].tick_volume=100;
        }
      string symbol="SATY_G"+IntegerToString(which)+"_"+Tag;int count=ArraySize(rows);
      bool ready=Create(symbol,rows)&&Warm(symbol,PERIOD_MN1,count);int hc=INVALID_HANDLE,hp=INVALID_HANDLE,h2=INVALID_HANDLE;Frame c[],p[],two[];
      if(ready){hc=Handle(symbol,PERIOD_MN1,3,1,true);hp=Handle(symbol,PERIOD_MN1,3,1,false);h2=Handle(symbol,PERIOD_MN1,3,2,true);ready=Ready(hc,count)&&Ready(hp,count)&&Ready(h2,count)&&Snapshot(hc,count,c)&&Snapshot(hp,count,p)&&Snapshot(h2,count,two);}
      int restored=which==0?6:3,first=-1,next=-1;
      for(int k=0;k<count;k++){if(original_month[k]==restored)first=k;if(original_month[k]==restored+3)next=k;}
      bool correct=ready&&first>=0&&next>=0;
      if(correct)correct=Same(c[1].value[first],1)&&p[0].value[first]==EMPTY_VALUE&&p[1].value[first]==EMPTY_VALUE&&
                         Same(p[1].value[next],1)&&two[1].value[first]==EMPTY_VALUE&&Same(two[1].value[next],1);
      Check(which==0?"MISSING_WHOLE_QUARTER_SAFE_RESEED":"INCOMPLETE_LAST_MONTH_SAFE_RESEED",correct,
            StringFormat("first_restored_month=%d first_index=%d next_index=%d current_RMA1=%s next_previous_RMA1=%s",
                         restored,first,next,ready?V(c[1].value[first]):"NOT_READY",ready?V(p[1].value[next]):"NOT_READY"));
      Release(hc);Release(hp);Release(h2);
     }
  }

void ZeroTest()
  {
   MqlRates rows[];ArrayResize(rows,12);
   for(int i=0;i<12;i++){ZeroMemory(rows[i]);rows[i].time=D'2026.02.02 00:00:00'+(i/4)*86400+(i%4)*21600;rows[i].open=100;rows[i].high=100;rows[i].low=100;rows[i].close=100;rows[i].tick_volume=100;}
   string symbol="SATY_Z_"+Tag;bool ready=Create(symbol,rows)&&Warm(symbol,PERIOD_D1,3);int h=INVALID_HANDLE;Frame f[];
   if(ready){h=Handle(symbol,PERIOD_M1,0,1);ready=Ready(h,12)&&Snapshot(h,12,f);}
   int bad=0;
   if(ready)for(int i=4;i<12;i++){if(f[0].value[i]!=100||f[1].value[i]!=0||f[2].value[i]!=0||f[3].value[i]!=EMPTY_VALUE||f[4].value[i]!=1)bad++;for(int b=11;b<41;b++)if(f[b].value[i]!=100)bad++;}
   Check("VALID_ZERO_ATR_NO_DIVISION",ready&&bad==0,StringFormat("closed_and_current_samples=8 levels=240 failures=%d",bad));Release(h);
  }
void OnStart()
  {
   Tag=StringFormat("%I64u",GetTickCount64());if(StringLen(Tag)>10)Tag=StringSubstr(Tag,StringLen(Tag)-10);
   Log=FileOpen("Saty_ATR_validation_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);CSV=FileOpen("Saty_ATR_validation_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(CSV!=INVALID_HANDLE)FileWrite(CSV,"fixture","mode","bar_time","buffer","actual","expected","match");
   Note(StringFormat("SYNTHETIC_ONLY|terminal_build=%d run=%s source_seed=first_available_full_period",(int)TerminalInfoInteger(TERMINAL_BUILD),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)));
   DayTests();if(!IsStopped())CalendarTests();if(!IsStopped())MissingCalendarTests();if(!IsStopped())ZeroTest();
   Note("NOT_TESTED|TRADINGVIEW_BROKER_PARITY|MT5 synthetic oracle is not a cross-feed live TradingView parity test.");
   Note(StringFormat("OVERALL=%s groups=%d failures=%d",Failures==0?"PASS":"FAIL",Groups,Failures));if(CSV!=INVALID_HANDLE)FileClose(CSV);if(Log!=INVALID_HANDLE)FileClose(Log);
  }
