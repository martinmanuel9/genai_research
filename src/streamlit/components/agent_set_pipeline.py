"""
Agent Set Pipeline Component

This component provides a UI for running agent set pipelines on direct text input.
It allows users to paste text content and process it through a selected agent set pipeline
without requiring the content to be stored in ChromaDB first.
"""

import streamlit as st
import time
from config.settings import config
from app_lib.api.client import api_client


def _display_citations(formatted_citations: str = ""):
    """
    Display formatted citations from the RAG service.

    Args:
        formatted_citations: Pre-formatted citation text from RAG service
    """
    if not formatted_citations:
        return

    st.divider()
    with st.expander("Sources and Citations", expanded=True):
        st.markdown(formatted_citations)


def agent_set_pipeline():
    """
    Agent Set Pipeline - Run agent pipelines on direct text input
    """
    st.subheader("Agent Set Pipeline")
    st.caption("Run a complete agent set pipeline on any text content")

    # ----------------------------
    # Check if there's an active pipeline - if yes, show status only
    # ----------------------------
    if "agent_pipeline_id" in st.session_state and st.session_state.agent_pipeline_id:
        pipeline_id = st.session_state.agent_pipeline_id
        _show_pipeline_status(pipeline_id)
        return

    # ----------------------------
    # No active pipeline - show form
    # ----------------------------

    # Fetch available agent sets
    try:
        agent_sets_response = api_client.get(f"{config.fastapi_url}/api/agent-sets")
        agent_sets = agent_sets_response.get("agent_sets", [])
        active_agent_sets = [s for s in agent_sets if s.get('is_active', True)]
    except Exception as e:
        st.warning(f"Could not load agent sets: {e}")
        active_agent_sets = []

    if not active_agent_sets:
        st.error("No agent sets available. Please create an agent set in the Agent & Orchestration Manager.")
        return

    # Agent set selector
    col1, col2 = st.columns([2, 1])

    with col1:
        agent_set_options = [s['name'] for s in active_agent_sets]
        selected_agent_set_name = st.selectbox(
            "Select Agent Set Pipeline",
            options=agent_set_options,
            key="pipeline_agent_set",
            help="Choose an agent set to process your text through its stages"
        )

    with col2:
        agent_set = next((s for s in active_agent_sets if s['name'] == selected_agent_set_name), None)
        if agent_set:
            st.metric("Usage Count", agent_set.get('usage_count', 0))

    # Show agent set details
    if agent_set:
        with st.expander("View Pipeline Configuration", expanded=False):
            st.write(f"**Description:** {agent_set.get('description', 'No description')}")
            st.write(f"**Type:** {agent_set.get('set_type', 'sequence')}")

            stages = agent_set.get('set_config', {}).get('stages', [])
            st.write(f"**Pipeline Stages ({len(stages)}):**")
            for idx, stage in enumerate(stages, 1):
                stage_name = stage.get('stage_name', f'Stage {idx}')
                agent_count = len(stage.get('agent_ids', []))
                exec_mode = stage.get('execution_mode', 'parallel')
                st.write(f"  {idx}. **{stage_name}** - {agent_count} agent(s) ({exec_mode})")
                if stage.get('description'):
                    st.caption(f"     {stage.get('description')}")

    st.markdown("---")

    # Text input section
    st.subheader("Input Content")

    input_method = st.radio(
        "Input Method",
        ["Paste Text", "Upload File"],
        horizontal=True,
        key="pipeline_input_method"
    )

    text_input = ""

    if input_method == "Paste Text":
        text_input = st.text_area(
            "Paste your content here",
            height=300,
            placeholder="Enter or paste the text content you want to process through the agent pipeline...",
            key="pipeline_text_input"
        )
    else:
        uploaded_file = st.file_uploader(
            "Upload a text file",
            type=['txt', 'md', 'json', 'csv'],
            key="pipeline_file_upload"
        )
        if uploaded_file:
            text_input = uploaded_file.read().decode('utf-8')
            st.text_area(
                "File Content Preview",
                value=text_input[:2000] + ("..." if len(text_input) > 2000 else ""),
                height=200,
                disabled=True
            )
            st.caption(f"Total characters: {len(text_input)}")

    # Section mode
    st.markdown("---")
    st.subheader("Processing Options")

    col1, col2 = st.columns(2)

    with col1:
        section_mode = st.selectbox(
            "Section Mode",
            ["auto", "single"],
            key="pipeline_section_mode",
            help="'auto': Automatically detect and split sections. 'single': Process as one section."
        )

    with col2:
        title = st.text_input(
            "Result Title",
            value="Agent Pipeline Analysis",
            key="pipeline_title"
        )

    # Execution mode
    run_mode = st.radio(
        "Execution Mode",
        ["Background (Async)", "Synchronous (Wait)"],
        horizontal=True,
        key="pipeline_run_mode",
        help="Background mode returns immediately and allows progress tracking. Synchronous waits for completion."
    )

    st.markdown("---")

    # Run button
    if st.button("Run Agent Pipeline", type="primary", key="run_agent_pipeline"):
        if not text_input or len(text_input.strip()) < 10:
            st.error("Please provide text content (at least 10 characters)")
            return

        if not agent_set:
            st.error("Please select an agent set")
            return

        payload = {
            "text_input": text_input,
            "agent_set_id": agent_set['id'],
            "title": title,
            "section_mode": section_mode
        }

        try:
            if run_mode == "Background (Async)":
                # Async mode - start pipeline and show progress
                with st.spinner("Starting pipeline..."):
                    response = api_client.post(
                        f"{config.fastapi_url}/api/agent-pipeline/run-async",
                        data=payload,
                        timeout=30
                    )

                pipeline_id = response.get("pipeline_id")
                if pipeline_id:
                    st.session_state.agent_pipeline_id = pipeline_id
                    st.success(f"Pipeline started: {pipeline_id}")
                    st.info("Refreshing to show progress...")
                    time.sleep(1)
                    st.rerun()
                else:
                    st.error("Failed to start pipeline: No pipeline ID returned")
            else:
                # Sync mode - wait for completion
                with st.spinner("Running pipeline... This may take several minutes."):
                    response = api_client.post(
                        f"{config.fastapi_url}/api/agent-pipeline/run",
                        data=payload,
                        timeout=600  # 10 minute timeout for sync
                    )

                _display_pipeline_result(response)

        except Exception as e:
            st.error(f"Failed to run pipeline: {e}")

    # Resume existing pipeline section
    st.markdown("---")
    with st.expander("Resume Existing Pipeline", expanded=False):
        _show_recent_pipelines()


def _show_pipeline_status(pipeline_id: str):
    """Show the status of an active pipeline"""
    st.info(f"Active Pipeline: `{pipeline_id}`")

    try:
        status_response = api_client.get(
            f"{config.fastapi_url}/api/agent-pipeline/status/{pipeline_id}",
            timeout=10
        )

        status = status_response.get("status", "UNKNOWN")
        progress = status_response.get("progress", 0)
        progress_message = status_response.get("progress_message", "")

        # Status indicator
        status_emoji = {
            "COMPLETED": "✅",
            "PROCESSING": "⏳",
            "QUEUED": "📝",
            "FAILED": "❌"
        }.get(status, "❓")

        st.write(f"**Status:** {status_emoji} {status}")

        if status in ["PROCESSING", "QUEUED"]:
            st.progress(progress / 100)
            st.caption(progress_message)

            col1, col2 = st.columns(2)
            with col1:
                if st.button("Refresh Status", key="refresh_pipeline_status"):
                    st.rerun()
            with col2:
                if st.button("Cancel & Start New", key="cancel_pipeline"):
                    del st.session_state.agent_pipeline_id
                    st.rerun()

            # Auto-refresh
            time.sleep(5)
            st.rerun()

        elif status == "COMPLETED":
            st.success("Pipeline completed!")

            # Get full result
            result_response = api_client.get(
                f"{config.fastapi_url}/api/agent-pipeline/result/{pipeline_id}",
                timeout=30
            )

            _display_pipeline_result(result_response)

            if st.button("Start New Pipeline", key="start_new_pipeline"):
                del st.session_state.agent_pipeline_id
                st.rerun()

        elif status == "FAILED":
            st.error(f"Pipeline failed: {status_response.get('error', 'Unknown error')}")

            if st.button("Start New Pipeline", key="start_new_after_fail"):
                del st.session_state.agent_pipeline_id
                st.rerun()

    except Exception as e:
        st.error(f"Failed to get pipeline status: {e}")
        if st.button("Clear & Start New", key="clear_failed_pipeline"):
            del st.session_state.agent_pipeline_id
            st.rerun()


def _display_pipeline_result(result: dict):
    """Display the pipeline result"""
    st.markdown("### Pipeline Results")

    # Summary metrics
    rag_used = result.get("rag_context_used", False)
    col1, col2, col3, col4, col5 = st.columns(5)

    with col1:
        st.metric("Sections", result.get("total_sections", 0))
    with col2:
        st.metric("Stages Executed", result.get("total_stages_executed", 0))
    with col3:
        st.metric("Agents Executed", result.get("total_agents_executed", 0))
    with col4:
        processing_time = result.get("processing_time", 0)
        st.metric("Processing Time", f"{processing_time:.1f}s")
    with col5:
        st.metric("RAG Context", "Yes" if rag_used else "No")

    if rag_used:
        st.caption(f"RAG Collection: {result.get('rag_collection', 'N/A')}")

    st.markdown("---")

    # Consolidated output
    st.subheader("Consolidated Output")
    consolidated = result.get("consolidated_output", "")

    # Download button
    st.download_button(
        label="Download as Markdown",
        data=consolidated,
        file_name=f"{result.get('title', 'result')}.md",
        mime="text/markdown",
        key="download_consolidated"
    )

    # Show consolidated output in expander
    with st.expander("View Full Output", expanded=True):
        st.markdown(consolidated)

    # Display citations if RAG was used and citations are available
    if rag_used:
        formatted_citations = result.get("formatted_citations", "")
        if formatted_citations:
            _display_citations(formatted_citations)

    # Section-by-section results
    section_results = result.get("section_results", [])
    if section_results:
        st.markdown("---")
        st.subheader("Section Details")

        for idx, section in enumerate(section_results):
            section_title = section.get("section_title", f"Section {idx + 1}")

            with st.expander(f"**{section_title}**", expanded=False):
                # Section content preview
                content_preview = section.get("section_content_preview", section.get("section_content", "")[:200])
                st.caption(f"Content preview: {content_preview}...")

                # Stage results
                stage_results = section.get("stage_results", [])
                for stage in stage_results:
                    stage_name = stage.get("stage_name", "Unknown Stage")
                    st.markdown(f"**{stage_name.title()} Stage** ({stage.get('execution_mode', 'parallel')})")

                    # Agent results
                    agent_results = stage.get("agent_results", [])
                    for agent in agent_results:
                        agent_name = agent.get("agent_name", "Unknown")
                        success = agent.get("success", True)
                        status_icon = "✅" if success else "❌"

                        with st.container():
                            st.write(f"{status_icon} **{agent_name}** ({agent.get('model_name', 'Unknown')})")
                            if success:
                                output = agent.get("output", "")
                                st.text_area(
                                    f"Output from {agent_name}",
                                    value=output,
                                    height=150,
                                    key=f"agent_output_{idx}_{stage_name}_{agent.get('agent_id', 0)}",
                                    disabled=True
                                )
                            else:
                                st.error(f"Error: {agent.get('error', 'Unknown error')}")

                    st.markdown("---")


def _show_recent_pipelines():
    """Show list of recent pipelines for resumption"""
    try:
        response = api_client.get(
            f"{config.fastapi_url}/api/agent-pipeline/list",
            timeout=10
        )
        pipelines = response.get("pipelines", [])

        if not pipelines:
            st.info("No recent pipelines found.")
            return

        st.write(f"**{len(pipelines)} recent pipeline(s):**")

        for pipeline in pipelines[:10]:
            pipeline_id = pipeline.get("pipeline_id", "")
            status = pipeline.get("status", "UNKNOWN")
            title = pipeline.get("title", "Untitled")
            agent_set_name = pipeline.get("agent_set_name", "Unknown")
            progress = pipeline.get("progress", 0)

            # Status emoji
            status_emoji = {
                "COMPLETED": "✅",
                "PROCESSING": "⏳",
                "QUEUED": "📝",
                "FAILED": "❌"
            }.get(status, "❓")

            col1, col2, col3 = st.columns([3, 2, 1])

            with col1:
                st.write(f"{status_emoji} **{title}**")
                st.caption(f"Agent Set: {agent_set_name}")

            with col2:
                st.write(f"**{status}**")
                if status in ["PROCESSING", "QUEUED"]:
                    st.progress(progress / 100)

            with col3:
                button_label = "View" if status == "COMPLETED" else "Resume"
                if st.button(button_label, key=f"resume_pipeline_{pipeline_id}"):
                    st.session_state.agent_pipeline_id = pipeline_id
                    st.rerun()

            st.markdown("---")

    except Exception as e:
        st.warning(f"Could not load recent pipelines: {e}")
