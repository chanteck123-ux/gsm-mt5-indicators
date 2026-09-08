//+------------------------------------------------------------------+
//| GSM_ADX_Compare.mq5                                               |
//| Read-only broker-history validation. No orders/account APIs.      |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#property script_show_inputs
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"
#property description "ADX 与同算法内置数据对照；原始 CSV 和真实状态写入 MQL5/Files。"

input string InpSymbols="";           // 品种列表，逗号分隔；空值自动探测黄金及 EURUSD
input int    InpADXPeriod=14;          // 被测 ADX 周期（至少 2）
input int    InpSamples=500;           // 每个组合已收盘样本数上限
input int    InpMinimumSamples=100;    // 最少充分预热样本；不足时标记未测试
input int    InpWarmupBars=200;        // 从共同历史起点排除的最少根数
input double InpTolerance=1.0e-8;      // 数值比较容差
input int    InpWaitSeconds=20;        // 每次数据准备的最长等待秒数
input bool   InpAllSymbolsAllTF=false; // 其他品种也测四周期；默认仅测 M15
input string InpOutputStem="GSM_ADX_Compare"; // 输出文件前缀（不含路径）

int g_report=INVALID_HANDLE,g_csv=INVALID_HANDLE;
int g_pass=0,g_fail=0,g_not_tested=0,g_combinations=0;
const string INDICATOR_PATH="GSM\\GSM_ADX_Trend_Meter";

struct NumericSeries { double value[]; };

string TFName(const ENUM_TIMEFRAMES tf)
  {
   string answer=EnumToString(tf);
   StringReplace(answer,"PERIOD_","");
   return answer;
  }

string MethodName(const int method)
  {
   return method==0 ? "WILDER" : "MT5_STANDARD";
  }

string ValueText(const double value)
  {
   if(value==EMPTY_VALUE) return "EMPTY_VALUE";
   if(!MathIsValidNumber(value)) return "INVALID_NUMBER";
   return DoubleToString(value,16);
  }

void Record(const string status,const string category,const string details)
  {
   const string line=status+"|"+category+"|"+details;
   Print(line);
   if(g_report!=INVALID_HANDLE)
     {
      FileWriteString(g_report,line+"\r\n");
      FileFlush(g_report);
     }
   if(status=="PASS") g_pass++;
   else if(status=="FAIL") g_fail++;
   else if(status=="NOT_TESTED") g_not_tested++;
  }

bool IsBrokerSymbol(const string symbol)
  {
   bool custom=false;
   if(!SymbolExist(symbol,custom)) return false;
   return !custom;
  }

bool IsGoldName(const string symbol)
  {
   string upper=symbol;
   StringToUpper(upper);
   return StringFind(upper,"XAUUSD")==0 || StringFind(upper,"GOLD")==0;
  }

string FindBrokerSymbol(const string prefix)
  {
   if(IsBrokerSymbol(prefix)) return prefix;
   string result="";
   for(int i=0;i<SymbolsTotal(false);i++)
     {
      string symbol=SymbolName(i,false),upper=symbol;
      StringToUpper(upper);
      if(StringFind(upper,prefix)!=0 || !IsBrokerSymbol(symbol)) continue;
      if(result=="" || StringLen(symbol)<StringLen(result)) result=symbol;
     }
   return result;
  }

void AddSymbol(string &symbols[],const string symbol)
  {
   if(symbol=="") return;
   for(int i=0;i<ArraySize(symbols);i++) if(symbols[i]==symbol) return;
   const int count=ArraySize(symbols);
   ArrayResize(symbols,count+1);
   symbols[count]=symbol;
  }

void ResolveSymbols(string &symbols[])
  {
   ArrayResize(symbols,0);
   string requested=InpSymbols;
   StringTrimLeft(requested);
   StringTrimRight(requested);
   if(requested!="")
     {
      string parts[];
      const int n=StringSplit(requested,(ushort)',',parts);
      for(int i=0;i<n;i++)
        {
         StringTrimLeft(parts[i]);
         StringTrimRight(parts[i]);
         AddSymbol(symbols,parts[i]);
        }
      return;
     }
   string gold=FindBrokerSymbol("XAUUSD");
   if(gold=="") gold=FindBrokerSymbol("GOLD");
   AddSymbol(symbols,gold);
   string second=FindBrokerSymbol("EURUSD");
   if(second=="") second=FindBrokerSymbol("GBPUSD");
   if(second=="") second=FindBrokerSymbol("USDJPY");
   AddSymbol(symbols,second);
   if(gold=="") Record("NOT_TESTED","REAL_GOLD_DISCOVERY","No broker XAUUSD/GOLD symbol found; no custom symbol substituted.");
   if(second=="") Record("NOT_TESTED","SECOND_SYMBOL_DISCOVERY","No EURUSD/GBPUSD/USDJPY broker symbol found.");
  }

// This prefix is synchronized with the production indicator's declared inputs.
// Group declarations are explicit string slots in the target MT5 runtime.
int CreateGSM(const string symbol,const ENUM_TIMEFRAMES tf,const int method,const bool alternate)
  {
   // Both profiles disable every delivery channel. The alternate profile turns
   // the alert master on, so the master switch is exercised without popup,
   // sound, or push calls. Display changes must not affect any closed buffer.
   return iCustom(symbol,tf,INDICATOR_PATH,
                  "",method,InpADXPeriod,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
                  "",!alternate,!alternate,alternate,!alternate,alternate?17:500,
                  clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
                  CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,
                  "",alternate,false,false,false);
  }

void DumpParameters(const int handle,const string key)
  {
   ENUM_INDICATOR indicator_type;
   MqlParam values[];
   const int count=IndicatorParameters(handle,indicator_type,values);
   Record("INFO","ACTUAL_PARAMETERS",key+StringFormat(" handle=%d count=%d",handle,count));
   for(int i=0;i<count;i++)
      Record("INFO","PARAMETER",key+StringFormat(" slot=%d type=%s integer=%I64d double=%.12g string=%s",
                                                i,EnumToString(values[i].type),values[i].integer_value,
                                                values[i].double_value,values[i].string_value));
  }

void ReleaseHandles(const int gsm,const int builtin,const int alternate)
  {
   if(gsm!=INVALID_HANDLE) IndicatorRelease(gsm);
   if(builtin!=INVALID_HANDLE) IndicatorRelease(builtin);
   if(alternate!=INVALID_HANDLE) IndicatorRelease(alternate);
  }

bool PrepareHistory(const string symbol,const ENUM_TIMEFRAMES tf,const int warmup,int &count)
  {
   const ulong start=GetTickCount64();
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   count=0;
   // Never request missing broker history implicitly: synchronous CopyRates may
   // otherwise wait inside the platform longer than this script's deadline.
   // Load history normally in MT5 first, then rerun this read-only comparison.
   const int available=Bars(symbol,tf);
   if(available<warmup+InpMinimumSamples+1) return false;
   while(!IsStopped() && GetTickCount64()-start<(ulong)InpWaitSeconds*1000)
     {
      const int bars=Bars(symbol,tf);
      if(bars<warmup+InpMinimumSamples+1) return false;
      const int requested=MathMin(bars,warmup+InpSamples+2);
      const int copied=CopyRates(symbol,tf,0,requested,rates);
      if(copied>=warmup+InpMinimumSamples+1 && bars>=warmup+InpMinimumSamples+1)
        {
         count=MathMin(InpSamples,MathMin(copied,bars)-warmup-1);
         return count>=InpMinimumSamples;
        }
      Sleep(200);
     }
   return false;
  }

bool CopyExact(const int handle,const int buffer,const int shift,const int count,double &result[])
  {
   ArrayResize(result,count);
   ArraySetAsSeries(result,false); // CopyBuffer fills oldest-to-newest physically.
   return CopyBuffer(handle,buffer,shift,count,result)==count;
  }

bool CaptureBatch(const string symbol,const ENUM_TIMEFRAMES tf,const int count,const int warmup,
                  const int gsm,const int builtin,const int alternate,
                  NumericSeries &actual[],NumericSeries &reference[],NumericSeries &visual[],
                  datetime &times[],datetime &history_start,int &history_count)
  {
   const ulong start=GetTickCount64();
   ArrayResize(actual,15);
   ArrayResize(reference,3);
   ArrayResize(visual,15);
   ArraySetAsSeries(times,false);
   while(!IsStopped() && GetTickCount64()-start<(ulong)InpWaitSeconds*1000)
     {
      const int bars=Bars(symbol,tf);
      const datetime current=iTime(symbol,tf,0);
      const datetime first=(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
      if(current==0 || first==0 || BarsCalculated(gsm)<bars || BarsCalculated(builtin)<bars ||
         BarsCalculated(alternate)<bars || bars-count-1<warmup)
        { Sleep(200); continue; }
      bool good=CopyTime(symbol,tf,1,count,times)==count;
      for(int b=0;b<15 && good;b++)
         good=CopyExact(gsm,b,1,count,actual[b].value) && CopyExact(alternate,b,1,count,visual[b].value);
      for(int b=0;b<3 && good;b++) good=CopyExact(builtin,b,1,count,reference[b].value);
      if(good && current==iTime(symbol,tf,0) && first==(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE) &&
         bars==Bars(symbol,tf) && BarsCalculated(gsm)>=bars && BarsCalculated(builtin)>=bars && BarsCalculated(alternate)>=bars)
        {
         history_start=first;
         history_count=bars;
         return true;
        }
      Sleep(200);
     }
   return false;
  }

bool ValidNumber(const double value)
  {
   return value!=EMPTY_VALUE && MathIsValidNumber(value);
  }

bool EqualOutput(const double left,const double right)
  {
   if(left==EMPTY_VALUE || right==EMPTY_VALUE) return left==right;
   return MathIsValidNumber(left) && MathIsValidNumber(right) && MathAbs(left-right)<=InpTolerance;
  }

bool ValidDerived(const int buffer,const double value)
  {
   if(!ValidNumber(value) || value!=MathRound(value)) return false;
   if(buffer==3) return value>=0 && value<=3;
   if(buffer==4 || buffer==5) return value>=-1 && value<=1;
   return value==0 || value==1;
  }

void CompareCase(const string symbol,const ENUM_TIMEFRAMES tf,const int method)
  {
   const string key=StringFormat("symbol=%s tf=%s method=%s adx_period=%d",symbol,TFName(tf),MethodName(method),InpADXPeriod);
   const string origin=IsBrokerSymbol(symbol)?"BROKER_HISTORY":"CUSTOM_SYMBOL_NOT_REAL_MARKET";
   g_combinations++;
   Print("COMPARE_START|",key);
   if(!SymbolSelect(symbol,true))
     { Record("NOT_TESTED","SYMBOL_SELECT",key+StringFormat(" error=%d",GetLastError())); return; }
   const int warmup=MathMax(InpWarmupBars,InpADXPeriod*10+12);
   int count=0;
   if(!PrepareHistory(symbol,tf,warmup,count))
     {
      Record("NOT_TESTED","HISTORY",key+StringFormat(" origin=%s bars=%d required=%d error=%d",origin,Bars(symbol,tf),warmup+InpMinimumSamples+1,GetLastError()));
      return;
     }
   ResetLastError();
   const int builtin=method==0?iADXWilder(symbol,tf,InpADXPeriod):iADX(symbol,tf,InpADXPeriod);
   const int gsm=CreateGSM(symbol,tf,method,false);
   const int alternate=CreateGSM(symbol,tf,method,true);
   if(builtin==INVALID_HANDLE || gsm==INVALID_HANDLE || alternate==INVALID_HANDLE)
     {
      Record("FAIL","HANDLE_CREATION",key+StringFormat(" builtin=%d gsm=%d alternate=%d error=%d",builtin,gsm,alternate,GetLastError()));
      ReleaseHandles(gsm,builtin,alternate);
      return;
     }
   if(g_combinations==1)
     {
      DumpParameters(gsm,key+" profile=visible_alert_master_off");
      DumpParameters(alternate,key+" profile=hidden_alert_master_on_channels_off");
     }
   NumericSeries actual[],reference[],visual[];
   datetime times[],history_start=0;
   int history_count=0;
   if(!CaptureBatch(symbol,tf,count,warmup,gsm,builtin,alternate,actual,reference,visual,times,history_start,history_count))
     {
      Record("NOT_TESTED","DATA_BATCH",key+StringFormat(" exact_copy_count=%d gsm_bars=%d builtin_bars=%d alternate_bars=%d error=%d",count,BarsCalculated(gsm),BarsCalculated(builtin),BarsCalculated(alternate),GetLastError()));
      ReleaseHandles(gsm,builtin,alternate);
      return;
     }
   double maximum[3]={0,0,0};
   int numeric_fail=0,derived_fail=0,toggle_fail=0;
   for(int b=0;b<15;b++)
     {
      for(int i=0;i<count;i++)
        {
         const double value=actual[b].value[i],other=visual[b].value[i];
         double delta=EMPTY_VALUE;
         if(b<3)
           {
            const double expected=reference[b].value[i];
            if(!ValidNumber(value) || !ValidNumber(expected)) numeric_fail++;
            else
              {
               delta=MathAbs(value-expected);
               maximum[b]=MathMax(maximum[b],delta);
               if(delta>InpTolerance) numeric_fail++;
              }
           }
         else if(!ValidDerived(b,value)) derived_fail++;
         const bool same=EqualOutput(value,other);
         if(!same) toggle_fail++;
         if(g_csv!=INVALID_HANDLE)
            FileWrite(g_csv,symbol,origin,TFName(tf),MethodName(method),InpADXPeriod,
                      TimeToString(times[i],TIME_DATE|TIME_SECONDS),b,ValueText(value),
                      b<3?ValueText(reference[b].value[i]):"",b<3?ValueText(delta):"",
                      ValueText(other),same?"MATCH":"DIFFERENT");
        }
     }
   const string span=StringFormat(" %s samples=%d line_values=%d history_first=%s history_bars=%d excluded_min=%d from=%s to=%s tolerance=%.12g",
                                 key,count,count*3,TimeToString(history_start,TIME_DATE|TIME_SECONDS),history_count,warmup,
                                 TimeToString(times[0],TIME_DATE|TIME_SECONDS),TimeToString(times[count-1],TIME_DATE|TIME_SECONDS),InpTolerance);
   Record(numeric_fail==0?"PASS":"FAIL","BUILTIN_NUMERIC",span+StringFormat(" origin=%s max_ADX=%.17g max_PlusDI=%.17g max_MinusDI=%.17g failures=%d",origin,maximum[0],maximum[1],maximum[2],numeric_fail));
   Record(derived_fail==0?"PASS":"FAIL","CLOSED_INTERFACE",key+StringFormat(" values=%d failures=%d",count*12,derived_fail));
   Record(toggle_fail==0?"PASS":"FAIL","VISUAL_TOGGLES",key+StringFormat(" values=%d failures=%d",count*15,toggle_fail));
   int live_fail=0,live_copies=0;
   double live[];
   for(int b=3;b<15;b++)
     {
      if(CopyExact(gsm,b,0,1,live)) { live_copies++; if(live[0]!=EMPTY_VALUE) live_fail++; }
      else live_fail++;
      if(CopyExact(alternate,b,0,1,live)) { live_copies++; if(live[0]!=EMPTY_VALUE) live_fail++; }
      else live_fail++;
     }
   Record(live_fail==0?"PASS":"FAIL","LIVE_CONFIRM_EMPTY",key+StringFormat(" exact_copies=%d failures=%d",live_copies,live_fail));
   if(origin!="BROKER_HISTORY") Record("NOT_TESTED","REAL_MARKET_COVERAGE",key+" custom-symbol checks cannot establish real broker gold coverage");
   FileFlush(g_csv);
   ReleaseHandles(gsm,builtin,alternate);
  }

void OnStart()
  {
   if(InpADXPeriod<2 || InpADXPeriod>100000 || InpSamples<1 || InpSamples>100000 ||
      InpMinimumSamples<1 || InpMinimumSamples>InpSamples || InpWarmupBars<0 ||
      InpWarmupBars>1000000 || !MathIsValidNumber(InpTolerance) || InpTolerance<0 ||
      InpWaitSeconds<1 || InpWaitSeconds>60 || InpOutputStem=="" ||
      StringFind(InpOutputStem,"\\")>=0 || StringFind(InpOutputStem,"/")>=0 || StringFind(InpOutputStem,":")>=0)
     { Print("FAIL|INPUT|对照脚本参数无效，请检查周期、样本数、等待时间和文件前缀。"); return; }
   g_report=FileOpen(InpOutputStem+"_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   g_csv=FileOpen(InpOutputStem+"_values.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(g_report==INVALID_HANDLE || g_csv==INVALID_HANDLE)
     {
      PrintFormat("FAIL|OUTPUT|不能创建测试证据文件 error=%d",GetLastError());
      if(g_report!=INVALID_HANDLE) FileClose(g_report);
      if(g_csv!=INVALID_HANDLE) FileClose(g_csv);
      return;
     }
   FileWrite(g_csv,"symbol","data_origin","timeframe","method","adx_period","bar_open_time","buffer",
             "gsm_value","builtin_value","absolute_error","alternate_visual_value","visual_match");
   Record("INFO","ENVIRONMENT",StringFormat("terminal_build=%d run_local=%s script=%s no_order_or_account_APIs=true",
                                             (int)TerminalInfoInteger(TERMINAL_BUILD),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),MQLInfoString(MQL_PROGRAM_NAME)));
   Record("INFO","LIMITATION","This script verifies numeric buffers on available history. It does not claim notification delivery, full visual QA, strategy profitability, or disconnect simulation.");
   string symbols[];
   ResolveSymbols(symbols);
   ENUM_TIMEFRAMES periods[4]={PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H4};
   for(int s=0;s<ArraySize(symbols) && !IsStopped();s++)
     {
      const bool all=InpAllSymbolsAllTF || IsGoldName(symbols[s]);
      for(int t=0;t<(all?4:1) && !IsStopped();t++)
        for(int method=0;method<2 && !IsStopped();method++)
           CompareCase(symbols[s],all?periods[t]:PERIOD_M15,method);
     }
   if(ArraySize(symbols)==0) Record("NOT_TESTED","ALL_COMPARISONS","No available symbol to test.");
   if(IsStopped()) Record("NOT_TESTED","INTERRUPTED","Script stopped before all requested cases completed.");
   const string overall=g_fail>0?"FAIL":(g_not_tested>0?"PARTIAL_NOT_TESTED":(g_pass>0?"PASS":"NOT_TESTED"));
   Record("INFO","SUMMARY",StringFormat("OVERALL=%s passed=%d failed=%d not_tested=%d combinations=%d",overall,g_pass,g_fail,g_not_tested,g_combinations));
   FileClose(g_csv);
   FileClose(g_report);
   Print("GSM ADX 对照完成：MQL5/Files/",InpOutputStem,"_results.txt 和 _values.csv");
  }
