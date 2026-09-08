// Independent second broker symbol and timeframe native chart validation.
// No symbol creation, trading or account APIs. Unmodified production EX5.
#property strict
#property version "1.00"
#property tester_indicator "GSM\\GSM_ADX_Trend_Meter.ex5"
input string SYMBOL_NAME="EURUSD";
input ENUM_TIMEFRAMES TargetTimeframe=PERIOD_M15;
input string OutputStem="GSM_ADX_Second_EURUSD_M15";
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
   bool custom=false;
   bool real=SymbolExist(SYMBOL_NAME,custom)&&!custom&&SymbolSelect(SYMBOL_NAME,true);
   Check("SECOND_BROKER_SYMBOL_NOT_CUSTOM",real,"symbol="+SYMBOL_NAME+" tf="+TF(TargetTimeframe));if(!real)return;
   long chart=ChartOpen(SYMBOL_NAME,TargetTimeframe);
   Check("SECOND_OWN_REAL_CHART",chart>0&&chart!=ChartID(),StringFormat("chart=%I64d",chart));if(chart<=0||chart==ChartID())return;
   Sleep(300);
   Check("SECOND_TRADE_DECORATIONS_OFF",CleanTradeDecorations(chart));
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=0;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   ChartSetInteger(chart,CHART_SHOW_GRID,false);ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);ChartSetInteger(chart,CHART_SCALE,3);
   ChartSetInteger(chart,CHART_COLOR_BACKGROUND,clrBlack);ChartSetInteger(chart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetString(chart,CHART_COMMENT,"REAL BROKER "+SYMBOL_NAME+" / GSM ADX / INDICATOR VALIDATION ONLY");
   Note(StringFormat("PHASE|SECOND_LOAD_BEGIN|chart=%I64d symbol=%s tf=%s expected_historical_alerts=0 current_bar=%s",chart,SYMBOL_NAME,TF(TargetTimeframe),
      TimeToString(iTime(SYMBOL_NAME,TargetTimeframe,0),TIME_DATE|TIME_MINUTES)));
   int h=iCustom(SYMBOL_NAME,TargetTimeframe,PATH,"",0,14,20.0,25.0,40.0,0.0,2,3,10,10,3,false,25.0,
      "",true,true,false,true,500,clrDodgerBlue,clrLimeGreen,clrTomato,2,1,1,clrSlateGray,STYLE_DOT,1,
      CORNER_LEFT_UPPER,12,14,10,"Microsoft YaHei",clrGainsboro,clrBlack,"",true,false,false,false);
   bool attached=h!=INVALID_HANDLE&&ReadyHandle(h,SYMBOL_NAME,TargetTimeframe)&&ChartIndicatorAdd(chart,1,h);
   ChartRedraw(chart);Sleep(300);
   string bootstrap=OutputStem+"_bootstrap.tpl";bool saved=attached&&ChartSaveTemplate(chart,bootstrap);
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   if(h!=INVALID_HANDLE)IndicatorRelease(h);
   bool applied=saved&&ChartApplyTemplate(chart,bootstrap);Check("SECOND_NATIVE_TEMPLATE_APPLIED",applied);
   string prefix="";int window=-1;bool panel=applied&&WaitPanel(chart,TargetTimeframe,prefix,window);
   Check("SECOND_NATIVE_PANEL_READY",panel,"symbol="+SYMBOL_NAME+" tf="+TF(TargetTimeframe));
   if(panel)
     {
      CaptureData(chart,TargetTimeframe,window,prefix);
      Check("SECOND_TRADE_DECORATIONS_ABSENT",CleanTradeDecorations(chart));
      ChartRedraw(chart);Sleep(1500);
      Check("SECOND_NATIVE_TEMPLATE_SAVED",ChartSaveTemplate(chart,OutputStem+".tpl"),"template="+OutputStem+".tpl");
      Check("SECOND_NATIVE_SCREENSHOT",SaveScreenshot(chart,OutputStem+".png"),"image="+OutputStem+".png");
      Note("TEMPLATE_AND_IMAGE_REVIEW_REQUIRED|"+OutputStem+".tpl|Confirm 3 curves, 20/25/40 levels, Chinese panel, and actual broker symbol/timeframe.");
     }
   Note(StringFormat("PHASE|SECOND_LOAD_END|chart=%I64d symbol=%s tf=%s expected_historical_alerts=0",chart,SYMBOL_NAME,TF(TargetTimeframe)));
   for(int w=(int)ChartGetInteger(chart,CHART_WINDOWS_TOTAL)-1;w>=1;w--)
      for(int k=ChartIndicatorsTotal(chart,w)-1;k>=0;k--)ChartIndicatorDelete(chart,w,ChartIndicatorName(chart,w,k));
   Sleep(300);Check("SECOND_FINAL_CLEANUP",PrefixCount(chart,"GSM_ADX_")==0);
   ChartClose(chart);
  }
void OnStart()
  {
   Report=FileOpen(OutputStem+"_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   CSV=FileOpen(OutputStem+"_buffers.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   string header="timeframe,time";for(int b=0;b<15;b++)header+=",buffer"+IntegerToString(b);
   if(CSV!=INVALID_HANDLE)FileWriteString(CSV,header+"\r\n");
   Note("INFO|SECOND_REAL_NATIVE_UI|symbol="+SYMBOL_NAME+" tf="+TF(TargetTimeframe)+"; default Wilder14; alerts master true; popup/sound/push false.");
   Run();Note(StringFormat("RUNTIME_SCOPE=%s groups=%d failures=%d; visual and historical-alert verdict requires native image/template/journal review",Failures==0?"PASS":"FAIL",Groups,Failures));
   if(CSV!=INVALID_HANDLE)FileClose(CSV);if(Report!=INVALID_HANDLE)FileClose(Report);
  }
