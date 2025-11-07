# import streamlit as st

# st.set_page_config(page_title="EECS470 GUI Debugger", layout="wide")

# # 初始化 session_state
# if "cycle" not in st.session_state:
#     st.session_state["cycle"] = 0

# st.title("EECS470 CPU GUI Debugger")

# # Sidebar 控制所有頁面共用的 cycle
# cycle = st.slider("Global Cycle", 0, 100, st.session_state["cycle"])
# st.session_state["cycle"] = cycle

# st.markdown("從左側選單切換模組（RS / ROB / ...），所有頁面會同步到相同 cycle。")
import streamlit as st

st.set_page_config(page_title="EECS470 GUI Debugger", layout="wide")

# 初始化 global cycle
if "global_cycle" not in st.session_state:
    st.session_state["global_cycle"] = 0

# 主頁介面
st.title("EECS470 GUI Debugger - Main Control")

col1, col2, col3 = st.columns([1, 2, 1])
with col1:
    if st.button("⬅ Prev"):
        st.session_state["global_cycle"] = max(st.session_state["global_cycle"] - 1, 0)

with col2:
    cycle = st.slider("Global Cycle", 0, 800, st.session_state["global_cycle"])
    st.session_state["global_cycle"] = cycle

with col3:
    if st.button("➡ Next"):
        st.session_state["global_cycle"] += 1

st.markdown("---")
st.write(f"**Current Global Cycle:** {st.session_state['global_cycle']}")
st.info("切換頁面後，勾選 Sync with Global 的模組都會跟著此 cycle 一起動。")
