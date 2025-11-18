import json, pandas as pd, streamlit as st

st.title("CDB Viewer")

# --- Session state ---
if "page_cycle_cdb" not in st.session_state:
    st.session_state["page_cycle_cdb"] = 0

sync = st.checkbox("🔗 Sync with Global", value=True)
cycle = st.session_state.get("global_cycle", 0) if sync else st.session_state["page_cycle_cdb"]

col1, col2, col3 = st.columns(3)
with col1:
    if st.button("⬅ Prev (CDB)"):
        st.session_state["page_cycle_cdb"] = max(cycle - 1, 0)
with col2:
    st.metric("CDB Cycle", cycle)
with col3:
    if st.button("➡ Next (CDB)"):
        st.session_state["page_cycle_cdb"] = cycle + 1


# --- Utilities ---
def sanitize_value(v):
    if isinstance(v, str) and v.lower() == "x":
        return None
    return v


def load_trace(path):
    traces = []
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue

            # 兼容大小寫 key
            key = "CDB" if "CDB" in data else "cdb"
            rows = data.get(key, [])

            for row in rows:
                for k, v in row.items():
                    row[k] = sanitize_value(v)

            traces.append({
                "cycle": data.get("cycle", len(traces)),
                "rows": rows
            })
    return traces


# --- Load file ---
try:
    trace = load_trace("dump_files/cdb_trace.json")
except FileNotFoundError:
    st.info("找不到 `dump_files/cdb_trace.json`（可選）。")
    st.stop()

if not trace:
    st.warning("⚠ 沒有有效的 CDB trace 資料。")
    st.stop()

cycle = min(cycle, len(trace) - 1)
st.write(f"顯示第 {cycle} 個 cycle 狀態")

rows = trace[cycle].get("rows", [])
if not rows:
    st.info("此 cycle 沒有 CDB 資料。")
else:
    df = pd.DataFrame(rows)
    st.dataframe(df, use_container_width=True)
