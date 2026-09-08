// Volume Flow Indicator [LazyBear] - native MT5 adaptation.
// Original supplied Pine source: @author LazyBear.
// Formula source is reference material, not authorization to contact its author.
// No trading, account, DLL, notification or external-service API calls.
#property strict
#property version "1.00"
#property description "LazyBear VFI：典型价格、波动过滤、截量资金流与 EMA 信号。"
#property description "默认使用 Tick Volume；与 TradingView 数据源成交量不保证一致。"
#property indicator_separate_window
#property indicator_buffers 13
#property indicator_plots 10
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_type3 DRAW_NONE
#property indicator_color1 clrGreen
#property indicator_color2 clrOrange
#property indicator_color3 clrGray
#property indicator_width1 2
#property indicator_width2 1
#property indicator_width3 3

enum VFIVolumeMode { VFI_TICK_VOLUME=0, VFI_REAL_VOLUME=1 };
input int VFILength=130;                  // VFI 长度（1～1000000）
input double Coefficient=0.2;             // 波动过滤系数（非负）
input double MaxVolumeCoefficient=2.5;    // 最大成交量倍数（非负）
input int SignalLength=5;                 // EMA 信号周期（1～1000000）
input bool SmoothVFI=false;               // VFI 额外使用 SMA(3)
input VFIVolumeMode VolumeMode=VFI_TICK_VOLUME; // 成交量：默认 Tick；Real 不自动回退
input bool ShowVFILine=true;              // 显示 VFI 线（不改变缓冲区）
input bool ShowSignalLine=true;           // 显示 EMA 信号线（不改变缓冲区）
input bool ShowHistogram=false;           // 显示 VFI-EMA 柱（原版默认关闭）
input color VFIColor=clrGreen;            // VFI 颜色
input color SignalColor=clrOrange;        // EMA 信号颜色
input color HistogramColor=clrGray;       // 差值柱颜色

double VFI[],Signal[],Histogram[],Flow[],Cutoff[],PriorVolume[],CappedVolume[],RawVFI[],LogReturn[],Volatility[];
double Typical[],SelectedVolume[],EMAState[];
datetime g_oldest=0;
ulong g_error_time=0;
int g_vfi_begin=0;

// VFI_HELPERS_BEGIN
bool VFIValid(const double value){return value!=EMPTY_VALUE && MathIsValidNumber(value);}
double VFITypical(const double high,const double low,const double close)
  {
   if(!VFIValid(high)||!VFIValid(low)||!VFIValid(close))return EMPTY_VALUE;
   double value=(high+low+close)/3.0;
   return VFIValid(value)&&value>0?value:EMPTY_VALUE;
  }
double VFISignedFlow(const double movement,const double cutoff,const double capped_volume)
  {
   if(!VFIValid(movement)||!VFIValid(cutoff)||!VFIValid(capped_volume)||capped_volume<0)return EMPTY_VALUE;
   if(movement>cutoff)return capped_volume;
   if(movement< -cutoff)return -capped_volume;
   return 0.0;
  }
// VFI_HELPERS_END

void Warn(const string message)
  {
   ulong now=GetTickCount64();
   if(g_error_time==0||now-g_error_time>=10000){Print("VFI：",message);g_error_time=now;}
  }
bool ValidInputs()
  {
   if(VFILength<1||VFILength>1000000||SignalLength<1||SignalLength>1000000)
     {Print("VFI 初始化失败：VFI 与 EMA 周期必须在 1～1000000 之间。");return false;}
   if(!VFIValid(Coefficient)||Coefficient<0||!VFIValid(MaxVolumeCoefficient)||MaxVolumeCoefficient<0)
     {Print("VFI 初始化失败：过滤与截量系数必须为有限非负数。");return false;}
   if(VolumeMode!=VFI_TICK_VOLUME&&VolumeMode!=VFI_REAL_VOLUME)
     {Print("VFI 初始化失败：成交量模式无效。");return false;}
   return true;
  }
void EmptyAt(const int i)
  {
   VFI[i]=EMPTY_VALUE;Signal[i]=EMPTY_VALUE;Histogram[i]=EMPTY_VALUE;Flow[i]=EMPTY_VALUE;Cutoff[i]=EMPTY_VALUE;
   PriorVolume[i]=EMPTY_VALUE;CappedVolume[i]=EMPTY_VALUE;RawVFI[i]=EMPTY_VALUE;LogReturn[i]=EMPTY_VALUE;Volatility[i]=EMPTY_VALUE;
  }
bool SumWindow(const double &values[],const int from,const int length,double &sum)
  {
   sum=0;
   if(from<0||length<1||from>ArraySize(values)-length)return false;
   // Compensated summation keeps long volume/flow windows stable.
   double correction=0;
   for(int j=from;j<from+length;j++)
     {
      if(!VFIValid(values[j]))return false;
      double adjusted=values[j]-correction;
      double next=sum+adjusted;
      correction=(next-sum)-adjusted;sum=next;
     }
   return VFIValid(sum);
  }
int OnInit()
  {
   if(!ValidInputs())return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,VFI,INDICATOR_DATA);SetIndexBuffer(1,Signal,INDICATOR_DATA);SetIndexBuffer(2,Histogram,INDICATOR_DATA);
   SetIndexBuffer(3,Flow,INDICATOR_DATA);SetIndexBuffer(4,Cutoff,INDICATOR_DATA);SetIndexBuffer(5,PriorVolume,INDICATOR_DATA);
   SetIndexBuffer(6,CappedVolume,INDICATOR_DATA);SetIndexBuffer(7,RawVFI,INDICATOR_DATA);SetIndexBuffer(8,LogReturn,INDICATOR_DATA);
   SetIndexBuffer(9,Volatility,INDICATOR_DATA);SetIndexBuffer(10,Typical,INDICATOR_CALCULATIONS);SetIndexBuffer(11,SelectedVolume,INDICATOR_CALCULATIONS);
   SetIndexBuffer(12,EMAState,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(VFI,false);ArraySetAsSeries(Signal,false);ArraySetAsSeries(Histogram,false);ArraySetAsSeries(Flow,false);
   ArraySetAsSeries(Cutoff,false);ArraySetAsSeries(PriorVolume,false);ArraySetAsSeries(CappedVolume,false);ArraySetAsSeries(RawVFI,false);
   ArraySetAsSeries(LogReturn,false);ArraySetAsSeries(Volatility,false);ArraySetAsSeries(Typical,false);ArraySetAsSeries(SelectedVolume,false);ArraySetAsSeries(EMAState,false);
   string labels[10]={"VFI","EMA of VFI","VFI minus EMA","SignedFlow","PriceCutoff","PriorAverageVolume","CappedVolume","UnsmoothedVFI","LogReturn","PopulationVolatility30"};
   for(int k=0;k<10;k++)
     {
      PlotIndexSetString(k,PLOT_LABEL,labels[k]);PlotIndexSetDouble(k,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(k,PLOT_DRAW_TYPE,DRAW_NONE);PlotIndexSetInteger(k,PLOT_SHOW_DATA,k<3);
     }
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,ShowVFILine?DRAW_LINE:DRAW_NONE);
   PlotIndexSetInteger(1,PLOT_DRAW_TYPE,ShowSignalLine?DRAW_LINE:DRAW_NONE);
   PlotIndexSetInteger(2,PLOT_DRAW_TYPE,ShowHistogram?DRAW_HISTOGRAM:DRAW_NONE);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,VFIColor);PlotIndexSetInteger(1,PLOT_LINE_COLOR,SignalColor);PlotIndexSetInteger(2,PLOT_LINE_COLOR,HistogramColor);
   int raw_begin=MathMax(VFILength,30)+VFILength-1;
   g_vfi_begin=raw_begin+(SmoothVFI?2:0);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,g_vfi_begin);PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,g_vfi_begin);PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,g_vfi_begin);
   IndicatorSetInteger(INDICATOR_LEVELS,1);IndicatorSetDouble(INDICATOR_LEVELVALUE,0,0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR,0,clrGray);IndicatorSetInteger(INDICATOR_LEVELSTYLE,0,STYLE_DOT);
   IndicatorSetInteger(INDICATOR_DIGITS,4);
   string unit=VolumeMode==VFI_TICK_VOLUME?"Tick量":"Real量";
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("VFI [LazyBear] MT5 (%d, EMA%d, %s%s)",VFILength,SignalLength,unit,SmoothVFI?", SMA3":""));
   PrintFormat("VFI_INIT | symbol=%s tf=%s length=%d coef=%.8g vcoef=%.8g signal=%d smooth=%s volume=%s first_VFI_index=%d",
      _Symbol,EnumToString(_Period),VFILength,Coefficient,MaxVolumeCoefficient,SignalLength,SmoothVFI?"true":"false",unit,g_vfi_begin);
   return INIT_SUCCEEDED;
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<1)return 0;
   ArraySetAsSeries(time,false);ArraySetAsSeries(high,false);ArraySetAsSeries(low,false);ArraySetAsSeries(close,false);
   ArraySetAsSeries(tick_volume,false);ArraySetAsSeries(volume,false);
   bool rebuild=prev_calculated<=0||prev_calculated>rates_total||(g_oldest!=0&&g_oldest!=time[0]);
   int start=rebuild?0:MathMax(0,prev_calculated-1);
   double alpha=2.0/(SignalLength+1.0);
   for(int i=start;i<rates_total;i++)
     {
      EmptyAt(i);
      EMAState[i]=i>0?EMAState[i-1]:EMPTY_VALUE;
      Typical[i]=VFITypical(high[i],low[i],close[i]);
      long raw_volume=VolumeMode==VFI_TICK_VOLUME?tick_volume[i]:volume[i];
      SelectedVolume[i]=raw_volume>=0?(double)raw_volume:EMPTY_VALUE;
      if(i>=1&&VFIValid(Typical[i])&&VFIValid(Typical[i-1]))
        {
         double value=MathLog(Typical[i])-MathLog(Typical[i-1]);
         if(VFIValid(value))LogReturn[i]=value;
        }
      double summed=0;
      if(i>=30&&SumWindow(LogReturn,i-29,30,summed))
        {
         double average=summed/30.0,variance=0;
         for(int j=i-29;j<=i;j++){double delta=LogReturn[j]-average;variance+=delta*delta;}
         double deviation=MathSqrt(variance/30.0);
         if(VFIValid(deviation))
           {
            Volatility[i]=deviation;
            double cutoff=Coefficient*deviation*close[i];
            if(VFIValid(cutoff))Cutoff[i]=cutoff;
           }
        }
      if(i>=VFILength&&SumWindow(SelectedVolume,i-VFILength,VFILength,summed))
        {
         double average=summed/VFILength;
         if(VFIValid(average)&&average>=0)
           {
            PriorVolume[i]=average;
            double cap=average*MaxVolumeCoefficient;
            if(VFIValid(cap)&&cap>=0&&VFIValid(SelectedVolume[i]))CappedVolume[i]=MathMin(SelectedVolume[i],cap);
           }
        }
      if(i>=1&&VFIValid(Typical[i])&&VFIValid(Typical[i-1]))
         Flow[i]=VFISignedFlow(Typical[i]-Typical[i-1],Cutoff[i],CappedVolume[i]);
      if(VFIValid(PriorVolume[i])&&PriorVolume[i]>0&&i>=VFILength-1&&SumWindow(Flow,i-VFILength+1,VFILength,summed))
        {
         double raw=summed/PriorVolume[i];
         if(VFIValid(raw))RawVFI[i]=raw;
        }
      if(SmoothVFI)
        {
         if(i>=2&&SumWindow(RawVFI,i-2,3,summed))VFI[i]=summed/3.0;
        }
      else VFI[i]=RawVFI[i];
      if(VFIValid(VFI[i]))
        {
         // Seed from the first valid VFI. Retain only the internal EMA state
         // across unavailable VFI values; public signal/histogram remain EMPTY.
         double ema=VFIValid(EMAState[i])?alpha*VFI[i]+(1.0-alpha)*EMAState[i]:VFI[i];
         if(VFIValid(ema))
           {
            EMAState[i]=ema;Signal[i]=ema;double difference=VFI[i]-ema;
            if(VFIValid(difference))Histogram[i]=difference;
           }
        }
     }
   g_oldest=time[0];
   if(rates_total>g_vfi_begin&&PriorVolume[rates_total-1]==0)
      Warn(VolumeMode==VFI_REAL_VOLUME?"当前 Real Volume 均量为 0，VFI 暂不可用；没有切换为 Tick Volume。":"当前 Tick Volume 均量为 0，VFI 暂不可用。");
   return rates_total;
  }
