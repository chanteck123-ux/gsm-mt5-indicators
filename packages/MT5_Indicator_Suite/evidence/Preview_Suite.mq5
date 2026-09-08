// Visual fixture only. Opens and closes its own synthetic charts.
// Uses the actual compiled indicators; never draws reconstructed indicator data.
#property strict
#property version "1.00"

const string PreviewSymbol="CODEX_SUITE_CLASSIC";
int PreviewLog=INVALID_HANDLE;
long OwnedCharts[];
string HostObjectsBefore[];
ulong PreviewStarted=0;

void LogPreview(const string text)
{
   Print(text);
   if(PreviewLog!=INVALID_HANDLE) {FileWrite(PreviewLog,text); FileFlush(PreviewLog);}
}

bool HasName(const string name,const string &names[])
{
   for(int i=0;i<ArraySize(names);i++) if(names[i]==name) return true;
   return false;
}

bool IsSuiteObject(const string name)
{
   return StringFind(name,"CA_BBR_")==0 || StringFind(name,"VP_")==0;
}

void SnapshotHost()
{
   const int n=ObjectsTotal(0,-1,-1);
   ArrayResize(HostObjectsBefore,n);
   for(int i=0;i<n;i++) HostObjectsBefore[i]=ObjectName(0,i,-1,-1);
}

int CountSuiteObjects(const long chart,const string prefix)
{
   int count=0;
   const int n=ObjectsTotal(chart,-1,-1);
   for(int i=0;i<n;i++)
      if(StringFind(ObjectName(chart,i,-1,-1),prefix)==0) count++;
   return count;
}

void CleanNewHostObjects()
{
   int removed=0;
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
   {
      const string name=ObjectName(0,i,-1,-1);
      if(IsSuiteObject(name) && !HasName(name,HostObjectsBefore))
         if(ObjectDelete(0,name)) removed++;
   }
   if(removed>0) LogPreview(StringFormat("HOST_CLEANUP new_suite_objects_removed=%d host_chart=%I64d",removed,ChartID()));
}

void StyleChart(const long chart,const string label)
{
   ChartSetInteger(chart,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(chart,CHART_SHOW_GRID,false);
   ChartSetInteger(chart,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
   ChartSetInteger(chart,CHART_AUTOSCROLL,true);
   ChartSetInteger(chart,CHART_SHIFT,true);
   ChartSetDouble(chart,CHART_SHIFT_SIZE,16);
   ChartSetInteger(chart,CHART_SCALE,3);
   ChartSetInteger(chart,CHART_COLOR_BACKGROUND,clrBlack);
   ChartSetInteger(chart,CHART_COLOR_FOREGROUND,clrSilver);
   ChartSetInteger(chart,CHART_COLOR_CHART_UP,C'105,150,125');
   ChartSetInteger(chart,CHART_COLOR_CHART_DOWN,C'175,100,100');
   ChartSetInteger(chart,CHART_COLOR_CANDLE_BULL,C'65,105,85');
   ChartSetInteger(chart,CHART_COLOR_CANDLE_BEAR,C'120,60,60');
   ChartSetInteger(chart,CHART_SHOW_TRADE_LEVELS,false);
   ChartSetString(chart,CHART_COMMENT,"SYNTHETIC DATA / VISUAL CHECK ONLY\n"+label+"\nActual MT5 indicator on generated data; not a performance backtest.");
   ChartNavigate(chart,CHART_END,0);
   ChartRedraw(chart);
}

int CreateHandle(const int kind)
{
   // Full default user display settings: BB fill/background ON; VP objects ON.
   if(kind==0) return iCustom(PreviewSymbol,PERIOD_M1,"Bollinger_RSI_ChartArt_MT5");
   if(kind==1) return iCustom(PreviewSymbol,PERIOD_M1,"SMA_Ribbon_10_MT5");
   if(kind==2) return iCustom(PreviewSymbol,PERIOD_M1,"EMA_20_50_100_200_MT5");
   return iCustom(PreviewSymbol,PERIOD_M1,"Volume_Profile_MT5",false,200,200,1,20,70,0,0,true,true,68,true,clrDimGray,clrRed,clrDodgerBlue,1,true);
}

bool WaitHandle(const int handle,const int count,const int timeout_ms=12000)
{
   const ulong deadline=GetTickCount64()+(ulong)timeout_ms;
   double probe[];
   while(GetTickCount64()<deadline && GetTickCount64()-PreviewStarted<115000 && !IsStopped())
   {
      if(CopyBuffer(handle,0,0,1,probe)==1 && BarsCalculated(handle)>=count) return true;
      Sleep(100);
   }
   return false;
}

bool WaitTargetIndicator(const long chart,const string expected,const int count,int &target_handle)
{
   const ulong deadline=GetTickCount64()+12000;
   while(GetTickCount64()<deadline && GetTickCount64()-PreviewStarted<115000 && !IsStopped())
   {
      const int total=ChartIndicatorsTotal(chart,0);
      for(int p=0;p<total;p++)
      {
         const string label=ChartIndicatorName(chart,0,p);
         if(label==expected)
         {
            target_handle=ChartIndicatorGet(chart,0,label);
            if(target_handle!=INVALID_HANDLE) return WaitHandle(target_handle,count,4000);
         }
      }
      Sleep(100);
   }
   return false;
}

void CloseOwnedChart(const long chart)
{
   if(chart<=0 || chart==ChartID()) return;
   bool owned=false;
   for(int i=0;i<ArraySize(OwnedCharts);i++) if(OwnedCharts[i]==chart) {owned=true; break;}
   if(!owned) return;
   // This chart was opened by this script. Closing it triggers indicator cleanup.
   const bool closed=ChartClose(chart);
   LogPreview(StringFormat("CLOSE chart=%I64d requested=%d error=%d",chart,closed,GetLastError()));
   Sleep(250);
   for(int i=0;i<ArraySize(OwnedCharts);i++) if(OwnedCharts[i]==chart) OwnedCharts[i]=0;
}

void PreviewOne(const int kind,const string label,const string shortname,const string object_prefix,const string image_name)
{
   ResetLastError();
   const long chart=ChartOpen(PreviewSymbol,PERIOD_M1);
   if(chart<=0 || chart==ChartID())
   {
      LogPreview(StringFormat("FAIL %s ChartOpen=%I64d error=%d",label,chart,GetLastError()));
      return;
   }
   int owned=ArraySize(OwnedCharts); ArrayResize(OwnedCharts,owned+1); OwnedCharts[owned]=chart;
   // Own fresh chart only: remove any indicators a user's default template adds.
   for(int p=ChartIndicatorsTotal(chart,0)-1;p>=0;p--)
      ChartIndicatorDelete(chart,0,ChartIndicatorName(chart,0,p));
   StyleChart(chart,label);
   int handle=CreateHandle(kind);
   const bool attached=(handle!=INVALID_HANDLE && ChartIndicatorAdd(chart,0,handle));
   const bool ready=(attached && WaitHandle(handle,5000));
   ChartRedraw(chart); Sleep(700);
   int target_objects=ObjectsTotal(chart,-1,-1);
   int source_objects=(StringLen(object_prefix)>0 ? CountSuiteObjects(chart,object_prefix) : 0);
   LogPreview(StringFormat("ATTACH %s chart=%I64d handle=%d attached=%d ready=%d indicators=%d target_objects=%d target_own_objects=%d host_objects=%d error=%d",
                          label,chart,handle,attached,ready,ChartIndicatorsTotal(chart,0),target_objects,source_objects,ObjectsTotal(0,-1,-1),GetLastError()));

   bool template_applied=false,template_ready=false;
   // An iCustom instance can retain the script's host ChartID for object calls.
   // Save the actual attached indicator and its actual inputs as a native template,
   // then let MT5 recreate it as a chart-owned instance if target objects are absent.
   if(attached && StringLen(object_prefix)>0 && source_objects==0 && !IsStopped())
   {
      const string template_name="suite_preview_"+IntegerToString(kind)+"_"+IntegerToString((long)PreviewStarted)+".tpl";
      const bool saved=ChartSaveTemplate(chart,template_name);
      if(saved)
      {
         ChartIndicatorDelete(chart,0,shortname);
         IndicatorRelease(handle); handle=INVALID_HANDLE;
         Sleep(250);
         CleanNewHostObjects();
         ResetLastError();
         template_applied=ChartApplyTemplate(chart,template_name);
         const int apply_error=GetLastError();
         if(template_applied) template_ready=WaitTargetIndicator(chart,shortname,5000,handle);
         StyleChart(chart,label);
         ChartRedraw(chart); Sleep(700);
         source_objects=CountSuiteObjects(chart,object_prefix);
         LogPreview(StringFormat("TEMPLATE %s name=%s saved=1 applied=%d ready=%d apply_error=%d target_own_objects=%d target_objects=%d host_objects=%d",
                                label,template_name,template_applied,template_ready,apply_error,source_objects,ObjectsTotal(chart,-1,-1),ObjectsTotal(0,-1,-1)));
      }
      else LogPreview(StringFormat("TEMPLATE %s saved=0 error=%d",label,GetLastError()));
   }

   StyleChart(chart,label);
   ChartRedraw(chart); Sleep(700);
   // Replace this script's named previous artifact so existence cannot be stale.
   if(FileIsExist(image_name)) FileDelete(image_name);
   ResetLastError();
   // Pixel-anchored objects use the live chart canvas coordinates. Preserve
   // its actual dimensions instead of cropping them with a smaller bitmap.
   int shot_width=(int)ChartGetInteger(chart,CHART_WIDTH_IN_PIXELS,0);
   int shot_height=(int)ChartGetInteger(chart,CHART_HEIGHT_IN_PIXELS,0);
   LogPreview(StringFormat("CANVAS %s width=%d height=%d",label,shot_width,shot_height));
   const bool screenshot=ChartScreenShot(chart,image_name,shot_width,shot_height,ALIGN_RIGHT);
   const int shot_error=GetLastError();
   // File presence is evidence the asynchronous request produced a local artifact.
   bool exists=false;
   for(int wait=0;wait<30 && !IsStopped();wait++)
   {
      if(FileIsExist(image_name)) {exists=true; break;}
      Sleep(100);
   }
   const bool object_ok=(StringLen(object_prefix)==0 || CountSuiteObjects(chart,object_prefix)>0);
   LogPreview(StringFormat("SCREENSHOT %s chart=%I64d file=%s returned=%d exists=%d error=%d final_indicators=%d objects=%d own_objects=%d object_check=%d native_template=%d",
                          label,chart,image_name,screenshot,exists,shot_error,ChartIndicatorsTotal(chart,0),ObjectsTotal(chart,-1,-1),
                          StringLen(object_prefix)>0 ? CountSuiteObjects(chart,object_prefix) : 0,object_ok,template_applied));
   if(!object_ok) LogPreview("VISUAL_REVIEW_REQUIRED: expected object drawings absent from target chart; do not present this screenshot as a successful indicator preview.");
   if(handle!=INVALID_HANDLE) IndicatorRelease(handle);
   CloseOwnedChart(chart);
   CleanNewHostObjects();
}

void OnStart()
{
   PreviewStarted=GetTickCount64();
   PreviewLog=FileOpen("suite_preview_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   SnapshotHost();
   LogPreview(StringFormat("SYNTHETIC DATA / VISUAL CHECK ONLY host_chart=%I64d host_symbol=%s",ChartID(),ChartSymbol(0)));
   bool custom=false;
   if(!SymbolExist(PreviewSymbol,custom) || !custom || !SymbolSelect(PreviewSymbol,true))
   {
      LogPreview("FAIL: expected custom fixture CODEX_SUITE_CLASSIC is absent; run classic validation first.");
      if(PreviewLog!=INVALID_HANDLE) FileClose(PreviewLog);
      return;
   }
   MqlRates probe[];
   if(CopyRates(PreviewSymbol,PERIOD_M1,0,5000,probe)!=5000)
   {
      LogPreview("FAIL: custom fixture has fewer than 5000 available M1 bars.");
      if(PreviewLog!=INVALID_HANDLE) FileClose(PreviewLog);
      return;
   }
   PreviewOne(0,"ChartArt Bollinger + RSI","ChartArt BB+RSI (closed conditions)","CA_BBR_","suite_bb.png");
   if(!IsStopped()) PreviewOne(1,"SMA Ribbon 10","SMA Ribbon 10 (TV)","","suite_sma.png");
   if(!IsStopped()) PreviewOne(2,"EMA 20 / 50 / 100 / 200","EMA 4 (close)","","suite_ema.png");
   if(!IsStopped()) PreviewOne(3,"Volume Profile (repeated source weights)","Volume Profile (source weights)","VP_","suite_vp.png");
   for(int i=0;i<ArraySize(OwnedCharts);i++) if(OwnedCharts[i]>0) CloseOwnedChart(OwnedCharts[i]);
   CleanNewHostObjects();
   LogPreview(StringFormat("DONE elapsed_ms=%I64u host_objects=%d manual_visual_QA_required=1",GetTickCount64()-PreviewStarted,ObjectsTotal(0,-1,-1)));
   if(PreviewLog!=INVALID_HANDLE) {FileClose(PreviewLog); PreviewLog=INVALID_HANDLE;}
}
