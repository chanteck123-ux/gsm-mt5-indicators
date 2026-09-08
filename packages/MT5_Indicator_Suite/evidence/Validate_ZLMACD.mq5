// Synthetic indicator validation. No orders, account calls, or external calls.
#property strict
#property version "1.00"
const int N=5000;
const string Sym="CODEX_SUITE_ZL";
struct Metric { string name; int samples; int failures; double max_error; };
Metric Metrics[];
int Summary=INVALID_HANDLE;
ulong Started=0;

int AddMetric(const string name)
  {
   int n=ArraySize(Metrics); ArrayResize(Metrics,n+1);
   Metrics[n].name=name; Metrics[n].samples=0; Metrics[n].failures=0; Metrics[n].max_error=0;
   return(n);
  }
bool Good(const double x) { return(x!=EMPTY_VALUE && MathIsValidNumber(x)); }
void Compare(const int m,const double actual,const double expected,const double tolerance=1e-8)
  {
   Metrics[m].samples++;
   if(actual==EMPTY_VALUE && expected==EMPTY_VALUE) return;
   if(!Good(actual) || !Good(expected))
     { Metrics[m].failures++; Metrics[m].max_error=1e100; return; }
   double err=MathAbs(actual-expected);
   Metrics[m].max_error=MathMax(err,Metrics[m].max_error);
   if(err>tolerance) Metrics[m].failures++;
  }
void Condition(const int m,const bool okay) { Compare(m,okay ? 1.0 : 0.0,1.0,0); }
void Note(const string msg)
  {
   Print(msg);
   if(Summary!=INVALID_HANDLE) { FileWrite(Summary,msg); FileFlush(Summary); }
  }
void Finish()
  {
   int failures=0;
   for(int m=0;m<ArraySize(Metrics);m++)
     {
      bool pass=(Metrics[m].samples>0 && Metrics[m].failures==0);
      if(!pass) failures++;
      Note(StringFormat("%s | %s | samples=%d | failures=%d | max_error=%.12g",
                        pass ? "PASS" : "FAIL",Metrics[m].name,Metrics[m].samples,
                        Metrics[m].failures,Metrics[m].max_error));
     }
   Note(StringFormat("OVERALL=%s | metric_groups=%d | failed_groups=%d | elapsed_ms=%I64u",
                     failures==0 ? "PASS" : "FAIL",ArraySize(Metrics),failures,GetTickCount64()-Started));
   if(Summary!=INVALID_HANDLE) { FileClose(Summary); Summary=INVALID_HANDLE; }
  }
bool CreateData(MqlRates &rates[])
  {
   bool custom=false; bool exists=SymbolExist(Sym,custom);
   if((exists && !custom) || (!exists && !CustomSymbolCreate(Sym,"CodexValidation"))) return(false);
   if(!CustomSymbolSetInteger(Sym,SYMBOL_DIGITS,5) ||
      !CustomSymbolSetDouble(Sym,SYMBOL_POINT,0.00001) ||
      !CustomSymbolSetInteger(Sym,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED)) return(false);
   ArrayResize(rates,N);
   double previous=100.0;
   for(int i=0;i<N;i++)
     {
      int p=i%1000;
      double c;
      if(p<300) c=100.0+0.012*p+2.2*MathSin(i*0.083)+0.7*MathSin(i*0.017);
      else if(p<600) c=103.6-0.012*(p-300)+2.2*MathSin(i*0.083)+0.7*MathSin(i*0.017);
      else if(p<720) c=100.0;
      else c=100.0+3.0*MathSin(i*0.04)+0.9*MathSin(i*0.17);
      c=NormalizeDouble(c,5);
      rates[i].time=D'2026.01.05 00:00:00'+i*60;
      rates[i].open=previous; rates[i].close=c;
      rates[i].high=MathMax(previous,c)+0.1; rates[i].low=MathMin(previous,c)-0.1;
      rates[i].tick_volume=100; rates[i].real_volume=0; rates[i].spread=0;
      previous=c;
     }
   return(CustomRatesReplace(Sym,rates[0].time,rates[N-1].time,rates)==N && SymbolSelect(Sym,true));
  }
bool Ready(int &handles[],const int count)
  {
   ulong deadline=GetTickCount64()+50000;
   double poke[];
   while(GetTickCount64()<deadline && !IsStopped())
     {
      bool all=true;
      for(int i=0;i<ArraySize(handles);i++)
        {
         if(handles[i]==INVALID_HANDLE) return(false);
         if(CopyBuffer(handles[i],0,0,1,poke)!=1 || BarsCalculated(handles[i])<count) all=false;
        }
      if(all) return(true);
      Sleep(100);
     }
   for(int i=0;i<ArraySize(handles);i++)
      Note(StringFormat("WAIT index=%d bars=%d expected=%d",i,BarsCalculated(handles[i]),count));
   return(false);
  }
bool Buffer(const int h,const int b,const int n,double &dst[])
  {
   ArraySetAsSeries(dst,false);
   int copied=CopyBuffer(h,b,0,n,dst);
   if(copied!=n) Note(StringFormat("COPY failed handle=%d buffer=%d got=%d need=%d error=%d",h,b,copied,n,GetLastError()));
   return(copied==n);
  }

// Independent full-series oracle: SMA explicitly sums each full window;
// DEMA is computed in two separate EMA passes, not the production cache helper.
void RefEMA(const double &src[],const int len,double &dst[])
  {
   int n=ArraySize(src); ArrayResize(dst,n); ArrayInitialize(dst,EMPTY_VALUE);
   double alpha=2.0/(len+1.0),last=EMPTY_VALUE;
   for(int i=0;i<n;i++)
     {
      if(!Good(src[i])) continue;
      last=Good(last) ? alpha*src[i]+(1.0-alpha)*last : src[i];
      dst[i]=last;
     }
  }
void RefMA(const double &src[],const int len,const int kind,double &dst[])
  {
   int n=ArraySize(src); ArrayResize(dst,n); ArrayInitialize(dst,EMPTY_VALUE);
   if(kind==0) { RefEMA(src,len,dst); return; }
   if(kind==2)
     {
      double one[],two[]; RefEMA(src,len,one); RefEMA(one,len,two);
      for(int i=0;i<n;i++) if(Good(one[i]) && Good(two[i])) dst[i]=2.0*one[i]-two[i];
      return;
     }
   for(int i=len-1;i<n;i++)
     {
      bool full=true; double sum=0;
      for(int j=i-len+1;j<=i;j++)
        { if(!Good(src[j])) { full=false; break; } sum+=src[j]; }
      if(full) dst[i]=sum/len;
     }
  }
void RefMACD(const double &src[],const int osc,const int sig,const int fastlen,
             const int slowlen,const int siglen,double &main[],double &signal[],double &hist[])
  {
   double fast[],slow[]; RefMA(src,fastlen,osc,fast); RefMA(src,slowlen,osc,slow);
   int n=ArraySize(src); ArrayResize(main,n); ArrayResize(hist,n);
   for(int i=0;i<n;i++) main[i]=(Good(fast[i]) && Good(slow[i])) ? fast[i]-slow[i] : EMPTY_VALUE;
   RefMA(main,siglen,sig,signal);
   for(int i=0;i<n;i++) hist[i]=(Good(main[i]) && Good(signal[i])) ? main[i]-signal[i] : EMPTY_VALUE;
  }
void ValidateCase(const int handle,const double &src[],const int osc,const int sig,
                  const int fastlen,const int slowlen,const int siglen,const string label)
  {
   int numeric=AddMetric(label+" - independent MA formula/warmup");
   int events=AddMetric(label+" - histogram colors and closed crosses");
   int n=ArraySize(src);
   double main[],signal[],hist[],colors[],cross[],rm[],rs[],rh[];
   bool copied=Buffer(handle,0,n,main) && Buffer(handle,1,n,signal) && Buffer(handle,2,n,hist) &&
               Buffer(handle,3,n,colors) && Buffer(handle,4,n,cross);
   if(!copied) { Condition(numeric,false); Condition(events,false); return; }
   RefMACD(src,osc,sig,fastlen,slowlen,siglen,rm,rs,rh);
   for(int i=0;i<n;i++)
     {
      Compare(numeric,main[i],rm[i]); Compare(numeric,signal[i],rs[i]); Compare(numeric,hist[i],rh[i]);
      if(!Good(hist[i])) { Compare(events,cross[i],EMPTY_VALUE,0); continue; }
      bool prev=(i>0 && Good(hist[i-1]));
      bool rise=(prev && hist[i]>hist[i-1]);
      int expected_color=(hist[i]>=0) ? (rise ? 0 : 1) : (rise ? 2 : 3);
      double expected_cross=prev ? 0 : EMPTY_VALUE;
      if(i<n-1 && prev)
        {
         if(hist[i]>0 && hist[i-1]<=0) expected_cross=1;
         else if(hist[i]<0 && hist[i-1]>=0) expected_cross=-1;
        }
      if(colors[i]!=expected_color || cross[i]!=expected_cross)
         Note(StringFormat("EVENT_MISMATCH %s index=%d color_actual=%.12g expected=%d cross_actual=%.12g expected=%.12g hist=%.12g previous_valid=%d",
                           label,i,colors[i],expected_color,cross[i],expected_cross,hist[i],prev));
      Compare(events,colors[i],expected_color,0); Compare(events,cross[i],expected_cross,0);
     }
  }
int Sign(const double value) { return(value>0 ? 1 : (value<0 ? -1 : 0)); }

void OnStart()
  {
   Started=GetTickCount64();
   Summary=FileOpen("suite_zl_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("SYNTHETIC M1 INDICATOR VALIDATION ONLY. 5000 bars, no trading performance conclusions.");
   int setup=AddMetric("Synthetic source and indicator handles");
   MqlRates rates[];
   if(!CreateData(rates)) { Condition(setup,false); Note("Data creation failed"); Finish(); return; }
   double src[]; ArrayResize(src,N); for(int i=0;i<N;i++) src[i]=rates[i].close;
   int reference=iMACD(Sym,PERIOD_M1,12,26,9,PRICE_CLOSE);
   int pre[]={reference};
   if(!Ready(pre,N)) { Condition(setup,false); Finish(); return; }
   int handles[]; ArrayResize(handles,15);
   // 0 preset, 1..9 custom (osc*3+sig+1), 10 CM, 11 length=1,
   // 12 signal SMA with insufficient history, 13 fast>=slow, 14 typical price.
   handles[0]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_CLOSE,12,26,9,0,0,0,false);
   for(int osc=0;osc<3;osc++)
      for(int sig=0;sig<3;sig++)
         handles[1+osc*3+sig]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_CLOSE,12,26,9,1,osc,sig,false);
   handles[10]=iCustom(Sym,PERIOD_M1,"CM_MACD_Ult_MTF_MT5",true,PERIOD_H1,12,26,9,true,true,true,true,true,true,10000);
   handles[11]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_CLOSE,1,1,1,1,2,1,false);
   handles[12]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_CLOSE,12,26,10000,1,1,1,false);
   handles[13]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_CLOSE,26,12,9,1,0,1,false);
   handles[14]=iCustom(Sym,PERIOD_M1,"ZeroLag_MACD_MT5",PRICE_TYPICAL,12,26,9,0,0,0,false);
   if(!Ready(handles,N)) { Condition(setup,false); Finish(); return; }
   Condition(setup,true);
   ValidateCase(handles[0],src,2,0,12,26,9,"Preset DEMA/EMA");
   for(int osc=0;osc<3;osc++)
      for(int sig=0;sig<3;sig++)
         ValidateCase(handles[1+osc*3+sig],src,osc,sig,12,26,9,StringFormat("Custom osc=%d sig=%d",osc,sig));
   ValidateCase(handles[11],src,2,1,1,1,1,"Length one and equality histogram");
   ValidateCase(handles[12],src,1,1,12,26,10000,"Insufficient SMA signal history");
   ValidateCase(handles[13],src,0,1,26,12,9,"Reversed fast and slow lengths");
   double typical[]; ArrayResize(typical,N);
   for(int i=0;i<N;i++) typical[i]=(rates[i].high+rates[i].low+rates[i].close)/3.0;
   ValidateCase(handles[14],typical,2,0,12,26,9,"Typical price source");

   double cm[],cs[],ch[],cc[],zm[],zs[],zh[],zc[],em[],es[],eh[];
   int equivalence=AddMetric("CM vs Custom EMA/SMA on same M1 source after 600 bars");
   bool copied=Buffer(handles[10],0,N,cm) && Buffer(handles[10],2,N,cs) &&
               Buffer(handles[10],3,N,ch) && Buffer(handles[10],7,N,cc) &&
               Buffer(handles[0],0,N,zm) && Buffer(handles[0],1,N,zs) &&
               Buffer(handles[0],2,N,zh) && Buffer(handles[0],4,N,zc) &&
               Buffer(handles[2],0,N,em) && Buffer(handles[2],1,N,es) && Buffer(handles[2],2,N,eh);
   if(!copied) Condition(equivalence,false);
   else
     {
      int c_up=0,c_down=0,z_up=0,z_down=0,different=0;
      int csv=FileOpen("suite_zl_comparison.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(csv!=INVALID_HANDLE)
         FileWrite(csv,"time","close","cm_macd","cm_signal","cm_hist","zl_macd","zl_signal","zl_hist","cm_closedcross","zl_closedcross","custom_ema_sma_macd","custom_ema_sma_signal","custom_ema_sma_hist");
      for(int i=600;i<N-1;i++)
        {
         Compare(equivalence,em[i],cm[i]); Compare(equivalence,es[i],cs[i]); Compare(equivalence,eh[i],ch[i]);
         if(cc[i]>0) c_up++; else if(cc[i]<0) c_down++;
         if(zc[i]>0) z_up++; else if(zc[i]<0) z_down++;
         if(Sign(ch[i])!=Sign(zh[i])) different++;
         if(csv!=INVALID_HANDLE)
            FileWrite(csv,TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES),rates[i].close,cm[i],cs[i],ch[i],zm[i],zs[i],zh[i],cc[i],zc[i],em[i],es[i],eh[i]);
        }
      if(csv!=INVALID_HANDLE) FileClose(csv);
      int valid=N-601;
      Note(StringFormat("COMPARISON synthetic_closed_bars=%d skipped_initial_bars=600 period=M1 parameters=12/26/9",valid));
      Note(StringFormat("CM upward_crosses=%d downward_crosses=%d total_crosses=%d crossings_per_1000_bars=%.6f",c_up,c_down,c_up+c_down,1000.0*(c_up+c_down)/valid));
      Note(StringFormat("ZL_DEFAULT upward_crosses=%d downward_crosses=%d total_crosses=%d crossings_per_1000_bars=%.6f",z_up,z_down,z_up+z_down,1000.0*(z_up+z_down)/valid));
      Note(StringFormat("DIRECTION_DISAGREEMENT bars=%d fraction=%.8f percent=%.6f",different,(double)different/valid,100.0*different/valid));
      Note("These are indicator zero-cross frequencies, not orders, trades, win rates or profit factors.");
     }

   // A custom tick modifies the latest candle and forces a Calculate event.
   // Closed candles must retain their values; all updated outputs still match
   // an independent full-series recomputation.
   int update=AddMetric("Latest-bar quote update and closed-bar stability");
   double before[]; bool have_before=Buffer(handles[0],0,N,before);
   MqlTick tick[]; ArrayResize(tick,1); ZeroMemory(tick[0]);
   tick[0].time=rates[N-1].time+59; tick[0].time_msc=(long)tick[0].time*1000;
   tick[0].bid=rates[N-1].close+5.0; tick[0].ask=tick[0].bid; tick[0].last=tick[0].bid;
   tick[0].volume=1; tick[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   int added=CustomTicksAdd(Sym,tick);
   double fresh[]; bool changed=false; ulong deadline=GetTickCount64()+12000;
   while(added==1 && have_before && GetTickCount64()<deadline && !IsStopped())
     {
      if(Buffer(handles[0],0,N,fresh) && MathAbs(fresh[N-1]-before[N-1])>1e-6) { changed=true; break; }
      Sleep(100);
     }
   Condition(update,changed);
   if(changed)
     {
      for(int i=0;i<N-1;i++) Compare(update,fresh[i],before[i]);
      double updated[]; if(CopyClose(Sym,PERIOD_M1,0,N,updated)==N)
        {
         ValidateCase(handles[0],updated,2,0,12,26,9,"Recomputed preset after latest tick");
         ValidateCase(handles[5],updated,1,1,12,26,9,"Recomputed SMA/SMA after latest tick");
        }
      else Condition(update,false);
     }
   long chart=ChartOpen(Sym,PERIOD_M1);
   if(chart>0)
     {
      ChartSetString(chart,CHART_COMMENT,"SYNTHETIC ONLY - CM MACD vs DEMA/EMA MACD - NO TRADING PERFORMANCE");
      ChartSetInteger(chart,CHART_SHOW_GRID,false);
      ChartSetInteger(chart,CHART_SCALE,3);
      bool add_cm=ChartIndicatorAdd(chart,1,handles[10]);
      bool add_zl=ChartIndicatorAdd(chart,2,handles[0]);
      ChartNavigate(chart,CHART_END,0); ChartRedraw(chart); Sleep(1000);
      bool snap=ChartScreenShot(chart,"suite_zl_comparison.png",1600,1000,ALIGN_RIGHT);
      Note(StringFormat("VISUAL synthetic_only=1 cm=%d zl=%d screenshot=%d",add_cm,add_zl,snap));
     }
   for(int i=0;i<ArraySize(handles);i++) if(handles[i]!=INVALID_HANDLE) IndicatorRelease(handles[i]);
   if(reference!=INVALID_HANDLE) IndicatorRelease(reference);
   Finish();
  }
