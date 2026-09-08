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
const string Sym="CODEX_IND_SYNTH";
const string FlatSym="CODEX_IND_FLAT";

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
         int phase=i%1000;
         if(phase<300) c=100.0+0.012*phase+2.2*MathSin(i*0.083)+0.7*MathSin(i*0.017);
         else if(phase<600) c=103.6-0.012*(phase-300)+2.2*MathSin(i*0.083)+0.7*MathSin(i*0.017);
         else if(phase<720) c=100.0;
         else c=100.0+3.0*MathSin(i*0.04)+0.9*MathSin(i*0.17);
         c=NormalizeDouble(c,5);
        }
      rates[i].time=first+i*60;
      rates[i].open=previous;
      rates[i].close=c;
      rates[i].high=flat ? c : MathMax(previous,c)+0.1;
      rates[i].low=flat ? c : MathMin(previous,c)-0.1;
      rates[i].tick_volume=100;
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

void OnStart()
  {
   Started=GetTickCount64();
   Summary=FileOpen("validation_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("Synthetic indicator validation. No trading or account access. M1 bars=5000; source starts 2026-01-05.");
   int setup=AddMetric("Synthetic data and indicator readiness");
   MqlRates rates[],flat_rates[];
   if(!CreateData(Sym,false,rates) || !CreateData(FlatSym,true,flat_rates))
     { Condition(setup,false); Finish(); return; }
   // Prepare offline source series first. There is no broker tick stream in
   // this portable fixture to drive dependencies that initially return zero.
   int refm=iMACD(Sym,PERIOD_M1,12,26,9,PRICE_CLOSE);
   int refh=iMACD(Sym,PERIOD_H1,12,26,9,PRICE_CLOSE);
   int refr=iRSI(Sym,PERIOD_M1,14,PRICE_CLOSE);
   int flat_ref=iRSI(FlatSym,PERIOD_M1,14,PRICE_CLOSE);
   int pre_handles[]={refm,refh,refr,flat_ref};
   int pre_counts[]={N,84,N,N};
   if(!Ready(pre_handles,pre_counts)) { Condition(setup,false); Finish(); return; }
   Note("Reference M1/H1 histories are ready; loading custom indicators.");
   // Complete indicator inputs, explicit fixed names for reproducible loading.
   int cm=iCustom(Sym,PERIOD_M1,"CM_MACD_Ult_MTF_MT5",true,PERIOD_H1,12,26,9,true,true,true,true,true,true,10000);
   int cmh=iCustom(Sym,PERIOD_M1,"CM_MACD_Ult_MTF_MT5",false,PERIOD_H1,12,26,9,true,true,true,true,true,true,10000);
   int sr=iCustom(Sym,PERIOD_M1,"Stoch_RSI_MT5",14,14,3,3);
   int sf=iCustom(FlatSym,PERIOD_M1,"Stoch_RSI_MT5",14,14,3,3);
   int handles[]={cm,cmh,sr,sf,refm,refh,refr};
   int counts[]={N,N,N,N,N,84,N};
   if(!Ready(handles,counts)) { Condition(setup,false); Finish(); return; }
   Condition(setup,true);
   double macd[],sig[],hist[],hc[],mc[],dot[],cross[],hm[],hs[],hh[],hcol[],hcross[];
   double main_ref[],sig_ref[],hmain_ref[],hsig_ref[],rsi[],k[],d[],fk[],fd[];
   int nh=BarsCalculated(refh);
   bool copied=Buffer(cm,0,N,macd) && Buffer(cm,2,N,sig) && Buffer(cm,3,N,hist) &&
               Buffer(cm,4,N,hc) && Buffer(cm,1,N,mc) && Buffer(cm,5,N,dot) && Buffer(cm,7,N,cross) &&
               Buffer(cmh,0,N,hm) && Buffer(cmh,2,N,hs) && Buffer(cmh,3,N,hh) &&
               Buffer(cmh,4,N,hcol) && Buffer(cmh,7,N,hcross) &&
               Buffer(refm,0,N,main_ref) && Buffer(refm,1,N,sig_ref) &&
               Buffer(refh,0,nh,hmain_ref) && Buffer(refh,1,nh,hsig_ref) &&
               Buffer(refr,0,N,rsi) && Buffer(sr,0,N,k) && Buffer(sr,1,N,d) &&
               Buffer(sf,0,N,fk) && Buffer(sf,1,N,fd);
   int copy_metric=AddMetric("All public and color_id buffers copied");
   Condition(copy_metric,copied);
   if(!copied) { Finish(); return; }
   int a=AddMetric("Current TF MACD main equals reference iMACD");
   int b=AddMetric("Current TF signal equals reference iMACD SMA signal");
   int c=AddMetric("Current TF histogram equals main minus signal");
   int colors=AddMetric("Histogram and MACD color_id indices");
   int crosses=AddMetric("Closed-bar cross directions and dot values");
   int warmup=AddMetric("Warmup empty values and no live-bar dot");
   int ha=AddMetric("H1 mapping uses previous completed H1 main and signal");
   int hb=AddMetric("H1 histogram colors use preceding mapped chart bar");
   int hcross_metric=AddMetric("H1 confirmed cross direction at mapped chart boundaries");
   int hconst=AddMetric("H1 value stays constant inside each source hour");
   int sk=AddMetric("Stoch RSI K versus independent RSI normalization and SMA");
   int sd=AddMetric("Stoch RSI D versus independent SMA of K");
   int bounds=AddMetric("Stoch RSI values bounded 0 to 100");
   int flat=AddMetric("Flat-price zero RSI range yields zero K and D");
   int saw_up=0,saw_down=0,hour_edges=0;
   bool seen_colors[5];
   ArrayInitialize(seen_colors,false);
   double raw_ref[],k_ref[],d_ref[];
   ArrayResize(raw_ref,N); ArrayResize(k_ref,N); ArrayResize(d_ref,N);
   ArrayInitialize(raw_ref,EMPTY_VALUE); ArrayInitialize(k_ref,EMPTY_VALUE); ArrayInitialize(d_ref,EMPTY_VALUE);
   for(int i=27;i<N;i++)
     {
      double lo=rsi[i],hi=rsi[i];
      for(int j=i-13;j<i;j++) { lo=MathMin(lo,rsi[j]); hi=MathMax(hi,rsi[j]); }
      raw_ref[i]=hi>lo ? 100.0*(rsi[i]-lo)/(hi-lo) : 0.0;
      if(i>=29) k_ref[i]=(raw_ref[i]+raw_ref[i-1]+raw_ref[i-2])/3.0;
      if(i>=31) d_ref[i]=(k_ref[i]+k_ref[i-1]+k_ref[i-2])/3.0;
     }
   int csv=FileOpen("validation_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(csv!=INVALID_HANDLE)
      FileWrite(csv,"time","synthetic_close","macd","reference_macd","signal","reference_signal","histogram","hist_color","cross","H1_confirmed_macd","H1_reference_macd","Stoch_K","K_reference","Stoch_D","D_reference");
   for(int i=0;i<N;i++)
     {
      if(i<33) Condition(warmup,macd[i]==EMPTY_VALUE && sig[i]==EMPTY_VALUE && hist[i]==EMPTY_VALUE);
      if(i<29) Condition(warmup,k[i]==EMPTY_VALUE);
      if(i<31) Condition(warmup,d[i]==EMPTY_VALUE);
      if(i>=33)
        {
         Compare(a,macd[i],main_ref[i]); Compare(b,sig[i],sig_ref[i]);
         double value=main_ref[i]-sig_ref[i];
         Compare(c,hist[i],value);
         Compare(colors,mc[i],value>=0 ? 0.0 : 1.0,0.0);
         int color_id=4;
         int direction=0;
         if(i>33)
           {
            double previous=main_ref[i-1]-sig_ref[i-1];
            if(value>0 && value>previous) color_id=0;
            else if(value>0 && value<previous) color_id=1;
            else if(value<=0 && value<previous) color_id=2;
            else if(value<=0 && value>previous) color_id=3;
            if(i<N-1 && value>0 && previous<=0) direction=1;
            if(i<N-1 && value<0 && previous>=0) direction=-1;
           }
         Compare(colors,hc[i],color_id,0.0); seen_colors[color_id]=true;
         Compare(crosses,cross[i],direction,0.0);
         if(direction!=0) { Compare(crosses,dot[i],sig_ref[i]); if(direction>0) saw_up++; else saw_down++; }
         else Condition(crosses,dot[i]==EMPTY_VALUE);
        }
      int hshift=iBarShift(Sym,PERIOD_H1,rates[i].time,false)+1;
      int hindex=nh-1-hshift;
      double href=EMPTY_VALUE;
      if(hindex>=33)
        {
         href=hmain_ref[hindex];
         Compare(ha,hm[i],href); Compare(ha,hs[i],hsig_ref[hindex]);
         Compare(ha,hh[i],href-hsig_ref[hindex]);
         if(i>0 && Good(hh[i-1]))
           {
            int color_id=4;
            if(hh[i]>0 && hh[i]>hh[i-1]) color_id=0;
            else if(hh[i]>0 && hh[i]<hh[i-1]) color_id=1;
            else if(hh[i]<=0 && hh[i]<hh[i-1]) color_id=2;
            else if(hh[i]<=0 && hh[i]>hh[i-1]) color_id=3;
            Compare(hb,hcol[i],color_id,0.0);
            int hdirection=0;
            if(i<N-1 && hh[i]>0 && hh[i-1]<=0) hdirection=1;
            if(i<N-1 && hh[i]<0 && hh[i-1]>=0) hdirection=-1;
            Compare(hcross_metric,hcross[i],hdirection,0.0);
            if((i%60)!=0) { Compare(hconst,hm[i],hm[i-1],0.0); Compare(hconst,hcross[i],0.0,0.0); }
            else hour_edges++;
           }
        }
      else Condition(warmup,hm[i]==EMPTY_VALUE);
      if(i>=29) { Compare(sk,k[i],k_ref[i]); Condition(bounds,k[i]>=-1e-9 && k[i]<=100.0+1e-9); Compare(flat,fk[i],0.0); }
      if(i>=31) { Compare(sd,d[i],d_ref[i]); Condition(bounds,d[i]>=-1e-9 && d[i]<=100.0+1e-9); Compare(flat,fd[i],0.0); }
      if(csv!=INVALID_HANDLE && i>=2040)
         FileWrite(csv,TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES),rates[i].close,macd[i],main_ref[i],sig[i],sig_ref[i],hist[i],hc[i],cross[i],hm[i],href,k[i],k_ref[i],d[i],d_ref[i]);
     }
   if(csv!=INVALID_HANDLE) FileClose(csv);
   Condition(warmup,dot[N-1]==EMPTY_VALUE && cross[N-1]==0.0);
   int coverage=AddMetric("Coverage of both cross directions, five histogram states, and H1 boundaries");
   Condition(coverage,saw_up>0 && saw_down>0 && hour_edges>0);
   for(int i=0;i<5;i++) Condition(coverage,seen_colors[i]);
   Note(StringFormat("Coverage upward_crosses=%d downward_crosses=%d H1_boundaries=%d",saw_up,saw_down,hour_edges));

   // Mutate only the latest synthetic M1 bar: prior values must remain stable.
   int refresh=AddMetric("Latest synthetic bar update refreshes MACD and preserves closed bars");
   int hstable=AddMetric("Latest synthetic M1 update does not alter confirmed H1 values");
   MqlRates changed[]; ArrayResize(changed,1); changed[0]=rates[N-1];
   changed[0].close-=3.0; changed[0].low=MathMin(changed[0].low,changed[0].close);
   bool updated=true;
   // Emit a quote event as a live terminal would receive. CustomRatesUpdate
   // alone changes stored history without guaranteeing a new Calculate event.
   MqlTick quote[]; ArrayResize(quote,1); ZeroMemory(quote[0]);
   quote[0].time=changed[0].time+59;
   quote[0].time_msc=(long)quote[0].time*1000;
   quote[0].bid=changed[0].close;
   quote[0].ask=changed[0].close;
   quote[0].last=changed[0].close;
   quote[0].volume=1;
   quote[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   int quote_added=CustomTicksAdd(Sym,quote);
   updated=(quote_added==1);
   Note(StringFormat("Synthetic quote event added=%d error=%d",quote_added,GetLastError()));
   Sleep(500);
   datetime refreshed_times[];
   int time_count=CopyTime(Sym,PERIOD_H1,0,nh,refreshed_times);
   Note(StringFormat("H1 time series after quote: %d/%d",time_count,nh));
   double fresh[],fresh_h[],fresh_ref[],fresh_h_ref[],fresh_rsi[],fresh_k[],fresh_d[];
   bool refreshed=false;
   const ulong update_deadline=GetTickCount64()+12000;
   while(updated && GetTickCount64()<update_deadline && GetTickCount64()-Started<105000 && !IsStopped())
     {
      // Request underlying indicators first in this offline fixture.
      if(Buffer(refm,0,N,fresh_ref) && Buffer(refh,0,nh,fresh_h_ref) &&
         Buffer(refr,0,N,fresh_rsi) && Buffer(cm,0,N,fresh) && Buffer(cmh,0,N,fresh_h) &&
         Good(fresh[N-1]) && MathAbs(fresh[N-1]-macd[N-1])>1e-8)
        { refreshed=true; break; }
      Sleep(100);
     }
   Condition(refresh,updated && refreshed);
   if(refreshed)
     {
      Compare(refresh,fresh[N-1],fresh_ref[N-1]);
      for(int i=33;i<N-1;i++) Compare(refresh,fresh[i],macd[i]);
      for(int i=2040;i<N;i++) Compare(hstable,fresh_h[i],hm[i]);
     }
   else Condition(hstable,false);

   int stoch_refresh=AddMetric("Stoch RSI live-bar update and closed-bar stability");
   if(refreshed && Buffer(sr,0,N,fresh_k) && Buffer(sr,1,N,fresh_d))
     {
      double latest_raw[5];
      for(int offset=0;offset<5;offset++)
        {
         int index=N-1-offset;
         double lo=fresh_rsi[index],hi=fresh_rsi[index];
         for(int back=1;back<14;back++)
           {lo=MathMin(lo,fresh_rsi[index-back]);hi=MathMax(hi,fresh_rsi[index-back]);}
         latest_raw[offset]=(hi>lo) ? 100.0*(fresh_rsi[index]-lo)/(hi-lo) : 0.0;
        }
      double expected_k=(latest_raw[0]+latest_raw[1]+latest_raw[2])/3.0;
      double prior_k=(latest_raw[1]+latest_raw[2]+latest_raw[3])/3.0;
      double older_k=(latest_raw[2]+latest_raw[3]+latest_raw[4])/3.0;
      Compare(stoch_refresh,fresh_k[N-1],expected_k);
      Compare(stoch_refresh,fresh_d[N-1],(expected_k+prior_k+older_k)/3.0);
      for(int i=31;i<N-1;i++)
        {Compare(stoch_refresh,fresh_k[i],k[i]);Compare(stoch_refresh,fresh_d[i],d[i]);}
     }
   else Condition(stoch_refresh,false);

   // Visual evidence on synthetic data only. This is not a performance chart.
   long chart=ChartOpen(Sym,PERIOD_M1);
   if(chart>0 && GetTickCount64()-Started<110000)
     {
      ChartSetString(chart,CHART_COMMENT,"SYNTHETIC DATA - INDICATOR VALIDATION ONLY");
      ChartSetInteger(chart,CHART_SHOW_GRID,false);
      ChartSetInteger(chart,CHART_SCALE,3);
      ChartSetInteger(chart,CHART_AUTOSCROLL,true);
      bool attach1=ChartIndicatorAdd(chart,1,cm);
      bool attach2=ChartIndicatorAdd(chart,2,sr);
      ChartNavigate(chart,CHART_END,0);
      ChartRedraw(chart);
      Sleep(1000);
      bool screenshot=ChartScreenShot(chart,"validation_synthetic_chart.png",1600,1000,ALIGN_RIGHT);
      Note(StringFormat("VISUAL synthetic_only=1 chart_open=1 macd_attached=%d stoch_attached=%d screenshot_requested=%d",attach1,attach2,screenshot));
     }
   else Note("VISUAL skipped: chart unavailable or time budget.");
   for(int i=0;i<ArraySize(handles);i++) if(handles[i]!=INVALID_HANDLE) IndicatorRelease(handles[i]);
   Finish();
  }

