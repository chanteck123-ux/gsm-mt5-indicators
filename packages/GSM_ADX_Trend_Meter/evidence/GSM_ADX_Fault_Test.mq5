#property strict
#property script_show_inputs
#property version "1.00"
const string PRODUCTION_SOURCE_SHA256="dd9d9843faec00000b9a02ebf039da1373ff7a885061280ad0faf4f7e41b1d96";
// Native integration test for instrumented production OnCalculate.
// Creates only unique custom symbols; no account, order, or trading API calls.
// Fault variant location: MQL5/Indicators/GSM_TEST/GSM_ADX_FaultInjected.ex5.
int g_file=INVALID_HANDLE,g_csv=INVALID_HANDLE,g_checks=0,g_fails=0,g_groups=0,g_passed=0,g_before=0;
string g_group="";
long g_tick_msc=0;

void Log(const string message)
  {
   Print(message);
   if(g_file!=INVALID_HANDLE){FileWrite(g_file,message);FileFlush(g_file);}
  }
void Group(const string name){g_group=name;g_before=g_fails;g_groups++;}
void EndGroup()
  {
   bool pass=g_fails==g_before;
   if(pass)g_passed++;
   Log((pass?"PASS|":"FAIL|")+g_group+"|new_failures="+IntegerToString(g_fails-g_before));
  }
void Check(const bool ok,const string label)
  {
   g_checks++;
   if(!ok){g_fails++;Log("ASSERT_FAIL|"+g_group+"|"+label+"|error="+IntegerToString(GetLastError()));}
  }
string Key(const string symbol,const string name){return "GAF_"+symbol+"_"+name;}
double Diag(const string symbol,const string name){return GlobalVariableGet(Key(symbol,name));}
void Fault(const string symbol,const int mode)
  {
   GlobalVariableSet(Key(symbol,"MODE"),mode);
   GlobalVariableSet(Key(symbol,"HIT_MODE"),0);
   GlobalVariableSet(Key(symbol,"HITS"),0);
  }
void Diagnostics(const string stage,const string symbol)
  {
   string names[]={"MODE","CALLS","PROCESSED","CURRENT","CLOSED","TOTAL","PREV","RETURN","NEED_REBUILD","DATA_READY","SILENT_BASELINE","REAL_BARS","REQUEST","REAL_N0","REAL_N1","REAL_N2","REPORTED_N2","HIT_MODE","HITS"};
   for(int j=0;j<ArraySize(names);j++)
      if(g_csv!=INVALID_HANDLE)FileWrite(g_csv,stage,symbol,names[j],DoubleToString(Diag(symbol,names[j]),0));
   if(g_csv!=INVALID_HANDLE)FileFlush(g_csv);
   Log(StringFormat("READBACK|%s|%s|processed=%s|current=%s|closed=%s|mode=%d|hit=%d|calls=%d|need_rebuild=%d|ready=%d",stage,symbol,
      TimeToString((datetime)Diag(symbol,"PROCESSED"),TIME_DATE|TIME_SECONDS),
      TimeToString((datetime)Diag(symbol,"CURRENT"),TIME_DATE|TIME_SECONDS),
      TimeToString((datetime)Diag(symbol,"CLOSED"),TIME_DATE|TIME_SECONDS),
      (int)Diag(symbol,"MODE"),(int)Diag(symbol,"HIT_MODE"),(int)Diag(symbol,"CALLS"),(int)Diag(symbol,"NEED_REBUILD"),(int)Diag(symbol,"DATA_READY")));
  }

bool CreateFixture(const string symbol,const int count)
  {
   ResetLastError();
   if(!CustomSymbolCreate(symbol,"CodexADXFault")){Log("SETUP_FAIL|CustomSymbolCreate|"+symbol);return false;}
   bool properties=CustomSymbolSetInteger(symbol,SYMBOL_DIGITS,2) &&
      CustomSymbolSetDouble(symbol,SYMBOL_POINT,0.01) &&
      CustomSymbolSetDouble(symbol,SYMBOL_TRADE_TICK_SIZE,0.01) &&
      CustomSymbolSetInteger(symbol,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED) &&
      SymbolSelect(symbol,true);
   if(!properties){Log("SETUP_FAIL|CustomSymbol properties|"+symbol);return false;}
   MqlRates rates[];ArrayResize(rates,count);ArraySetAsSeries(rates,false);
   datetime first=D'2026.08.03 00:00:00';
   double previous=2300.0;
   for(int i=0;i<count;i++)
     {
      ZeroMemory(rates[i]);rates[i].time=first+i*60;
      rates[i].open=previous;
      double price=2300+8*MathSin(i*0.11)+2*MathSin(i*0.43)+0.025*i;
      rates[i].close=NormalizeDouble(price,2);
      rates[i].high=NormalizeDouble(MathMax(rates[i].open,rates[i].close)+0.25+(i%4)*0.05,2);
      rates[i].low=NormalizeDouble(MathMin(rates[i].open,rates[i].close)-0.25-(i%3)*0.06,2);
      rates[i].tick_volume=100+i%30;rates[i].real_volume=10+i%7;rates[i].spread=2;
      previous=rates[i].close;
     }
   int copied=CustomRatesReplace(symbol,first,rates[count-1].time,rates);
   if(copied!=count){Log(StringFormat("SETUP_FAIL|CustomRatesReplace|expected=%d actual=%d",count,copied));return false;}
   g_tick_msc=(long)rates[count-1].time*1000+100;
   string keys[]={"MODE","CALLS","PROCESSED","CURRENT","CLOSED","TOTAL","PREV","RETURN","NEED_REBUILD","DATA_READY","SILENT_BASELINE","REAL_BARS","REQUEST","REAL_N0","REAL_N1","REAL_N2","REPORTED_N2","HIT_MODE","HITS"};
   for(int j=0;j<ArraySize(keys);j++)GlobalVariableSet(Key(symbol,keys[j]),0);
   Fault(symbol,0);
   return true;
  }
bool Pulse(const string symbol,const datetime candle,const double price)
  {
   long minimum=(long)candle*1000+100;
   if(g_tick_msc<minimum)g_tick_msc=minimum;
   else g_tick_msc+=100;
   if(g_tick_msc>=(long)(candle+60)*1000){Log("PULSE_FAIL|tick exceeded intended current bar");return false;}
   MqlTick ticks[];ArrayResize(ticks,1);ZeroMemory(ticks[0]);
   ticks[0].time_msc=g_tick_msc;ticks[0].time=(datetime)(g_tick_msc/1000);
   ticks[0].bid=price;ticks[0].ask=price+0.02;ticks[0].last=price;ticks[0].volume=1;ticks[0].volume_real=1;
   ticks[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST|TICK_FLAG_VOLUME;
   int added=CustomTicksAdd(symbol,ticks);
   if(added!=1)Log(StringFormat("PULSE_FAIL|CustomTicksAdd|actual=%d error=%d",added,GetLastError()));
   return added==1;
  }
int CreateIndicator(const string symbol,const int method,const bool injected)
  {
   string path=injected?"GSM_TEST\\GSM_ADX_FaultInjected":"GSM\\GSM_ADX_Trend_Meter";
   // Exact production inputs, including input-group placeholders. Enable only
   // the alert master and log path; popup, sound and push are all disabled.
   return iCustom(symbol,PERIOD_M1,path,
      "",method,14,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
      "",false,false,false,false,500,
      clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
      CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,
      "",true,false,false,false);
  }
bool Read(const int handle,const int buffer,const int start,const int count,double &values[])
  {
   ArrayResize(values,count);ArraySetAsSeries(values,false);
   return CopyBuffer(handle,buffer,start,count,values)==count;
  }
bool WaitReady(const string symbol,const int handle,const int normal,const datetime expected_current,const int seconds=15)
  {
   ulong start=GetTickCount64(),last_pulse=start;double a[],b[];
   while(!IsStopped() && GetTickCount64()-start<(ulong)seconds*1000)
     {
      bool complete=true;
      for(int k=0;k<15;k++)
        {
         if(!Read(handle,k,1,1,a)||!Read(normal,k,1,1,b)){complete=false;continue;}
         if(a[0]==EMPTY_VALUE||b[0]==EMPTY_VALUE||!MathIsValidNumber(a[0])||!MathIsValidNumber(b[0]))complete=false;
        }
      if(complete && (datetime)Diag(symbol,"CURRENT")==expected_current && (datetime)Diag(symbol,"PROCESSED")==iTime(symbol,PERIOD_M1,1))return true;
      if(GetTickCount64()-last_pulse>=500){Pulse(symbol,expected_current,SymbolInfoDouble(symbol,SYMBOL_BID));last_pulse=GetTickCount64();}
      Sleep(50);
     }
   Diagnostics("WAIT_READY_TIMEOUT",symbol);
   return false;
  }
bool WaitFault(const string symbol,const int handle,const int mode,const datetime expected_current,const double previous_calls,const int seconds=15)
  {
   ulong start=GetTickCount64(),last_pulse=start;double scratch[];
   while(!IsStopped() && GetTickCount64()-start<(ulong)seconds*1000)
     {
      Read(handle,0,0,2,scratch);
      bool backend_ready=(mode!=2 || Diag(symbol,"REAL_BARS")>=Diag(symbol,"TOTAL"));
      if(backend_ready && Diag(symbol,"CALLS")>previous_calls && (int)Diag(symbol,"HIT_MODE")==mode && (datetime)Diag(symbol,"CURRENT")==expected_current)return true;
      if(GetTickCount64()-last_pulse>=500){Pulse(symbol,expected_current,SymbolInfoDouble(symbol,SYMBOL_BID));last_pulse=GetTickCount64();}
      Sleep(50);
     }
   Diagnostics("WAIT_FAULT_TIMEOUT",symbol);return false;
  }
void CompareAll(const int injected,const int normal,const int count,const string label)
  {
   double a[],b[];double largest=0;int valid=0,empty=0;
   for(int k=0;k<15;k++)
     {
      bool ar=Read(injected,k,0,count,a),br=Read(normal,k,0,count,b);
      Check(ar&&br,label+" exact CopyBuffer count buffer "+IntegerToString(k));
      if(!ar||!br)continue;
      for(int j=0;j<count;j++)
        {
         if(a[j]==EMPTY_VALUE||b[j]==EMPTY_VALUE){empty++;Check(a[j]==b[j],label+" EMPTY agreement");}
         else
           {
            valid++;double error=MathAbs(a[j]-b[j]);if(error>largest)largest=error;
            Check(MathIsValidNumber(a[j])&&MathIsValidNumber(b[j])&&error<=1e-8,label+" value agreement");
           }
        }
     }
   Log(StringFormat("VALUE_COMPARE|%s|buffers=15|bars=%d|valid=%d|empty=%d|max_abs_error=%.12g",label,count,valid,empty,largest));
  }
void CheckFaultEmpty(const int handle)
  {
   double a[];
   for(int k=0;k<15;k++)
     {
      bool got=Read(handle,k,0,2,a);Check(got,"fault exposes exactly two latest positions buffer "+IntegerToString(k));
      if(!got)continue;
      Check(a[0]==EMPTY_VALUE,"fault latest closed position is EMPTY buffer "+IntegerToString(k));
      Check(a[1]==EMPTY_VALUE,"fault current position is EMPTY buffer "+IntegerToString(k));
     }
  }

void RunMethod(const int method,const string suffix)
  {
   string label=method==0?"WILDER":"MT5_STANDARD";
   string symbol="GAF_"+(method==0?"W_":"S_")+suffix;
   int fixture_count=400;
   Group(label+"_initial_real_builtin_baseline");
   bool created=CreateFixture(symbol,fixture_count);Check(created,"unique custom symbol and exact history fixture");
   if(!created){EndGroup();return;}
   datetime current=D'2026.08.03 00:00:00'+(fixture_count-1)*60;
   double price=2315.0;
   Check(Pulse(symbol,current,price),"initial real quote");
   int injected=CreateIndicator(symbol,method,true),normal=CreateIndicator(symbol,method,false);
   Check(injected!=INVALID_HANDLE&&normal!=INVALID_HANDLE,"instrumented and normal real indicator handles");
   if(injected==INVALID_HANDLE||normal==INVALID_HANDLE){EndGroup();return;}
   bool ready=WaitReady(symbol,injected,normal,current);Check(ready,"both real indicators ready at initial closed bar");
   if(!ready){EndGroup();IndicatorRelease(injected);IndicatorRelease(normal);return;}
   CompareAll(injected,normal,120,label+" initial baseline");
   Diagnostics("BASELINE",symbol);EndGroup();

   for(int mode=1;mode<=2;mode++)
     {
      string fault_name=mode==1?"third_CopyBuffer_partial_return":"BarsCalculated_not_ready_return";
      Group(label+"_"+fault_name);
      datetime processed=(datetime)Diag(symbol,"PROCESSED");
      double calls=Diag(symbol,"CALLS");
      current+=60;price+=mode==1?1.2:-0.8;
      Fault(symbol,mode);
      Check(Pulse(symbol,current,price),"new bar quote with injected API fault");
      bool observed=WaitFault(symbol,injected,mode,current,calls);Check(observed,"production calculation executed the selected controlled API fault");
      Diagnostics("FAULT_"+IntegerToString(mode),symbol);
      Check((datetime)Diag(symbol,"CLOSED")>processed,"new closed bar genuinely awaits processing");
      Check((datetime)Diag(symbol,"PROCESSED")==processed,"fault does not consume pending closed bar");
      Check(Diag(symbol,"NEED_REBUILD")==1,"fault schedules a complete safe rebuild");
      Check(Diag(symbol,"DATA_READY")==0,"fault marks current panel data unavailable");
      if(mode==1)
        {
         Check(Diag(symbol,"REAL_N0")==Diag(symbol,"REQUEST")&&Diag(symbol,"REAL_N1")==Diag(symbol,"REQUEST")&&Diag(symbol,"REAL_N2")==Diag(symbol,"REQUEST"),"real backend returned all three lines in full before injection");
         Check(Diag(symbol,"REPORTED_N2")==Diag(symbol,"REQUEST")-1,"only third-line reported return count is shortened");
        }
      else Check(Diag(symbol,"REAL_BARS")>=fixture_count+mode,"real backend was calculated before injected zero return");
      CheckFaultEmpty(injected);EndGroup();

      Group(label+"_same_bar_recovery_after_"+fault_name);
      Fault(symbol,0);
      Check(Pulse(symbol,current,price+0.01),"new quote while staying within the same unclosed bar");
      bool restored=WaitReady(symbol,injected,normal,current);Check(restored,"real data recovers without advancing another bar");
      Check((datetime)Diag(symbol,"PROCESSED")==iTime(symbol,PERIOD_M1,1),"recovery consumes the pending confirmed bar");
      Check((datetime)Diag(symbol,"PROCESSED")>processed,"pending signal bar was not silently skipped");
      Check((datetime)Diag(symbol,"CURRENT")==current,"recovery occurred on the intended same current bar");
      if(restored)CompareAll(injected,normal,120,label+" recovered mode "+IntegerToString(mode));
      Diagnostics("RECOVERED_"+IntegerToString(mode),symbol);EndGroup();
     }
   IndicatorRelease(injected);IndicatorRelease(normal);
  }

void OnStart()
  {
   g_file=FileOpen("GSM_ADX_Fault_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   g_csv=FileOpen("GSM_ADX_Fault_diagnostics.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_file==INVALID_HANDLE||g_csv==INVALID_HANDLE){Print("FAIL|Cannot open fault test evidence");return;}
   FileWrite(g_csv,"stage","symbol","diagnostic","value");
   Log("GSM ADX controlled API return fault injection");
   Log("PRODUCTION_SOURCE_SHA256="+PRODUCTION_SOURCE_SHA256);
   Log("TERMINAL_BUILD="+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   Log("SCOPE=Instrumented full production code; real iADX/iADXWilder backend; controlled API return-count simulation, not a real network disconnection.");
   Log("DELIVERY_CHANNELS=Popup off, Sound off, Push off. Alert master on for production processed-bar path and logs.");
   string suffix=IntegerToString((long)(GetTickCount64()%100000000));
   RunMethod(0,suffix);RunMethod(1,suffix);
   Log(StringFormat("OVERALL=%s|groups=%d|passed_groups=%d|assertions=%d|failures=%d",g_fails==0?"PASS":"FAIL",g_groups,g_passed,g_checks,g_fails));
   FileFlush(g_file);FileFlush(g_csv);FileClose(g_file);FileClose(g_csv);
  }
