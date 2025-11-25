import json, pandas as pd, streamlit as st

st.title("Functional Unit (FU) Input Viewer ⚙️")

# --- Session state ---
if "page_cycle_fu" not in st.session_state:
    st.session_state["page_cycle_fu"] = 0

sync = st.checkbox("🔗 Sync with Global", value=True)
cycle = st.session_state.get("global_cycle", 0) if sync else st.session_state["page_cycle_fu"]

col1, col2, col3 = st.columns(3)
with col1:
    if st.button("⬅ Prev (FU)"):
        st.session_state["page_cycle_fu"] = max(cycle - 1, 0)
with col2:
    st.metric("FU Cycle", cycle)
with col3:
    if st.button("➡ Next (FU)"):
        st.session_state["page_cycle_fu"] = cycle + 1


# --- Load JSON trace ---
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

            key = "FU" if "FU" in data else "fu"
            traces.append({
                "cycle": data.get("cycle", len(traces)),
                "rows": data.get(key, [])
            })
    return traces


# --- Try loading trace file ---
try:
    trace = load_trace("dump_files/fu_trace.json")
except FileNotFoundError:
    st.info("找不到 `dump_files/fu_trace.json`（可選）。")
    st.stop()

if not trace:
    st.warning("⚠ 沒有有效的 FU trace 資料。")
    st.stop()

cycle = min(cycle, len(trace) - 1)
st.write(f"顯示第 {cycle} 個 cycle 狀態")

rows = trace[cycle].get("rows", [])
if not rows:
    st.info("此 cycle 沒有 FU 資料。")
else:
    df = pd.DataFrame(rows)

    # --- 🔧 確保所有欄位存在 ---
    for col in ["idx", "valid", "dest_tag", "rob_idx", "src1_val", "src2_val"]:
        if col not in df.columns:
            df[col] = None

    # --- 顯示主要欄位 ---
    show_cols = ["idx", "valid", "dest_tag", "rob_idx", "src1_val", "src2_val"]

    # --- 過濾或顯示 ---
    if df.empty:
        st.info("此 cycle 沒有 FU 輸入資料。")
    else:
        st.dataframe(df[show_cols], use_container_width=True)

        if "valid" in df.columns:
            valid_count = int(df["valid"].sum())
            st.info(f"本 cycle 有 **{valid_count}** 個有效的 FU 請求。")
