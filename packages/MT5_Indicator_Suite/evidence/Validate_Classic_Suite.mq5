// Synthetic-data runtime validation only. No accounts, orders or external calls.
#property strict
#property version "1.00"

struct Metric
  {
   string name;
   int samples;
   int failures;
   double max_error;
  };
Metric Metrics[];
int Summary=INVALID_HANDLE;
ulong Started=0;
const int N=5000;
const string Sym="CODEX_SUITE_CLASSIC";
const string FlatSym="CODEX_SUITE_CLASSIC_FLAT";

int AddMetric(const string name)
  {
   int n=ArraySize(Metrics);
   ArrayResize(Metrics,n+1);
   Metrics[n].name=name;
   Metrics[n].samples=0;
   Metrics[n].failures=0;
   Metrics[n].max_error=0.0;
   return(n);
  }

bool Good(const double x)
  {
   return(x!=EMPTY_VALUE && MathIsValidNumber(x));
  }

void Compare(const int metric,const double actual,const double expected,const double tolerance=1e-8)
  {
   Metrics[metric].samples++;
   if(!Good(actual) || !Good(expected))
     {
      Metrics[metric].failures++;
      Metrics[metric].max_error=1e100;
      return;
     }
   double err=MathAbs(actual-expected);
   if(err>Metrics[metric].max_error) Metrics[metric].max_error=err;
   if(err>tolerance) Metrics[metric].failures++;
  }

void Condition(const int metric,const bool okay)
  {
   Compare(metric,okay ? 1.0 : 0.0,1.0,0.0);
  }

void Note(const string message)
  {
   Print(message);
   if(Summary!=INVALID_HANDLE) { FileWrite(Summary,message); FileFlush(Summary); }
  }

void Finish()
  {
   int failures=0;
   for(int i=0;i<ArraySize(Metrics);i++)
     {
      string verdict=(Metrics[i].samples>0 && Metrics[i].failures==0) ? "PASS" : "FAIL";
      if(verdict=="FAIL") failures++;
      Note(StringFormat("%s | %s | samples=%d | failures=%d | max_error=%.12g",
                        verdict,Metrics[i].name,Metrics[i].samples,Metrics[i].failures,Metrics[i].max_error));
     }
   Note(StringFormat("OVERALL=%s | metric_groups=%d | failed_groups=%d | elapsed_ms=%I64u",
                     failures==0 ? "PASS" : "FAIL",ArraySize(Metrics),failures,GetTickCount64()-Started));
   if(Summary!=INVALID_HANDLE) { FileFlush(Summary); FileClose(Summary); Summary=INVALID_HANDLE; }
  }

bool CreateData(const string symbol,const bool flat,MqlRates &rates[])
  {
   ResetLastError();
   bool is_custom=false;
   bool exists=SymbolExist(symbol,is_custom);
   if((exists && !is_custom) || (!exists && !CustomSymbolCreate(symbol,"CodexValidation")))
     {
      Note(StringFormat("CustomSymbolCreate failed %s error=%d",symbol,GetLastError()));
      return(false);
     }
   if(!CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,5) ||
      !CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.00001) ||
      !CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED))
      return(false);
   ArrayResize(rates,N);
   const datetime first=D'2026.01.05 00:00:00';
   double previous=100.0;
   for(int i=0;i<N;i++)
     {
      double c=100.0;
      if(!flat)
        {
         c=100.0+1.5*MathSin(i*0.13)+0.7*MathSin(i*0.037);
         if(i%80==20) c=60.0;
         if(i%80==21) c=((i/80)%3==1 ? 101.0 : 100.0);
         if(i%80==60) c=140.0;
         if(i%80==61) c=((i/80)%3==1 ? 99.0 : 100.0);
         if(i==N-2) c=60.0;
         if(i==N-1) c=100.0;
         c=NormalizeDouble(c,5);
        }
      rates[i].time=first+i*60;
      rates[i].open=previous;
      rates[i].close=c;
      rates[i].high=flat ? c : MathMax(previous,c)+0.1;
      rates[i].low=flat ? c : MathMin(previous,c)-0.1;
      rates[i].tick_volume=100+i%31;
      rates[i].real_volume=0;
      rates[i].spread=0;
      previous=c;
     }
   if(CustomRatesReplace(symbol,rates[0].time,rates[N-1].time,rates)!=N)
     {
      Note(StringFormat("CustomRatesReplace failed %s error=%d",symbol,GetLastError()));
      return(false);
     }
   return(SymbolSelect(symbol,true));
  }

bool Ready(int &handles[],int &counts[])
  {
   const ulong deadline=GetTickCount64()+55000;
   double poke[];
   while(GetTickCount64()<deadline && GetTickCount64()-Started<95000 && !IsStopped())
     {
      bool done=true;
      for(int i=0;i<ArraySize(handles);i++)
        {
         if(handles[i]==INVALID_HANDLE) return(false);
         int copied=CopyBuffer(handles[i],0,0,1,poke);
         if(copied!=1 || BarsCalculated(handles[i])<counts[i]) done=false;
        }
      if(done) return(true);
      Sleep(100);
     }
   for(int i=0;i<ArraySize(handles);i++)
      Note(StringFormat("WAIT handle_index=%d calculated=%d required=%d",i,BarsCalculated(handles[i]),counts[i]));
   return(false);
  }

bool Buffer(const int h,const int b,const int n,double &a[])
  {
   ArraySetAsSeries(a,false);
   ResetLastError();
   int copied=CopyBuffer(h,b,0,n,a);
   if(copied!=n) Note(StringFormat("CopyBuffer h=%d b=%d expected=%d got=%d error=%d",h,b,n,copied,GetLastError()));
   return(copied==n);
  }

double DirectSMA(const MqlRates &r[],const int index,const int period)
{
   double sum=0;
   for(int j=index-period+1;j<=index;j++) sum+=r[j].close;
   return sum/period;
}

long ExactWindowUnits(const MqlRates &r[],const int index,const int period)
{
   // The synthetic fixture is rounded to five decimals. Sum integer price units
   // over each complete window so equality is exact, independent of float order.
   long total=0;
   for(int j=index-period+1;j<=index;j++) total+=(long)MathRound(r[j].close*100000.0);
   return total;
}

void ReferenceBB(const MqlRates &r[],double &basis[],double &upper[],double &lower[],double &rsi[])
{
   int count=ArraySize(r);
   ArrayResize(basis,count); ArrayResize(upper,count); ArrayResize(lower,count); ArrayResize(rsi,count);
   ArrayInitialize(basis,EMPTY_VALUE); ArrayInitialize(upper,EMPTY_VALUE); ArrayInitialize(lower,EMPTY_VALUE); ArrayInitialize(rsi,EMPTY_VALUE);
   for(int i=199;i<count;i++)
   {
      const double mean=DirectSMA(r,i,200);
      double variance=0;
      for(int j=i-199;j<=i;j++) variance+=(r[j].close-mean)*(r[j].close-mean);
      basis[i]=mean; upper[i]=mean+2*MathSqrt(variance/200.0); lower[i]=mean-2*MathSqrt(variance/200.0);
   }
   double avg_up=0,avg_down=0;
   for(int i=1;i<count;i++)
   {
      const double difference=r[i].close-r[i-1].close;
      const double up=MathMax(difference,0),down=MathMax(-difference,0);
      if(i<=6) {avg_up+=up/6.0; avg_down+=down/6.0;}
      else {avg_up=avg_up*(5.0/6.0)+up/6.0; avg_down=avg_down*(5.0/6.0)+down/6.0;}
      if(i>=6) rsi[i]=(avg_up+avg_down>0 ? 100.0*avg_up/(avg_up+avg_down) : 50.0);
   }
}

void TestVP(const int handle,const int flat_handle,const MqlRates &r[],const MqlRates &flat_rates[])
{
   int metric=AddMetric("VP nested candle-level reference POC VAH VAL weights input coverage count");
   int empty_metric=AddMetric("VP latest snapshot only; flat range has EMPTY prices and no fabricated POC");
   double lo=r[N-200].low,hi=r[N-200].high;
   for(int i=N-200;i<N;i++) {lo=MathMin(lo,r[i].low); hi=MathMax(hi,r[i].high);}
   const double step=(hi-lo)/199.0;
   double weights[200]; ArrayInitialize(weights,0);
   double input_volume=0,flat_input_volume=0;
   for(int i=N-200;i<N;i++) flat_input_volume+=(double)flat_rates[i].tick_volume;
   for(int i=N-200;i<N;i++)
   {
      input_volume+=(double)r[i].tick_volume;
      for(int j=0;j<200;j++)
      {
         const double level=lo+j*step;
         if(level>=r[i].low && level<r[i].high) weights[j]+=(double)r[i].tick_volume;
      }
   }
   double total=0,max_weight=0;
   int poc=0;
   for(int j=0;j<200;j++) {total+=weights[j]; if(weights[j]>max_weight) {max_weight=weights[j]; poc=j;}}
   int bottom=poc,top=poc;
   double included=weights[poc];
   while(included<total*0.68)
   {
      double above=(top<199 ? weights[top+1] : 0),below=(bottom>0 ? weights[bottom-1] : 0);
      if(above==0 && below==0) break;
      if(above>=below && top<199) {top++; included+=weights[top];}
      else if(bottom>0) {bottom--; included+=weights[bottom];}
      else break;
   }
   double expected[7]={lo+poc*step,lo+top*step,lo+bottom*step,total,input_volume,100.0*included/total,200.0};
   for(int b=0;b<7;b++)
   {
      double a[],f[];
      if(!Buffer(handle,b,N,a) || !Buffer(flat_handle,b,N,f)) {Condition(metric,false); continue;}
      Compare(metric,a[N-1],expected[b]);
      for(int i=0;i<N-1;i++) Condition(empty_metric,a[i]==EMPTY_VALUE && f[i]==EMPTY_VALUE);
      if(b<=2 || b==5) Condition(empty_metric,f[N-1]==EMPTY_VALUE);
      else Compare(empty_metric,f[N-1],b==6 ? 200.0 : (b==4 ? flat_input_volume : 0.0));
   }
   Note(StringFormat("VP reference POC=%.10f VAH=%.10f VAL=%.10f level_weights=%.0f input_volume=%.0f VA_percent=%.8f",expected[0],expected[1],expected[2],total,input_volume,expected[5]));
}

void OnStart()
{
   Started=GetTickCount64();
   Summary=FileOpen("suite_classic_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("SYNTHETIC CUSTOM SYMBOLS ONLY. This script makes no trades or account API calls; this is not a performance backtest.");
   MqlRates rates[],flat_rates[];
   int setup=AddMetric("Custom disabled synthetic symbol fixture and indicator readiness");
   if(!CreateData(Sym,false,rates) || !CreateData(FlatSym,true,flat_rates)) {Condition(setup,false); Finish(); return;}
   int sma=iCustom(Sym,PERIOD_M1,"SMA_Ribbon_10_MT5");
   int ema=iCustom(Sym,PERIOD_M1,"EMA_20_50_100_200_MT5");
   // Each input group occupies a string slot in the indicator parameter list.
   // Pass both group placeholders plus every one of the 13 real BB inputs.
   int bb=iCustom(Sym,PERIOD_M1,"Bollinger_RSI_ChartArt_MT5","",200,2.0,6,50.0,"",false,C'35,45,60',true,10.0,true,false,500,C'22,55,32',C'60,25,25');
   int bbflat=iCustom(FlatSym,PERIOD_M1,"Bollinger_RSI_ChartArt_MT5","",200,2.0,6,50.0,"",false,C'35,45,60',true,10.0,true,false,500,C'22,55,32',C'60,25,25');
   int vp=iCustom(Sym,PERIOD_M1,"Volume_Profile_MT5",false,200,200,1,20,70,0,0,true,true,68,true,clrDimGray,clrRed,clrDodgerBlue,1,false);
   int vpflat=iCustom(FlatSym,PERIOD_M1,"Volume_Profile_MT5",false,200,200,1,20,70,0,0,true,true,68,true,clrDimGray,clrRed,clrDodgerBlue,1,false);
   int handles[6]={sma,ema,bb,bbflat,vp,vpflat};
   ENUM_INDICATOR bb_type;
   MqlParam bb_parameters[];
   const int bb_parameter_count=IndicatorParameters(bb,bb_type,bb_parameters);
   Note(StringFormat("BB_PARAMETER_LAYOUT count=%d indicator_type=%d",bb_parameter_count,(int)bb_type));
   for(int q=0;q<bb_parameter_count;q++)
      Note(StringFormat("BB_PARAMETER index=%d type=%s integer=%I64d double=%.17g string=%s",q,EnumToString(bb_parameters[q].type),bb_parameters[q].integer_value,bb_parameters[q].double_value,bb_parameters[q].string_value));
   int counts[6]={N,N,N,N,N,N};
   if(!Ready(handles,counts)) {Condition(setup,false); Finish(); return;}
   Condition(setup,true);
   int warmup=AddMetric("SMA EMA BB RSI warmup EMPTY_VALUE and no live-bar arrows");
   int smav=AddMetric("All ten SMA independent direct-window means");
   int smac=AddMetric("All ten SMA color indices compare close with MA");
   int emav=AddMetric("All four EMA geometric decay first-close seed reference");
   int bbv=AddMetric("BB basis and population standard deviation independent direct-window formula");
   int rsiv=AddMetric("RSI Wilder independent gain fraction formula including flat RSI=50");
   int arrows=AddMetric("BB simultaneous RSI and price crossings, closed-bar-only arrows");
   int trend=AddMetric("Exact original non-RSI TrendColor conditions and colored candle buffers");
   int flat_slope=AddMetric("Exactly equal complete SMA window sums cannot manufacture trend colors");
   int flat=AddMetric("Flat BB=100 all three lines with no buy/sell arrows");
   int coverage=AddMetric("Both BB arrow directions and source color directions exercised");
   int smaperiods[10]={20,50,100,150,200,250,300,400,500,600};
   for(int p=0;p<10;p++)
   {
      double values[],colors[];
      if(!Buffer(sma,2*p,N,values) || !Buffer(sma,2*p+1,N,colors)) {Condition(smav,false); continue;}
      for(int i=0;i<N;i++)
      {
         if(i<smaperiods[p]-1) {Condition(warmup,values[i]==EMPTY_VALUE); continue;}
         const double reference=DirectSMA(rates,i,smaperiods[p]);
         Compare(smav,values[i],reference);
         Compare(smac,colors[i],rates[i].close>=reference ? 0 : 1,0);
      }
   }
   int emaperiods[4]={20,50,100,200};
   for(int p=0;p<4;p++)
   {
      double values[];
      if(!Buffer(ema,p,N,values)) {Condition(emav,false); continue;}
      const double a=2.0/(emaperiods[p]+1.0),decay=1.0-a;
      for(int i=0;i<N;i++)
      {
         if(i<emaperiods[p]-1) {Condition(warmup,values[i]==EMPTY_VALUE); continue;}
         // Direct finite geometric weighted sum differs from implementation recurrence.
         double reference=MathPow(decay,i)*rates[0].close,weight=a;
         for(int j=i;j>=1;j--)
         {
            reference+=weight*rates[j].close;
            weight*=decay;
            if(weight<1e-17) break;
         }
         Compare(emav,values[i],reference);
      }
   }
   double basis[],upper[],lower[],rsi[],buy[],sell[],tr[],cc[],co[],ch[],cl[],cclose[],rb[],ru[],rl[],rrsi[];
   if(!Buffer(bb,0,N,basis) || !Buffer(bb,1,N,upper) || !Buffer(bb,2,N,lower) || !Buffer(bb,12,N,rsi) ||
      !Buffer(bb,5,N,buy) || !Buffer(bb,6,N,sell) || !Buffer(bb,13,N,tr) || !Buffer(bb,11,N,cc) ||
      !Buffer(bb,7,N,co) || !Buffer(bb,8,N,ch) || !Buffer(bb,9,N,cl) || !Buffer(bb,10,N,cclose))
   {Condition(bbv,false); Finish(); return;}
   ReferenceBB(rates,rb,ru,rl,rrsi);
   int buys=0,sells=0,bulls=0,bears=0,flat_windows=0,trend_diagnostics=0;
   for(int i=0;i<N;i++)
   {
      if(i<199) Condition(warmup,basis[i]==EMPTY_VALUE && upper[i]==EMPTY_VALUE && lower[i]==EMPTY_VALUE);
      else {Compare(bbv,basis[i],rb[i]); Compare(bbv,upper[i],ru[i]); Compare(bbv,lower[i],rl[i]);}
      if(i<6) Condition(warmup,rsi[i]==EMPTY_VALUE); else Compare(rsiv,rsi[i],rrsi[i]);
      if(i<200) {Condition(warmup,buy[i]==EMPTY_VALUE && sell[i]==EMPTY_VALUE && tr[i]==EMPTY_VALUE); continue;}
      const bool long_condition=rrsi[i]>50 && rrsi[i-1]<=50 && rates[i].close>rl[i] && rates[i-1].close<=rl[i-1];
      const bool short_condition=rrsi[i]<50 && rrsi[i-1]>=50 && rates[i].close<ru[i] && rates[i-1].close>=ru[i-1];
      const double offset=MathMax(10*0.00001,(rates[i].high-rates[i].low)*0.25);
      if(long_condition && i<N-1) {Compare(arrows,buy[i],rates[i].low-offset); buys++;} else Condition(arrows,buy[i]==EMPTY_VALUE);
      if(short_condition && i<N-1) {Compare(arrows,sell[i],rates[i].high+offset); sells++;} else Condition(arrows,sell[i]==EMPTY_VALUE);
      const long current_units=ExactWindowUnits(rates,i,200),previous_units=ExactWindowUnits(rates,i-1,200);
      const bool bearish=rates[i-1].close>ru[i] && rates[i].close<ru[i] && current_units<previous_units;
      const bool bullish=rates[i-1].close<rl[i] && rates[i].close>rl[i] && current_units>previous_units;
      const int direction=(bearish ? -1 : (bullish ? 1 : 0));
      if(current_units==previous_units) {Condition(flat_slope,tr[i]==0); flat_windows++;}
      if(tr[i]!=direction && trend_diagnostics<12)
      {
         Note(StringFormat("TREND_MISMATCH index=%d time=%s actual=%.0f expected=%d actual_basis_delta=%.17g naive_reference_delta=%.17g exact_window_units_delta=%I64d incoming=%.10f outgoing=%.10f candle_OHLC=[%.17g,%.17g,%.17g,%.17g] color=%.0f",
                           i,TimeToString(rates[i].time),tr[i],direction,basis[i]-basis[i-1],rb[i]-rb[i-1],current_units-previous_units,
                           rates[i].close,rates[i-200].close,co[i],ch[i],cl[i],cclose[i],cc[i]));
         trend_diagnostics++;
      }
      Compare(trend,tr[i],direction,0);
      if(direction!=0)
      {
         Compare(trend,cc[i],direction>0 ? 0 : 1,0);
         Compare(trend,co[i],rates[i].open); Compare(trend,ch[i],rates[i].high);
         Compare(trend,cl[i],rates[i].low); Compare(trend,cclose[i],rates[i].close);
         if(direction>0) bulls++; else bears++;
      }
      else Condition(trend,co[i]==EMPTY_VALUE && ch[i]==EMPTY_VALUE && cl[i]==EMPTY_VALUE && cclose[i]==EMPTY_VALUE);
   }
   Condition(coverage,buys>0 && sells>0);
   Condition(coverage,bulls>0 && bears>0);
   Condition(coverage,flat_windows>0);
   Condition(warmup,buy[N-1]==EMPTY_VALUE && sell[N-1]==EMPTY_VALUE);
   Note(StringFormat("COVERAGE buy_arrows=%d sell_arrows=%d bull_colors=%d bear_colors=%d exact_equal_SMA_windows=%d",buys,sells,bulls,bears,flat_windows));
   for(int b=0;b<3;b++)
   {
      double a[]; if(!Buffer(bbflat,b,N,a)) {Condition(flat,false); continue;}
      for(int i=199;i<N;i++) Compare(flat,a[i],100.0);
   }
   for(int b=5;b<=6;b++)
   {
      double a[]; if(!Buffer(bbflat,b,N,a)) {Condition(flat,false); continue;}
      for(int i=0;i<N;i++) Condition(flat,a[i]==EMPTY_VALUE);
   }
   double frsi[];
   if(Buffer(bbflat,12,N,frsi)) for(int i=6;i<N;i++) Compare(rsiv,frsi[i],50.0);
   else Condition(rsiv,false);
   TestVP(vp,vpflat,rates,flat_rates);
   int csv=FileOpen("suite_classic_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   double s20[],s600[],e20[],e200[];
   if(csv!=INVALID_HANDLE && Buffer(sma,0,N,s20) && Buffer(sma,18,N,s600) && Buffer(ema,0,N,e20) && Buffer(ema,3,N,e200))
   {
      FileWrite(csv,"time","close","sma20","sma600","ema20","ema200","bb_basis","ref_basis","bb_upper","ref_upper","bb_lower","ref_lower","rsi","ref_rsi","buy_arrow","sell_arrow","source_trend");
      for(int i=600;i<N;i++) FileWrite(csv,TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES),rates[i].close,s20[i],s600[i],e20[i],e200[i],basis[i],rb[i],upper[i],ru[i],lower[i],rl[i],rsi[i],rrsi[i],buy[i],sell[i],tr[i]);
   }
   if(csv!=INVALID_HANDLE) FileClose(csv);
   for(int i=0;i<ArraySize(handles);i++) if(handles[i]!=INVALID_HANDLE) IndicatorRelease(handles[i]);
   Finish();
}

