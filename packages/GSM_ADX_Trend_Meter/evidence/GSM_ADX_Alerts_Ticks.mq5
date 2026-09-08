// Production alert scheduler validation: after initial rates seed, ONLY ticks
// generate intrabar changes and the next bar. No production source modification.
// EnableAlerts=true, popup/sound/push=false: journal only, no external delivery.
#property strict
#property version "1.00"
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"
const string PATH="GSM\\GSM_ADX_Trend_Meter";
const int N=160;
int Report=INVALID_HANDLE,Groups=0,Failures=0;
string SymbolNameTest="";
double Weak=20,Trend=25,Strong=40;
long LastTickMS=0;
struct Frame {double v[];};
void Note(const string text){Print(text);if(Report!=INVALID_HANDLE){FileWriteString(Report,text+"\r\n");FileFlush(Report);}}
void Check(const string name,const bool okay,const string detail=""){Groups++;if(!okay)Failures++;Note((okay?"PASS|":"FAIL|")+name+"|"+detail);}
bool Valid(const double a){return a!=EMPTY_VALUE&&MathIsValidNumber(a);}
bool Same(const double a,const double b){return (!Valid(a)||!Valid(b))?a==b:MathAbs(a-b)<=1e-8;}
bool Tick(const datetime minute,const int second,const double price)
  {
   if(!SymbolInfoInteger(SymbolNameTest,SYMBOL_SELECT))SymbolSelect(SymbolNameTest,true);
   MqlTick tick[];ArrayResize(tick,1);ZeroMemory(tick[0]);
   long stamp=(long)(minute+second)*1000;if(stamp<=LastTickMS)stamp=LastTickMS+1;
   if(stamp>=(long)(minute+60)*1000){Note("TICK_TIMESTAMP_FAIL");return false;}
   tick[0].time_msc=stamp;tick[0].time=(datetime)(stamp/1000);tick[0].bid=price;tick[0].ask=price;tick[0].last=price;
   tick[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   for(int trial=0;trial<5;trial++)
     {
      if(!SymbolInfoInteger(SymbolNameTest,SYMBOL_SELECT))SymbolSelect(SymbolNameTest,true);
      ResetLastError();int added=CustomTicksAdd(SymbolNameTest,tick);
      if(added==1){LastTickMS=stamp;Sleep(80);return true;}
      Note(StringFormat("TICK_RETRY added=%d error=%d trial=%d",added,GetLastError(),trial));Sleep(150);
     }
   return false;
  }
bool Ready(const int handle,const int bars)
  {
   ulong start=GetTickCount64();double probe[];
   while(!IsStopped()&&GetTickCount64()-start<7000)
     {if(CopyBuffer(handle,0,0,1,probe)==1&&BarsCalculated(handle)==bars)return true;Sleep(40);}
   Note(StringFormat("READY_FAIL handle=%d expected=%d calculated=%d error=%d",handle,bars,BarsCalculated(handle),GetLastError()));return false;
  }
bool Snapshot(const int handle,Frame &f[])
  {
   ArrayResize(f,15);
   for(int b=0;b<15;b++){ArraySetAsSeries(f[b].v,true);if(CopyBuffer(handle,b,0,16,f[b].v)!=16)return false;}
   return true;
  }
bool CurrentEmpty(const Frame &f[]){for(int b=3;b<15;b++)if(f[b].v[0]!=EMPTY_VALUE)return false;return true;}
bool SameClosed(const Frame &a[],const Frame &b[])
  {for(int k=0;k<15;k++)for(int s=1;s<16;s++)if(!Same(a[k].v[s],b[k].v[s]))return false;return true;}
bool Above(const double &a[],const int s){return a[s]>=Trend&&a[s+1]>=Trend;}
bool Rising(const double &a[],const int s){return a[s]>a[s+1]&&a[s+1]>a[s+2]&&a[s+2]>a[s+3];}
bool Low(const double &a[],const int s){for(int i=0;i<10;i++)if(a[s+i]>=Weak)return false;return true;}
int Crosses(const double &p[],const double &m[],const int s)
  {
   int count=0;for(int i=0;i<10;i++)if((p[s+i]>m[s+i]&&p[s+i+1]<=m[s+i+1]) ||
      (m[s+i]>p[s+i]&&m[s+i+1]<=p[s+i+1]))count++;return count;
  }
int ExpectedMask(const Frame &f[],const int s)
  {
   int mask=0;
   if(f[0].v[s]>Weak&&f[0].v[s+1]<=Weak)mask|=1;
   if(f[0].v[s]>Trend&&f[0].v[s+1]<=Trend)mask|=2;
   bool up=f[0].v[s]>f[0].v[s+1];
   if(up&&f[1].v[s]>f[2].v[s]&&f[1].v[s+1]<=f[2].v[s+1])mask|=4;
   if(up&&f[2].v[s]>f[1].v[s]&&f[2].v[s+1]<=f[1].v[s+1])mask|=8;
   if(f[0].v[s+1]>Strong&&f[0].v[s]<f[0].v[s+1]&&f[0].v[s+1]>=f[0].v[s+2])mask|=16;
   if(Above(f[0].v,s)&&!Above(f[0].v,s+1))mask|=32;
   if(Rising(f[0].v,s)&&!Rising(f[0].v,s+1))mask|=64;
   if(Low(f[0].v,s)&&!Low(f[0].v,s+1))mask|=128;
   bool now=f[0].v[s]<Weak&&Crosses(f[1].v,f[2].v,s)>=3;
   bool prior=f[0].v[s+1]<Weak&&Crosses(f[1].v,f[2].v,s+1)>=3;
   if(now&&!prior)mask|=256;
   return mask;
  }
string Event(const int e,const double adx)
  {
   switch(e)
     {
      case 0:return StringFormat("ADX 上穿 %g，关注趋势形成",Weak);
      case 1:return StringFormat("ADX 上穿 %g，强度提升",Trend);
      case 2:return "偏多 DI 交叉，趋势强度增强"+(adx<Weak?"（强度仍低，尚未形成明显趋势）":"");
      case 3:return "偏空 DI 交叉，趋势强度增强"+(adx<Weak?"（强度仍低，尚未形成明显趋势）":"");
      case 4:return "ADX 高位转弱，检查持仓保护";
      case 5:return StringFormat("ADX 连续 2 根站稳 %g",Trend);
      case 6:return "ADX 连续 3 次比较增强";
      case 7:return "趋势偏弱持续 10 根";
      case 8:return "低 ADX + DI 反复交叉，震荡风险较高";
     }
   return "";
  }
string Events(const int mask,const double adx)
  {string text="";for(int e=0;e<9;e++)if((mask&(1<<e))!=0){if(text!="")text+="；";text+=Event(e,adx);}return text;}
void Run()
  {
   MqlRates rates[];ArrayResize(rates,N);
   for(int k=0;k<N;k++)
     {
      ZeroMemory(rates[k]);rates[k].time=D'2026.06.08 00:00'+60*k;
      rates[k].open=k==0?3000:rates[k-1].close;
      rates[k].close=NormalizeDouble(3000+5*MathSin(k/2.2)+2*MathSin(k/0.7),2);
      rates[k].high=NormalizeDouble(MathMax(rates[k].open,rates[k].close)+0.5,2);
      rates[k].low=NormalizeDouble(MathMin(rates[k].open,rates[k].close)-0.5,2);rates[k].tick_volume=100;
     }
   SymbolNameTest="AQT_"+IntegerToString((long)(GetTickCount64()%10000000));
   bool made=CustomSymbolCreate(SymbolNameTest,"GSM_ADX_Quote_Validation");
   if(made)
     {
      CustomSymbolSetInteger(SymbolNameTest,SYMBOL_DIGITS,2);CustomSymbolSetDouble(SymbolNameTest,SYMBOL_POINT,0.01);
      CustomSymbolSetInteger(SymbolNameTest,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
      made=CustomRatesUpdate(SymbolNameTest,rates)==N&&SymbolSelect(SymbolNameTest,true);
     }
   Check("SEED_HISTORY_ONCE",made,"symbol="+SymbolNameTest+"; all subsequent mutations use CustomTicksAdd only");if(!made)return;
   MqlRates warm[];CopyRates(SymbolNameTest,PERIOD_M1,0,N,warm);
   datetime current=rates[N-1].time;
   bool pulse=Tick(current,10,10000.0);int oracle=iADXWilder(SymbolNameTest,PERIOD_M1,14);
   double a[];ArraySetAsSeries(a,true);
   bool prepared=pulse&&Ready(oracle,N)&&CopyBuffer(oracle,0,0,2,a)==2&&Valid(a[0])&&Valid(a[1])&&a[0]>a[1]+0.1;
   Check("PREPARE_ADAPTIVE_THRESHOLDS",prepared);if(!prepared){if(oracle>=0)IndicatorRelease(oracle);return;}
   Weak=a[1]+(a[0]-a[1])/3;Trend=a[1]+2*(a[0]-a[1])/3;Strong=MathMin(99.9,Trend+20);
   if(!(0<Weak&&Weak<Trend&&Trend<Strong&&Strong<100)){Check("THRESHOLD_VALID",false);IndicatorRelease(oracle);return;}
   Note(StringFormat("PARAMETERS|symbol=%s method=WILDER period=14 weak=%.17g trend=%.17g strong=%.17g alerts=true popup=false sound=false push=false",SymbolNameTest,Weak,Trend,Strong));
   Note("PHASE|INITIAL_LOAD_BEGIN|symbol="+SymbolNameTest+" expected_alerts=0");
   int h=iCustom(SymbolNameTest,PERIOD_M1,PATH,"",0,14,Weak,Trend,Strong,0.0,2,3,10,10,3,false,25.0,
      "",false,false,false,false,500,clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
      CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,"",true,false,false,false);
   Frame baseline[],live[];bool loaded=Ready(h,N)&&Snapshot(h,baseline)&&CurrentEmpty(baseline);
   Check("INITIAL_CONFIRMED_DATA",loaded);Sleep(300);Note("PHASE|INITIAL_LOAD_END|symbol="+SymbolNameTest+" expected_alerts=0");
   if(!loaded){if(h>=0)IndicatorRelease(h);IndicatorRelease(oracle);return;}
   bool unchanged=true;int changes=0;
   Note("PHASE|INTRABAR_BEGIN|symbol="+SymbolNameTest+" expected_alerts=0");
   for(int k=0;k<6;k++)
     {
      double price=k%2==0?20000.0+5000*k:2000.0-100*k;
      if(!Tick(current,20+k*5,price)||!Ready(h,N)||!Snapshot(h,live)){unchanged=false;break;}
      unchanged=unchanged&&CurrentEmpty(live)&&SameClosed(baseline,live);
      for(int b=0;b<3;b++)if(!Same(live[b].v[0],baseline[b].v[0]))changes++;
     }
   if(!Tick(current,58,1000000.0)||!Ready(h,N)||!Snapshot(h,live))unchanged=false;
   bool pending=unchanged&&live[0].v[0]>Trend&&live[0].v[1]<=Weak;
   Check("UNFINISHED_MULTI_TICK_NO_CONFIRMED_EVENT",pending&&changes>0,StringFormat("live_raw_changes=%d closed_buffers_unchanged=%d",changes,unchanged));
   Note("PHASE|INTRABAR_END|symbol="+SymbolNameTest+" expected_alerts=0");
   if(!pending){IndicatorRelease(h);IndicatorRelease(oracle);return;}
   Note("PHASE|NEW_BAR_BEGIN|symbol="+SymbolNameTest);
   bool next=Tick(current+60,1,1000001.0)&&Ready(h,N+1)&&Snapshot(h,live)&&CurrentEmpty(live);
   int expected=next?ExpectedMask(live,1):0,actual=0;
   if(next)for(int e=0;e<9;e++)if(live[6+e].v[1]==1)actual|=1<<e;
   bool verified=next&&expected==actual&&(expected&3)==3;
   Check("CLOSE_CONFIRMS_MULTIPLE_EVENTS",verified,StringFormat("expected_mask=%d actual_mask=%d",expected,actual));
   if(verified)
      Note(StringFormat("EXPECTED_ALERT|symbol=%s|tf=M1|bar=%s|mask=%d|count=1|events=%s",
         SymbolNameTest,TimeToString(current,TIME_DATE|TIME_MINUTES),expected,Events(expected,live[0].v[1])));
   Frame confirmed[];bool stable=Snapshot(h,confirmed);
   Note("PHASE|SAME_BAR_DEDUP_BEGIN|symbol="+SymbolNameTest+" expected_additional_alerts=0");
   for(int k=0;k<12&&stable;k++)
     {
      stable=Tick(current+60,2+k*3,1000001.0+(k%2==0?100.0:-100.0))&&Ready(h,N+1)&&Snapshot(h,live)&&
         CurrentEmpty(live)&&SameClosed(confirmed,live);
     }
   Check("SAME_BAR_12_TICKS_CONFIRMED_STABLE",stable);
   Sleep(500);Note("PHASE|SAME_BAR_DEDUP_END|symbol="+SymbolNameTest+" expected_total_alerts=1");
   Note("LOG_VERIFICATION_REQUIRED|Compare production GSM_ADX_ALERT_CONFIRMED lines for this unique symbol against EXPECTED_ALERT; exactly one merged line and no initial/intrabar/dedup extra lines.");
   IndicatorRelease(h);IndicatorRelease(oracle);
  }
void OnStart()
  {
   Report=FileOpen("GSM_ADX_Alerts_Ticks_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("INFO|SYNTHETIC_QUOTE_ONLY_SCHEDULER|Unmodified production EX5; initial rates seed once; all delivery channels false.");
   Run();Note(StringFormat("BUFFER_SCOPE=%s groups=%d failures=%d; final alert-dispatch verdict requires matching native journal",Failures==0?"PASS":"FAIL",Groups,Failures));
   if(Report!=INVALID_HANDLE)FileClose(Report);
  }
