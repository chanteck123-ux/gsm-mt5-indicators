// Tests the production indicator using independent Python CSV oracles.
// Creates only unique test custom symbols; no account, order or trade API calls.
struct VFIExpected {double b[10];};
int g_report=INVALID_HANDLE,g_values=INVALID_HANDLE,g_checks=0,g_failures=0,g_groups=0,g_passed=0,g_before=0;
string g_group="",g_suffix="",g_symbols[13];
int g_handles[13],g_counts[13];
long g_tick_msc=0;

void Log(const string message)
  {
   Print(message);
   if(g_report!=INVALID_HANDLE){FileWrite(g_report,message);FileFlush(g_report);}
  }
void Group(const string name){g_group=name;g_before=g_failures;g_groups++;}
void EndGroup(){bool ok=g_failures==g_before;if(ok)g_passed++;Log((ok?"PASS|":"FAIL|")+g_group+"|new_failures="+IntegerToString(g_failures-g_before));}
void Check(const bool ok,const string label)
  {
   g_checks++;
   if(!ok){g_failures++;if(g_failures<80)Log("ASSERT_FAIL|"+g_group+"|"+label+"|error="+IntegerToString(GetLastError()));}
  }
bool Same(const double actual,const double expected)
  {
   if(actual==EMPTY_VALUE||expected==EMPTY_VALUE)return actual==expected;
   return MathIsValidNumber(actual)&&MathIsValidNumber(expected)&&MathAbs(actual-expected)<=1e-8;
  }
bool Read(const int handle,const int buffer,const int count,double &values[])
  {
   ArrayResize(values,count);ArraySetAsSeries(values,false);
   return CopyBuffer(handle,buffer,0,count,values)==count;
  }
bool Ready(const int handle,const int count,const int timeout=15)
  {
   ulong begin=GetTickCount64();double values[];
   while(!IsStopped()&&GetTickCount64()-begin<(ulong)timeout*1000)
     {
      if(Read(handle,0,count,values)&&BarsCalculated(handle)>=count)return true;
      Sleep(50);
     }
   Log(StringFormat("READY_FAIL|handle=%d expected=%d actual=%d",handle,count,BarsCalculated(handle)));return false;
  }
int Create(const string symbol,const int length,const double coef,const double vcoef,const int signal,const bool smooth,const int mode,
           const bool show=true,const bool hist=false,const color line_color=clrGreen)
  {
   return iCustom(symbol,PERIOD_M1,"GSM\\Volume_Flow_Indicator_MT5",length,coef,vcoef,signal,smooth,mode,show,show,hist,line_color,clrOrange,clrGray);
  }
bool LoadFixture(const string name,MqlRates &rates[],VFIExpected &expected[])
  {
   int h=FileOpen("vfi_fixtures\\"+name+".csv",FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE){Log("FIXTURE_FAIL|file="+name);return false;}
   for(int k=0;k<17;k++)FileReadString(h);
   int rows=0;ArrayResize(rates,0);ArrayResize(expected,0);
   while(!FileIsEnding(h))
     {
      string ts=FileReadString(h);if(ts=="")break;
      ArrayResize(rates,rows+1);ArrayResize(expected,rows+1);ZeroMemory(rates[rows]);
      rates[rows].time=(datetime)StringToInteger(ts);
      rates[rows].open=StringToDouble(FileReadString(h));rates[rows].high=StringToDouble(FileReadString(h));
      rates[rows].low=StringToDouble(FileReadString(h));rates[rows].close=StringToDouble(FileReadString(h));
      rates[rows].tick_volume=StringToInteger(FileReadString(h));rates[rows].real_volume=StringToInteger(FileReadString(h));rates[rows].spread=2;
      for(int k=0;k<10;k++){string value=FileReadString(h);expected[rows].b[k]=value=="EMPTY"?EMPTY_VALUE:StringToDouble(value);}
      rows++;
     }
   FileClose(h);ArraySetAsSeries(rates,false);return rows>0;
  }
bool MakeSymbol(const string symbol,const MqlRates &rates[])
  {
   if(!CustomSymbolCreate(symbol,"CodexVFI"))return false;
   if(!CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,5)||!CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.00001)||
      !CustomSymbolSetDouble(symbol,SYMBOL_TRADE_TICK_SIZE,0.00001)||!CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED)||!SymbolSelect(symbol,true))return false;
   int count=ArraySize(rates);
   int result=CustomRatesReplace(symbol,rates[0].time,rates[count-1].time,rates);
   if(result!=count)Log(StringFormat("FIXTURE_FAIL|CustomRatesReplace expected=%d actual=%d",count,result));
   return result==count;
  }
bool Snapshot(const int handle,const int count,VFIExpected &rows[])
  {
   ArrayResize(rows,count);double values[];
   for(int k=0;k<10;k++)
     {
      if(!Read(handle,k,count,values))return false;
      for(int i=0;i<count;i++)rows[i].b[k]=values[i];
     }
   return true;
  }
void RunCase(const string name,const int count,const int length,const double coef,const double vcoef,const int signal,const bool smooth,const int mode,const int index)
  {
   Group("Python_oracle_"+name);
   MqlRates rates[];VFIExpected expected[];
   bool loaded=LoadFixture(name,rates,expected);Check(loaded&&ArraySize(rates)==count,"independent CSV fixture exact count");
   if(!loaded||ArraySize(rates)!=count){EndGroup();return;}
   string symbol="VFI_"+IntegerToString(index)+"_"+g_suffix;
   bool created=MakeSymbol(symbol,rates);Check(created,"unique native custom symbol history");
   if(!created){EndGroup();return;}
   int h=Create(symbol,length,coef,vcoef,signal,smooth,mode),hidden=Create(symbol,length,coef,vcoef,signal,smooth,mode,false);
   Check(h!=INVALID_HANDLE&&hidden!=INVALID_HANDLE,"real production visible and hidden handles");
   if(h==INVALID_HANDLE||hidden==INVALID_HANDLE){EndGroup();return;}
   bool ready=Ready(h,count)&&Ready(hidden,count);Check(ready,"both production instances calculated complete history");
   if(!ready){EndGroup();IndicatorRelease(h);IndicatorRelease(hidden);return;}
   g_symbols[index]=symbol;g_handles[index]=h;g_counts[index]=count;
   double actual[],invisible[];
   for(int k=0;k<10;k++)
     {
      bool copied=Read(h,k,count,actual)&&Read(hidden,k,count,invisible);Check(copied,"CopyBuffer exact count buffer "+IntegerToString(k));
      if(!copied)continue;
      double max_error=0;int valid=0,empty=0;
      for(int i=0;i<count-1;i++)
        {
         double want=expected[i].b[k];Check(Same(actual[i],want),name+" independent Python buffer "+IntegerToString(k)+" old index "+IntegerToString(i));
         Check(Same(actual[i],invisible[i]),name+" display off buffer unchanged");
         if(want==EMPTY_VALUE)empty++;
         else {valid++;if(actual[i]!=EMPTY_VALUE)max_error=MathMax(max_error,MathAbs(actual[i]-want));}
         if(g_values!=INVALID_HANDLE)FileWrite(g_values,name,TimeToString(rates[i].time,TIME_DATE|TIME_SECONDS),k,
             actual[i]==EMPTY_VALUE?"EMPTY":DoubleToString(actual[i],15),want==EMPTY_VALUE?"EMPTY":DoubleToString(want,15));
        }
      Log(StringFormat("NUMERIC|case=%s|buffer=%d|closed_samples=%d|valid=%d|empty=%d|max_abs_error=%.12g",name,k,count-1,valid,empty,max_error));
     }
   if(index==6)
     {
      VFIExpected got[];Check(Snapshot(h,count,got),"cap fixture readback");
      if(ArraySize(got)==count)
        {
         Check(Same(got[50].b[5],100),"hand answer: prior mean volume 100 excludes current 1000");
         Check(Same(got[50].b[6],250)&&Same(got[50].b[3],250),"hand answer: volume1000 capped to250 positive flow");
         Check(Same(got[50].b[0],2.5)&&Same(got[50].b[1],2.5)&&Same(got[50].b[2],0),"hand answer: length1 VFI2.5, EMA1=2.5, difference0");
        }
     }
   IndicatorRelease(hidden);EndGroup();
  }

void HandRules()
  {
   Group("Actual_production_helpers_strict_threshold_invalid_and_zero");
   Check(VFISignedFlow(1,1,250)==0,"positive movement exactly cutoff gives zero");
   Check(VFISignedFlow(-1,1,250)==0,"negative movement exactly negative cutoff gives zero");
   Check(VFISignedFlow(1.25,1,250)==250,"strictly above cutoff gives capped positive flow");
   Check(VFISignedFlow(-1.25,1,250)==-250,"strictly below negative cutoff gives capped negative flow");
   Check(VFISignedFlow(0,0,250)==0,"flat price with cutoff0 gives valid zero");
   Check(VFISignedFlow(1,0,0)==0,"valid zero volume is preserved");
   Check(VFISignedFlow(EMPTY_VALUE,1,250)==EMPTY_VALUE,"unavailable movement remains EMPTY");
   Check(VFISignedFlow(1,EMPTY_VALUE,250)==EMPTY_VALUE,"unavailable cutoff remains EMPTY");
   Check(VFITypical(100,100,100)==100,"valid typical price");
   Check(VFITypical(0,0,0)==EMPTY_VALUE,"zero typical price is invalid for logarithm");
   Check(VFITypical(-100,-100,-100)==EMPTY_VALUE,"negative typical price is invalid for logarithm");
   double argument=2,nan_value=MathArcsin(argument),power=10000,inf_value=MathExp(power);
   Check(!MathIsValidNumber(nan_value)&&!MathIsValidNumber(inf_value),"NaN and infinity fixtures valid as invalid-number tests");
   Check(VFITypical(nan_value,100,100)==EMPTY_VALUE&&VFITypical(inf_value,100,100)==EMPTY_VALUE,"NaN and infinity are not usable prices");
   Check(VFISignedFlow(1,nan_value,250)==EMPTY_VALUE&&VFISignedFlow(1,1,inf_value)==EMPTY_VALUE,"invalid flow operands stay EMPTY");
   EndGroup();
  }

void FutureAndPrefix()
  {
   Group("Fixed_start_prefix_and_future_perturbation_no_leakage");
   VFIExpected base[],future[],prefix[];
   bool got=g_handles[9]!=INVALID_HANDLE&&g_handles[10]!=INVALID_HANDLE&&g_handles[11]!=INVALID_HANDLE&&
      Snapshot(g_handles[9],240,base)&&Snapshot(g_handles[10],240,future)&&Snapshot(g_handles[11],160,prefix);
   Check(got,"full, future changed and prefix production histories ready");
   if(got)
      for(int i=0;i<159;i++)for(int k=0;k<10;k++)
        {
         Check(Same(base[i].b[k],future[i].b[k]),"future prices/volumes do not change earlier output");
         Check(Same(base[i].b[k],prefix[i].b[k]),"prefix output matches same-time full-history output");
        }
   EndGroup();
  }
bool Pulse(const string symbol,const datetime bar,const double price)
  {
   long minimum=(long)bar*1000+100;if(g_tick_msc<minimum)g_tick_msc=minimum;else g_tick_msc+=100;
   if(g_tick_msc>=(long)(bar+60)*1000)return false;
   MqlTick tick[];ArrayResize(tick,1);ZeroMemory(tick[0]);tick[0].time_msc=g_tick_msc;tick[0].time=(datetime)(g_tick_msc/1000);
   tick[0].bid=price;tick[0].ask=price+.00002;tick[0].last=price;tick[0].volume=1;tick[0].volume_real=1;
   tick[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   return CustomTicksAdd(symbol,tick)==1;
  }
bool WaitRate(const string symbol,const datetime bar,const double price,const int count)
  {
   ulong begin=GetTickCount64();MqlRates current[];
   while(!IsStopped()&&GetTickCount64()-begin<15000)
     {
      if(CopyRates(symbol,PERIOD_M1,0,1,current)==1&&current[0].time==bar&&MathAbs(current[0].close-price)<1e-7&&Bars(symbol,PERIOD_M1)==count)return true;
      Sleep(50);
     }
   return false;
  }
void CurrentAndAppend()
  {
   Group("Native_current_tick_update_equals_fresh_full_calculation");
   string symbol=g_symbols[0];int handle=g_handles[0],count=g_counts[0];
   if(handle==INVALID_HANDLE){Check(false,"default fixture available");EndGroup();return;}
   VFIExpected before[],after[],fresh[];MqlRates last[];
   bool saved=Snapshot(handle,count,before)&&CopyRates(symbol,PERIOD_M1,0,1,last)==1;Check(saved,"current-bar baseline saved");
   if(!saved){EndGroup();return;}
   datetime current=last[0].time;double price=NormalizeDouble(last[0].close+.75,5);
   Check(Pulse(symbol,current,price),"real custom-symbol quote changes current candle");
   Check(WaitRate(symbol,current,price,count),"native current candle updated at unchanged bar count");
   Check(Ready(handle,count),"existing production instance recalculated");
   int oracle=Create(symbol,130,.2,2.5,5,false,0,true,true,clrLime);
   bool got=oracle!=INVALID_HANDLE&&Ready(oracle,count)&&Snapshot(handle,count,after)&&Snapshot(oracle,count,fresh);Check(got,"new parameter-distinct instance forces independent full calculation");
   if(got)
     {
      int current_changed=0;
      for(int i=0;i<count;i++)for(int k=0;k<10;k++)
        {
         Check(Same(after[i].b[k],fresh[i].b[k]),"incremental update equals full restart at same history");
         if(i<count-1)Check(Same(before[i].b[k],after[i].b[k]),"unclosed quote cannot alter earlier closed value");
         else if(!Same(before[i].b[k],after[i].b[k]))current_changed++;
        }
      Check(current_changed>0,"live update actually changed at least one current value");
     }
   if(oracle!=INVALID_HANDLE)IndicatorRelease(oracle);EndGroup();
   if(!got)return;

   Group("Native_new_bar_preserves_all_prior_confirmed_values");
   current+=60;price=NormalizeDouble(price+.3,5);
   Check(Pulse(symbol,current,price),"quote opens next candle");
   Check(WaitRate(symbol,current,price,count+1),"native history appends exactly one new bar");
   Check(Ready(handle,count+1),"existing indicator calculated appended history");
   VFIExpected appended[];bool copied=Snapshot(handle,count+1,appended);Check(copied,"all ten outputs after append readable");
   if(copied)for(int i=0;i<count;i++)for(int k=0;k<10;k++)Check(Same(after[i].b[k],appended[i].b[k]),"previous finalized values retain timestamp alignment after append");
   EndGroup();
  }
void Preview()
  {
   Group("Native_chart_screenshot_with_actual_VFI_EMA_histogram");
   if(g_handles[0]==INVALID_HANDLE){Check(false,"preview fixture exists");EndGroup();return;}
   string symbol=g_symbols[0];long chart=ChartOpen(symbol,PERIOD_M1);Check(chart>0,"create owned preview chart");
   if(chart<=0){EndGroup();return;}
   int h=Create(symbol,130,.2,2.5,5,false,0,true,true);
   Check(h!=INVALID_HANDLE&&Ready(h,Bars(symbol,PERIOD_M1)),"preview production instance calculated");
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_SCALE,3);ChartSetInteger(chart,CHART_AUTOSCROLL,true);
   ChartSetInteger(chart,CHART_COLOR_BACKGROUND,clrWhite);ChartSetInteger(chart,CHART_COLOR_FOREGROUND,clrBlack);
   Check(ChartIndicatorAdd(chart,1,h),"attach real VFI in native separate subwindow");
   ChartRedraw(chart);Sleep(500);
   int width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS),height=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,0);
   long windows=ChartGetInteger(chart,CHART_WINDOWS_TOTAL);
   for(int w=1;w<windows;w++)height+=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,w);
   Check(width>0&&height>0,"native canvas dimensions observed");
   bool shot=ChartScreenShot(chart,"VFI_MT5_preview.png",width,height,ALIGN_RIGHT);Check(shot,"native screenshot requested");
   Sleep(500);Check(FileIsExist("VFI_MT5_preview.png"),"native screenshot file exists");
   Log(StringFormat("PREVIEW|width=%d height=%d windows=%d histogram_enabled=true synthetic_fixture=%s",width,height,(int)windows,symbol));
   ChartClose(chart);if(h!=INVALID_HANDLE)IndicatorRelease(h);EndGroup();
  }
void OnStart()
  {
   for(int k=0;k<13;k++){g_handles[k]=INVALID_HANDLE;g_counts[k]=0;}
   g_report=FileOpen("VFI_Validation_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   g_values=FileOpen("VFI_Validation_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_report==INVALID_HANDLE||g_values==INVALID_HANDLE){Print("FAIL|cannot open VFI evidence");return;}
   FileWrite(g_values,"case","bar_time","buffer","actual","independent_python_expected");
   Log("VFI production native validation with independent Python reference");Log("SOURCE_SHA256="+SOURCE_SHA256);Log("HELPER_SHA256="+HELPER_SHA256);
   Log("TERMINAL_BUILD="+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   Log("DATA=Fixed synthetic OHLC/TickVolume/RealVolume. No profitability or real-market equivalence claim.");
   g_suffix=IntegerToString((long)(GetTickCount64()%100000000));
   HandRules();
// INSERT_CASE_CALLS
   FutureAndPrefix();CurrentAndAppend();Preview();
   for(int k=0;k<13;k++)if(g_handles[k]!=INVALID_HANDLE)IndicatorRelease(g_handles[k]);
   Log(StringFormat("OVERALL=%s|groups=%d|passed_groups=%d|assertions=%d|failures=%d",g_failures==0?"PASS":"FAIL",g_groups,g_passed,g_checks,g_failures));
   FileFlush(g_report);FileFlush(g_values);FileClose(g_report);FileClose(g_values);
  }
