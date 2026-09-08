"""Create an instrumented *test-only* copy of the actual production indicator.

No production file is modified. API wrappers proxy the real built-ins except for
two explicit injected return-count modes. The outer event wrapper records the
production g_processed_time after both failure and success paths.
"""
from pathlib import Path
import hashlib
import json

base = Path(__file__).resolve().parent
source = base.parents[1] / "outputs/GSM_ADX_Trend_Meter/MQL5/Indicators/GSM/GSM_ADX_Trend_Meter.mq5"
raw = source.read_bytes()
text = raw.decode("utf-8-sig")
source_sha = hashlib.sha256(raw).hexdigest()
replacements = [
    ("BarsCalculated(g_handle)", "GSMFaultBarsCalculated(g_handle)"),
    ("int n0=CopyBuffer(g_handle,0,0,requested,T0);", "int n0=GSMFaultCopyBuffer(g_handle,0,0,requested,T0);"),
    ("int n1=CopyBuffer(g_handle,1,0,requested,T1);", "int n1=GSMFaultCopyBuffer(g_handle,1,0,requested,T1);"),
    ("int n2=CopyBuffer(g_handle,2,0,requested,T2);", "int n2=GSMFaultCopyBuffer(g_handle,2,0,requested,T2);"),
    ("int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],", "int GSMProductionOnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],"),
]
for old, new in replacements:
    assert text.count(old) == 1, (old, text.count(old))
    text = text.replace(old, new)

wrapper = r'''
// GSM_TEST_ONLY_INJECTION_BEGIN
// This file is ONLY an engineering fault-return harness, never the user indicator.
// Mode 1: real CopyBuffer third line runs, then reports one fewer copied item.
// Mode 2: real BarsCalculated runs, then reports zero calculated bars.
// Mode 0: API calls are unmodified proxies. No data or event formulas are replaced.
string GSMFaultKey(const string name) { return "GAF_"+_Symbol+"_"+name; }
int GSMFaultMode()
  {
   if(StringFind(_Symbol,"GAF_")!=0) return 0;
   return (int)GlobalVariableGet(GSMFaultKey("MODE"));
  }
void GSMFaultSet(const string name,const double value) { GlobalVariableSet(GSMFaultKey(name),value); }
int GSMFaultBarsCalculated(const int handle)
  {
   int real_count=BarsCalculated(handle);
   GSMFaultSet("REAL_BARS",real_count);
   if(GSMFaultMode()==2)
     {
      GSMFaultSet("HIT_MODE",2);
      GSMFaultSet("HITS",GlobalVariableGet(GSMFaultKey("HITS"))+1);
      return 0;
     }
   return real_count;
  }
int GSMFaultCopyBuffer(const int handle,const int line,const int start,const int count,double &target[])
  {
   int copied=CopyBuffer(handle,line,start,count,target);
   GSMFaultSet("REQUEST",count);
   GSMFaultSet("REAL_N"+IntegerToString(line),copied);
   if(GSMFaultMode()==1 && line==2 && copied>0)
     {
      GSMFaultSet("HIT_MODE",1);
      GSMFaultSet("HITS",GlobalVariableGet(GSMFaultKey("HITS"))+1);
      GSMFaultSet("REPORTED_N2",copied-1);
      return copied-1;
     }
   if(line==2) GSMFaultSet("REPORTED_N2",copied);
   return copied;
  }
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   int result=GSMProductionOnCalculate(rates_total,prev_calculated,time,open,high,low,close,tick_volume,volume,spread);
   GSMFaultSet("CALLS",GlobalVariableGet(GSMFaultKey("CALLS"))+1);
   GSMFaultSet("PROCESSED",(double)g_processed_time);
   GSMFaultSet("CURRENT",(double)time[0]);
   GSMFaultSet("CLOSED",rates_total>1?(double)time[1]:0);
   GSMFaultSet("TOTAL",rates_total);
   GSMFaultSet("PREV",prev_calculated);
   GSMFaultSet("RETURN",result);
   GSMFaultSet("NEED_REBUILD",g_need_rebuild?1:0);
   GSMFaultSet("DATA_READY",g_data_ready?1:0);
   GSMFaultSet("SILENT_BASELINE",g_silent_baseline?1:0);
   return result;
  }
// GSM_TEST_ONLY_INJECTION_END
'''
variant = base / "GSM_ADX_FaultInjected.mq5"
variant.write_text(f'// TEST ONLY. Original production SHA256={source_sha}\n' + text + '\n' + wrapper, encoding="utf-8")
harness = (base / "adx_fault_harness.mqh").read_text(encoding="utf-8")
script = base / "GSM_ADX_Fault_Test.mq5"
script.write_text('#property strict\n#property script_show_inputs\n#property version "1.00"\n'
                  + f'const string PRODUCTION_SOURCE_SHA256="{source_sha}";\n' + harness, encoding="utf-8")
metadata = {
    "production_path": str(source),
    "production_sha256": source_sha,
    "test_variant_sha256": hashlib.sha256(variant.read_bytes()).hexdigest(),
    "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
    "production_modified": False,
    "replacement_count": len(replacements),
    "replacements": [{"old": a, "new": b} for a, b in replacements],
    "appended_block": "GSM_TEST_ONLY_INJECTION_BEGIN/END: two API proxy wrappers and outer OnCalculate diagnostics",
    "scope": "Controlled API return-count simulation, not a real network disconnect or native API failure",
}
(base / "adx_fault_transformation.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False, indent=2))
