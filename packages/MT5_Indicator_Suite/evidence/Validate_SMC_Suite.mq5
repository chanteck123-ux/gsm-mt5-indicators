// Deterministic runtime tests on disabled custom symbols. No trading/account access.
#property strict
#property version "1.00"
struct Metric { string name; int samples,failed; double max_error; };
struct Row { double v[35]; };
Metric Metrics[];
int Report=INVALID_HANDLE;
ulong Started=0;
const int FullN=1500,PrefixN=1100;
string FullSym,PrefixSym,FutureSym,ProbeSym;

void Note(const string s)
{
   Print(s);
   if(Report!=INVALID_HANDLE) { FileWrite(Report,s); FileFlush(Report); }
}
int MetricId(const string name)
{
   int i=ArraySize(Metrics); ArrayResize(Metrics,i+1);
   Metrics[i].name=name; Metrics[i].samples=0; Metrics[i].failed=0; Metrics[i].max_error=0;
   return i;
}
void Check(const int m,const bool condition)
{
   Metrics[m].samples++;
   if(!condition) Metrics[m].failed++;
}
void Equal(const int m,const double actual,const double expected,const double eps=1e-9)
{
   Metrics[m].samples++;
   if(actual==EMPTY_VALUE && expected==EMPTY_VALUE) return;
   if(actual==EMPTY_VALUE || expected==EMPTY_VALUE || !MathIsValidNumber(actual) || !MathIsValidNumber(expected))
   { Metrics[m].failed++; Metrics[m].max_error=DBL_MAX; return; }
   double error=MathAbs(actual-expected);
   if(error>Metrics[m].max_error) Metrics[m].max_error=error;
   if(error>eps) Metrics[m].failed++;
}
void Finish()
{
   int bad=0;
   for(int i=0;i<ArraySize(Metrics);i++)
   {
      bool okay=(Metrics[i].samples>0 && Metrics[i].failed==0);
      if(!okay) bad++;
      Note(StringFormat("%s | %s | samples=%d | failures=%d | max_error=%.12g",okay ? "PASS" : "FAIL",
                        Metrics[i].name,Metrics[i].samples,Metrics[i].failed,Metrics[i].max_error));
   }
   Note(StringFormat("OVERALL=%s | groups=%d | failed_groups=%d | elapsed_ms=%I64u",bad==0 ? "PASS" : "FAIL",
                     ArraySize(Metrics),bad,GetTickCount64()-Started));
   if(Report!=INVALID_HANDLE) { FileClose(Report); Report=INVALID_HANDLE; }
}

void BuildRates(MqlRates &a[],const int n,const bool future,const bool probe=false)
{
   ArrayResize(a,n);
   double previous=100;
   for(int i=0;i<n;i++)
   {
      ZeroMemory(a[i]);
      int phase=i%360,step=i%120;
      double trend=(phase<180 ? phase*0.045 : (360-phase)*0.045);
      double displacement=(step<40 ? 0 : (step<80 ? 3.5 : -2.0));
      double c=100+trend+2.6*MathSin(i*0.10)+0.65*MathSin(i*0.38)+displacement;
      if(future && i>=PrefixN) c+=45*MathSin(i*0.63)+20;
      if(probe) c=(i<20 ? 100+0.05*i : (i<50 ? 105-0.06*(i-20) : 100+0.05*(i-50)));
      c=NormalizeDouble(c,6);
      a[i].time=D'2026.01.05 00:00:00'+i*60;
      a[i].open=(probe ? c : previous); a[i].close=c;
      a[i].high=NormalizeDouble(MathMax(a[i].open,c)+0.07+0.003*(i%7),6);
      a[i].low=NormalizeDouble(MathMin(a[i].open,c)-0.08-0.004*(i%9),6);
      if(probe)
      {
         a[i].high=c+0.05; a[i].low=c-0.05;
         if(i==30) { a[i].high=150; a[i].low=10; }
         if(i==45) a[i].high=140;
         if(i==50) a[i].low=50;
      }
      a[i].tick_volume=100+i%37; a[i].spread=0;
      previous=c;
   }
}
bool Publish(const string symbol,MqlRates &a[])
{
   bool custom=false;
   bool exists=SymbolExist(symbol,custom);
   if((exists && !custom) || (!exists && !CustomSymbolCreate(symbol,"CodexValidation"))) return false;
   if(!CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,6) || !CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.000001) ||
      !CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED)) return false;
   // These exact CODEX_SMC_* symbols are test-owned. Replace their entire fixture range.
   if(CustomRatesReplace(symbol,D'2026.01.01',D'2026.12.31 23:59:59',a)!=ArraySize(a)) return false;
   return SymbolSelect(symbol,true);
}
bool WarmFrame(const string symbol,const ENUM_TIMEFRAMES tf,const int expected)
{
   // Trigger timeframe construction from the SCRIPT, which can wait for history.
   // An indicator's first CopyRates may return -1 and, on an offline fixture,
   // there is no live tick to schedule another OnCalculate.
   ulong deadline=GetTickCount64()+60000;
   MqlRates warm[];
   while(GetTickCount64()<deadline && !IsStopped())
   {
      int copied=CopyRates(symbol,tf,0,expected,warm);
      int available=Bars(symbol,tf);
      if(copied==expected && available==expected)
      {
         Note(StringFormat("WARM_READY symbol=%s tf=%s bars=%d",symbol,EnumToString(tf),available));
         return true;
      }
      if(available>expected)
      {
         Note(StringFormat("UNEXPECTED_HISTORY symbol=%s tf=%s actual=%d expected=%d",symbol,EnumToString(tf),available,expected));
         return false;
      }
      Sleep(100);
   }
   Note(StringFormat("WARM_FAIL symbol=%s tf=%s expected=%d bars=%d err=%d",symbol,EnumToString(tf),expected,Bars(symbol,tf),GetLastError()));
   return false;
}
bool WarmAll(const string symbol,const int count)
{
   return WarmFrame(symbol,PERIOD_M1,count) && WarmFrame(symbol,PERIOD_M5,(count+4)/5) && WarmFrame(symbol,PERIOD_D1,(count+1439)/1440);
}
int Load(const string sym,const bool draw=false,const int swing_length=50,const bool monochrome=false,
         const ENUM_TIMEFRAMES fvg_timeframe=PERIOD_CURRENT,const int mitigation=0,const bool all_features=true)
{
   // Source port has no input groups. 38 genuine inputs; input 32 is DrawObjects.
   // Enable both OB classes and FVG for feature coverage; production FVG default is false.
   return iCustom(sym,PERIOD_M1,"SMC_Structure_MT5",5,swing_length,3,0.10,0,mitigation,false,
                  true,true,0,0,0,0,true,all_features,5,5,true,all_features,true,fvg_timeframe,1,
                  true,all_features,all_features,false,false,false,false,false,monochrome,draw,false,true,3000,100,50,120);
}
bool Ready(const int h,const int count,const int timeout_ms=60000)
{
   ulong deadline=GetTickCount64()+(ulong)timeout_ms;
   double poke[];
   while(GetTickCount64()<deadline && !IsStopped())
   {
      int copied=CopyBuffer(h,0,0,1,poke);
      if(copied==1 && BarsCalculated(h)==count) return true;
      if(BarsCalculated(h)>count)
      { Note(StringFormat("UNEXPECTED_BUFFER_COUNT h=%d actual=%d expected=%d",h,BarsCalculated(h),count)); return false; }
      if(h==INVALID_HANDLE) break;
      Sleep(100);
   }
   Note(StringFormat("NOT_READY h=%d expected=%d bars=%d error=%d",h,count,BarsCalculated(h),GetLastError()));
   return false;
}
bool RefreshOldHandleWithQuote(const string symbol,const int handle,const int count,const MqlRates &current_bar)
{
   // CustomRatesUpdate is an offline history write, not a server quote event.
   // A dependent iCustom has no timer-based calculation retry. After dependencies
   // are ready, publish a real custom quote inside the SAME unfinished minute.
   // The OLD handle must recover; a fresh handle is never accepted as a substitute.
   for(int attempt=0;attempt<3 && !IsStopped();attempt++)
   {
      if(!WarmAll(symbol,count)) return false;
      MqlTick prior,ticks[]; ZeroMemory(prior); ArrayResize(ticks,1); ZeroMemory(ticks[0]);
      long next_msc=(long)current_bar.time*1000+59000+attempt;
      if(SymbolInfoTick(symbol,prior) && prior.time_msc>=next_msc) next_msc=prior.time_msc+1;
      if(next_msc>=(long)(current_bar.time+60)*1000)
      { Note("QUOTE_FAIL: cannot advance tick without leaving the intended current bar"); return false; }
      ticks[0].time_msc=next_msc; ticks[0].time=(datetime)(next_msc/1000);
      ticks[0].bid=current_bar.close; ticks[0].ask=current_bar.close; ticks[0].last=current_bar.close;
      ticks[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
      ResetLastError();
      int added=CustomTicksAdd(symbol,ticks);
      int error=GetLastError();
      Note(StringFormat("QUOTE_PULSE symbol=%s attempt=%d time_msc=%I64d price=%.6f added=%d error=%d old_handle=%d",
                        symbol,attempt+1,next_msc,current_bar.close,added,error,handle));
      if(added!=1) return false;
      Sleep(150);
      if(!SourceUpdated(symbol,current_bar))
      {
         MqlRates observed[];
         if(CopyRates(symbol,PERIOD_M1,current_bar.time,current_bar.time,observed)==1)
            Note(StringFormat("QUOTE_CHANGED_OHLC expected=%.6f/%.6f/%.6f/%.6f actual=%.6f/%.6f/%.6f/%.6f",
                              current_bar.open,current_bar.high,current_bar.low,current_bar.close,
                              observed[0].open,observed[0].high,observed[0].low,observed[0].close));
         return false;
      }
      if(!WarmAll(symbol,count)) return false;
      if(Ready(handle,count,5000))
      {
         Note(StringFormat("OLD_HANDLE_RECOVERED symbol=%s handle=%d quote_attempt=%d bars=%d",symbol,handle,attempt+1,BarsCalculated(handle)));
         return true;
      }
   }
   return false;
}
bool Snapshot(const int h,const int n,Row &rows[])
{
   ArrayResize(rows,n);
   double a[]; ArraySetAsSeries(a,false);
   for(int b=0;b<35;b++)
   {
      int count=CopyBuffer(h,b,0,n,a);
      if(count!=n) { Note(StringFormat("COPY_FAIL buffer=%d expected=%d copied=%d error=%d",b,n,count,GetLastError())); return false; }
      for(int i=0;i<n;i++) rows[i].v[b]=a[i];
   }
   return true;
}
bool SourceUpdated(const string symbol,const MqlRates &expected)
{
   const ulong deadline=GetTickCount64()+10000;
   MqlRates observed[];
   while(GetTickCount64()<deadline && !IsStopped())
   {
      if(CopyRates(symbol,PERIOD_M1,expected.time,expected.time,observed)==1 &&
         observed[0].time==expected.time && MathAbs(observed[0].open-expected.open)<1e-9 && MathAbs(observed[0].close-expected.close)<1e-9 &&
         MathAbs(observed[0].high-expected.high)<1e-9 && MathAbs(observed[0].low-expected.low)<1e-9)
         return true;
      Sleep(50);
   }
   return false;
}
void CompareHistory(const int metric,Row &a[],Row &b[],const int n)
{
   for(int i=0;i<n;i++) for(int k=0;k<35;k++) Equal(metric,a[i].v[k],b[i].v[k]);
}
void ExportEvents(MqlRates &rates[],Row &rows[])
{
   int f=FileOpen("suite_smc_events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f==INVALID_HANDLE) { Note("Unable to write suite_smc_events.csv"); return; }
   FileWrite(f,"bar_index","bar_open","known_from","open","high","low","close","internal_bias","swing_bias",
               "internal_event","swing_event","region_mask","swing_high","swing_low","bull_ob_upper","bull_ob_lower",
               "bear_ob_upper","bear_ob_lower","bull_fvg_upper","bull_fvg_lower","bear_fvg_upper","bear_fvg_lower","ob_count","fvg_count");
   for(int i=1;i<ArraySize(rows)-1;i++)
   {
      if(rows[i].v[2]==0 && rows[i].v[3]==0 && rows[i].v[14]==0) continue;
      FileWrite(f,i,TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES),TimeToString(rates[i+1].time,TIME_DATE|TIME_MINUTES),
                rates[i].open,rates[i].high,rates[i].low,rates[i].close,rows[i].v[0],rows[i].v[1],
                rows[i].v[2],rows[i].v[3],rows[i].v[14],rows[i].v[4],rows[i].v[5],rows[i].v[6],rows[i].v[7],
                rows[i].v[8],rows[i].v[9],rows[i].v[10],rows[i].v[11],rows[i].v[12],rows[i].v[13],rows[i].v[16],rows[i].v[17]);
   }
   FileClose(f);
}

int CountSMCObjects(const long chart)
{
   int n=0;
   for(int i=0;i<ObjectsTotal(chart,0,-1);i++) if(StringFind(ObjectName(chart,i,0,-1),"SMCL_")==0) n++;
   return n;
}
void DrawCheck()
{
   int m=MetricId("Native chart-owned source SMC, OB/FVG objects and actual-canvas screenshot");
   string host_before[];
   int n_host=ObjectsTotal(0,0,-1); ArrayResize(host_before,n_host);
   for(int i=0;i<n_host;i++) host_before[i]=ObjectName(0,i,0,-1);
   long view=ChartOpen(PrefixSym,PERIOD_M1);
   if(view==0) { Check(m,false); return; }
   for(int i=ChartIndicatorsTotal(view,0)-1;i>=0;i--) ChartIndicatorDelete(view,0,ChartIndicatorName(view,0,i));
   ChartSetInteger(view,CHART_SHOW_GRID,false);
   ChartSetInteger(view,CHART_SCALE,3);
   ChartSetInteger(view,CHART_COLOR_BACKGROUND,clrWhite);
   ChartSetInteger(view,CHART_COLOR_FOREGROUND,clrBlack);
   ChartSetInteger(view,CHART_COLOR_CHART_UP,clrDarkGreen);
   ChartSetInteger(view,CHART_COLOR_CHART_DOWN,clrFireBrick);
   ChartSetInteger(view,CHART_COLOR_CANDLE_BULL,clrSeaGreen);
   ChartSetInteger(view,CHART_COLOR_CANDLE_BEAR,clrIndianRed);
   ChartSetInteger(view,CHART_SHIFT,true); ChartSetDouble(view,CHART_SHIFT_SIZE,20);
   int h=Load(PrefixSym,true);
   bool attached=(h!=INVALID_HANDLE && ChartIndicatorAdd(view,0,h));
   Check(m,attached);
   if(!attached) { Note(StringFormat("ChartIndicatorAdd failed err=%d",GetLastError())); return; }
   Check(m,Ready(h,FullN));
   ChartRedraw(view); Sleep(500);
   if(CountSMCObjects(view)==0)
   {
      string template_name="suite_smc_native_"+IntegerToString((long)Started)+".tpl";
      bool saved=ChartSaveTemplate(view,template_name);
      Check(m,saved);
      if(saved)
      {
         ChartIndicatorDelete(view,0,"SMC LuxAlgo Source (Closed Bars)");
         IndicatorRelease(h); h=INVALID_HANDLE; Sleep(200);
         bool applied=ChartApplyTemplate(view,template_name);
         Check(m,applied);
         ulong deadline=GetTickCount64()+20000;
         while(applied && h==INVALID_HANDLE && GetTickCount64()<deadline && !IsStopped())
         {
            for(int j=0;j<ChartIndicatorsTotal(view,0);j++)
            {
               string label=ChartIndicatorName(view,0,j);
               if(label=="SMC LuxAlgo Source (Closed Bars)") { h=ChartIndicatorGet(view,0,label); break; }
            }
            if(h==INVALID_HANDLE) Sleep(100);
         }
         Check(m,h!=INVALID_HANDLE && Ready(h,FullN));
         Note(StringFormat("NATIVE_TEMPLATE applied=%d target_objects=%d",applied,CountSMCObjects(view)));
      }
   }
   ChartRedraw(view); Sleep(500);
   int object_count=0,ob_labels=0,fvg_labels=0,owners=0;
   for(int i=0;i<ObjectsTotal(view,0,-1);i++)
   {
      string name=ObjectName(view,i,0,-1);
      if(StringFind(name,"SMCL_")!=0) continue;
      object_count++;
      if(StringFind(name,"OWNER")>=0) owners++;
      string label=ObjectGetString(view,name,OBJPROP_TEXT);
      if(StringFind(label,"OB")>=0) ob_labels++;
      if(StringFind(label,"FVG")>=0) fvg_labels++;
   }
   Note(StringFormat("DRAW chart=%I64d host=%I64d objects=%d owners=%d ob_labels=%d fvg_labels=%d",view,ChartID(),object_count,owners,ob_labels,fvg_labels));
   Check(m,object_count>0 && object_count<=450 && owners==1);
   Check(m,ob_labels>0); Check(m,fvg_labels>0);
   int width=(int)ChartGetInteger(view,CHART_WIDTH_IN_PIXELS,0),height=(int)ChartGetInteger(view,CHART_HEIGHT_IN_PIXELS,0);
   if(FileIsExist("suite_smc_chart.png")) FileDelete("suite_smc_chart.png");
   Check(m,width>0 && height>0 && ChartScreenShot(view,"suite_smc_chart.png",width,height,ALIGN_RIGHT));
   bool exists=false;
   for(int j=0;j<30 && !IsStopped();j++) { if(FileIsExist("suite_smc_chart.png")) { exists=true; break; } Sleep(100); }
   Check(m,exists); Note(StringFormat("SCREENSHOT canvas=%dx%d exists=%d",width,height,exists));
   if(h!=INVALID_HANDLE) IndicatorRelease(h);
   ChartClose(view); Sleep(200);
   // Remove only this test's new host-context objects, never pre-existing indicators.
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,"SMCL_")!=0) continue;
      bool existed=false;
      for(int j=0;j<ArraySize(host_before);j++) if(name==host_before[j]) { existed=true; break; }
      if(!existed) ObjectDelete(0,name);
   }
}

void OnStart()
{
   Started=GetTickCount64();
   string run_id=IntegerToString((long)(Started%100000000));
   FullSym="CODEX_SMC_F_"+run_id; PrefixSym="CODEX_SMC_P_"+run_id;
   FutureSym="CODEX_SMC_U_"+run_id; ProbeSym="CODEX_SMC_T_"+run_id;
   Report=FileOpen("suite_smc_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("SMC complete LuxAlgo source adaptation validation. Synthetic M1 fixtures; no performance/trading claims.");
   int setup=MetricId("Custom fixtures, disabled trading and all 35 public buffers ready");
   MqlRates full[],prefix[],future[],probe[];
   BuildRates(full,FullN,false); BuildRates(prefix,PrefixN,false); BuildRates(future,FullN,true); BuildRates(probe,90,false,true);
   if(!Publish(FullSym,full) || !Publish(PrefixSym,prefix) || !Publish(FutureSym,future) || !Publish(ProbeSym,probe))
   { Check(setup,false); Note(StringFormat("PUBLISH_FAIL err=%d",GetLastError())); Finish(); return; }
   if(!WarmAll(FullSym,FullN) || !WarmAll(PrefixSym,PrefixN) || !WarmAll(FutureSym,FullN) || !WarmAll(ProbeSym,90))
   { Check(setup,false); Finish(); return; }
   int hf=Load(FullSym),hp=Load(PrefixSym),hu=Load(FutureSym),ht=Load(ProbeSym,false,10,false,PERIOD_CURRENT,0,false);
   if(!Ready(hf,FullN) || !Ready(hp,PrefixN) || !Ready(hu,FullN) || !Ready(ht,90))
   { Check(setup,false); Finish(); return; }
   Row f[],p[],u[],t[];
   if(!Snapshot(hf,FullN,f) || !Snapshot(hp,PrefixN,p) || !Snapshot(hu,FullN,u) || !Snapshot(ht,90,t))
   { Check(setup,false); Finish(); return; }
   Check(setup,true);
   Check(setup,SourceUpdated(FullSym,full[FullN-1]));
   Check(setup,SourceUpdated(PrefixSym,prefix[PrefixN-1]));
   Check(setup,SourceUpdated(FutureSym,future[FullN-1]));
   Check(setup,SourceUpdated(ProbeSym,probe[89]));
   int causality=MetricId("Full 1500 vs prefix 1100, all historical buffers through 1098");
   CompareHistory(causality,f,p,PrefixN-1);
   int futureproof=MetricId("Adversarial future prices cannot change prefix historical buffers");
   CompareHistory(futureproof,f,u,PrefixN-1);
   int daily=MetricId("Prior-day high/low appear at next day boundary, never during the source day");
   double day_high=full[0].high,day_low=full[0].low;
   for(int j=1;j<1440;j++) { day_high=MathMax(day_high,full[j].high); day_low=MathMin(day_low,full[j].low); }
   Check(daily,f[1438].v[25]==EMPTY_VALUE && f[1438].v[26]==EMPTY_VALUE);
   for(int j=1439;j<FullN-1;j++) { Equal(daily,f[j].v[25],day_high); Equal(daily,f[j].v[26],day_low); }
   int delay=MetricId("Source leg: exact right-side confirmation, high priority and same-leg suppression");
   for(int b=30;b<40;b++) Check(delay,t[b].v[4]!=150);
   Equal(delay,t[40].v[4],150); Equal(delay,t[41].v[4],150);
   Check(delay,t[40].v[5]!=10); // Candidate has both extreme wicks: source high branch wins.
   Equal(delay,t[55].v[4],150); // A later lower high must not replace a same-direction leg pivot.
   for(int b=50;b<60;b++) Check(delay,t[b].v[5]!=50);
   Equal(delay,t[60].v[5],50); Equal(delay,t[61].v[5],50);
   int bounds=MetricId("Region boundaries, active count cap, event domain and ATR validity");
   int active_price_count=0,mask_or=0,bos_i=0,choch_i=0,bos_s=0,choch_s=0;
   for(int i=1;i<FullN-1;i++)
   {
      for(int b=6;b<=12;b+=2)
      {
         bool empty1=(f[i].v[b]==EMPTY_VALUE),empty2=(f[i].v[b+1]==EMPTY_VALUE);
         Check(bounds,empty1==empty2);
         if(!empty1) { Check(bounds,f[i].v[b]>f[i].v[b+1]); active_price_count++; }
      }
      Check(bounds,f[i].v[16]>=0 && f[i].v[17]>=0 && f[i].v[32]<=100 && f[i].v[33]<=100 && f[i].v[17]<=50);
      Equal(bounds,f[i].v[16],f[i].v[32]+f[i].v[33]);
      Check(bounds,MathAbs(f[i].v[2])<=2 && MathAbs(f[i].v[3])<=2);
      if(i>=199) Check(bounds,f[i].v[15]!=EMPTY_VALUE && MathIsValidNumber(f[i].v[15]) && f[i].v[15]>0);
      else Check(bounds,f[i].v[15]==EMPTY_VALUE);
      mask_or|=(int)f[i].v[14];
      if(MathAbs(f[i].v[2])==1) bos_i++; if(MathAbs(f[i].v[2])==2) choch_i++;
      if(MathAbs(f[i].v[3])==1) bos_s++; if(MathAbs(f[i].v[3])==2) choch_s++;
   }
   Check(bounds,active_price_count>100);
   int coverage=MetricId("Synthetic fixture covers BOS, CHoCH, OB, FVG, retest and invalidation");
   Check(coverage,bos_i>0); Check(coverage,choch_i>0); Check(coverage,bos_s>0); Check(coverage,choch_s>0);
   Check(coverage,(mask_or&3)==3); Check(coverage,(mask_or&12)==12);
   Check(coverage,(mask_or&240)!=0); Check(coverage,(mask_or&3840)!=0);
   Note(StringFormat("COVERAGE internal BOS=%d CHoCH=%d swing BOS=%d CHoCH=%d region_mask_or=%d valid_region_samples=%d",
                     bos_i,choch_i,bos_s,choch_s,mask_or,active_price_count));
   int current=MetricId("Current bar produces no confirmed events and freezes last closed snapshot");
   for(int k=0;k<35;k++)
      if(k==2 || k==3 || k==14 || k==34) Equal(current,f[FullN-1].v[k],0);
      else Equal(current,f[FullN-1].v[k],f[FullN-2].v[k]);
   ExportEvents(full,f);
   int mtf=MetricId("M5 FVG source alignment and 35-buffer prefix/future causality");
   int hmf=Load(FullSym,false,50,false,PERIOD_M5),hmp=Load(PrefixSym,false,50,false,PERIOD_M5),hmu=Load(FutureSym,false,50,false,PERIOD_M5);
   Row mf[],mp[],mu[];
   bool mtf_ready=Ready(hmf,FullN) && Ready(hmp,PrefixN) && Ready(hmu,FullN) && Snapshot(hmf,FullN,mf) && Snapshot(hmp,PrefixN,mp) && Snapshot(hmu,FullN,mu);
   Check(mtf,mtf_ready);
   if(mtf_ready)
   {
      CompareHistory(mtf,mf,mp,PrefixN-1); CompareHistory(mtf,mf,mu,PrefixN-1);
      int created=0;
      for(int j=1;j<FullN-1;j++)
      {
         if(mf[j].v[31]!=EMPTY_VALUE) Check(mtf,mf[j].v[31]<=(double)full[j+1].time);
         if(((int)mf[j].v[14]&12)!=0)
         {
            created++;
            Check(mtf,((long)full[j+1].time%300)==0);
            Equal(mtf,mf[j].v[31],(double)full[j+1].time,0);
         }
      }
      Check(mtf,created>0); Note(StringFormat("M5_FVG_CREATIONS=%d",created));
   }
   IndicatorRelease(hmf); IndicatorRelease(hmp); IndicatorRelease(hmu);
   int update=MetricId("History OHLC update plus quote event refreshes OLD handle without changing closed buffers");
   MqlRates changed[]; ArrayResize(changed,1); changed[0]=full[FullN-1];
   changed[0].close+=60; changed[0].high=MathMax(changed[0].high,changed[0].close+1); changed[0].low-=20;
   Check(update,CustomRatesUpdate(FullSym,changed)==1);
   Check(update,SourceUpdated(FullSym,changed[0]));
   Check(update,WarmAll(FullSym,FullN));
   Sleep(200);
   Row refreshed[];
   bool got=RefreshOldHandleWithQuote(FullSym,hf,FullN,changed[0]) && Snapshot(hf,FullN,refreshed);
   Check(update,got);
   if(got) CompareHistory(update,f,refreshed,FullN-1);
   // Force a distinct calculation block after mutation. Only monochrome DRAW
   // colors differ; source computation gates and public calculations are unchanged.
   // This guards against a false pass from an old handle still exposing cached data.
   int fresh_handle=Load(FullSym,false,50,true);
   Row fresh_replay[];
   got=Ready(fresh_handle,FullN) && Snapshot(fresh_handle,FullN,fresh_replay);
   Check(update,got);
   if(got) CompareHistory(update,f,fresh_replay,FullN-1);
   IndicatorRelease(fresh_handle);
   int append=MetricId("Append plus quote event refreshes OLD handle; prefix and full state remain equal");
   Check(append,CustomRatesUpdate(PrefixSym,full)>=1);
   Check(append,WarmAll(PrefixSym,FullN));
   Sleep(200);
   Row expanded[];
   got=RefreshOldHandleWithQuote(PrefixSym,hp,FullN,full[FullN-1]) && Snapshot(hp,FullN,expanded);
   Check(append,got);
   if(got)
   {
      CompareHistory(append,p,expanded,PrefixN-1);
      CompareHistory(append,f,expanded,FullN-1);
   }
   IndicatorRelease(hf); IndicatorRelease(hp); IndicatorRelease(hu); IndicatorRelease(ht);
   DrawCheck();
   Finish();
}
