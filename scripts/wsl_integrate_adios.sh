#!/bin/bash
set -euo pipefail
SRC=/home/axymorrsen/op13-kernel/src
P=/home/axymorrsen/op13-kernel/patches/adios/patches/stable/0001-linux6.12.44-ADIOS-3.2.0.patch
LOGDIR=/home/axymorrsen/op13-kernel/logs
cd "$SRC"

echo "=== Extract block/adios.c ==="
python3 - <<'PY'
from pathlib import Path
p = Path("/home/axymorrsen/op13-kernel/patches/adios/patches/stable/0001-linux6.12.44-ADIOS-3.2.0.patch")
text = p.read_text(errors="replace")
start = text.find("diff --git a/block/adios.c")
if start < 0:
    raise SystemExit("adios.c not in patch")
end = text.find("diff --git", start + 10)
chunk = text[start: end if end > 0 else None]
out = []
for line in chunk.splitlines():
    if line.startswith(("diff ", "index ", "---", "+++", "new file", "@@")):
        continue
    if line.startswith("+"):
        out.append(line[1:])
    elif line.startswith("\\"):
        continue
    # context lines with space shouldn't appear in /dev/null new file
Path("block/adios.c").write_text("\n".join(out) + "\n")
print("wrote block/adios.c lines", len(out), "bytes", Path("block/adios.c").stat().st_size)
# basic sanity
t = Path("block/adios.c").read_text()
for must in ["adios", "elevator", "blk-mq", "MODULE_"]:
    print("contains", must, must.lower() in t.lower() or must in t)
PY

echo "=== Kconfig.iosched ==="
python3 - <<'PY'
from pathlib import Path
p = Path("block/Kconfig.iosched")
t = p.read_text()
if "MQ_IOSCHED_ADIOS" in t:
    print("already has ADIOS kconfig")
else:
    block = '''
config MQ_IOSCHED_ADIOS
	tristate "Adaptive Deadline I/O scheduler"
	default y
	help
	  ADIOS (Adaptive Deadline I/O Scheduler) is a blk-mq I/O scheduler
	  that combines deadline scheduling with adaptive latency control.
	  Say Y for mobile latency-sensitive storage workloads.

'''
    idx = t.find("config IOSCHED_BFQ")
    if idx >= 0:
        p.write_text(t[:idx] + block + t[idx:])
        print("inserted before BFQ")
    else:
        p.write_text(t + block)
        print("appended kconfig")
print(p.read_text())
PY

echo "=== Makefile ==="
if ! grep -q 'adios.o' block/Makefile; then
  printf 'obj-$(CONFIG_MQ_IOSCHED_ADIOS)\t+= adios.o\n' >> block/Makefile
  echo "appended adios.o"
else
  echo "makefile already has adios"
fi
grep -n adios block/Makefile

echo "=== elevator.c references ==="
grep -n "elevator_get_default\|kyber\|mq-deadline\|adios" block/elevator.c | head -40

echo "=== try compile adios.o alone later ==="
ls -la block/adios.c block/Kconfig.iosched
