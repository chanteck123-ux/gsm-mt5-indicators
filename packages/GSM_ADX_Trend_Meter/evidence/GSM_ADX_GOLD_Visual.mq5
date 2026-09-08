// Real broker GOLD chart: same chart ID switches M5 -> M15 -> H1 -> H4.
// No symbol creation, trading or account APIs. Unmodified production EX5.
#property strict
#property version "1.00"
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"
const string SYMBOL_NAME="GOLD";
const string PATH="GSM\\GSM_ADX_Trend_Meter";
int Report=INVALID_HANDLE,CSV=INVALID_HANDLE,Groups=0,Failures=0;
void Note(const string text){Print(text);if(Report!=INVALID_HANDLE){FileWriteString(Report,text+"\r\n");FileFlush(Report);}}
void Check(const string name,const bool okay,const string detail=""){Groups++;if(!okay)Failures++;Note((okay?"PASS|":"FAIL|")+name+"|"+detail);}
string TF(const ENUM_TIMEFRAMES tf){string s=EnumToString(tf);StringReplace(s,"PERIOD_","");return s;}
bool Valid(const double value){return value!=EMPTY_VALUE&&MathIsValidNumber(value);}
int PrefixCount(const long chart,const string prefix)
  {int count=0;for(int k=0;k<ObjectsTotal(chart,-1,-1);k++)if(StringFind(ObjectName(chart,k,-1,-1),prefix)==0)count++;return count;}
bool CleanTradeDecorations(const long chart)
  {
   if(chart<=0||chart==ChartID())return false;
   ChartSetInteger(chart,CHART_SHOW_TRADE_HISTORY,false);
   ChartSetInteger(chart,CHART_SHOW_TRADE_LEVELS,false);
   // Exact automatic-history prefix observed in the saved native template.
   // Only this script's newly created chart is touched; account history is not.
   ObjectsDeleteAll(chart,"autotrade ",-1,-1);
   ChartRedraw(chart);Sleep(200);
   return !ChartGetInteger(chart,CHART_SHOW_TRADE_HISTORY)&&!ChartGetInteger(chart,CHART_SHOW_TRADE_LEVELS)&&PrefixCount(chart,"autotrade ")==0;
  }
int FindPanel(const long chart,const string period,string &prefix,int &window)
  {
   int count=0;prefix="";window=-1;
   for(int k=0;k<ObjectsTotal(chart,-1,-1);k++)
     {
      string name=ObjectName(chart,k,-1,-1);
      if(StringFind(name,"GSM_ADX_")!=0||StringLen(name)<3||StringSubstr(name,StringLen(name)-2)!="P0")continue;
      if(ObjectGetString(chart,name,OBJPROP_TEXT)!="GSM ADX 趋势强弱测量器")continue;
      count++;string p=StringSubstr(name,0,StringLen(name)-2);
      string source=ObjectGetString(chart,p+"P1",OBJPROP_TEXT);
      if(StringFind(source,SYMBOL_NAME)>=0&&StringFind(source,"周期："+period)>=0){prefix=p;window=ObjectFind(chart,name);}
     }
   return count;
  }
bool ReadyHandle(const int handle,const string symbol,const ENUM_TIMEFRAMES tf)
  {
   ulong start=GetTickCount64();double data[];
   while(!IsStopped()&&GetTickCount64()-start<25000)
     {
      int got=CopyBuffer(handle,0,1,1,data);
      if(got==1&&Valid(data[0])&&BarsCalculated(handle)>=Bars(symbol,tf)&&Bars(symbol,tf)>100)return true;
      Sleep(100);
     }
   return false;
  }
bool SaveScreenshot(const long chart,const string file)
  {
   if(!CleanTradeDecorations(chart))return false;
   ChartRedraw(chart);Sleep(1500);ChartRedraw(chart);Sleep(600);
   int width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS,0),height=0;
   int windows=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL);
   for(int w=0;w<windows;w++)height+=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,w);
   if(FileIsExist(file))FileDelete(file);
   bool saved=width>0&&height>0&&ChartScreenShot(chart,file,width,height,ALIGN_RIGHT);
   for(int wait=0;wait<50&&!FileIsExist(file);wait++)Sleep(100);
   Note(StringFormat("NATIVE_SCREENSHOT|file=%s|chart=%I64d|size=%dx%d|windows=%d",file,chart,width,height,windows));
   return saved&&FileIsExist(file);
  }
bool WaitPanel(const long chart,const ENUM_TIMEFRAMES tf,string &prefix,int &window)
  {
   ulong start=GetTickCount64();
   while(!IsStopped()&&GetTickCount64()-start<30000)
     {
      if(ChartSymbol(chart)==SYMBOL_NAME&&ChartPeriod(chart)==tf&&FindPanel(chart,TF(tf),prefix,window)==1&&window>=1&&prefix!="")
        {
         string data=ObjectGetString(chart,prefix+"P4",OBJPROP_TEXT);
         if(StringFind(data,"ADX：")>=0&&StringFind(data,"+DI：")>=0&&StringFind(data,"-DI：")>=0)return true;
        }
      ChartRedraw(chart);Sleep(100);
     }
   Note(StringFormat("PANEL_WAIT_FAIL chart=%I64d wanted=%s actual=%s window=%d prefix=%s",chart,TF(tf),TF(ChartPeriod(chart)),window,prefix));return false;
  }
bool CaptureData(const long chart,const ENUM_TIMEFRAMES tf,const int window,const string prefix)
  {
   string shortname="";
   for(int k=0;k<ChartIndicatorsTotal(chart,window);k++)
     {string name=ChartIndicatorName(chart,window,k);if(StringFind(name,"GSM ADX 趋势强弱测量器")==0){shortname=name;break;}}
   int h=shortname!=""?ChartIndicatorGet(chart,window,shortname):INVALID_HANDLE;
   if(h==INVALID_HANDLE)return false;
   bool ready=ReadyHandle(h,SYMBOL_NAME,tf);double d[1];
   int valid_lines=0,empty_current=0;bool finite=ready;
   for(int b=0;b<3&&finite;b++){if(CopyBuffer(h,b,1,1,d)!=1||!Valid(d[0]))finite=false;else valid_lines++;}
   for(int b=3;b<15&&finite;b++){if(CopyBuffer(h,b,0,1,d)!=1||d[0]!=EMPTY_VALUE)finite=false;else empty_current++;}
   Check("REAL_CURVES_AND_CLOSED_INTERFACE",finite&&valid_lines==3&&empty_current==12,
      StringFormat("tf=%s native_shortname=%s lines=%d current_confirmed_empty=%d",TF(tf),shortname,valid_lines,empty_current));
   string p0=ObjectGetString(chart,prefix+"P0",OBJPROP_TEXT),p2=ObjectGetString(chart,prefix+"P2",OBJPROP_TEXT),
      p3=ObjectGetString(chart,prefix+"P3",OBJPROP_TEXT),p10=ObjectGetString(chart,prefix+"P10",OBJPROP_TEXT);
   bool chinese=p0=="GSM ADX 趋势强弱测量器"&&StringFind(p2,"ADX Wilder")>=0&&StringFind(p2,"14")>=0&&
      StringFind(p3,"最近已收盘K线")>=0&&StringFind(p10,"不是自动买卖指令")>=0;
   Check("REAL_CHINESE_PANEL",chinese,"tf="+TF(tf)+" prefix="+prefix+" "+p2+" "+p3);
   bool exported=finite;
   for(int s=50;s>=1&&exported;s--)
     {
      datetime time=iTime(SYMBOL_NAME,tf,s);if(time<=0){exported=false;break;}
      string row=TF(tf)+","+TimeToString(time,TIME_DATE|TIME_MINUTES);
      for(int b=0;b<15;b++)
        {
         if(CopyBuffer(h,b,s,1,d)!=1){exported=false;break;}
         row+=","+(d[0]==EMPTY_VALUE?"EMPTY_VALUE":DoubleToString(d[0],16));
        }
      if(exported&&CSV!=INVALID_HANDLE)FileWriteString(CSV,row+"\r\n");
     }
   if(CSV!=INVALID_HANDLE)FileFlush(CSV);
   Check("REAL_RECENT_BUFFER_CSV",exported,"tf="+TF(tf)+" rows=50 buffers=15");
   IndicatorRelease(h);
   return finite&&chinese&&exported;
  }
void Run()
  {
   bool custom=false;bool real=SymbolExist(SYMBOL_NAME,custom)&&!custom&&SymbolSelect(SYMBOL_NAME,true);
   Check("BROKER_GOLD_NOT_CUSTOM",real,"symbol=GOLD; no replacement or synthetic fallback");if(!real)return;
   ENUM_TIMEFRAMES periods[4]={PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H4};
   for(int k=0;k<4;k++)
      Note(StringFormat("CACHED_HISTORY|symbol=GOLD tf=%s bars=%d oldest=%s latest=%s",TF(periods[k]),Bars(SYMBOL_NAME,periods[k]),
         TimeToString((datetime)SeriesInfoInteger(SYMBOL_NAME,periods[k],SERIES_FIRSTDATE),TIME_DATE|TIME_MINUTES),
         TimeToString(iTime(SYMBOL_NAME,periods[k],0),TIME_DATE|TIME_MINUTES)));
   long chart=ChartOpen(SYMBOL_NAME,PERIOD_M5);
   Check("OWN_REAL_CHART",chart>0&&chart!=ChartID(),StringFormat("chart=%I64d host=%I64d",chart,ChartID()));if(chart<=0||chart==ChartID())return;
   Sleep(300);
   Check("OWN_CHART_TRADE_DECORATIONS_OFF",CleanTradeDecorations(chart));
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=0;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);ChartSetInteger(chart,CHART_SCALE,3);
   ChartSetInteger(chart,CHART_COLOR_BACKGROUND,clrBlack);ChartSetInteger(chart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetString(chart,CHART_COMMENT,"REAL BROKER GOLD / GSM ADX / INDICATOR VALIDATION ONLY");
   Note(StringFormat("PHASE|REAL_LOAD_BEGIN|chart=%I64d tf=M5 expected_historical_alerts=0 current_bar=%s",chart,
      TimeToString(iTime(SYMBOL_NAME,PERIOD_M5,0),TIME_DATE|TIME_MINUTES)));
   int h=iCustom(SYMBOL_NAME,PERIOD_M5,PATH,"",0,14,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
      "",true,true,false,true,500,clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
      CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,"",true,false,false,false);
   bool attach=h!=INVALID_HANDLE&&ReadyHandle(h,SYMBOL_NAME,PERIOD_M5)&&ChartIndicatorAdd(chart,1,h);
   ChartRedraw(chart);Sleep(300);
   string bootstrap="GSM_ADX_GOLD_bootstrap.tpl";bool saved=attach&&ChartSaveTemplate(chart,bootstrap);
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   if(h!=INVALID_HANDLE)IndicatorRelease(h);
   bool native=saved&&ChartApplyTemplate(chart,bootstrap);Check("REAL_NATIVE_TEMPLATE_APPLIED",native,"bootstrap="+bootstrap);
   string prior_prefix="";
   for(int k=0;k<4&&native&&!IsStopped();k++)
     {
      ENUM_TIMEFRAMES tf=periods[k];
      if(k>0)
        {
         Note(StringFormat("PHASE|REAL_TIMEFRAME_SWITCH_BEGIN|chart=%I64d tf=%s expected_historical_alerts=0 current_bar=%s",chart,TF(tf),
            TimeToString(iTime(SYMBOL_NAME,tf,0),TIME_DATE|TIME_MINUTES)));
         native=ChartSetSymbolPeriod(chart,SYMBOL_NAME,tf);
         Check("REAL_SAME_CHART_TIMEFRAME_SWITCH",native,StringFormat("chart=%I64d from=%s to=%s",chart,TF(periods[k-1]),TF(tf)));
        }
      string prefix="";int window=-1;bool panel=native&&WaitPanel(chart,tf,prefix,window);
      Check("REAL_NATIVE_PANEL_READY",panel,"tf="+TF(tf));if(!panel)break;
      if(prior_prefix!="")Check("OLD_TIMEFRAME_OBJECTS_CLEANED",prefix!=prior_prefix&&PrefixCount(chart,prior_prefix)==0,"tf="+TF(tf));
      CaptureData(chart,tf,window,prefix);
      Check("REAL_TRADE_DECORATIONS_ABSENT",CleanTradeDecorations(chart),"tf="+TF(tf));
      ChartRedraw(chart);Sleep(1500);
      string template_name="GSM_ADX_GOLD_"+TF(tf)+".tpl",image_name="GSM_ADX_GOLD_"+TF(tf)+".png";
      bool template_saved=ChartSaveTemplate(chart,template_name);
      Check("REAL_NATIVE_TEMPLATE_SAVED",template_saved,"tf="+TF(tf)+" template="+template_name);
      Check("REAL_NATIVE_SCREENSHOT",SaveScreenshot(chart,image_name),"tf="+TF(tf)+" image="+image_name);
      Note("TEMPLATE_AND_IMAGE_REVIEW_REQUIRED|"+template_name+"|Confirm native 3 DRAW_LINE plots, ADX/PlusDI/MinusDI, default colors/widths, and horizontal levels 20/25/40; screenshot must be visually inspected.");
      Note(StringFormat("PHASE|REAL_LOAD_END|chart=%I64d tf=%s prefix=%s expected_historical_alerts=0",chart,TF(tf),prefix));
      prior_prefix=prefix;
     }
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   Sleep(300);Check("REAL_FINAL_UNLOAD_CLEANUP",PrefixCount(chart,"GSM_ADX_")==0,StringFormat("remaining=%d",PrefixCount(chart,"GSM_ADX_")));
   ChartClose(chart);
   Note("JOURNAL_REVIEW_REQUIRED|No historical GSM_ADX_ALERT_CONFIRMED lines may occur within load/switch phases. A genuine new live broker bar after the recorded current_bar boundary is not an old-history replay.");
  }
void OnStart()
  {
   Report=FileOpen("GSM_ADX_GOLD_Visual_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   CSV=FileOpen("GSM_ADX_GOLD_Visual_buffers.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   string header="timeframe,time";for(int b=0;b<15;b++)header+=",buffer"+IntegerToString(b);
   if(CSV!=INVALID_HANDLE)FileWriteString(CSV,header+"\r\n");
   Note("INFO|REAL_GOLD_NATIVE_UI|Same chart native M5/M15/H1/H4 switch; default Wilder14; EnableAlerts=true with all three external channels=false.");
   Run();Note(StringFormat("RUNTIME_SCOPE=%s groups=%d failures=%d; final visual/level/alert verdict requires native template/image/journal review",Failures==0?"PASS":"FAIL",Groups,Failures));
   if(CSV!=INVALID_HANDLE)FileClose(CSV);if(Report!=INVALID_HANDLE)FileClose(Report);
  }
