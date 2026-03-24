#!/usr/bin/env python3
"""
Dashboard — Streamlit dashboard for monitoring autoresearch optimization.

Real-time visualization of:
- Score progression over time
- Test case pass/fail breakdown
- Criterion-level analysis
- Mutation history
- Cost tracking
"""

import json
import os
from pathlib import Path
from typing import Dict, List, Any

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st


def load_results(skill_name: str) -> List[Dict]:
    """Load all results from results.jsonl."""
    results_path = Path(__file__).parent / "data" / skill_name / "results.jsonl"

    if not results_path.exists():
        return []

    results = []
    with open(results_path) as f:
        for line in f:
            results.append(json.loads(line))

    return results


def load_state(skill_name: str) -> Dict[str, Any]:
    """Load optimization state."""
    state_path = Path(__file__).parent / "data" / skill_name / "state.json"

    if not state_path.exists():
        return {}

    return json.loads(state_path.read_text())


def load_test_suite(skill_name: str) -> Dict[str, Any]:
    """Load test suite."""
    test_suite_path = Path(__file__).parent / "data" / skill_name / "test_suite.json"

    if not test_suite_path.exists():
        return {}

    return json.loads(test_suite_path.read_text())


def main():
    """Main dashboard app."""

    st.set_page_config(
        page_title="Auto-Research Dashboard",
        page_icon="🧬",
        layout="wide"
    )

    st.title("🧬 Auto-Research Optimization Dashboard")

    # Sidebar: Skill selection
    st.sidebar.header("Settings")

    data_dir = Path(__file__).parent / "data"
    skills = [d.name for d in data_dir.iterdir() if d.is_dir() and (d / "results.jsonl").exists()]

    if not skills:
        st.warning("No optimized skills found. Run `python3 optimizer.py <skill_name>` first.")
        return

    skill_name = st.sidebar.selectbox("Select Skill", skills)

    # Load data
    results = load_results(skill_name)
    state = load_state(skill_name)
    test_suite = load_test_suite(skill_name)

    if not results:
        st.warning(f"No results found for {skill_name}")
        return

    # Convert to DataFrame
    df = pd.DataFrame(results)

    # Metrics overview
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Total Runs", len(df))

    with col2:
        best_score = df["avg_score"].max()
        st.metric("Best Score", f"{best_score:.1f}/100")

    with col3:
        current_score = df.iloc[-1]["avg_score"]
        st.metric("Current Score", f"{current_score:.1f}/100")

    with col4:
        improvement = best_score - df.iloc[0]["avg_score"]
        st.metric("Improvement", f"+{improvement:.1f}")

    # Score progression
    st.header("Score Progression")

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df["run"],
        y=df["avg_score"],
        mode="lines+markers",
        name="Average Score",
        line=dict(color="#00CC96", width=2)
    ))

    # Add best score line
    fig.add_hline(
        y=best_score,
        line_dash="dash",
        line_color="red",
        annotation_text=f"Best: {best_score:.1f}"
    )

    fig.update_layout(
        xaxis_title="Run Number",
        yaxis_title="Score (0-100)",
        hovermode="x unified",
        height=400
    )

    st.plotly_chart(fig, use_container_width=True)

    # Test case breakdown
    if test_suite and "test_cases" in test_suite:
        st.header("Test Case Analysis")

        # Get latest results
        latest_results = df.iloc[-1]["results"]

        test_data = []
        for result in latest_results:
            test_data.append({
                "Test ID": result["test_id"],
                "Type": result["type"],
                "Score": result["score"]
            })

        test_df = pd.DataFrame(test_data)

        # Pass/fail by test type
        col1, col2 = st.columns(2)

        with col1:
            st.subheader("Scores by Test Type")
            fig = px.box(
                test_df,
                x="Type",
                y="Score",
                color="Type",
                title="Score Distribution by Test Type"
            )
            fig.update_layout(height=300)
            st.plotly_chart(fig, use_container_width=True)

        with col2:
            st.subheader("Test Pass Rate")
            pass_counts = test_df.groupby("Type").apply(
                lambda x: (x["Score"] >= 60).sum()
            )
            total_counts = test_df.groupby("Type").size()

            fig = go.Figure(data=[
                go.Bar(
                    x=pass_counts.index,
                    y=pass_counts.values,
                    name="Passed (≥60)",
                    marker_color="#00CC96"
                ),
                go.Bar(
                    x=total_counts.index,
                    y=total_counts.values - pass_counts.values,
                    name="Failed (<60)",
                    marker_color="#EF553B"
                )
            ])

            fig.update_layout(
                barmode="stack",
                xaxis_title="Test Type",
                yaxis_title="Count",
                height=300
            )

            st.plotly_chart(fig, use_container_width=True)

    # Criterion analysis
    if latest_results:
        st.header("Criterion Analysis")

        # Aggregate criterion scores
        criterion_data = {
            "Correct Triggering": [],
            "Workflow Adherence": [],
            "Error Avoidance": [],
            "Output Quality": [],
            "User Intent": []
        }

        for result in latest_results:
            scores = result["evaluation"]["scores"]
            criterion_data["Correct Triggering"].append(scores["correct_triggering"])
            criterion_data["Workflow Adherence"].append(scores["workflow_adherence"])
            criterion_data["Error Avoidance"].append(scores["error_avoidance"])
            criterion_data["Output Quality"].append(scores["output_quality"])
            criterion_data["User Intent"].append(scores["user_intent"])

        criterion_df = pd.DataFrame(criterion_data)

        # Average scores by criterion
        avg_scores = criterion_df.mean()

        fig = go.Figure(data=[
            go.Bar(
                x=avg_scores.index,
                y=avg_scores.values,
                marker_color=[
                    "#00CC96" if s >= 15 else "#EF553B"
                    for s in avg_scores.values
                ]
            )
        ])

        fig.update_layout(
            xaxis_title="Criterion",
            yaxis_title="Average Score (0-20)",
            height=400
        )

        st.plotly_chart(fig, use_container_width=True)

    # Mutation history
    st.header("Mutation Strategy Effectiveness")

    mutation_stats = df.groupby("mutation")["avg_score"].agg([
        ("Count", "count"),
        ("Average Score", "mean"),
        ("Best Score", "max")
    ]).reset_index()

    st.dataframe(
        mutation_stats.sort_values("Best Score", ascending=False),
        use_container_width=True
    )

    # Cost tracking (estimated)
    st.header("Estimated Cost")

    # Rough estimates:
    # - Test execution: 4 tests × $0.01 = $0.04 per run
    # - Evaluation: 4 tests × $0.02 = $0.08 per run
    # - Mutation: $0.01 per run
    # Total: ~$0.13 per run

    cost_per_run = 0.13
    total_cost = len(df) * cost_per_run

    col1, col2 = st.columns(2)

    with col1:
        st.metric("Cost Per Run", f"${cost_per_run:.2f}")

    with col2:
        st.metric("Total Estimated Cost", f"${total_cost:.2f}")

    # Recent runs table
    st.header("Recent Runs")

    recent_df = df[["run", "mutation", "avg_score"]].tail(10).sort_values("run", ascending=False)
    st.dataframe(recent_df, use_container_width=True)

    # Export button
    if st.button("Export Results (JSON)"):
        st.download_button(
            "Download",
            data=json.dumps(results, indent=2),
            file_name=f"{skill_name}_results.json",
            mime="application/json"
        )


if __name__ == "__main__":
    main()
