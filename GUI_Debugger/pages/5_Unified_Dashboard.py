import json
import pandas as pd
import streamlit as st

st.set_page_config(page_title="Unified Dashboard", layout="wide")

st.title("🖥️ R10K OOO Processor - Unified Dashboard")

# Load trace function
def load_trace(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            return [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return None

# Load all traces
rs_trace = load_trace("dump_files/rs_trace.json")
rob_trace = load_trace("dump_files/rob_trace.json")
retire_trace = load_trace("dump_files/retire_trace.json")
cdb_trace = load_trace("dump_files/cdb_trace.json")

# Check if any trace is missing
missing_traces = []
if rs_trace is None:
    missing_traces.append("RS")
if rob_trace is None:
    missing_traces.append("ROB")
if retire_trace is None:
    missing_traces.append("Retire")
if cdb_trace is None:
    missing_traces.append("CDB")

if missing_traces:
    st.warning(f"⚠️ Missing trace files: {', '.join(missing_traces)}")

# Global cycle control
if "global_cycle" not in st.session_state:
    st.session_state["global_cycle"] = 0

# Determine max cycle from available traces
max_cycles = []
if rs_trace:
    max_cycles.append(len(rs_trace) - 1)
if rob_trace:
    max_cycles.append(len(rob_trace) - 1)
if retire_trace:
    max_cycles.append(len(retire_trace) - 1)
if cdb_trace:
    max_cycles.append(len(cdb_trace) - 1)

max_cycle = max(max_cycles) if max_cycles else 100

# Cycle control at the top
st.markdown("### 🎛️ Cycle Control")
col1, col2, col3, col4 = st.columns([1, 3, 1, 1])

with col1:
    if st.button("⏮️ First"):
        st.session_state["global_cycle"] = 0
        st.rerun()

with col2:
    cycle = st.slider("Cycle", 0, max_cycle, st.session_state["global_cycle"], key="cycle_slider")
    st.session_state["global_cycle"] = cycle

with col3:
    if st.button("⬅️ Prev"):
        st.session_state["global_cycle"] = max(st.session_state["global_cycle"] - 1, 0)
        st.rerun()

with col4:
    if st.button("➡️ Next"):
        st.session_state["global_cycle"] = min(st.session_state["global_cycle"] + 1, max_cycle)
        st.rerun()

st.markdown("---")

# Display mode selection
display_mode = st.radio(
    "Display Mode:",
    ["Tabs (Switch between components)", "Expanders (All visible, collapsible)", "Grid (Compact 2x2)", "Vertical (All stacked)"],
    horizontal=True
)

st.markdown("---")

# Get current cycle data
cycle = st.session_state["global_cycle"]

rs_data = rs_trace[min(cycle, len(rs_trace)-1)].get("RS", []) if rs_trace else []
rob_data = rob_trace[min(cycle, len(rob_trace)-1)].get("ROB", []) if rob_trace else []
retire_data = retire_trace[min(cycle, len(retire_trace)-1)].get("RETIRE", []) if retire_trace else []
cdb_data = cdb_trace[min(cycle, len(cdb_trace)-1)].get("CDB", []) if cdb_trace else []

# Convert to DataFrames
rs_df = pd.DataFrame(rs_data) if rs_data else pd.DataFrame()
rob_df = pd.DataFrame(rob_data) if rob_data else pd.DataFrame()
retire_df = pd.DataFrame(retire_data) if retire_data else pd.DataFrame()
cdb_df = pd.DataFrame(cdb_data) if cdb_data else pd.DataFrame()

# === TABS MODE ===
if display_mode == "Tabs (Switch between components)":
    tab1, tab2, tab3, tab4 = st.tabs(["📋 Reservation Station", "🔄 Reorder Buffer", "✅ Retire", "📡 CDB"])
    
    with tab1:
        st.subheader(f"Reservation Station - Cycle {cycle}")
        if not rs_df.empty:
            st.dataframe(rs_df, use_container_width=True, height=400)
        else:
            st.info("No RS data available for this cycle")
    
    with tab2:
        st.subheader(f"Reorder Buffer - Cycle {cycle}")
        if not rob_df.empty:
            st.dataframe(rob_df, use_container_width=True, height=400)
        else:
            st.info("No ROB data available for this cycle")
    
    with tab3:
        st.subheader(f"Retire Stage - Cycle {cycle}")
        if not retire_df.empty:
            st.dataframe(retire_df, use_container_width=True, height=400)
        else:
            st.info("No Retire data available for this cycle")
    
    with tab4:
        st.subheader(f"Common Data Bus - Cycle {cycle}")
        if not cdb_df.empty:
            st.dataframe(cdb_df, use_container_width=True, height=400)
        else:
            st.info("No CDB data available for this cycle")

# === EXPANDERS MODE ===
elif display_mode == "Expanders (All visible, collapsible)":
    with st.expander("📋 Reservation Station", expanded=True):
        st.subheader(f"Cycle {cycle}")
        if not rs_df.empty:
            st.dataframe(rs_df, use_container_width=True, height=300)
        else:
            st.info("No RS data available")
    
    with st.expander("🔄 Reorder Buffer", expanded=True):
        st.subheader(f"Cycle {cycle}")
        if not rob_df.empty:
            st.dataframe(rob_df, use_container_width=True, height=300)
        else:
            st.info("No ROB data available")
    
    with st.expander("✅ Retire Stage", expanded=False):
        st.subheader(f"Cycle {cycle}")
        if not retire_df.empty:
            st.dataframe(retire_df, use_container_width=True, height=300)
        else:
            st.info("No Retire data available")
    
    with st.expander("📡 Common Data Bus", expanded=False):
        st.subheader(f"Cycle {cycle}")
        if not cdb_df.empty:
            st.dataframe(cdb_df, use_container_width=True, height=300)
        else:
            st.info("No CDB data available")

# === GRID MODE (2x2) ===
elif display_mode == "Grid (Compact 2x2)":
    col_left, col_right = st.columns(2)
    
    with col_left:
        st.subheader("📋 Reservation Station")
        if not rs_df.empty:
            st.dataframe(rs_df, use_container_width=True, height=350)
        else:
            st.info("No RS data")
        
        st.markdown("---")
        
        st.subheader("✅ Retire Stage")
        if not retire_df.empty:
            st.dataframe(retire_df, use_container_width=True, height=250)
        else:
            st.info("No Retire data")
    
    with col_right:
        st.subheader("🔄 Reorder Buffer")
        if not rob_df.empty:
            st.dataframe(rob_df, use_container_width=True, height=350)
        else:
            st.info("No ROB data")
        
        st.markdown("---")
        
        st.subheader("📡 Common Data Bus")
        if not cdb_df.empty:
            st.dataframe(cdb_df, use_container_width=True, height=250)
        else:
            st.info("No CDB data")

# === VERTICAL MODE ===
else:  # Vertical (All stacked)
    st.subheader("📋 Reservation Station")
    if not rs_df.empty:
        st.dataframe(rs_df, use_container_width=True, height=250)
    else:
        st.info("No RS data available")
    
    st.markdown("---")
    
    st.subheader("🔄 Reorder Buffer")
    if not rob_df.empty:
        st.dataframe(rob_df, use_container_width=True, height=250)
    else:
        st.info("No ROB data available")
    
    st.markdown("---")
    
    st.subheader("✅ Retire Stage")
    if not retire_df.empty:
        st.dataframe(retire_df, use_container_width=True, height=250)
    else:
        st.info("No Retire data available")
    
    st.markdown("---")
    
    st.subheader("📡 Common Data Bus")
    if not cdb_df.empty:
        st.dataframe(cdb_df, use_container_width=True, height=250)
    else:
        st.info("No CDB data available")

# Footer with stats
st.markdown("---")
col1, col2, col3, col4, col5, col6 = st.columns(6)
with col1:
    st.metric("RS Entries", len(rs_df) if not rs_df.empty else 0)
with col2:
    st.metric("ROB Entries", len(rob_df) if not rob_df.empty else 0)
with col3:
    st.metric("Retire Entries", len(retire_df) if not retire_df.empty else 0)
with col4:
    st.metric("CDB Entries", len(cdb_df) if not cdb_df.empty else 0)
with col5:
    st.metric("Current Cycle", cycle)
with col6:
    st.metric("Max Cycle", max_cycle)
