
import json, pandas as pd, streamlit as st

st.title("Reservation Station Viewer")

# 初始化頁面 cycle（RS 專屬）
if "page_cycle_rs" not in st.session_state:
    st.session_state["page_cycle_rs"] = 0

# 是否跟隨全域 cycle
sync = st.checkbox("🔗 Sync with Global", value=True)

# 若同步 → 使用全域 cycle；否則用本頁自己的 cycle
if sync:
    cycle = st.session_state.get("global_cycle", 0)
else:
    cycle = st.session_state["page_cycle_rs"]

col1, col2, col3 = st.columns(3)
with col1:
    if st.button("⬅ Prev (RS)"):
        st.session_state["page_cycle_rs"] = max(cycle - 1, 0)
with col2:
    st.metric("RS Cycle", cycle)
with col3:
    if st.button("➡ Next (RS)"):
        st.session_state["page_cycle_rs"] = cycle + 1

# 載入 trace（JSONL，每行一筆）
def load_trace(path):
    with open(path, encoding="utf-8", errors="ignore") as f:
        return [json.loads(line) for line in f if line.strip()]

try:
    trace = load_trace("dump_files/rs_trace.json")
except FileNotFoundError:
    st.error("找不到 `dump_files/rs_trace.json`，請先產生 RS trace 檔。")
    st.stop()

# clamp cycle
cycle = min(cycle, max(0, len(trace)-1))
st.write(f"顯示第 {cycle} 個 cycle 狀態")
df = pd.DataFrame(trace[cycle].get("RS", []))
st.dataframe(df, use_container_width=True)
