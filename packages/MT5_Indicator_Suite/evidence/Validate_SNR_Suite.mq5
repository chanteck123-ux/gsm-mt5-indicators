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
const int N=160;
const string Sym="CODEX_SUITE_SNR_MANUAL";
const string FlatSym="CODEX_SUITE_SNR_STALL";

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

struct Series {double data[];};
int TestHandles[];
string HostNamesBefore[];
long TestChart=0;
const datetime FirstBar=D'2026.03.02 00:00:00';

void Track(const int handle)
{
   const int n=ArraySize(TestHandles); ArrayResize(TestHandles,n+1); TestHandles[n]=handle;
}
void ReleaseTracked(const int handle)
{
   if(handle==INVALID_HANDLE) return;
   IndicatorRelease(handle);
   for(int i=0;i<ArraySize(TestHandles);i++) if(TestHandles[i]==handle) TestHandles[i]=INVALID_HANDLE;
}
void Cleanup()
{
   if(TestChart>0 && TestChart!=ChartID()) {ChartClose(TestChart); TestChart=0; Sleep(100);}
   for(int i=0;i<ArraySize(TestHandles);i++) if(TestHandles[i]!=INVALID_HANDLE) IndicatorRelease(TestHandles[i]);
   ArrayResize(TestHandles,0);
}

void SetBar(MqlRates &r[],const int index,const double low,const double close)
{
   r[index].low=low; r[index].close=close;
}
void BuildFixture(MqlRates &r[],const int mode=0)
{
   ArrayResize(r,N); ZeroMemory(r);
   for(int i=0;i<N;i++)
   {
      r[i].time=FirstBar+i*60; r[i].open=108; r[i].high=110; r[i].low=105; r[i].close=108;
      r[i].tick_volume=100; r[i].real_volume=0; r[i].spread=0;
   }
   r[30].low=100; r[50].low=100.2;
   if(mode==1) // A sustained visit: no rejection and only one visit from bar 60.
   {
      for(int i=60;i<=67;i++) SetBar(r,i,100,100.4);
      return;
   }
   if(mode==2) // First touch fails the minimum reaction by its right-wing close.
   {
      SetBar(r,31,100.9,101.0); SetBar(r,32,101.1,101.2); SetBar(r,33,101.3,101.6);
      return;
   }
   if(mode==3) // Strict pivots exist but are only five bars apart, below min=6.
   {
      r[35].low=100.2; r[50].low=105;
      return;
   }
   if(mode==4) // Equal lows within a right wing are not strict pivots.
   {
      r[32].low=100; return;
   }
   if(mode==5 || mode==6)
   {
      // A close-break followed by a close only INSIDE the old zone, rather than
      // through the opposite boundary. Mode 6 mirrors prices for resistance.
      SetBar(r,70,97,98); SetBar(r,71,97,98);
      if(mode==5)
      {
         SetBar(r,72,99.3,99.5); SetBar(r,73,99.4,99.6); SetBar(r,75,100,108);
      }
      else
      {
         SetBar(r,72,97,98); SetBar(r,73,99.3,99.5);
         for(int i=0;i<N;i++)
         {
            const double old_high=r[i].high;
            r[i].open=200-r[i].open; r[i].close=200-r[i].close;
            r[i].high=200-r[i].low; r[i].low=200-old_high;
         }
      }
      return;
   }
   SetBar(r,60,100,100.5); SetBar(r,61,100.1,100.6); SetBar(r,62,100.1,101);
   SetBar(r,63,99.9,104); SetBar(r,64,100.1,104); SetBar(r,65,100.1,104);
   SetBar(r,67,98.9,100.3);
   SetBar(r,70,97,98); SetBar(r,71,97,98); SetBar(r,72,94.8,95); SetBar(r,73,94,95);
   SetBar(r,79,100,100.4);
   SetBar(r,82,97,98); SetBar(r,84,97,98); SetBar(r,86,98.9,100.3);
}

bool FixtureFailure(const string symbol,const string stage)
{
   Note(StringFormat("FIXTURE_FAIL symbol=%s stage=%s error=%d",symbol,stage,GetLastError()));
   return false;
}
bool InstallFixture(const string symbol,const MqlRates &r[],const int count)
{
   ResetLastError();
   if(StringFind(symbol,"CODEX_SUITE_SNR_")!=0 || count<1 || count>ArraySize(r)) return FixtureFailure(symbol,"guard-name-or-count");
   bool custom=false;
   const bool exists=SymbolExist(symbol,custom);
   if(exists && !custom) return FixtureFailure(symbol,"existing-symbol-is-not-custom");
   ResetLastError();
   if(!exists && !CustomSymbolCreate(symbol,"CodexValidation\\SNR")) return FixtureFailure(symbol,"CustomSymbolCreate");
   ResetLastError();
   if(!CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,5)) return FixtureFailure(symbol,"set-digits");
   ResetLastError();
   if(!CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.00001)) return FixtureFailure(symbol,"set-point");
   ResetLastError();
   if(!CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED)) return FixtureFailure(symbol,"disable-trading");
   ResetLastError();
   if(!SymbolSelect(symbol,true)) return FixtureFailure(symbol,"SymbolSelect-before-history");
   // A newly created unique symbol has no history to delete. On a same-name
   // rerun, inspect the owned known fixture range first: empty history is valid,
   // while read/delete errors other than ERR_HISTORY_NOT_FOUND (4401) fail.
   if(exists)
   {
      MqlTick old_ticks[];
      ResetLastError();
      const int ticks_found=CopyTicksRange(symbol,old_ticks,COPY_TICKS_ALL,(ulong)FirstBar*1000,(ulong)(FirstBar+10000*60)*1000);
      const int ticks_error=GetLastError();
      if(ticks_found<0 && ticks_error!=4401) return FixtureFailure(symbol,"inspect-old-ticks");
      if(ticks_found>0)
      {
         ResetLastError();
         if(CustomTicksDelete(symbol,(ulong)FirstBar*1000,(ulong)(FirstBar+10000*60)*1000)<0) return FixtureFailure(symbol,"delete-existing-ticks");
      }
      MqlRates old_rates[];
      ResetLastError();
      const int rates_found=CopyRates(symbol,PERIOD_M1,FirstBar,FirstBar+10000*60,old_rates);
      const int rates_error=GetLastError();
      if(rates_found<0 && rates_error!=4401) return FixtureFailure(symbol,"inspect-old-rates");
      if(rates_found>0)
      {
         ResetLastError();
         if(CustomRatesDelete(symbol,FirstBar,FirstBar+10000*60)<0) return FixtureFailure(symbol,"delete-existing-rates");
      }
      Note(StringFormat("FIXTURE_CLEAN symbol=%s ticks_found=%d tick_error=%d rates_found=%d rates_error=%d",symbol,ticks_found,ticks_error,rates_found,rates_error));
   }
   MqlRates selected[]; ArrayResize(selected,count);
   for(int i=0;i<count;i++) selected[i]=r[i];
   ResetLastError();
   const int replaced=CustomRatesReplace(symbol,selected[0].time,selected[count-1].time,selected);
   if(replaced!=count) return FixtureFailure(symbol,StringFormat("CustomRatesReplace-returned-%d-expected-%d",replaced,count));
   Note(StringFormat("FIXTURE_READY symbol=%s existed=%d published_bars=%d",symbol,exists,replaced));
   return true;
}

int SNR(const string symbol,const bool show_bad=true,const bool show_minor=true,const bool draw=false,const int return_bars=3)
{
   int handle=iCustom(symbol,PERIOD_M1,"GSM_SNR_MT5",3,14,0.15,0.50,6,3,6,20,3,1500,3000,30,
                      show_bad,show_minor,false,true,true,draw,clrSeaGreen,clrCrimson,clrDimGray,return_bars);
   Track(handle); return handle;
}

bool Ready(const int handle,const int count,const int timeout=12000)
{
   if(handle==INVALID_HANDLE) return false;
   const ulong deadline=GetTickCount64()+(ulong)timeout;
   double poke[];
   while(GetTickCount64()<deadline && GetTickCount64()-Started<115000 && !IsStopped())
   {
      if(CopyBuffer(handle,0,0,1,poke)==1 && BarsCalculated(handle)==count) return true;
      if(BarsCalculated(handle)>count) {Note(StringFormat("EXCESS_BARS handle=%d actual=%d expected=%d",handle,BarsCalculated(handle),count)); return false;}
      Sleep(100);
   }
   Note(StringFormat("NOT_READY handle=%d calculated=%d required=%d error=%d",handle,BarsCalculated(handle),count,GetLastError()));
   return false;
}
bool ReadAll(const int handle,const int count,Series &result[])
{
   ArrayResize(result,14);
   for(int b=0;b<14;b++)
   {
      ArraySetAsSeries(result[b].data,false);
      const int copied=CopyBuffer(handle,b,0,count,result[b].data);
      if(copied!=count) {Note(StringFormat("COPY_FAIL handle=%d buffer=%d got=%d needed=%d error=%d",handle,b,copied,count,GetLastError())); return false;}
   }
   return true;
}
void Same(const int metric,const double actual,const double expected)
{
   if(actual==EMPTY_VALUE || expected==EMPTY_VALUE) Condition(metric,actual==EMPTY_VALUE && expected==EMPTY_VALUE);
   else Compare(metric,actual,expected);
}
bool Bit(const double value,const int mask)
{
   return Good(value) && (((int)value & mask)==mask);
}

void ReferenceATR(const MqlRates &r[],double &atr[])
{
   ArrayResize(atr,ArraySize(r)); ArrayInitialize(atr,EMPTY_VALUE);
   double true_ranges[]; ArrayResize(true_ranges,ArraySize(r));
   for(int i=1;i<ArraySize(r);i++)
      true_ranges[i]=MathMax(r[i].high,r[i-1].close)-MathMin(r[i].low,r[i-1].close);
   double initial=0;
   for(int i=1;i<=14;i++) initial+=true_ranges[i];
   atr[14]=initial/14.0;
   for(int i=15;i<ArraySize(r);i++) atr[i]=atr[i-1]+(true_ranges[i]-atr[i-1])/14.0;
}

bool AddQuote(const string symbol,const MqlRates &bar)
{
   MqlTick quotes[]; ArrayResize(quotes,1); ZeroMemory(quotes[0]);
   quotes[0].time=bar.time+59; quotes[0].time_msc=(long)quotes[0].time*1000;
   quotes[0].bid=bar.close; quotes[0].ask=bar.close; quotes[0].last=bar.close;
   quotes[0].volume=1; quotes[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   return CustomTicksAdd(symbol,quotes)==1;
}

bool HostHad(const string name)
{
   for(int i=0;i<ArraySize(HostNamesBefore);i++) if(HostNamesBefore[i]==name) return true;
   return false;
}
void CleanVisualHost()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,"GSNR_")==0 && !HostHad(name)) ObjectDelete(0,name);
   }
}
int RectangleCount(const long chart)
{
   int count=0;
   for(int i=0;i<ObjectsTotal(chart);i++)
   {
      string name=ObjectName(chart,i);
      if(StringFind(name,"GSNR_")==0 && ObjectGetInteger(chart,name,OBJPROP_TYPE)==OBJ_RECTANGLE) count++;
   }
   return count;
}

void VisualCheck(const string symbol,const double lower,const double upper)
{
   const int visual=AddMetric("Actual SNR chart objects frozen bounds role time and native-canvas screenshot");
   ArrayResize(HostNamesBefore,ObjectsTotal(0));
   for(int i=0;i<ArraySize(HostNamesBefore);i++) HostNamesBefore[i]=ObjectName(0,i);
   TestChart=ChartOpen(symbol,PERIOD_M1);
   if(TestChart<=0 || TestChart==ChartID()) {Condition(visual,false); return;}
   ChartSetInteger(TestChart,CHART_MODE,CHART_CANDLES); ChartSetInteger(TestChart,CHART_SHOW_GRID,false);
   ChartSetInteger(TestChart,CHART_SCALE,4); ChartSetInteger(TestChart,CHART_AUTOSCROLL,true);
   ChartSetInteger(TestChart,CHART_SHIFT,true); ChartSetDouble(TestChart,CHART_SHIFT_SIZE,20);
   ChartSetString(TestChart,CHART_COMMENT,"SYNTHETIC DATA / VISUAL CHECK ONLY\nGSM SNR: real compiled indicator on scripted manual bars. No trade performance.");
   int handle=SNR(symbol,false,true,true);
   bool attached=handle!=INVALID_HANDLE && ChartIndicatorAdd(TestChart,0,handle);
   bool ready=attached && Ready(handle,80);
   ChartRedraw(TestChart); Sleep(500);
   bool template_applied=false;
   if(attached && RectangleCount(TestChart)==0)
   {
      // Keep the complete requested name short. A 31-character name was
      // silently rewritten by MT5 to *.tp.tpl, so applying the original failed.
      string tpl="snr_"+IntegerToString((long)Started)+".tpl";
      ResetLastError();
      bool saved=ChartSaveTemplate(TestChart,tpl);
      const int save_error=GetLastError();
      if(saved)
      {
         ResetLastError();
         const bool deleted=ChartIndicatorDelete(TestChart,0,"GSM SNR (confirmed zones)");
         const int delete_error=GetLastError();
         ReleaseTracked(handle); handle=INVALID_HANDLE;
         Sleep(200); CleanVisualHost();
         ResetLastError();
         template_applied=ChartApplyTemplate(TestChart,tpl);
         const int apply_error=GetLastError();
         if(template_applied)
         {
            const ulong deadline=GetTickCount64()+12000;
            while(GetTickCount64()<deadline && !IsStopped())
            {
               if(handle==INVALID_HANDLE && ChartIndicatorsTotal(TestChart,0)>0)
               {
                  handle=ChartIndicatorGet(TestChart,0,"GSM SNR (confirmed zones)");
                  if(handle!=INVALID_HANDLE) Track(handle);
               }
               if(handle!=INVALID_HANDLE)
               {
                  double poke[];
                  ready=CopyBuffer(handle,0,0,1,poke)==1 && BarsCalculated(handle)==80;
               }
               ChartRedraw(TestChart);
               if(ready && RectangleCount(TestChart)>0) break;
               Sleep(100);
            }
         }
         Note(StringFormat("SNR_TEMPLATE name=%s saved=%d save_error=%d deleted=%d delete_error=%d applied=%d apply_error=%d ready=%d target_objects=%d rectangles=%d host_objects=%d",
                           tpl,saved,save_error,deleted,delete_error,template_applied,apply_error,ready,ObjectsTotal(TestChart),RectangleCount(TestChart),ObjectsTotal(0)));
      }
      else Note(StringFormat("SNR_TEMPLATE name=%s saved=0 save_error=%d",tpl,save_error));
   }
   ChartNavigate(TestChart,CHART_END,0); ChartRedraw(TestChart); Sleep(500);
   int rectangles=RectangleCount(TestChart),checked=0;
   for(int i=0;i<ObjectsTotal(TestChart);i++)
   {
      string name=ObjectName(TestChart,i);
      if(StringFind(name,"GSNR_")!=0 || ObjectGetInteger(TestChart,name,OBJPROP_TYPE)!=OBJ_RECTANGLE) continue;
      Compare(visual,ObjectGetDouble(TestChart,name,OBJPROP_PRICE,0),upper);
      Compare(visual,ObjectGetDouble(TestChart,name,OBJPROP_PRICE,1),lower);
      Compare(visual,(double)ObjectGetInteger(TestChart,name,OBJPROP_TIME,0),(double)(FirstBar+75*60),0);
      Compare(visual,(double)ObjectGetInteger(TestChart,name,OBJPROP_WIDTH),2,0);
      Condition(visual,StringFind(ObjectGetString(TestChart,name,OBJPROP_TOOLTIP),"MAJOR SUPPORT")>=0);
      checked++;
   }
   int width=(int)ChartGetInteger(TestChart,CHART_WIDTH_IN_PIXELS,0);
   int height=(int)ChartGetInteger(TestChart,CHART_HEIGHT_IN_PIXELS,0);
   const string picture="suite_snr.png";
   if(FileIsExist(picture)) FileDelete(picture);
   bool shot=width>0 && height>0 && ChartScreenShot(TestChart,picture,width,height,ALIGN_RIGHT);
   bool exists=false;
   for(int k=0;k<30;k++) {if(FileIsExist(picture)) {exists=true;break;} Sleep(100);}
   Condition(visual,attached && ready && rectangles==1 && checked==1 && shot && exists);
   Note(StringFormat("SNR_VISUAL chart=%I64d attached=%d ready=%d template=%d rectangles=%d objects=%d width=%d height=%d screenshot=%d exists=%d",TestChart,attached,ready,template_applied,rectangles,ObjectsTotal(TestChart),width,height,shot,exists));
   if(handle!=INVALID_HANDLE) ReleaseTracked(handle);
   ChartClose(TestChart); TestChart=0; Sleep(200); CleanVisualHost();
}

void OnStart()
{
   Started=GetTickCount64(); Summary=FileOpen("suite_snr_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("SYNTHETIC MANUAL SCENARIOS. No trades or account API calls. Engineering thresholds are not handbook-specified numeric rules.");
   int setup=AddMetric("SNR named custom fixture creation and all indicator buffers ready");
   MqlRates r[],stall_r[],weak_r[],separation_r[],equal_r[],future_r[],live_r[],return_support_r[],return_resistance_r[];
   BuildFixture(r); BuildFixture(stall_r,1); BuildFixture(weak_r,2); BuildFixture(separation_r,3); BuildFixture(equal_r,4);
   BuildFixture(return_support_r,5); BuildFixture(return_resistance_r,6);
   ArrayCopy(future_r,r); ArrayCopy(live_r,r);
   for(int i=90;i<N;i++)
   {
      double c=80.0+25.0*MathSin(i*0.9);
      future_r[i].open=c; future_r[i].close=c; future_r[i].low=c-5.0; future_r[i].high=c+5.0;
   }
   live_r[N-1].open=50; live_r[N-1].close=50; live_r[N-1].low=40; live_r[N-1].high=160;
   string symbols[11]={Sym,"CODEX_SUITE_SNR_STALL","CODEX_SUITE_SNR_WEAK","CODEX_SUITE_SNR_SEP","CODEX_SUITE_SNR_EQUAL",
                       "CODEX_SUITE_SNR_FUTURE","CODEX_SUITE_SNR_LIVE","CODEX_SUITE_SNR_APPEND","CODEX_SUITE_SNR_VIS",
                       "CODEX_SUITE_SNR_RS","CODEX_SUITE_SNR_RR"};
   const string suffix=StringFormat("_%06d",(int)(TimeLocal()%1000000));
   for(int k=0;k<ArraySize(symbols);k++) {symbols[k]+=suffix; Note("FIXTURE "+symbols[k]);}
   bool created=InstallFixture(symbols[0],r,N) && InstallFixture(symbols[1],stall_r,N) && InstallFixture(symbols[2],weak_r,N) &&
                InstallFixture(symbols[3],separation_r,N) && InstallFixture(symbols[4],equal_r,N) && InstallFixture(symbols[5],future_r,N) &&
                InstallFixture(symbols[6],live_r,N) && InstallFixture(symbols[7],r,54) && InstallFixture(symbols[8],r,80) &&
                InstallFixture(symbols[9],return_support_r,N) && InstallFixture(symbols[10],return_resistance_r,N);
   if(!created) {Condition(setup,false); Cleanup(); Finish(); return;}
   int full_h=SNR(symbols[0]),default_h=SNR(symbols[0],false),major_h=SNR(symbols[0],false,false);
   int stall_h=SNR(symbols[1]),stall_default_h=SNR(symbols[1],false),weak_h=SNR(symbols[2]),sep_h=SNR(symbols[3]),equal_h=SNR(symbols[4]);
   int future_h=SNR(symbols[5]),live_h=SNR(symbols[6]),append_h=SNR(symbols[7]);
   int return_support_h=SNR(symbols[9]),return_resistance_h=SNR(symbols[10]),return_off_h=SNR(symbols[9],true,true,false,0);
   for(int k=0;k<ArraySize(TestHandles);k++)
      if(!Ready(TestHandles[k],TestHandles[k]==append_h ? 54 : N)) {Condition(setup,false); Cleanup(); Finish(); return;}
   Series full[],defaults[],major[],stall[],stall_defaults[],weak[],separation[],equal[],future[],live[],prefix[],return_support[],return_resistance[],return_off[];
   if(!ReadAll(full_h,N,full) || !ReadAll(default_h,N,defaults) || !ReadAll(major_h,N,major) || !ReadAll(stall_h,N,stall) ||
      !ReadAll(stall_default_h,N,stall_defaults) || !ReadAll(weak_h,N,weak) || !ReadAll(sep_h,N,separation) || !ReadAll(equal_h,N,equal) ||
      !ReadAll(future_h,N,future) || !ReadAll(live_h,N,live) || !ReadAll(append_h,54,prefix) ||
      !ReadAll(return_support_h,N,return_support) || !ReadAll(return_resistance_h,N,return_resistance) || !ReadAll(return_off_h,N,return_off))
   {Condition(setup,false); Cleanup(); Finish(); return;}
   Condition(setup,true);
   int atr_metric=AddMetric("Independent Wilder ATR and first-pivot frozen zone width");
   int formation=AddMetric("Exactly two separated strict-pivot reactions; activation at second pivot plus wing");
   int geometry=AddMetric("Zone bounds remain frozen through reactions ATR changes and both role flips");
   int wait=AddMetric("Formation and distant price emit no arrival/rejection; first arrival is not a chase signal");
   int visits=AddMetric("One continuous multi-bar visit counts once; outside bar re-arms next visit");
   int major_metric=AddMetric("Two reactions are minor and third confirmed reaction makes zone major");
   int flips=AddMetric("Close beyond distal boundary flips both ways without breaking-bar retest");
   int fake=AddMetric("Wick penetration with reclaim flags false break while preserving role");
   int multi_return=AddMetric("Two/three-bar partial-zone reclaim restores original role; zero disables; old break history stays");
   int chop=AddMetric("Three side-to-side close crossings mark bad zone and suppress default display/arrows");
   int timeout=AddMetric("Visit deadline inclusive six elapsed bars; overdue visit becomes bad without extra touch");
   int invalid=AddMetric("Weak first reaction too-close touches and equal lows cannot form confirmed zone");
   int causal=AddMetric("All 14 buffers preserve past prefix under future price perturbation");
   int live_metric=AddMetric("Current bar is a held closed snapshot with zero events/arrival and EMPTY arrows");
   int append_metric=AddMetric("Appending bars reproduces fresh full-history calculation and preserves prior closed prefix");
   double reference_atr[]; ReferenceATR(r,reference_atr);
   const double lower=100.0-0.15*reference_atr[30],upper=100.0+0.15*reference_atr[30];
   for(int i=14;i<N-1;i++) Compare(atr_metric,full[9].data[i],reference_atr[i]);
   Compare(atr_metric,reference_atr[30],75.0/14.0);
   Compare(atr_metric,full[0].data[53],upper); Compare(atr_metric,full[1].data[53],lower);
   for(int i=17;i<=52;i++) {Compare(formation,full[10].data[i],0,0); Condition(formation,!Bit(full[6].data[i],1));}
   Condition(formation,Bit(full[6].data[53],1)); Compare(formation,full[4].data[53],2,0);
   Compare(formation,full[10].data[53],1,0);
   for(int i=0;i<=52;i++) for(int b=0;b<14;b++) Same(formation,prefix[b].data[i],full[b].data[i]);
   Compare(formation,prefix[6].data[53],0,0); Compare(formation,prefix[10].data[53],0,0);
   for(int i=53;i<N;i++)
   {
      if(Good(full[0].data[i])) {Compare(geometry,full[0].data[i],upper); Compare(geometry,full[1].data[i],lower);}
      if(Good(full[2].data[i])) {Compare(geometry,full[2].data[i],upper); Compare(geometry,full[3].data[i],lower);}
   }
   for(int i=53;i<=59;i++)
      Condition(wait,full[13].data[i]==0 && full[7].data[i]==EMPTY_VALUE && full[8].data[i]==EMPTY_VALUE);
   Condition(wait,Bit(full[6].data[60],16) && full[13].data[60]==1 && full[7].data[60]==EMPTY_VALUE);
   for(int i=60;i<=62;i++) Compare(visits,full[4].data[i],2,0);
   Condition(visits,Bit(full[6].data[63],64)); Compare(visits,full[4].data[63],3,0);
   Compare(visits,full[7].data[63],r[63].low-0.1*reference_atr[63]);
   for(int i=61;i<=65;i++) Condition(visits,!Bit(full[6].data[i],16));
   for(int i=64;i<=66;i++) Compare(visits,full[4].data[i],3,0);
   Condition(visits,Bit(full[6].data[67],16)); Compare(visits,full[4].data[68],4,0);
   Condition(major_metric,major[0].data[53]==EMPTY_VALUE && major[4].data[53]==EMPTY_VALUE);
   Compare(major_metric,major[0].data[63],upper); Compare(major_metric,major[4].data[63],3,0);
   Condition(flips,Bit(full[6].data[70],8) && !Bit(full[6].data[70],32));
   Compare(flips,full[2].data[70],upper); Condition(flips,full[0].data[70]==EMPTY_VALUE && full[8].data[70]==EMPTY_VALUE);
   Condition(flips,Bit(full[6].data[74],4) && !Bit(full[6].data[74],16));
   Condition(flips,!Bit(full[6].data[74],256) && !Bit(full[6].data[74],512));
   Compare(flips,full[0].data[74],upper); Condition(flips,full[2].data[74]==EMPTY_VALUE && full[7].data[74]==EMPTY_VALUE);
   Condition(fake,Bit(full[6].data[67],256) && !Bit(full[6].data[67],8) && Good(full[7].data[67]));
   Condition(fake,Bit(full[6].data[71],512) && !Bit(full[6].data[71],4) && Good(full[8].data[71]));
   Compare(fake,full[0].data[67],upper); Compare(fake,full[2].data[71],upper);
   Condition(multi_return,Bit(return_support[6].data[70],8) && Bit(return_support[6].data[72],256));
   Compare(multi_return,return_support[0].data[72],upper); Compare(multi_return,return_support[1].data[72],lower);
   Condition(multi_return,return_support[2].data[72]==EMPTY_VALUE && Good(return_support[7].data[72]));
   Condition(multi_return,!Bit(return_support[6].data[72],4) && !Bit(return_support[6].data[72],16));
   Condition(multi_return,return_support[13].data[73]==0 && return_support[4].data[73]==2);
   Condition(multi_return,Bit(return_support[6].data[75],16) && return_support[4].data[75]==3);
   Condition(multi_return,Bit(return_resistance[6].data[70],4) && Bit(return_resistance[6].data[73],512));
   Compare(multi_return,return_resistance[2].data[73],upper); Compare(multi_return,return_resistance[3].data[73],lower);
   Condition(multi_return,return_resistance[0].data[73]==EMPTY_VALUE && Good(return_resistance[8].data[73]));
   Condition(multi_return,!Bit(return_resistance[6].data[73],8) && !Bit(return_resistance[6].data[73],32));
   Condition(multi_return,!Bit(return_off[6].data[72],256) && Good(return_off[2].data[72]) && return_off[0].data[72]==EMPTY_VALUE);
   Compare(chop,full[12].data[82],0,0); Condition(chop,defaults[2].data[82]==EMPTY_VALUE);
   Compare(chop,full[10].data[82],1,0);
   Condition(chop,Bit(full[6].data[86],256) && full[7].data[86]==EMPTY_VALUE && full[13].data[86]==0);
   Compare(timeout,stall[11].data[66],1,0); Compare(timeout,stall[11].data[67],0,0);
   for(int i=60;i<=68;i++) Compare(timeout,stall[4].data[i],2,0);
   Condition(timeout,stall_defaults[0].data[67]==EMPTY_VALUE && stall[7].data[67]==EMPTY_VALUE);
   for(int i=17;i<N;i++)
   {
      Compare(invalid,weak[10].data[i],0,0); Compare(invalid,separation[10].data[i],0,0); Compare(invalid,equal[10].data[i],0,0);
   }
   for(int b=0;b<14;b++) for(int i=0;i<90;i++) Same(causal,future[b].data[i],full[b].data[i]);
   for(int b=0;b<14;b++) for(int i=0;i<N;i++) Same(live_metric,live[b].data[i],full[b].data[i]);
   Compare(live_metric,full[6].data[N-1],0,0); Compare(live_metric,full[13].data[N-1],0,0);
   Condition(live_metric,full[7].data[N-1]==EMPTY_VALUE && full[8].data[N-1]==EMPTY_VALUE);
   Same(live_metric,full[9].data[N-1],full[9].data[N-2]);

   MqlRates appended[]; ArrayResize(appended,N-54);
   for(int i=54;i<N;i++) appended[i-54]=r[i];
   const bool appended_ok=CustomRatesUpdate(symbols[7],appended)==N-54 && AddQuote(symbols[7],r[N-1]);
   Series appended_values[];
   if(appended_ok && Ready(append_h,N) && ReadAll(append_h,N,appended_values))
   {
      for(int b=0;b<14;b++) for(int i=0;i<N;i++) Same(append_metric,appended_values[b].data[i],full[b].data[i]);
      for(int b=0;b<14;b++) for(int i=0;i<=52;i++) Same(append_metric,appended_values[b].data[i],prefix[b].data[i]);
   }
   else Condition(append_metric,false);

   int csv=FileOpen("suite_snr_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(csv!=INVALID_HANDLE)
   {
      FileWrite(csv,"bar","time","open","high","low","close","support_upper","support_lower","resistance_upper","resistance_lower","support_reactions","resistance_reactions","event_mask","bull_rejection","bear_rejection","ATR","zone_count","support_quality","resistance_quality","arrival_mask");
      for(int i=0;i<N;i++) FileWrite(csv,i,TimeToString(r[i].time,TIME_DATE|TIME_MINUTES),r[i].open,r[i].high,r[i].low,r[i].close,
                                   full[0].data[i],full[1].data[i],full[2].data[i],full[3].data[i],full[4].data[i],full[5].data[i],full[6].data[i],
                                   full[7].data[i],full[8].data[i],full[9].data[i],full[10].data[i],full[11].data[i],full[12].data[i],full[13].data[i]);
      FileClose(csv);
   }
   Note(StringFormat("MANUAL_REFERENCE pivot1=30 pivot2=50 activation_closed_bar=53 known_from_bar=54 lower=%.12f upper=%.12f arrival=60 bounce=63 fake_down=67 S_to_R=70 fake_up=71 R_to_S=74 third_cross=82 stall_bad=67",lower,upper));
   VisualCheck(symbols[8],lower,upper);
   Cleanup(); Finish();
}

