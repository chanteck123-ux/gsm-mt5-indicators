"""Embed the exact production rule block in a native MT5 test script.

Expected answers are hand-written in adx_rules_harness.mqh, not obtained by
implementing a second copy of the production formulas.  The script additionally
checks causal prefix/replay equivalence over a fixed deterministic dataset.
"""
from pathlib import Path
import hashlib
import sys

base = Path(__file__).resolve().parent
source = Path(sys.argv[1]) if len(sys.argv) > 1 else base.parents[1] / "outputs/GSM_ADX_Trend_Meter/MQL5/Indicators/GSM/GSM_ADX_Trend_Meter.mq5"
text = source.read_text(encoding="utf-8-sig")
start = text.index("// GSM_RULES_BEGIN")
end = text.index("// GSM_RULES_END", start) + len("// GSM_RULES_END")
block = text[start:end]
digest = hashlib.sha256(block.encode("utf-8")).hexdigest()
harness = (base / "adx_rules_harness.mqh").read_text(encoding="utf-8")
output = base / "GSM_ADX_Rules_Test.mq5"
output.write_text(
    '// Generated test: exact production rule block followed by independent hand-authored assertions.\n'
    '#property strict\n#property script_show_inputs\n'
    '#property version "1.00"\n'
    + f'const string RULE_BLOCK_SHA256="{digest}";\n'
    + block + '\n\n' + harness,
    encoding="utf-8",
)
(base / "adx_rule_block_sha256.txt").write_text(digest + "\n", encoding="ascii")
print(f"Generated {output}\nProduction block SHA256={digest}")
