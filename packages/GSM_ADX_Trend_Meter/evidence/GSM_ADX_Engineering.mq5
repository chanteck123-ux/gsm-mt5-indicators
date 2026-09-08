// Synthetic, read-only engineering validation for GSM ADX. No trading APIs.
#property strict
#property version "1.00"
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"

const int N=300;
const string PATH="GSM\\GSM_ADX_Trend_Meter";
int Report=INVALID_HANDLE,Groups=0,Failed=0;
ulong Started=0;
string Suffix="";
struct Frame { double v[]; };

void Note(const string message)
  { Print(message); if(Report!=INVALID_HANDLE) {FileWriteString(Report,message+"\r\n");FileFlush(Report);} }
void Check(const string label,const bool passed,const string detail="")
  { Groups++; if(!passed)Failed++; Note((passed?"PASS|":"FAIL|")+label+"|"+detail); }
bool Same(const double a,const double b)
  { return (a==EMPTY_VALUE || b==EMPTY_VALUE)?a==b:MathIsValidNumber(a)&&MathIsValidNumber(b)&&MathAbs(a-b)<=1e-8; }
string Name(const string stem) {return "ADX_"+stem+"_"+Suffix;}

void MakeRates(MqlRates &rates[],const bool flat=false)
  {
   ArrayResize(rates,N);
   for(int k=0;k<N;k++)
     {
      ZeroMemory(rates[k]); rates[k].time=D'2026.03.02 00:00:00'+k*60;
      double close=100+7*MathSin(k/10.0)+2*MathSin(k/2.7)+0.015*k;
      if(k>210)close+=0.12*(k-210);
      rates[k].open=(k>0?rates[k-1].close:100.0);
      rates[k].close=NormalizeDouble(flat?100:close,2);
      if(flat)rates[k].open=100;
      rates[k].high=flat?100:NormalizeDouble(MathMax(rates[k].open,rates[k].close)+0.35+0.2*(1+MathSin(k/3.0)),2);
      rates[k].low=flat?100:NormalizeDouble(MathMin(rates[k].open,rates[k].close)-0.35-0.2*(1+MathCos(k/4.0)),2);
      rates[k].tick_volume=100; rates[k].spread=0;
     }
  }

bool Warm(const string symbol,const int expected,const int timeout=3000)
  {
   ulong end=GetTickCount64()+(ulong)timeout; MqlRates data[];
   while(GetTickCount64()<end && !IsStopped())
     {
      if(CopyRates(symbol,PERIOD_M1,0,expected,data)==expected && Bars(symbol,PERIOD_M1)==expected)return true;
      Sleep(20);
     }
   Note(StringFormat("WARM_FAIL symbol=%s expected=%d bars=%d error=%d",symbol,expected,Bars(symbol,PERIOD_M1),GetLastError()));
   return false;
  }

bool Create(const string symbol,const MqlRates &source[],const int start,const int count)
  {
   bool custom=false;
   if(SymbolExist(symbol,custom)) {Note("FIXTURE_FAIL name unexpectedly exists "+symbol);return false;}
   if(!CustomSymbolCreate(symbol,"GSM_ADX_Validation")) {Note(StringFormat("FIXTURE_FAIL create=%s err=%d",symbol,GetLastError()));return false;}
   CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2);CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01);
   CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
   MqlRates rows[];ArrayResize(rows,count);for(int k=0;k<count;k++)rows[k]=source[start+k];
   return CustomRatesReplace(symbol,rows[0].time,rows[count-1].time,rows)==count && SymbolSelect(symbol,true) && Warm(symbol,count);
  }

int Handle(const string symbol,const int method,const int period=14,const bool draw=false,
           const bool hidden=false,const bool alerts=false,const int panel_x=12,
           const double weak=20,const double trend=25,const double strong=40,
           const double epsilon=0,const int confirm=2,const int cross_window=10,const int cross_min=3,
           const ENUM_TIMEFRAMES tf=PERIOD_M1)
  {
   return iCustom(symbol,tf,PATH,"",method,period,weak,trend,strong,epsilon,confirm,3,10,cross_window,cross_min,false,25.0,
                  "",draw,!hidden,hidden,draw&&!hidden,hidden?7:500,
                  method==0?clrDodgerBlue:clrOrange,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
                  CORNER_LEFT_UPPER,panel_x,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,"",alerts,false,false,false);
  }

bool Ready(const int handle,const int expected,const int timeout=6000)
  {
   const ulong end=GetTickCount64()+(ulong)timeout;double probe[];
   while(handle!=INVALID_HANDLE && GetTickCount64()<end && !IsStopped())
     {
      int copied=CopyBuffer(handle,0,0,1,probe),calculated=BarsCalculated(handle);
      if(copied==1 && calculated==expected)return true;
      if(calculated>expected)break;
      Sleep(20);
     }
   Note(StringFormat("NOT_READY handle=%d expected=%d bars=%d err=%d",handle,expected,BarsCalculated(handle),GetLastError()));return false;
  }

bool Snapshot(const int handle,const int count,Frame &frame[])
  {
   ArrayResize(frame,15);
   for(int b=0;b<15;b++)
     { ArraySetAsSeries(frame[b].v,false); if(CopyBuffer(handle,b,0,count,frame[b].v)!=count)return false; }
   return true;
  }

bool EqualClosed(const Frame &a[],const Frame &b[],const int closed,long &checked,int &bad)
  {
   bad=0;checked=0;
   if(ArraySize(a)!=15 || ArraySize(b)!=15)return false;
   for(int k=0;k<15;k++)
     {
      if(ArraySize(a[k].v)<closed || ArraySize(b[k].v)<closed)return false;
      for(int i=0;i<closed;i++)
        {
         checked++;
         if(!Same(a[k].v[i],b[k].v[i]))
           {
            if(bad<3)Note(StringFormat("DIFF buffer=%d chronological=%d left=%.17g right=%.17g",k,i,a[k].v[i],b[k].v[i]));
            bad++;
           }
        }
     }
   return bad==0;
  }

bool CurrentEmpty(const Frame &frame[],const int count)
  {for(int b=3;b<15;b++)if(frame[b].v[count-1]!=EMPTY_VALUE)return false;return true;}

bool SameOHLC(const string symbol,const MqlRates &expected)
  {
   MqlRates seen[];
   if(CopyRates(symbol,PERIOD_M1,expected.time,expected.time,seen)!=1)return false;
   bool okay=Same(seen[0].open,expected.open)&&Same(seen[0].high,expected.high)&&Same(seen[0].low,expected.low)&&Same(seen[0].close,expected.close);
   if(!okay)Note(StringFormat("OHLC_CHANGED %s expected=%.8f/%.8f/%.8f/%.8f actual=%.8f/%.8f/%.8f/%.8f",
                            symbol,expected.open,expected.high,expected.low,expected.close,seen[0].open,seen[0].high,seen[0].low,seen[0].close));
   return okay;
  }

bool Pulse(const string symbol,const MqlRates &bar)
  {
   MqlTick prior,ticks[];ZeroMemory(prior);ArrayResize(ticks,1);ZeroMemory(ticks[0]);
   long stamp=(long)bar.time*1000+59000;
   if(SymbolInfoTick(symbol,prior) && prior.time_msc>=stamp)stamp=prior.time_msc+1;
   if(stamp>=(long)(bar.time+60)*1000)return false;
   ticks[0].time_msc=stamp;ticks[0].time=(datetime)(stamp/1000);
   ticks[0].bid=bar.close;ticks[0].ask=bar.close;ticks[0].last=bar.close;
   ticks[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   if(CustomTicksAdd(symbol,ticks)!=1){Note(StringFormat("PULSE_FAIL %s err=%d",symbol,GetLastError()));return false;}
   return true;
  }

bool UpdateAndRefresh(const string symbol,const MqlRates &bar,const int handle,const int count)
  {
   MqlRates update[];ArrayResize(update,1);update[0]=bar;
   if(CustomRatesUpdate(symbol,update)!=1 || !Warm(symbol,count))return false;
   for(int n=0;n<3;n++)
     {
      if(!Pulse(symbol,bar))return false;
      Sleep(40);
      if(!SameOHLC(symbol,bar))return false;
      if(Ready(handle,count,1500))return true;
     }
   return false;
  }

void NumericBuiltin(const string symbol,const int method,const int period,const int gsm,const int count,const string tag)
  {
   int builtin=method==0?iADXWilder(symbol,PERIOD_M1,period):iADX(symbol,PERIOD_M1,period);
   bool ready=Ready(builtin,count);int bad=0;long checked=0;double maximum=0;
   for(int b=0;b<3 && ready;b++)
     {
      double a[],r[];ArraySetAsSeries(a,false);ArraySetAsSeries(r,false);
      if(CopyBuffer(gsm,b,0,count,a)!=count || CopyBuffer(builtin,b,0,count,r)!=count){ready=false;break;}
      for(int i=2*period+12;i<count-1;i++)
        {checked++;if(!Same(a[i],r[i]))bad++;if(a[i]!=EMPTY_VALUE && r[i]!=EMPTY_VALUE)maximum=MathMax(maximum,MathAbs(a[i]-r[i]));}
     }
   Check(tag,ready&&checked>0&&bad==0,StringFormat("method=%d period=%d values=%I64d failures=%d max_error=%.17g",method,period,checked,bad,maximum));
   if(builtin!=INVALID_HANDLE)IndicatorRelease(builtin);
  }

void AlgorithmTests(const int method,const MqlRates &rates[])
  {
   string key="method="+IntegerToString(method),full=Name("F"+IntegerToString(method)),prefix=Name("P"+IntegerToString(method));
   bool fixture=Create(full,rates,0,N)&&Create(prefix,rates,0,80);
   Check("FIXTURE",fixture,key+" full="+full+" prefix="+prefix);if(!fixture)return;
   Note("STAGE|INITIAL_LOAD_BEGIN|"+key+" symbol="+prefix);
   int hf=Handle(full,method),hp=Handle(prefix,method,14,false,false,true);
   Frame reference[],partial[];
   bool ready=Ready(hf,N)&&Ready(hp,80)&&Snapshot(hf,N,reference)&&Snapshot(hp,80,partial);
   Check("INITIAL_LOAD",ready,key);Note("STAGE|INITIAL_LOAD_END|"+key+" symbol="+prefix);
   if(!ready){if(hf!=INVALID_HANDLE)IndicatorRelease(hf);if(hp!=INVALID_HANDLE)IndicatorRelease(hp);return;}
   long compared=0;int mismatch=0;
   bool identical=EqualClosed(reference,partial,79,compared,mismatch);
   Check("INITIAL_PREFIX",identical,key+StringFormat(" values=%I64d failures=%d",compared,mismatch));
   NumericBuiltin(full,method,14,hf,N,"SYNTHETIC_BUILTIN");
   long total=0;int failures=0,steps=0;bool empty=true;
   Note("STAGE|REPLAY_BEGIN|"+key+" symbol="+prefix+" from_count=80 to_count=200");
   for(int count=81;count<=200 && !IsStopped();count++)
     {
      if(!UpdateAndRefresh(prefix,rates[count-1],hp,count)||!Snapshot(hp,count,partial))
        {failures++;Note("REPLAY_DATA_FAIL count="+IntegerToString(count));break;}
      if(!EqualClosed(reference,partial,count-1,compared,mismatch))failures+=MathMax(1,mismatch);
      total+=compared;steps++;empty=empty&&CurrentEmpty(partial,count);
      if(count%20==0)Note("REPLAY_PROGRESS|"+key+StringFormat(" count=%d values=%I64d failures=%d",count,total,failures));
      if(failures>0)break;
     }
   Note("STAGE|REPLAY_END|"+key+" symbol="+prefix);
   Check("BAR_BY_BAR_SAME_START",steps==120&&failures==0,key+StringFormat(" steps=%d values=%I64d failures=%d",steps,total,failures));
   Check("EVERY_STEP_CURRENT_CONFIRMED_EMPTY",steps==120&&empty,key+StringFormat(" steps=%d checks=%d",steps,steps*12));
   if(steps==120)
     {
      Frame before[],after[];bool snap=Snapshot(hp,200,before);int mutation_fail=0,raw_changes=0;
      int quote_oracle=method==0?iADXWilder(prefix,PERIOD_M1,14):iADX(prefix,PERIOD_M1,14);
      snap=snap&&Ready(quote_oracle,200);
      Note("STAGE|SAME_BAR_QUOTES_BEGIN|"+key+" symbol="+prefix+" count=200");
      for(int q=0;q<8 && snap;q++)
        {
         MqlRates change=rates[199];change.high+=20+q;change.low-=20+q;
         change.close=NormalizeDouble(change.close+(q%2==0?10.0:-10.0),2);
         if(!UpdateAndRefresh(prefix,change,hp,200)||!Snapshot(hp,200,after)) {mutation_fail++;break;}
         if(!EqualClosed(before,after,199,compared,mismatch))mutation_fail+=MathMax(1,mismatch);
         if(!CurrentEmpty(after,200))mutation_fail++;
         for(int b=0;b<3;b++)
           {
            double raw[];
            if(CopyBuffer(quote_oracle,b,0,1,raw)!=1 || !Same(raw[0],after[b].v[199]))mutation_fail++;
            if(!Same(after[b].v[199],before[b].v[199]))raw_changes++;
           }
        }
      Note("STAGE|SAME_BAR_QUOTES_END|"+key+" symbol="+prefix);
      Check("CURRENT_OHLC_OLD_HANDLE_STABLE",snap&&mutation_fail==0&&raw_changes>0,key+StringFormat(" repeats=8 failures=%d old_handle=%d live_raw_changes=%d",mutation_fail,hp,raw_changes));
      if(quote_oracle!=INVALID_HANDLE)IndicatorRelease(quote_oracle);
     }
   MqlRates future[];ArrayCopy(future,rates);for(int i=200;i<N;i++)
     {future[i].open+=70;future[i].high+=80;future[i].low+=60;future[i].close+=70;}
   string future_symbol=Name("U"+IntegerToString(method));
   int hu=INVALID_HANDLE;Frame altered[];
   bool future_ready=Create(future_symbol,future,0,N);
   if(future_ready){hu=Handle(future_symbol,method);future_ready=Ready(hu,N)&&Snapshot(hu,N,altered);}
   identical=future_ready&&EqualClosed(reference,altered,200,compared,mismatch);
   Check("FUTURE_PERTURBATION",identical,key+StringFormat(" past_values=%I64d failures=%d future_start=200",compared,mismatch));
   int hidden=Handle(full,method,14,false,true,true);Frame invisible[];
   bool hidden_ready=Ready(hidden,N)&&Snapshot(hidden,N,invisible);
   identical=hidden_ready&&EqualClosed(reference,invisible,N-1,compared,mismatch);
   Check("HIDDEN_AND_ALERT_MASTER",identical,key+StringFormat(" values=%I64d failures=%d",compared,mismatch));
   int alternate=Handle(full,method,10);if(Ready(alternate,N))NumericBuiltin(full,method,10,alternate,N,"PERIOD_PARAMETER_CHANGE");else Check("PERIOD_PARAMETER_CHANGE",false,key);
   int extra_periods[3]={2,7,30};
   for(int p=0;p<3;p++)
     {
      int extra=Handle(full,method,extra_periods[p]);
      if(Ready(extra,N))NumericBuiltin(full,method,extra_periods[p],extra,N,"EXPLICIT_PERIOD_PARAMETER");
      else Check("EXPLICIT_PERIOD_PARAMETER",false,key+" period="+IntegerToString(extra_periods[p]));
      if(extra!=INVALID_HANDLE)IndicatorRelease(extra);
     }
   int levels=Handle(full,method,14,false,false,false,12,15,22,35);Frame changed[];
   bool levels_ready=Ready(levels,N)&&Snapshot(levels,N,changed);int level_bad=0;long level_count=0;
   if(levels_ready)
      for(int i=50;i<N-1;i++)
        {
         double a=reference[0].v[i],old=reference[0].v[i-1];
         for(int b=0;b<3;b++){level_count++;if(!Same(reference[b].v[i],changed[b].v[i]))level_bad++;}
         double state=a<15?0:a<22?1:a<=35?2:3;
         if(changed[3].v[i]!=state || changed[6].v[i]!=(a>15&&old<=15?1:0) || changed[7].v[i]!=(a>22&&old<=22?1:0))level_bad++;
         level_count+=3;
        }
   Check("CHANGED_THRESHOLDS",levels_ready&&level_bad==0,key+StringFormat(" values=%I64d failures=%d levels=15/22/35",level_count,level_bad));
   string deep=Name("D"+IntegerToString(method));int hd=INVALID_HANDLE;Frame loaded[];
   bool deeper=Create(deep,rates,40,N-40);
   if(deeper){hd=Handle(deep,method);deeper=Ready(hd,N-40);}
   MqlRates older[];ArrayResize(older,40);for(int i=0;i<40;i++)older[i]=rates[i];
   if(deeper)deeper=CustomRatesUpdate(deep,older)==40&&Warm(deep,N)&&Pulse(deep,rates[N-1])&&Ready(hd,N)&&Snapshot(hd,N,loaded);
   identical=deeper&&EqualClosed(reference,loaded,N-1,compared,mismatch);
   Check("DEEPER_HISTORY_REBUILD",identical,key+StringFormat(" same_final_origin_values=%I64d failures=%d",compared,mismatch));
   int handles[]={hf,hp,hu,hidden,alternate,levels,hd};for(int k=0;k<ArraySize(handles);k++)if(handles[k]!=INVALID_HANDLE)IndicatorRelease(handles[k]);
  }

void WarmupAndInvalid(const MqlRates &rates[])
  {
   MqlRates flat[];MakeRates(flat,true);string symbol=Name("ZERO");bool fixture=Create(symbol,flat,0,100);Check("ZERO_FIXTURE",fixture);if(!fixture)return;
   for(int method=0;method<2;method++)
     {
      int h=Handle(symbol,method);Frame f[];bool ready=Ready(h,100)&&Snapshot(h,100,f);int bad=0,zero_count=0,warm_count=0;
      if(ready)
        {
         for(int b=0;b<3;b++)
           {
            int begin=b==0?28:(method==0?15:14);
            for(int i=0;i<begin;i++){warm_count++;if(f[b].v[i]!=EMPTY_VALUE)bad++;}
            for(int i=50;i<99;i++){zero_count++;if(f[b].v[i]!=0)bad++;}
           }
         for(int i=50;i<99;i++)
           {if(f[3].v[i]!=0 || f[4].v[i]!=0 || f[5].v[i]!=0 || f[14].v[i]!=0)bad++;}
         // Entry lookback needs one extra earlier-state sample: the earliest
         // ADX chronological index is 28, so trend/rise/low/choppy differ.
         if(f[3].v[27]!=EMPTY_VALUE || f[5].v[28]!=EMPTY_VALUE || f[11].v[29]!=EMPTY_VALUE ||
            f[12].v[31]!=EMPTY_VALUE || f[13].v[37]!=EMPTY_VALUE || f[14].v[24]!=EMPTY_VALUE)bad++;
        }
      Check("WARMUP_AND_VALID_ZERO",ready&&bad==0,StringFormat("method=%d warmup_values=%d valid_zero_values=%d failures=%d",method,warm_count,zero_count,bad));
      if(h!=INVALID_HANDLE)IndicatorRelease(h);
     }
   int invalids[5];invalids[0]=Handle(symbol,0,1);invalids[1]=Handle(symbol,0,14,false,false,false,12,25,20,40);
   invalids[2]=Handle(symbol,0,14,false,false,false,12,20,25,40,-0.01);
   invalids[3]=Handle(symbol,0,14,false,false,false,12,20,25,40,0,0);
   invalids[4]=Handle(symbol,0,14,false,false,false,12,20,25,40,0,2,2,3);
   int rejected=0;
   for(int k=0;k<5;k++)
     {
      if(invalids[k]==INVALID_HANDLE){rejected++;continue;}
      // iCustom can return a handle before asynchronous OnInit has executed.
      // Retain handles until asynchronous OnInit runs. CopyBuffer on an
      // init-failed handle can block for the terminal's full history timeout.
      Sleep(500);
      int calculated=BarsCalculated(invalids[k]);
      Note(StringFormat("INVALID_INIT_PROBE|case=%d handle=%d calculated=%d; root must corroborate all five Chinese OnInit failures in native log",k,invalids[k],calculated));
      if(calculated<=0)rejected++;
      IndicatorRelease(invalids[k]);
     }
   Check("INVALID_INPUT_REJECTION",rejected==5,StringFormat("cases=5 rejected=%d",rejected));
  }

int CountPrefix(const long chart,const string prefix)
  {int n=0;for(int i=0;i<ObjectsTotal(chart,-1,-1);i++)if(StringFind(ObjectName(chart,i,-1,-1),prefix)==0)n++;return n;}

int FindPanels(const long chart,string &prefixes[],int &windows[])
  {
   ArrayResize(prefixes,0);ArrayResize(windows,0);
   for(int i=0;i<ObjectsTotal(chart,-1,-1);i++)
     {
      string name=ObjectName(chart,i,-1,-1);
      if(StringFind(name,"GSM_ADX_")!=0 || StringSubstr(name,StringLen(name)-2)!="P0")continue;
      if(ObjectGetString(chart,name,OBJPROP_TEXT)!="GSM ADX 趋势强弱测量器")continue;
      int n=ArraySize(prefixes);ArrayResize(prefixes,n+1);ArrayResize(windows,n+1);
      prefixes[n]=StringSubstr(name,0,StringLen(name)-2);windows[n]=ObjectFind(chart,name);
     }
   return ArraySize(prefixes);
  }

bool Screenshot(const long chart,const string file)
  {
   ChartRedraw(chart);Sleep(300);
   int width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS,0);
   int height=0,windows=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL);
   for(int w=0;w<windows;w++)height+=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,w);
   // Include every subwindow rather than cropping to main-chart height.
   if(FileIsExist(file))FileDelete(file);
   bool request=width>0&&height>0&&ChartScreenShot(chart,file,width,height,ALIGN_RIGHT);
   for(int i=0;i<30&&!FileIsExist(file);i++)Sleep(100);
   Note(StringFormat("SCREENSHOT file=%s canvas=%dx%d windows=%d",file,width,height,windows));
   return request&&FileIsExist(file);
  }

void Visual(const MqlRates &rates[])
  {
   string symbol=Name("VIS");if(!Create(symbol,rates,0,N)){Check("VISUAL_FIXTURE",false);return;}
   long chart=ChartOpen(symbol,PERIOD_M1);if(chart<=0 || chart==ChartID()){Check("OWN_CHART",false);return;}
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=0;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);ChartSetInteger(chart,CHART_SCALE,3);
   ChartSetInteger(chart,CHART_COLOR_BACKGROUND,clrBlack);ChartSetInteger(chart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetString(chart,CHART_COMMENT,"SYNTHETIC DATA / NO TRADING RESULTS / GSM ADX ENGINEERING");
   int one=Handle(symbol,0,14,true,false,false,12),two=Handle(symbol,1,10,true,false,false,650);
   bool attached=Ready(one,N)&&Ready(two,N)&&ChartIndicatorAdd(chart,1,one)&&ChartIndicatorAdd(chart,1,two);
   ChartRedraw(chart);Sleep(200);
   string tpl="GSM_ADX_engineering.tpl";bool saved=attached&&ChartSaveTemplate(chart,tpl);
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   if(one!=INVALID_HANDLE)IndicatorRelease(one);if(two!=INVALID_HANDLE)IndicatorRelease(two);
   bool applied=saved&&ChartApplyTemplate(chart,tpl);string prefixes[];int panel_windows[];
   const ulong end=GetTickCount64()+12000;
   while(applied && GetTickCount64()<end && !IsStopped())
     {ChartRedraw(chart);if(FindPanels(chart,prefixes,panel_windows)==2)break;Sleep(100);}
   bool panels=FindPanels(chart,prefixes,panel_windows)==2;
   Check("NATIVE_MULTI_INSTANCE_PANEL",applied&&panels&&panel_windows[0]>=1&&panel_windows[1]>=1&&prefixes[0]!=prefixes[1],
         StringFormat("saved=%d applied=%d panels=%d subwindows=%d",saved,applied,ArraySize(prefixes),(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1));
   Note("VISUAL_TEMPLATE|"+tpl+"|Root must inspect native saved level properties 20/25/40 and screenshot separately.");
   bool marker_closed=true,marked=false;
   datetime current=rates[N-1].time;
   for(int i=0;i<ObjectsTotal(chart,-1,-1);i++)
     {
      string name=ObjectName(chart,i,-1,-1);
      if(StringFind(name,"GSM_ADX_")!=0 || ObjectGetInteger(chart,name,OBJPROP_TYPE)!=OBJ_ARROW)continue;
      marked=true;if((datetime)ObjectGetInteger(chart,name,OBJPROP_TIME)>=current)marker_closed=false;
     }
   Check("NATIVE_MARKERS_CLOSED",panels&&marked&&marker_closed);
   Check("NATIVE_SCREENSHOT_CREATED",panels&&Screenshot(chart,"GSM_ADX_engineering_chart.png"));
   const string sentinel="ADX_ENGINEERING_UNRELATED_OBJECT";
   ObjectCreate(chart,sentinel,OBJ_LABEL,0,0,0);ObjectSetString(chart,sentinel,OBJPROP_TEXT,"ENGINEERING SENTINEL");
   int window=1;string first=ChartIndicatorName(chart,window,0);
   string before_names[];int before_windows[];FindPanels(chart,before_names,before_windows);
   bool deleted=first!=""&&ChartIndicatorDelete(chart,window,first);
   const ulong cleanup_end=GetTickCount64()+8000;
   while(GetTickCount64()<cleanup_end && !IsStopped())
     {Sleep(100);if(FindPanels(chart,prefixes,panel_windows)==1)break;}
   bool survivor=FindPanels(chart,prefixes,panel_windows)==1&&ObjectFind(chart,sentinel)>=0;
   Check("REMOVE_ONE_PRESERVES_OTHER",deleted&&survivor,StringFormat("remaining_panels=%d sentinel=%d",ArraySize(prefixes),ObjectFind(chart,sentinel)>=0));
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   Sleep(300);
   Check("UNLOAD_OWN_OBJECT_CLEANUP",CountPrefix(chart,"GSM_ADX_")==0&&ObjectFind(chart,sentinel)>=0,
         StringFormat("remaining_owned_objects=%d sentinel=%d",CountPrefix(chart,"GSM_ADX_"),ObjectFind(chart,sentinel)>=0));
   ChartClose(chart);
  }

void OnStart()
  {
   Started=GetTickCount64();Suffix=StringFormat("%I64u",Started);if(StringLen(Suffix)>10)Suffix=StringSubstr(Suffix,StringLen(Suffix)-10);
   Report=FileOpen("GSM_ADX_Engineering_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   Note("SYNTHETIC_ONLY|Fixed M1 OHLC from 2026-03-02; no broker-gold claim, no orders, no account APIs.");
   Note(StringFormat("ENVIRONMENT|terminal_build=%d run=%s suffix=%s",(int)TerminalInfoInteger(TERMINAL_BUILD),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),Suffix));
   MqlRates rates[];MakeRates(rates);
   AlgorithmTests(0,rates);if(!IsStopped())AlgorithmTests(1,rates);
   if(!IsStopped())WarmupAndInvalid(rates);
   if(!IsStopped())Visual(rates);
   Note("NOT_TESTED|REAL_DISCONNECT|No network disconnect was performed; quote-driven custom-history refresh is not a network recovery test.");
   Note("NOT_TESTED|NOTIFICATION_DELIVERY|All popup, sound and push channels disabled. Review STAGE and GSM_ADX_ALERT_CONFIRMED logs separately for local deduplication.");
   Note(StringFormat("OVERALL=%s groups=%d failed=%d elapsed_ms=%I64u",Failed==0?"PASS_ENGINEERING_SCOPE":"FAIL",Groups,Failed,GetTickCount64()-Started));
   if(Report!=INVALID_HANDLE)FileClose(Report);
  }
