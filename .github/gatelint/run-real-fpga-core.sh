#!/usr/bin/env bash
set -Eeuo pipefail

root=${1:?fixture root required}
work=${2:?work directory required}
yosys_data=$(yosys-config --datdir)

stage() {
  printf '%s\n' "$1" | tee "$work/current-stage.txt"
}
trap 'rc=$?; printf "failed stage: %s (exit %d)\n" "$(cat "$work/current-stage.txt" 2>/dev/null || echo unknown)" "$rc" > "$work/failure.txt"; exit "$rc"' ERR

stage vhdl-lowering
ghdl --synth --std=08 --out=verilog \
  "$root/rtl/vhdl_counter.vhd" -e vhdl_counter \
  > "$work/vhdl_counter.v" 2> "$work/ghdl.stderr"
grep -Eq '^[[:space:]]*module[[:space:]]+vhdl_counter' "$work/vhdl_counter.v"

stage behavioral-simulation
iverilog -g2012 -s tb -o "$work/behavioral.vvp" \
  "$work/vhdl_counter.v" \
  "$root/rtl/uart_challenge.sv" \
  "$root/rtl/top.v" \
  "$root/sim/tb.sv" \
  > "$work/behavioral-compile.stdout" 2> "$work/behavioral-compile.stderr"
vvp "$work/behavioral.vvp" \
  > "$work/behavioral.stdout" 2> "$work/behavioral.stderr"
grep -q GATELINT_SIM_PASS "$work/behavioral.stdout"

stage synthesis
cat > "$work/synth.ys" <<YOSYS
read_verilog -sv "$work/vhdl_counter.v" "$root/rtl/uart_challenge.sv" "$root/rtl/top.v"
hierarchy -check -top top
proc; flatten; opt; check -assert
write_verilog -noattr "$work/generic-synth.v"
design -reset
read_verilog -sv "$work/vhdl_counter.v" "$root/rtl/uart_challenge.sv" "$root/rtl/top.v"
synth_ice40 -device u -top top -json "$work/ice40-synth.json"
check -assert
stat -top top
YOSYS
yosys -s "$work/synth.ys" > "$work/yosys.stdout" 2> "$work/yosys.stderr"
test -s "$work/generic-synth.v"
test -s "$work/ice40-synth.json"

stage constraint-closure
python3 - "$work/ice40-synth.json" "$root/constraints/icebreaker.pcf" <<'PY'
import json, sys
netlist = json.load(open(sys.argv[1], encoding='utf-8'))
ports = set(netlist['modules']['top']['ports'])
pcf = {}
for raw in open(sys.argv[2], encoding='utf-8'):
    line = raw.split('#', 1)[0].strip()
    if not line:
        continue
    fields = line.split()
    if fields[0] != 'set_io':
        raise SystemExit(f'unsupported PCF command: {line}')
    positional = [x for x in fields[1:] if not x.startswith('-')]
    if len(positional) < 2:
        raise SystemExit(f'malformed PCF line: {line}')
    port, pin = positional[-2:]
    if port in pcf:
        raise SystemExit(f'duplicate PCF port: {port}')
    pcf[port] = pin
if ports != set(pcf):
    raise SystemExit(f'port/PCF mismatch: ports={sorted(ports)} pcf={sorted(pcf)}')
if len(set(pcf.values())) != len(pcf):
    raise SystemExit('duplicate physical pin')
expected = {'CLK': '35', 'RX': '6', 'TX': '9', 'LEDR_N': '11'}
if pcf != expected:
    raise SystemExit(f'unexpected iCEBreaker constraints: {pcf}')
PY

stage post-synthesis-simulation
iverilog -g2012 -DGATELINT_POST_SYNTH=1 -s tb \
  -o "$work/post-synth.vvp" \
  "$yosys_data/ice40/cells_sim.v" \
  "$work/generic-synth.v" \
  "$root/sim/tb.sv" \
  > "$work/post-synth-compile.stdout" 2> "$work/post-synth-compile.stderr"
vvp "$work/post-synth.vvp" \
  > "$work/post-synth.stdout" 2> "$work/post-synth.stderr"
grep -q GATELINT_SIM_PASS "$work/post-synth.stdout"

stage logical-equivalence
cat > "$work/equivalence.ys" <<YOSYS
read_verilog -sv "$work/vhdl_counter.v" "$root/rtl/uart_challenge.sv" "$root/rtl/top.v"
prep -top top
flatten
memory_map
opt -full
check -assert
equiv_opt -assert -map +/ice40/cells_sim.v synth_ice40 -device u -top top
YOSYS
yosys -s "$work/equivalence.ys" \
  > "$work/equivalence.stdout" 2> "$work/equivalence.stderr"

stage place-route-timing
nextpnr-ice40 --up5k --package sg48 \
  --json "$work/ice40-synth.json" \
  --pcf "$root/constraints/icebreaker.pcf" \
  --asc "$work/routed.asc" --freq 12 --seed 1 \
  > "$work/nextpnr.stdout" 2> "$work/nextpnr.stderr"
test -s "$work/routed.asc"
if grep -Eqi 'unconstrained[^[:alnum:]]*(io|port)' "$work/nextpnr.stdout" "$work/nextpnr.stderr"; then
  echo 'nextpnr reported unconstrained I/O' >&2
  exit 1
fi
python3 - "$work/nextpnr.stdout" "$work/nextpnr.stderr" <<'PY'
import re, sys
text = '\n'.join(open(p, encoding='utf-8', errors='replace').read() for p in sys.argv[1:])
matches = re.findall(r'Max frequency for clock[^:]*:\s*([0-9.]+)\s*MHz(?:\s*\((PASS|FAIL) at\s*([0-9.]+)\s*MHz\))?', text, re.I)
if not matches:
    raise SystemExit('nextpnr did not report a clock maximum')
for maximum, result, target in matches:
    if result.upper() == 'FAIL' or float(maximum) < 12.0:
        raise SystemExit(f'nextpnr timing failed: {maximum} MHz, {result} at {target} MHz')
PY

stage independent-timing
icetime -d up5k -P sg48 -p "$root/constraints/icebreaker.pcf" \
  -m -t -r "$work/icetime.txt" "$work/routed.asc" \
  > "$work/icetime.stdout" 2> "$work/icetime.stderr"
test -s "$work/icetime.txt"
python3 - "$work/icetime.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
match = re.search(r'Timing estimate:\s*([0-9.]+)\s*ns\s*\(([0-9.]+)\s*MHz\)', text, re.I)
if not match:
    raise SystemExit('no parseable IceTime timing estimate')
if float(match.group(2)) < 12.0:
    raise SystemExit(f'IceTime failed target: {match.group(2)} MHz')
PY

stage bitstream-roundtrip
icepack "$work/routed.asc" "$work/gatelint.bin"
iceunpack "$work/gatelint.bin" "$work/roundtrip.asc"
test -s "$work/gatelint.bin"
test -s "$work/roundtrip.asc"
sed -E '/^[[:space:]]*($|#|\.comment|\.sym)/d; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' \
  "$work/routed.asc" > "$work/routed.canonical.asc"
sed -E '/^[[:space:]]*($|#|\.comment|\.sym)/d; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' \
  "$work/roundtrip.asc" > "$work/roundtrip.canonical.asc"
cmp "$work/routed.canonical.asc" "$work/roundtrip.canonical.asc"

stage complete
rm -f "$work/failure.txt"
