// No-trading example: read the latest closed VFI values from the public API.
#property strict
#property script_show_inputs
#property version "1.00"
void OnStart()
  {
   int handle=iCustom(_Symbol,_Period,"GSM\\Volume_Flow_Indicator_MT5");
   if(handle==INVALID_HANDLE){PrintFormat("VFI 创建失败：%d",GetLastError());return;}
   double vfi[],signal[],histogram[];
   bool available=false;
   datetime bar_time=0;
   for(int attempt=0;attempt<30&&!IsStopped();attempt++)
     {
      datetime candidate_time=iTime(_Symbol,_Period,1);
      if(BarsCalculated(handle)>1&&CopyBuffer(handle,0,1,1,vfi)==1&&CopyBuffer(handle,1,1,1,signal)==1&&CopyBuffer(handle,2,1,1,histogram)==1)
        {
         available=candidate_time>0&&candidate_time==iTime(_Symbol,_Period,1)&&vfi[0]!=EMPTY_VALUE&&signal[0]!=EMPTY_VALUE&&histogram[0]!=EMPTY_VALUE&&
            MathIsValidNumber(vfi[0])&&MathIsValidNumber(signal[0])&&MathIsValidNumber(histogram[0]);
         if(available){bar_time=candidate_time;break;}
        }
      Sleep(100);
     }
   if(available)PrintFormat("VFI 已收盘数据 | %s %s | K线 %s | VFI %.8f | EMA %.8f | 差值 %.8f",
      _Symbol,EnumToString(_Period),TimeToString(bar_time,TIME_DATE|TIME_MINUTES),vfi[0],signal[0],histogram[0]);
   else Print("VFI 数据准备中或所需历史不足；本次不使用空值。有效值 0 不等于 EMPTY。");
   IndicatorRelease(handle);
  }
