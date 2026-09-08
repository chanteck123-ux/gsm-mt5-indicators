"""Independent Python full-window reference, fixtures and native MT5 harness.

The Python oracle uses statistics.pstdev and math.fsum, independent of the MQL5
compensated-window implementation. Explicit hand answers test strict cutoff,
invalid values and the current-volume cap. No terminal is started here.
"""
from pathlib import Path
from datetime import datetime, timezone
import csv
import hashlib
import json
import math
import statistics

base = Path(__file__).resolve().parent
fixtures = base / "fixtures"
fixtures.mkdir(parents=True, exist_ok=True)
production = base.parents[1] / "outputs/GSM_ATR_VFI/MQL5/Indicators/GSM/Volume_Flow_Indicator_MT5.mq5"
text = production.read_text(encoding="utf-8-sig")
helper = text[text.index("// VFI_HELPERS_BEGIN"):text.index("// VFI_HELPERS_END") + len("// VFI_HELPERS_END")]
source_sha = hashlib.sha256(production.read_bytes()).hexdigest()
helper_sha = hashlib.sha256(helper.encode()).hexdigest()
START = int(datetime(2026, 8, 3, tzinfo=timezone.utc).timestamp())

def dataset(n, kind="wave"):
    rows=[]
    prior=2300.0
    for i in range(n):
        close=round(2300+8*math.sin(i*.11)+2*math.sin(i*.43)+i*.025,5)
        row=[START+60*i,prior,round(max(prior,close)+.27+(i%4)*.06,5),round(min(prior,close)-.26-(i%3)*.07,5),close,100+i%37,20+i%13]
        if kind=="flat":row[1:5]=[100.0]*4;row[5]=100
        if kind=="zero_tick":row[5]=0
        if kind=="zero_real":row[6]=0
        if kind=="gap" and 65<=i<90:row[5]=0
        if kind=="cap":
            price=100+i*.5;row[1:5]=[price]*4;row[5]=1000 if i==50 else 100
        if kind=="future" and i>=160:
            price=2000+(i-160)*2;row[1:5]=[price,price+1,price-1,price];row[5]=500+i%51;row[6]=100+i%21
        rows.append(row);prior=close
    return rows

def reference(rows, length, coef, vcoef, signal, smooth, mode):
    n=len(rows);out=[[None]*10 for _ in rows]
    typical=[(r[2]+r[3]+r[4])/3 for r in rows]
    volume=[float(r[5 if mode==0 else 6]) for r in rows]
    def mean(xs):return math.fsum(xs)/len(xs)
    def complete(xs):return all(x is not None and math.isfinite(x) for x in xs)
    ema_state=None
    for i in range(n):
        if i>0 and typical[i]>0 and typical[i-1]>0:
            out[i][8]=math.log(typical[i])-math.log(typical[i-1])
        changes=[out[j][8] for j in range(max(0,i-29),i+1)]
        if len(changes)==30 and complete(changes):
            out[i][9]=statistics.pstdev(changes)
            out[i][4]=coef*out[i][9]*rows[i][4]
        if i>=length:
            out[i][5]=mean(volume[i-length:i])
            out[i][6]=min(volume[i],out[i][5]*vcoef)
        if i>0 and out[i][4] is not None and out[i][6] is not None:
            move=typical[i]-typical[i-1]
            out[i][3]=out[i][6] if move>out[i][4] else -out[i][6] if move< -out[i][4] else 0.0
        flows=[out[j][3] for j in range(max(0,i-length+1),i+1)]
        if out[i][5] is not None and out[i][5]>0 and len(flows)==length and complete(flows):
            out[i][7]=math.fsum(flows)/out[i][5]
        raw=[out[j][7] for j in range(max(0,i-2),i+1)]
        out[i][0]=mean(raw) if smooth and len(raw)==3 and complete(raw) else None if smooth else out[i][7]
        if out[i][0] is not None:
            alpha=2/(signal+1)
            out[i][1]=out[i][0] if ema_state is None else alpha*out[i][0]+(1-alpha)*ema_state
            ema_state=out[i][1]
            out[i][2]=out[i][0]-out[i][1]
    return out

cases=[
    ("default_tick",520,130,.2,2.5,5,False,0,"wave"),
    ("smooth_tick",520,130,.2,2.5,5,True,0,"wave"),
    ("real_volume",320,30,.2,2.5,5,False,1,"wave"),
    ("real_zero_no_fallback",120,20,.2,2.5,5,False,1,"zero_real"),
    ("flat_valid_zero",100,7,.2,2.5,5,False,0,"flat"),
    ("zero_tick",100,7,.2,2.5,5,False,0,"zero_tick"),
    ("length1_volume_cap",100,1,0.,2.5,1,False,0,"cap"),
    ("short_history",20,7,.2,2.5,5,False,0,"wave"),
    ("vcoef_zero",90,5,.2,0.,5,False,0,"wave"),
    ("future_base",240,20,.2,2.5,5,False,0,"wave"),
    ("future_changed",240,20,.2,2.5,5,False,0,"future"),
    ("prefix_160",160,20,.2,2.5,5,False,0,"wave"),
    ("volume_gap_resume",180,7,.2,2.5,5,False,0,"gap"),
]
meta=[]
for name,n,length,coef,vcoef,signal,smooth,mode,kind in cases:
    rows=dataset(n,kind);expected=reference(rows,length,coef,vcoef,signal,smooth,mode)
    path=fixtures/(name+".csv")
    with path.open("w",newline="",encoding="ascii") as f:
        w=csv.writer(f);w.writerow(["time","open","high","low","close","tick_volume","real_volume"]+[f"buffer{k}" for k in range(10)])
        for row,values in zip(rows,expected):w.writerow(row+["EMPTY" if v is None else format(v,".17g") for v in values])
    first=[next((i for i in range(n) if expected[i][k] is not None),None) for k in range(10)]
    meta.append(dict(name=name,bars=n,length=length,coef=coef,vcoef=vcoef,signal=signal,smooth=smooth,volume_mode=mode,first_valid_old_index=first,fixture_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    if name=="length1_volume_cap":
        assert expected[50][5]==100 and expected[50][6]==250 and expected[50][3]==250
        assert expected[50][0]==2.5 and expected[50][1]==2.5 and expected[50][2]==0
    if name=="flat_valid_zero":assert all(v==0 for values in expected[36:] for v in values[:3])
    if name in ("zero_tick","real_zero_no_fallback","short_history"):assert all(values[0] is None for values in expected)

calls="\n".join(f'   RunCase("{name}",{n},{length},{coef:.17g},{vcoef:.17g},{signal},{str(smooth).lower()},{mode},{idx});'
                 for idx,(name,n,length,coef,vcoef,signal,smooth,mode,kind) in enumerate(cases))
harness=(base/"vfi_native_harness.mqh").read_text(encoding="utf-8")
harness=harness.replace("// INSERT_CASE_CALLS",calls)
script=base/"VFI_Validation.mq5"
script.write_text('#property strict\n#property script_show_inputs\n#property version "1.00"\n'
                  +f'const string SOURCE_SHA256="{source_sha}";\nconst string HELPER_SHA256="{helper_sha}";\n'
                  +helper+'\n'+harness,encoding="utf-8")
(base/"vfi_reference_manifest.json").write_text(json.dumps(dict(source_sha256=source_sha,helper_sha256=helper_sha,oracle="Python math.fsum and statistics.pstdev; explicit cap/zero hand assertions",cases=meta),ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"Generated {len(cases)} fixture/oracle CSVs, {script}; production SHA256={source_sha}")
