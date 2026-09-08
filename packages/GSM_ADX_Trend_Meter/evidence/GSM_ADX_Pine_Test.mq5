// Independent native-MT5 validation of the supplied BeikabuOyaji Pine formula.
// Synthetic custom-symbol data only. No trading, account or notification calls.
#property strict
#property version "1.00"
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"

const string PATH="GSM\\GSM_ADX_Trend_Meter";
const int N=180;
int Report=INVALID_HANDLE,CSV=INVALID_HANDLE,Groups=0,Failed=0,Skipped=0;
string Suffix="";
ulong Started=0;
struct Frame { double v[]; };

void Note(const string text)
  { Print(text); if(Report!=INVALID_HANDLE) {FileWriteString(Report,text+"\r\n");FileFlush(Report);} }
void Check(const string label,const bool okay,const string detail="")
  { Groups++;if(!okay)Failed++;Note((okay?"PASS|":"FAIL|")+label+"|"+detail); }
bool Valid(const double v) {return v!=EMPTY_VALUE&&MathIsValidNumber(v);}
bool Same(const double a,const double b)
  { return (!Valid(a)||!Valid(b)) ? a==b : MathAbs(a-b)<=1e-8; }
string V(const double value) {return value==EMPTY_VALUE?"EMPTY_VALUE":DoubleToString(value,16);}
string Sym(const string key) {return "PAX_"+key+"_"+Suffix;}

void Rates(MqlRates &rates[],const int size=180,const int kind=0)
  {
   ArrayResize(rates,size);
   for(int k=0;k<size;k++)
     {
      ZeroMemory(rates[k]);rates[k].time=D'2026.06.01 00:00:00'+60*k;
      rates[k].open=k==0?3000.0:rates[k-1].close;
      rates[k].close=NormalizeDouble(3000+16*MathSin(k/8.7)+5*MathSin(k/2.3)+0.02*k,2);
      rates[k].high=NormalizeDouble(MathMax(rates[k].open,rates[k].close)+0.8+0.3*(1+MathSin(k/3.1)),2);
      rates[k].low=NormalizeDouble(MathMin(rates[k].open,rates[k].close)-0.7-0.2*(1+MathCos(k/2.7)),2);
      if(kind==1) rates[k].open=rates[k].high=rates[k].low=rates[k].close=100.0;
      if(kind==2) { rates[k].open=10;rates[k].high=100;rates[k].low=-100;rates[k].close=10; }
      if(kind==3)
        {
         if(k==0) {rates[k].open=3.5;rates[k].high=4;rates[k].low=3;rates[k].close=3.5;}
         else if(k==1) {rates[k].open=3.5;rates[k].high=4;rates[k].low=1;rates[k].close=2;}
         else {rates[k].open=2.5;rates[k].high=3;rates[k].low=2;rates[k].close=2.5;}
        }
      rates[k].tick_volume=100;rates[k].spread=0;
     }
  }

// Independent oracle: direct chronological recurrence, followed by a fresh
// backward scan and ordinary sum of the N valid DX samples for EVERY output.
// This does not copy the production ring buffer or its cached accumulator.
void Oracle(const MqlRates &rates[],const int size,const int period,Frame &expected[],double &dx[])
  {
   ArrayResize(expected,3);ArrayResize(dx,size);ArrayInitialize(dx,EMPTY_VALUE);
   for(int b=0;b<3;b++){ArrayResize(expected[b].v,size);ArrayInitialize(expected[b].v,EMPTY_VALUE);}
   double smtr=0,smp=0,smm=0;
   for(int k=0;k<size;k++)
     {
      double pc=k>0?rates[k-1].close:0.0;
      double ph=k>0?rates[k-1].high:0.0;
      double pl=k>0?rates[k-1].low:0.0;
      double tr=MathMax(MathMax(rates[k].high-rates[k].low,MathAbs(rates[k].high-pc)),MathAbs(rates[k].low-pc));
      double up=rates[k].high-ph,dn=pl-rates[k].low;
      double dmplus=up>dn?MathMax(up,0):0;
      double dmminus=dn>up?MathMax(dn,0):0;
      smtr=smtr-smtr/period+tr;smp=smp-smp/period+dmplus;smm=smm-smm/period+dmminus;
      if(smtr!=0)
        {
         expected[1].v[k]=smp/smtr*100;expected[2].v[k]=smm/smtr*100;
         double denominator=expected[1].v[k]+expected[2].v[k];
         if(denominator!=0)dx[k]=MathAbs(expected[1].v[k]-expected[2].v[k])/denominator*100;
        }
      double total=0;int count=0;
      for(int j=k;j>=0 && count<period;j--)if(Valid(dx[j])){total+=dx[j];count++;}
      if(count==period)expected[0].v[k]=total/period;
     }
  }
bool Warm(const string symbol,const int size)
  {
   ulong begin=GetTickCount64();MqlRates data[];
   while(!IsStopped()&&GetTickCount64()-begin<3000)
     {if(CopyRates(symbol,PERIOD_M1,0,size,data)==size&&Bars(symbol,PERIOD_M1)==size)return true;Sleep(20);}
   Note(StringFormat("WARM_FAIL symbol=%s expected=%d bars=%d error=%d",symbol,size,Bars(symbol,PERIOD_M1),GetLastError()));return false;
  }
bool Create(const string symbol,const MqlRates &source[],const int size)
  {
   bool custom=false;if(SymbolExist(symbol,custom))return false;
   if(!CustomSymbolCreate(symbol,"GSM_ADX_Pine_Validation"))return false;
   CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2);CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01);
   CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
   MqlRates copy[];ArrayResize(copy,size);for(int k=0;k<size;k++)copy[k]=source[k];
   bool result=CustomRatesReplace(symbol,copy[0].time,copy[size-1].time,copy)==size && SymbolSelect(symbol,true) && Warm(symbol,size);
   if(!result)Note(StringFormat("FIXTURE_FAIL symbol=%s size=%d error=%d",symbol,size,GetLastError()));
   return result;
  }
int Handle(const string symbol,const int period,const bool alternate=false)
  {
   return iCustom(symbol,PERIOD_M1,PATH,"",2,period,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
                  "",false,!alternate,alternate,false,alternate?7:500,
                  clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
                  CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,
                  "",alternate,false,false,false);
  }
bool Snapshot(const int handle,const int size,Frame &data[])
  {
   if(handle==INVALID_HANDLE || BarsCalculated(handle)!=size)return false;
   ArrayResize(data,15);
   for(int b=0;b<15;b++){ArraySetAsSeries(data[b].v,false);if(CopyBuffer(handle,b,0,size,data[b].v)!=size)return false;}
   return true;
  }
bool Numeric(const Frame &actual[],const Frame &expected[],const int size,long &values,int &bad,double &maximum)
  {
   values=0;bad=0;maximum=0;
   if(ArraySize(actual)<3 || ArraySize(expected)<3)return false;
   for(int b=0;b<3;b++)
      for(int k=0;k<size;k++)
        {
         values++;if(!Same(actual[b].v[k],expected[b].v[k]))bad++;
         if(Valid(actual[b].v[k])&&Valid(expected[b].v[k]))maximum=MathMax(maximum,MathAbs(actual[b].v[k]-expected[b].v[k]));
        }
   return bad==0;
  }
bool Await(const int handle,const MqlRates &source[],const int size,const int period,Frame &actual[],const int timeout=5000)
  {
   Frame expected[];double dx[];Oracle(source,size,period,expected,dx);
   ulong begin=GetTickCount64();long count=0;int bad=0;double maximum=0;
   while(!IsStopped()&&GetTickCount64()-begin<(ulong)timeout)
     {
      double probe[];if(handle!=INVALID_HANDLE)CopyBuffer(handle,0,0,1,probe);
      if(Snapshot(handle,size,actual)&&Numeric(actual,expected,size,count,bad,maximum))return true;Sleep(20);
     }
   Note(StringFormat("AWAIT_FAIL handle=%d period=%d expectedbars=%d calculated=%d values=%I64d bad=%d max=%.17g error=%d",
      handle,period,size,BarsCalculated(handle),count,bad,maximum,GetLastError()));return false;
  }
bool ClosedEqual(const Frame &left[],const Frame &right[],const int size,long &values,int &bad,const bool exact=false)
  {
   values=0;bad=0;
   if(ArraySize(left)!=15 || ArraySize(right)!=15)return false;
   for(int b=0;b<15;b++)for(int k=0;k<size;k++)
     {
      values++;bool same=exact?left[b].v[k]==right[b].v[k]:Same(left[b].v[k],right[b].v[k]);
      if(!same){if(bad<3)Note(StringFormat("DIFF buffer=%d chrono=%d left=%.17g right=%.17g",b,k,left[b].v[k],right[b].v[k]));bad++;}
     }
   return bad==0;
  }
bool CurrentEmpty(const Frame &data[],const int size)
  {for(int b=3;b<15;b++)if(data[b].v[size-1]!=EMPTY_VALUE)return false;return true;}
bool Pulse(const string symbol,const MqlRates &bar)
  {
   if(!SymbolInfoInteger(symbol,SYMBOL_SELECT) && !SymbolSelect(symbol,true))
     {Note(StringFormat("PULSE_SELECT_FAIL symbol=%s error=%d",symbol,GetLastError()));return false;}
   MqlTick prior,ticks[];ZeroMemory(prior);ArrayResize(ticks,1);ZeroMemory(ticks[0]);
   long stamp=(long)bar.time*1000+59000;
   if(SymbolInfoTick(symbol,prior)&&prior.time_msc>=stamp)stamp=prior.time_msc+1;
   if(stamp>=(long)(bar.time+60)*1000){Note("PULSE_TIMESTAMP_FAIL "+symbol);return false;}
   ticks[0].time_msc=stamp;ticks[0].time=(datetime)(stamp/1000);ticks[0].bid=bar.close;ticks[0].ask=bar.close;ticks[0].last=bar.close;
   ticks[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   ResetLastError();int added=CustomTicksAdd(symbol,ticks);
   if(added!=1){Note(StringFormat("PULSE_ADD_FAIL symbol=%s added=%d selected=%d error=%d",symbol,added,(int)SymbolInfoInteger(symbol,SYMBOL_SELECT),GetLastError()));return false;}
   MqlRates seen[];int copied=CopyRates(symbol,PERIOD_M1,bar.time,bar.time,seen);
   if(copied!=1){Note(StringFormat("PULSE_VERIFY_COPY_FAIL symbol=%s copied=%d error=%d",symbol,copied,GetLastError()));return false;}
   bool same=Same(seen[0].open,bar.open)&&Same(seen[0].high,bar.high)&&Same(seen[0].low,bar.low)&&Same(seen[0].close,bar.close);
   if(!same)Note(StringFormat("PULSE_OHLC_MISMATCH %s expected=%.8f/%.8f/%.8f/%.8f actual=%.8f/%.8f/%.8f/%.8f",
      symbol,bar.open,bar.high,bar.low,bar.close,seen[0].open,seen[0].high,seen[0].low,seen[0].close));
   return same;
  }
bool Update(const string symbol,const MqlRates &source[],const int size,const int handle,const int period,Frame &actual[])
  {
   MqlRates one[];ArrayResize(one,1);one[0]=source[size-1];
   for(int attempt=0;attempt<5;attempt++)
     {
      if(!SymbolInfoInteger(symbol,SYMBOL_SELECT))SymbolSelect(symbol,true);
      ResetLastError();int updated=CustomRatesUpdate(symbol,one);
      if(updated!=1)
        {Note(StringFormat("UPDATE_IO_RETRY symbol=%s size=%d attempt=%d updated=%d error=%d",symbol,size,attempt,updated,GetLastError()));Sleep(100);continue;}
      if(!Warm(symbol,size)){Sleep(100);continue;}
      if(!Pulse(symbol,source[size-1])){Sleep(100);continue;}
      if(Await(handle,source,size,period,actual,1200))
        {if(attempt>0)Note(StringFormat("UPDATE_IO_RECOVERED symbol=%s size=%d attempt=%d",symbol,size,attempt));return true;}
     }
   Note(StringFormat("UPDATE_FAILED symbol=%s size=%d period=%d",symbol,size,period));
   return false;
  }
void SaveCSV(const string tag,const int period,const MqlRates &rates[],const Frame &actual[],const Frame &expected[],const double &dx[],const int size)
  {
   if(CSV==INVALID_HANDLE)return;
   for(int k=0;k<size;k++)
     {
      string row=tag+","+IntegerToString(period)+","+IntegerToString(k)+","+TimeToString(rates[k].time,TIME_DATE|TIME_MINUTES)+","+
         V(rates[k].open)+","+V(rates[k].high)+","+V(rates[k].low)+","+V(rates[k].close)+","+V(dx[k]);
      for(int b=0;b<3;b++)row+=","+V(expected[b].v[k]);
      for(int b=0;b<15;b++)row+=","+V(actual[b].v[k]);
      FileWriteString(CSV,row+"\r\n");
     }
   FileFlush(CSV);
  }
void MainPeriod(const int period,const MqlRates &source[])
  {
   string key="period="+IntegerToString(period),full=Sym("F"+IntegerToString(period)),prefix=Sym("P"+IntegerToString(period)),future=Sym("U"+IntegerToString(period));
   MqlRates changed[];ArrayResize(changed,N);for(int k=0;k<N;k++)changed[k]=source[k];
   for(int k=80;k<N;k++){changed[k].open+=500;changed[k].high+=600;changed[k].low+=400;changed[k].close+=550;}
   bool fixture=Create(full,source,N)&&Create(prefix,source,80)&&Create(future,changed,N);
   Check("PINE_FIXTURES",fixture,key);if(!fixture)return;
   int hf=Handle(full,period),hp=Handle(prefix,period),hu=Handle(future,period),hv=Handle(full,period,true);
   Frame main[],partial[],perturbed[],visual[];Frame expected[];double dx[];
   bool ready=Await(hf,source,N,period,main)&&Await(hp,source,80,period,partial)&&Await(hu,changed,N,period,perturbed)&&Await(hv,source,N,period,visual);
   Check("PINE_READY",ready,key);if(!ready){if(hf>=0)IndicatorRelease(hf);if(hp>=0)IndicatorRelease(hp);if(hu>=0)IndicatorRelease(hu);if(hv>=0)IndicatorRelease(hv);return;}
   Oracle(source,N,period,expected,dx);long values=0;int bad=0;double maximum=0;
   bool numeric=Numeric(main,expected,N,values,bad,maximum);
   Check("PINE_INDEPENDENT_FORMULA",numeric,key+StringFormat(" samples=%d values=%I64d failures=%d max_abs_error=%.17g from=%s to=%s",
      N,values,bad,maximum,TimeToString(source[0].time,TIME_DATE|TIME_MINUTES),TimeToString(source[N-1].time,TIME_DATE|TIME_MINUTES)));
   SaveCSV("MAIN",period,source,main,expected,dx,N);
   bool equal=ClosedEqual(main,partial,79,values,bad,true);
   Check("PINE_PREFIX_ALL15_EXACT",equal,key+StringFormat(" values=%I64d failures=%d",values,bad));
   equal=ClosedEqual(main,perturbed,79,values,bad,true);
   Check("PINE_FUTURE_PERTURB_ALL15_EXACT",equal,key+StringFormat(" values=%I64d failures=%d",values,bad));
   equal=ClosedEqual(main,visual,N-1,values,bad,true)&&CurrentEmpty(main,N)&&CurrentEmpty(visual,N);
   Check("PINE_VISUAL_ALERT_SWITCHES_ALL15",equal,key+StringFormat(" values=%I64d failures=%d",values,bad));
   bool replay=true;long total_values=0;int steps=0;
   for(int size=81;size<=N && replay&&!IsStopped();size++)
     {
      replay=Update(prefix,source,size,hp,period,partial);
      if(replay)replay=ClosedEqual(main,partial,size-1,values,bad,true)&&CurrentEmpty(partial,size);
      total_values+=values;steps++;
     }
   Check("PINE_APPEND_EVERY_BAR_ALL15_EXACT",replay&&steps==N-80,key+StringFormat(" replay_steps=%d values=%I64d",steps,total_values));
   Frame baseline[];bool snap=Snapshot(hf,N,baseline),stable=snap;int mutations=0;
   for(int attempt=0;attempt<4 && stable;attempt++)
     {
      MqlRates mutate[];ArrayResize(mutate,N);for(int k=0;k<N;k++)mutate[k]=source[k];
      mutate[N-1].high+=20+attempt*10;mutate[N-1].low-=10+attempt*5;
      mutate[N-1].close=(attempt%2==0?mutate[N-1].high-1:mutate[N-1].low+1);
      Frame snapshot[];stable=Update(full,mutate,N,hf,period,snapshot);
      if(stable)stable=ClosedEqual(baseline,snapshot,N-1,values,bad,true)&&CurrentEmpty(snapshot,N);
      mutations++;
     }
   Check("PINE_CURRENT_OHLC_CLOSED15_UNCHANGED",stable&&mutations==4,key+StringFormat(" mutations=%d last_values=%I64d",mutations,values));
   IndicatorRelease(hf);IndicatorRelease(hp);IndicatorRelease(hu);IndicatorRelease(hv);
  }
void Edge(const string label,const int kind,const int size,const int period)
  {
   MqlRates source[];Rates(source,size,kind);string symbol=Sym(label);
   bool fixture=Create(symbol,source,size);Check("PINE_EDGE_FIXTURE_"+label,fixture);if(!fixture)return;
   int h=Handle(symbol,period);Frame actual[],expected[];double dx[];
   bool ready=Await(h,source,size,period,actual);Oracle(source,size,period,expected,dx);
   long values=0;int bad=0;double maximum=0;
   bool exact=ready&&Numeric(actual,expected,size,values,bad,maximum);
   Check("PINE_EDGE_FORMULA_"+label,exact,StringFormat(" period=%d samples=%d values=%I64d failures=%d max=%.17g",period,size,values,bad,maximum));
   if(ready)
     {
      SaveCSV(label,period,source,actual,expected,dx,size);
      if(kind==1 && size<500)
         Check("PINE_FLAT_POSITIVE_SEED_IS_100",Same(actual[1].v[0],100)&&actual[2].v[0]==0&&Same(actual[0].v[period-1],100)&&
            actual[0].v[period-2]==EMPTY_VALUE,"first high/low/close=100; prior OHLC=0; first TR=100; first +DM=100; no false zero warm-up");
      if(kind==2)
        {
         bool okay=true;for(int k=0;k<size;k++)if(actual[1].v[k]!=0||actual[2].v[k]!=0||actual[0].v[k]!=EMPTY_VALUE)okay=false;
         Check("PINE_ZERO_DI_SUM_DX_UNAVAILABLE",okay,"valid nonzero TR; +DI=-DI=0 are valid; DX 0/0 and ADX are EMPTY");
        }
      if(kind==3)
         Check("PINE_VALID_ZERO_ADX_PRESERVED",actual[0].v[2]==0&&actual[1].v[2]>0&&actual[2].v[2]>0&&actual[3].v[2]==0&&
            actual[4].v[2]==0,"period2; first DX100 then two DX0 with valid positive DI denominator; ADX0 is valid weak state");
      if(kind==1 && size>500)
        {
         int gaps=0;for(int k=0;k<size;k++)if(!Valid(dx[k]))gaps++;
         if(gaps>0)
           {
            bool okay=actual[1].v[size-1]==EMPTY_VALUE&&actual[2].v[size-1]==EMPTY_VALUE&&Same(actual[0].v[size-1],100);
            Check("PINE_SMA_IGNORES_NA_AFTER_VALID_HISTORY",okay,StringFormat(" unavailable_DX_bars=%d; underflow makes smTR=0 and DI unavailable; last N valid DX100 retained",gaps));
           }
         else
           {
            Skipped++;
            Note("NOT_TESTED|PINE_SMA_POST_WARMUP_NA_TRANSITION|This native finite-OHLC fixture retained subnormal smTR; no post-warmup DX gap occurred. Long flat numeric oracle comparison is reported separately.");
           }
        }
     }
   if(h!=INVALID_HANDLE)IndicatorRelease(h);
  }
void OnStart()
  {
   Started=GetTickCount64();Suffix=IntegerToString((long)(Started%1000000));
   Report=FileOpen("GSM_ADX_Pine_Test.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   CSV=FileOpen("GSM_ADX_Pine_Test.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(Report==INVALID_HANDLE || CSV==INVALID_HANDLE){Print("Pine test output files cannot be opened.");return;}
   string header="fixture,period,chronological,time,open,high,low,close,oracle_dx,oracle_adx,oracle_plus,oracle_minus";
   for(int b=0;b<15;b++)header+=",actual_buffer"+IntegerToString(b);FileWriteString(CSV,header+"\r\n");
   Note("INFO|PINE_TEST|synthetic M1 custom symbols; native terminal executable; all external delivery channels disabled");
   Note("INFO|ORACLE|independent supplied recurrence + fresh scan of last N valid DX per bar; tolerance1e-8; all15 consistency exact");
   MqlRates source[];Rates(source);
   int periods[4]={14,2,7,30};for(int j=0;j<4&&!IsStopped();j++)MainPeriod(periods[j],source);
   Edge("FLAT",1,80,14);Edge("NADX",2,80,14);Edge("ZERO",3,40,2);Edge("GAPS",1,1300,2);
   Note(StringFormat("OVERALL=%s groups=%d passed=%d failed=%d not_tested=%d elapsed_ms=%I64u",Failed==0?"PASS":"FAIL",Groups,Groups-Failed,Failed,Skipped,GetTickCount64()-Started));
   FileClose(CSV);FileClose(Report);
  }
