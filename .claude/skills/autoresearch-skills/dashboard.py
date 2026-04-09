#!/usr/bin/env python3
"""
Skill Autoresearch Dashboard - Live visualization of skill optimization progress.

Usage:
    python3 dashboard.py --port 8502
"""

import argparse
import json
from pathlib import Path
from datetime import datetime

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# ─── Config ───────────────────────────────────────────────────────────────────

DATA_DIR = Path(__file__).parent / "data"
RESULTS_FILE = DATA_DIR / "results.jsonl"
STATE_FILE = DATA_DIR / "state.json"

st.set_page_config(
    page_title="Skill Autoresearch Dashboard",
    page_icon="🧬",
    layout="wide"
)

# ─── Load Data ─────────────────────────────────────────────────────────────────

@st.cache_data(ttl=10)
def load_results():
    """Load experiment results."""
    if not RESULTS_FILE.exists():
        return []

    results = []
    with open(RESULTS_FILE) as f:
        for line in f:
            results.append(json.loads(line))
    return results

@st.cache_data(ttl=10)
def load_state():
    """Load current state."""
    if not STATE_FILE.exists():
        return {}
    return json.loads(STATE_FILE.read_text())

# ─── Main App ─────────────────────────────────────────────────────────────────

st.title("🧬 Skill Autoresearch Dashboard")
st.markdown("Real-time monitoring of self-improving skill optimization")

# Load data
results = load_results()
state = load_state()

if not results:
    st.warning("No results yet. Run `python3 autoresearch.py` to start optimization.")
    st.stop()

# Metrics row
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric("Total Runs", state.get("run_number", 0))

with col2:
    best_score = state.get("best_score", 0)
    st.metric("Best Score", f"{best_score:.1f}/100")

with col3:
    latest_score = results[-1]["avg_score"] if results else 0
    delta = latest_score - results[-2]["avg_score"] if len(results) > 1 else 0
    st.metric("Latest Score", f"{latest_score:.1f}/100", f"{delta:+.1f}")

with col4:
    total_cost = state.get("total_cost", 0.0)
    st.metric("Estimated Cost", f"${total_cost:.2f}")

# Score over time
st.subheader("Score Progression")

df = pd.DataFrame(results)
df["timestamp"] = pd.to_datetime(df["timestamp"])

fig = go.Figure()
fig.add_trace(go.Scatter(
    x=df["timestamp"],
    y=df["avg_score"],
    mode="lines+markers",
    name="Average Score",
    line=dict(color="#1f77b4", width=2)
))

if best_score > 0:
    fig.add_hline(
        y=best_score,
        line_dash="dash",
        line_color="green",
        annotation_text=f"Best: {best_score:.1f}"
    )

fig.update_layout(
    xaxis_title="Time",
    yaxis_title="Score (0-100)",
    hovermode="x unified",
    height=300
)

st.plotly_chart(fig, use_container_width=True)

# Test case breakdown
st.subheader("Test Case Performance")

latest_results = results[-1]["results"] if results else []
test_df = pd.DataFrame([
    {
        "Test ID": r["test_id"],
        "Type": r["type"],
        "Score": r["score"],
        "Query": r["query"][:50] + "..." if len(r["query"]) > 50 else r["query"]
    }
    for r in latest_results
])

if not test_df.empty:
    fig = px.bar(
        test_df,
        x="Test ID",
        y="Score",
        color="Type",
        title="Per-Test Scores (Latest Run)",
        color_discrete_map={"positive": "green", "negative": "red", "edge_case": "orange"}
    )
    fig.update_layout(yaxis_range=[0, 100])
    st.plotly_chart(fig, use_container_width=True)

# Score breakdown by criterion
if latest_results:
    st.subheader("Score Breakdown by Criterion")

    criteria_scores = {}
    for r in latest_results:
        for criterion, score in r.get("breakdown", {}).items():
            if criterion not in criteria_scores:
                criteria_scores[criterion] = []
            criteria_scores[criterion].append(score)

    if criteria_scores:
        criteria_df = pd.DataFrame([
            {
                "Criterion": criterion,
                "Average": sum(scores) / len(scores)
            }
            for criterion, scores in criteria_scores.items()
        ])

        fig = px.bar(
            criteria_df,
            x="Criterion",
            y="Average",
            title="Average Scores by Evaluation Criterion"
        )
        fig.update_layout(yaxis_range=[0, 20])
        st.plotly_chart(fig, use_container_width=True)

# Detailed results table
st.subheader("Recent Runs")

display_df = df[["run", "timestamp", "avg_score", "total_score"]].tail(10)
display_df["timestamp"] = display_df["timestamp"].dt.strftime("%Y-%m-%d %H:%M")
st.dataframe(display_df, use_container_width=True)

# Skill comparison
if len(results) > 1:
    st.subheader("Top Performing Versions")

    top_runs = sorted(results, key=lambda x: x["avg_score"], reverse=True)[:5]

    for i, run in enumerate(top_runs, 1):
        with st.expander(f"Run {run['run']} - {run['avg_score']:.1f}/100"):
            st.write(f"**Timestamp:** {run['timestamp']}")
            st.write(f"**Total Score:** {run['total_score']:.1f}/{run['num_tests']*100}")

            for result in run["results"]:
                st.write(f"- Test {result['test_id']} ({result['type']}): {result['score']}/100")
                if result.get("reasoning"):
                    st.caption(f"  *{result['reasoning']}*")

# Auto-refresh
st.sidebar.title("Settings")
auto_refresh = st.sidebar.checkbox("Auto-refresh (30s)", value=False)

if auto_refresh:
    time.sleep(30)
    st.rerun()

# Manual refresh
if st.sidebar.button("Refresh Now"):
    st.rerun()
