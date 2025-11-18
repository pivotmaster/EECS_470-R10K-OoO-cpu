import json, pandas as pd, streamlit as st

st.title("Retire Viewer")

# =============================
# Session State
# =============================
if "page_cycle_retire" not in st.session_state:
    st.session_state["page_cycle_retire"] = 0

sync = st.checkbox("🔗 Sync with Global", value=True)

if sync:
    cycle = st.session_state.get("global_cycle", 0)
else:
    cycle = st.session_state["page_cycle_retire"]

# =============================
# Navigation Buttons
# =============================
col1, col2, col3 = st.columns(3)
with col1:
    if st.button("⬅ Prev (retire)"):
        st.session_state["page_cycle_retire"] = max(cycle - 1, 0)
with col2:
    st.metric("retire Cycle", cycle)
with col3:
    if st.button("➡ Next (retire)"):
        st.session_state["page_cycle_retire"] = cycle + 1

# =============================
# Load & Sanitize Trace
# =============================
def sanitize_value(v):
    """將 'x' 或未知值轉成 None，以避免顯示錯誤"""
    if isinstance(v, str) and v.lower() == "x":
        return None
    return v

def load_trace(path):
    with open(path, encoding="utf-8", errors="ignore") as f:
        traces = []
        for line in f:
            if not line.strip():
                continue
            try:
                data = json.loads(line)
                # 嘗試支援不同 key 命名方式
                key = "RETIRE" if "RETIRE" in data else "retires"
                rows = data.get(key, [])
                # 清理每一筆資料
                for row in rows:
                    for k, v in row.items():
                        row[k] = sanitize_value(v)
                traces.append({"cycle": data.get("cycle", len(traces)), "rows": rows})
            except json.JSONDecodeError:
                continue
        return traces

# =============================
# Read retire_trace.json
# =============================
try:
    trace = load_trace("dump_files/retire_trace.json")
except FileNotFoundError:
    st.info("找不到 `dump_files/retire_trace.json`（可選）。")
    st.stop()

# =============================
# Display current cycle
# =============================
if not trace:
    st.warning("⚠ 沒有有效的 retire trace 資料。")
    st.stop()

cycle = min(cycle, len(trace) - 1)
st.write(f"顯示第 {cycle} 個 cycle 狀態")

rows = trace[cycle].get("rows", [])
if not rows:
    st.info("此 cycle 沒有 retire 資料。")
else:
    df = pd.DataFrame(rows)
    st.dataframe(df, use_container_width=True)
