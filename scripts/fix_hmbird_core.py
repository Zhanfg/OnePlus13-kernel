#!/usr/bin/env python3
"""Fix incomplete HMBIRD (fengchi) integration in kernel/sched/core.c"""
from pathlib import Path

CORE = Path("/home/axymorrsen/op13-kernel/src/kernel/sched/core.c")
text = CORE.read_text()
orig = text
changes = []

# 1) scx_notify_sched_tick -> hmbird_notify_sched_tick
old = "scx_notify_sched_tick();"
new = """#ifdef CONFIG_HMBIRD_SCHED
\thmbird_notify_sched_tick();
#endif"""
if old in text:
    text = text.replace(old, new, 1)
    changes.append("scx_notify_sched_tick -> hmbird_notify_sched_tick")
else:
    changes.append("SKIP scx_notify (already fixed or missing)")

# 2) scx_switched_all load balance guard -> hmbird_enabled
old2 = """#ifdef CONFIG_SMP
\tif (!scx_switched_all()) {
\t\trq->idle_balance = idle_cpu(cpu);
\t\ttrigger_load_balance(rq);
\t}
#endif"""
# tolerate mixed whitespace
import re
pat2 = re.compile(
    r"#ifdef CONFIG_SMP\s*\n"
    r"\s*if \(!scx_switched_all\(\)\) \{\s*\n"
    r"\s*rq->idle_balance = idle_cpu\(cpu\);\s*\n"
    r"\s*trigger_load_balance\(rq\);\s*\n"
    r"\s*\}\s*\n"
    r"#endif",
    re.M,
)
new2 = """#ifdef CONFIG_SMP
#ifdef CONFIG_HMBIRD_SCHED
\tif (!hmbird_enabled()) {
#endif
\t\trq->idle_balance = idle_cpu(cpu);
\t\ttrigger_load_balance(rq);
#ifdef CONFIG_HMBIRD_SCHED
\t}
#endif
#endif"""
m = pat2.search(text)
if m:
    text = pat2.sub(new2, text, count=1)
    changes.append("scx_switched_all -> hmbird_enabled")
else:
    # looser fallback: just replace call
    if "scx_switched_all()" in text:
        text = text.replace("scx_switched_all()", "hmbird_enabled()", 1)
        changes.append("scx_switched_all simple replace")
    else:
        changes.append("SKIP scx_switched_all")

# 3) __setscheduler_prio: task_on_scx -> proper hmbird logic
# Replace the broken partial HMBIRD block
old3_patterns = [
    # broken partial application currently in tree
    re.compile(
        r"void __setscheduler_prio\(struct task_struct \*p, int prio\)\s*\{\s*"
        r"/\*\s*"
        r"\s*\* After switching all rt and fair class to ext,.*?"
        r"\s*\*/\s*"
        r"if \(p->sched_class == &stop_sched_class\)\s*"
        r";\s*/\*\s*do nothing\s*\*/\s*"
        r"else if \(dl_prio\(prio\)\)\s*"
        r"p->sched_class = &dl_sched_class;\s*"
        r"#ifdef CONFIG_HMBIRD_SCHED\s*"
        r"else if \(task_on_scx\(p\)\)\s*"
        r"p->sched_class = &hmbird_sched_class;\s*"
        r"#endif\s*"
        r"else if \(rt_prio\(prio\)\)\s*"
        r"p->sched_class = &rt_sched_class;\s*"
        r"else\s*"
        r"p->sched_class = &fair_sched_class;\s*"
        r"p->prio = prio;\s*"
        r"trace_android_rvh_setscheduler_prio\(p\);\s*"
        r"\}",
        re.S,
    ),
]
new3 = """void __setscheduler_prio(struct task_struct *p, int prio)
{
#ifdef CONFIG_HMBIRD_SCHED
\tbool on_hmbird = task_on_hmbird(p);

\tif (p->sched_class == &stop_sched_class)
\t\t;
\telse if (dl_prio(prio))
\t\tp->sched_class = &dl_sched_class;
\telse if (rt_prio(prio) && on_hmbird)
\t\tp->sched_class = &hmbird_sched_class;
\telse if (rt_prio(prio))
\t\tp->sched_class = &rt_sched_class;
\telse if (on_hmbird)
\t\tp->sched_class = &hmbird_sched_class;
\telse
\t\tp->sched_class = &fair_sched_class;
#else
\tif (dl_prio(prio))
\t\tp->sched_class = &dl_sched_class;
\telse if (rt_prio(prio))
\t\tp->sched_class = &rt_sched_class;
\telse
\t\tp->sched_class = &fair_sched_class;
#endif

\tp->prio = prio;
\ttrace_android_rvh_setscheduler_prio(p);
}"""
fixed3 = False
for pat in old3_patterns:
    if pat.search(text):
        text = pat.sub(new3, text, count=1)
        changes.append("fixed __setscheduler_prio")
        fixed3 = True
        break
if not fixed3:
    if "task_on_scx(p)" in text:
        text = text.replace("task_on_scx(p)", "task_on_hmbird(p)")
        changes.append("task_on_scx -> task_on_hmbird (simple)")
    else:
        changes.append("SKIP setscheduler_prio")

# 4) Add missing cgroup hmbird deadline helpers before the cftype entry
deadline_funcs = r'''
#ifdef CONFIG_HMBIRD_SCHED
static inline void update_cgroup_ids_table_core(int ids, u8 hmbird_cgroup_deadline_idx)
{
	if (ids < 0 || ids >= NUMS_CGROUP_KINDS) {
		pr_err("update_cgroup_ids_tab idx err!\n");
		return;
	}
	cgroup_ids_table[ids] = hmbird_cgroup_deadline_idx;
}

static int cgroup_write_hmbird_deadline(struct cgroup_subsys_state *css,
					struct cftype *cftype, u64 dl)
{
	int i;

	for (i = MIN_CGROUP_DL_IDX; i < MAX_GLOBAL_DSQS; ++i) {
		if (dl < HMBIRD_BPF_DSQS_DEADLINE[i])
			break;
	}

	i = max_t(int, i - 1, MIN_CGROUP_DL_IDX);
	if (!css || !css->cgroup || !css->cgroup->kn)
		return 0;
	update_cgroup_ids_table_core(css->cgroup->kn->id, i);

	return 0;
}

static u64 cgroup_read_hmbird_deadline(struct cgroup_subsys_state *css,
				       struct cftype *cft)
{
	u8 i;

	if (!css || !css->cgroup || !css->cgroup->kn)
		return (u64)HMBIRD_BPF_DSQS_DEADLINE[DEFAULT_CGROUP_DL_IDX];
	i = min_t(u8, cgroup_ids_table[css->cgroup->kn->id], MAX_GLOBAL_DSQS - 1);
	if ((int)i < 0) {
		pr_err("hmbird deadline idx invalid, name is %s\n",
		       css->cgroup->kn->name);
		i = DEFAULT_CGROUP_DL_IDX;
	}

	return (u64)HMBIRD_BPF_DSQS_DEADLINE[i];
}
#endif

'''

marker = """#ifdef CONFIG_HMBIRD_SCHED
{
.name = \"hmbird.deadline\",
.read_u64 = cgroup_read_hmbird_deadline,
.write_u64 = cgroup_write_hmbird_deadline,
},
#endif"""

# flexible whitespace match for marker
pat_marker = re.compile(
    r"#ifdef CONFIG_HMBIRD_SCHED\s*\n"
    r"\s*\{\s*\n"
    r'\s*\.name\s*=\s*"hmbird\.deadline",\s*\n'
    r"\s*\.read_u64\s*=\s*cgroup_read_hmbird_deadline,\s*\n"
    r"\s*\.write_u64\s*=\s*cgroup_write_hmbird_deadline,\s*\n"
    r"\s*\},\s*\n"
    r"#endif",
    re.M,
)

if "cgroup_write_hmbird_deadline" in text and "static int cgroup_write_hmbird_deadline" not in text:
    m = pat_marker.search(text)
    if m:
        text = text[: m.start()] + deadline_funcs + text[m.start() :]
        changes.append("inserted cgroup_read/write_hmbird_deadline")
    else:
        # insert before first hmbird.deadline occurrence
        idx = text.find('name = "hmbird.deadline"')
        if idx > 0:
            # walk back to #ifdef
            ifd = text.rfind("#ifdef CONFIG_HMBIRD_SCHED", 0, idx)
            if ifd > 0:
                text = text[:ifd] + deadline_funcs + text[ifd:]
                changes.append("inserted deadline funcs (fallback)")
            else:
                changes.append("FAIL insert deadline funcs")
        else:
            changes.append("FAIL no hmbird.deadline marker")
else:
    if "static int cgroup_write_hmbird_deadline" in text:
        changes.append("deadline funcs already present")
    else:
        changes.append("SKIP deadline (no cftype entry?)")

# Ensure linux/sched/hmbird.h public macros available if needed
# core.c already includes "hmbird.h" and slim.h under CONFIG_HMBIRD_SCHED

if text == orig:
    print("NO CHANGES MADE")
    for c in changes:
        print(" -", c)
    raise SystemExit(1)

CORE.write_text(text)
print("UPDATED", CORE)
for c in changes:
    print(" -", c)

# sanity: leftover scx calls that are errors
left = []
for s in ["scx_notify_sched_tick", "scx_switched_all", "task_on_scx"]:
    if s in text:
        # count occurrences
        n = text.count(s)
        left.append(f"{s} x{n}")
if left:
    print("WARN leftover:", ", ".join(left))
else:
    print("OK: no leftover scx symbols in core.c")
