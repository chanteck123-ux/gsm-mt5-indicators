#property strict

void OnStart()
  {
   int handle=iCustom(_Symbol,_Period,"GSM\\GSM_ADX_Trend_Meter");
   if(handle==INVALID_HANDLE)
     { PrintFormat("创建 GSM ADX 失败，错误 %d",GetLastError()); return; }

   if(BarsCalculated(handle)<2)
     { Print("GSM ADX 数据准备中，请等待后重试。"); IndicatorRelease(handle); return; }

   datetime before=iTime(_Symbol,_Period,1);
   if(before<=0)
     { Print("信号 K 线时间未准备好。"); IndicatorRelease(handle); return; }

   double adx[1],market[1],bull[1],bear[1];
   int n0=CopyBuffer(handle,0,1,1,adx);
   int n3=CopyBuffer(handle,3,1,1,market);
   int n8=CopyBuffer(handle,8,1,1,bull);
   int n9=CopyBuffer(handle,9,1,1,bear);
   if(n0!=1 || n3!=1 || n8!=1 || n9!=1)
     { Print("GSM ADX 复制数量不足，等待后重试。"); IndicatorRelease(handle); return; }

   if(adx[0]==EMPTY_VALUE || market[0]==EMPTY_VALUE || bull[0]==EMPTY_VALUE || bear[0]==EMPTY_VALUE ||
      !MathIsValidNumber(adx[0]) || !MathIsValidNumber(market[0]) ||
      !MathIsValidNumber(bull[0]) || !MathIsValidNumber(bear[0]))
     { Print("GSM ADX 预热／回看不足或数据暂不可用。"); IndicatorRelease(handle); return; }

   datetime signal_bar=iTime(_Symbol,_Period,1);
   if(signal_bar<=0 || signal_bar!=before)
     { Print("读取期间发生换柱，请重新获取同一批数据。"); IndicatorRelease(handle); return; }
   PrintFormat("%s %s，收盘K线=%s，ADX=%.2f，环境=%.0f，偏多事件=%.0f，偏空事件=%.0f",
      _Symbol,EnumToString(_Period),TimeToString(signal_bar,TIME_DATE|TIME_MINUTES),
      adx[0],market[0],bull[0],bear[0]);
   IndicatorRelease(handle);
  }
