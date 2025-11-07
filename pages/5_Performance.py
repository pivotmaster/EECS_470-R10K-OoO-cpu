
import json, pandas as pd, streamlit as st
import matplotlib.pyplot as plt

st.title("Performance Viewer")

if "page_cycle_perf" not in st.session_state:
    st.session_state["page_cycle_perf"] = 0

sync = st.checkbox("🔗 Sync with Global", value=True)

if sync:
    cycle = st.session_state.get("global_cycle", 0)
else:
    cycle = st.session_state["page_cycle_perf"]

col1, col2, col3 = st.columns(3)
with col1:
    if st.button("⬅ Prev (Perf)"):
        st.session_state["page_cycle_perf"] = max(cycle - 1, 0)
with col2:
    st.metric("Perf Cycle", cycle)
with col3:
    if st.button("➡ Next (Perf)"):
        st.session_state["page_cycle_perf"] = cycle + 1

def load_trace(path):
    with open(path, encoding="utf-8", errors="ignore") as f:
        return [json.loads(line) for line in f if line.strip()]

try:
    trace = load_trace("dump_files/perf_trace.json")
except FileNotFoundError:
    st.info("找不到 `dump_files/perf_trace.json`（可選）。")
    st.stop()

# 折線圖（單一圖、預設顏色）
df = pd.DataFrame(trace)
fig, ax = plt.subplots()
if {"cycle","instrs"} <= set(df.columns): ax.plot(df["cycle"], df["instrs"], label="instrs")
if {"cycle","stalls"} <= set(df.columns): ax.plot(df["cycle"], df["stalls"], label="stalls")
if {"cycle","mispred"} <= set(df.columns): ax.plot(df["cycle"], df["mispred"], label="mispred")
ax.set_xlabel("cycle"); ax.set_ylabel("count"); ax.legend()
st.pyplot(fig)
