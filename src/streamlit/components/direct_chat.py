import streamlit as st
import time
from config.settings import config
from config.constants import MODEL_KEY_MAP as model_key_map, MODEL_DESCRIPTIONS as model_descriptions
from app_lib.api.client import api_client
from services.chromadb_service import chromadb_service
from services.chat_service import chat_service
from components.upload_documents import render_upload_component, browse_documents
from components.history import Chat_History
from typing import List, Dict, Any, Optional

CHROMADB_API = config.endpoints.vectordb

@st.cache_data(show_spinner=False)
def fetch_collections():
    return chromadb_service.get_collections()

def display_citations(formatted_citations: str = ""):
    """
    Display formatted citations from the RAG service.

    The formatted_citations already contain all relevant information including:
    - Source document names and page numbers
    - Relevance quality tiers and distance scores
    - Contextual excerpts from the documents
    - Document position information

    Args:
        formatted_citations: Pre-formatted citation text from RAG service
    """
    if not formatted_citations:
        return

    st.divider()
    with st.expander("Sources and Citations", expanded=True):
        st.markdown(formatted_citations)

def Direct_Chat():
    if "collections" not in st.session_state:
        st.session_state.collections = fetch_collections()

    collections = st.session_state.collections
    chat_tab, pipeline_tab, doc_upload_tab, history_tab = st.tabs([
        "Chat with AI", "Agent Pipeline", "Upload Documents", "Chat History"
    ])

    with chat_tab:
        col1, col2 = st.columns([2, 1])
        with col1:
            mode = st.selectbox("Select AI Model:", list(model_key_map.keys()), key="chat_model")
            if model_key_map[mode] in model_descriptions:
                st.info(model_descriptions[model_key_map[mode]])

        use_rag = st.checkbox("Use RAG (Retrieval Augmented Generation)", key="chat_use_rag")
        collection_name = None
        document_id = None

        if use_rag:
            if collections:
                collection_name = st.selectbox(
                    "Document Collection:", collections, key="chat_coll"
                )

                # Option to filter by specific document
                filter_by_doc = st.checkbox(
                    "Filter by specific document?",
                    key="filter_by_document",
                    help="Enable this to search within a specific document instead of the entire collection"
                )

                if filter_by_doc:
                    # Show document browser
                    browse_documents(key_prefix="chat_doc_browse")

                    # Document selector
                    if "documents" in st.session_state and st.session_state.documents:
                        doc_options = {}
                        for doc in st.session_state.documents:
                            if hasattr(doc, 'document_name'):
                                doc_name = doc.document_name
                                doc_id_val = doc.document_id
                            else:
                                doc_name = doc.get('document_name', 'Unknown')
                                doc_id_val = doc.get('id', doc.get('document_id', ''))
                            if doc_id_val:
                                display_name = f"{doc_name} (ID: {doc_id_val[:8]}...)"
                                doc_options[display_name] = doc_id_val

                        if doc_options:
                            selected_display = st.selectbox(
                                "Select Document:",
                                options=list(doc_options.keys()),
                                key="chat_document_selector"
                            )
                            document_id = doc_options[selected_display]
                            st.info(f" Will search within: {selected_display}")
                        else:
                            st.warning("No documents found in this collection.")
                    else:
                        st.info("Load documents using the button above to see available documents.")
            else:
                st.warning("No collections available. Upload docs first.")

        user_input = st.text_area(
            "Ask your question:", height=100,
            placeholder="e.g. Summarize the latest uploaded document"
        )

        if st.button("Get Analysis", type="primary", key="chat_button"):
            if not user_input:
                st.warning("Please enter a question.")
            elif use_rag and not collection_name:
                st.error("Please select a collection for RAG mode.")
            else:
                with st.spinner(f"{mode} is analyzing..."):
                    try:
                        # If document_id is set, use document evaluation endpoint
                        # Otherwise use regular chat endpoint
                        if document_id:
                            # Document-specific evaluation
                            data = chat_service.evaluate_document(
                                document_id=document_id,
                                collection_name=collection_name,
                                prompt=user_input,
                                model_name=model_key_map[mode],
                                top_k=5
                            )
                            answer = data.get("response", "")
                            rt_ms = data.get("response_time_ms", 0)
                            session_id = data.get("session_id", "N/A")
                            formatted_citations = data.get("formatted_citations", "")

                            st.success("Analysis Complete (Document-Specific)")

                            # Debug information
                            st.info(f"Response length: {len(answer) if answer else 0} characters")

                            if answer and len(answer.strip()) > 0:
                                st.markdown("### Analysis Results")
                                st.markdown(answer)
                            else:
                                st.warning("No response generated or response is empty.")
                                st.write("**Full response data:**")
                                st.json(data)

                            st.caption(f"Response time: {rt_ms/1000:.2f}s")
                            st.caption(f"Session ID: {session_id}")
                            display_citations(formatted_citations)
                        else:
                            # Regular chat (with optional RAG across entire collection)
                            response = chat_service.send_message(
                                query=user_input,
                                model=model_key_map[mode],
                                use_rag=use_rag,
                                collection_name=collection_name
                            )
                            st.success("Analysis Complete:")
                            st.markdown(response.response)
                            if response.response_time_ms:
                                st.caption(f"Response time: {response.response_time_ms/1000:.2f}s")
                            if hasattr(response, 'session_id') and response.session_id:
                                st.caption(f"Session ID: {response.session_id}")

                            # Display citations if available (RAG mode)
                            formatted_citations = getattr(response, 'formatted_citations', '') or ''
                            display_citations(formatted_citations)
                    except Exception as e:
                        st.error(f"Request failed: {e}")

    with pipeline_tab:
        _render_agent_pipeline_tab(collections)

    with doc_upload_tab:
        st.header("Upload Documents for RAG")
        render_upload_component(
            available_collections=collections,
            load_collections_func=lambda: st.session_state.collections,
            create_collection_func=chromadb_service.create_collection,
            upload_endpoint=f"{CHROMADB_API}/documents/upload-and-process",
            job_status_endpoint=f"{CHROMADB_API}/jobs/{{job_id}}",
            key_prefix="eval"
        )

    with history_tab:
        Chat_History(key_prefix="direct_chat")


def _render_agent_pipeline_tab(collections: List[str]):
    """
    Render the Agent Pipeline tab for running agent set pipelines with RAG support.
    """
    st.subheader("Agent Set Pipeline with RAG")
    st.caption("Run a complete agent pipeline on your query, enhanced with document context from your collections")

    # Check for active pipeline
    if "direct_chat_pipeline_id" in st.session_state and st.session_state.direct_chat_pipeline_id:
        _show_pipeline_status_direct_chat(st.session_state.direct_chat_pipeline_id)
        return

    # Fetch agent sets
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

    # --- Agent Set Selection ---
    col1, col2 = st.columns([2, 1])
    with col1:
        agent_set_options = [s['name'] for s in active_agent_sets]
        selected_agent_set_name = st.selectbox(
            "Select Agent Set Pipeline",
            options=agent_set_options,
            key="dc_pipeline_agent_set",
            help="Choose an agent set to process your query"
        )
    with col2:
        agent_set = next((s for s in active_agent_sets if s['name'] == selected_agent_set_name), None)
        if agent_set:
            st.metric("Usage Count", agent_set.get('usage_count', 0))

    # Show agent set details
    if agent_set:
        with st.expander("View Pipeline Configuration", expanded=False):
            st.write(f"**Description:** {agent_set.get('description', 'No description')}")
            stages = agent_set.get('set_config', {}).get('stages', [])
            st.write(f"**Stages ({len(stages)}):**")
            for idx, stage in enumerate(stages, 1):
                st.write(f"  {idx}. **{stage.get('stage_name', f'Stage {idx}')}** - {len(stage.get('agent_ids', []))} agent(s)")

    st.markdown("---")

    # --- RAG Configuration ---
    st.subheader("RAG Context (Optional)")
    use_rag = st.checkbox(
        "Use RAG Context from Documents",
        value=True,
        key="dc_pipeline_use_rag",
        help="Enhance agent analysis with relevant context from your document collections"
    )

    rag_collection = None
    rag_document_id = None
    rag_top_k = 5

    if use_rag:
        if collections:
            rag_collection = st.selectbox(
                "Document Collection",
                collections,
                key="dc_pipeline_collection",
                help="Select the collection to retrieve context from"
            )

            col1, col2 = st.columns(2)
            with col1:
                rag_top_k = st.slider(
                    "Number of context chunks",
                    min_value=1,
                    max_value=20,
                    value=5,
                    key="dc_pipeline_top_k",
                    help="Number of relevant document chunks to include as context"
                )

            with col2:
                filter_by_doc = st.checkbox(
                    "Filter by specific document",
                    key="dc_pipeline_filter_doc"
                )

            if filter_by_doc:
                browse_documents(key_prefix="dc_pipeline_browse")
                if "documents" in st.session_state and st.session_state.documents:
                    doc_options = {}
                    for doc in st.session_state.documents:
                        doc_name = doc.get('document_name', 'Unknown') if isinstance(doc, dict) else getattr(doc, 'document_name', 'Unknown')
                        doc_id_val = doc.get('document_id', doc.get('id', '')) if isinstance(doc, dict) else getattr(doc, 'document_id', '')
                        if doc_id_val:
                            display_name = f"{doc_name} (ID: {doc_id_val[:8]}...)"
                            doc_options[display_name] = doc_id_val
                    if doc_options:
                        selected_display = st.selectbox(
                            "Select Document:",
                            options=list(doc_options.keys()),
                            key="dc_pipeline_document"
                        )
                        rag_document_id = doc_options[selected_display]
        else:
            st.warning("No collections available. Upload documents first.")
            use_rag = False

    st.markdown("---")

    # --- Query Input ---
    st.subheader("Your Query")
    user_query = st.text_area(
        "Enter your question or content to analyze",
        height=150,
        placeholder="e.g., Generate test cases for the authentication requirements...",
        key="dc_pipeline_query"
    )

    # --- Processing Options ---
    col1, col2 = st.columns(2)
    with col1:
        title = st.text_input(
            "Result Title",
            value="Agent Pipeline Analysis",
            key="dc_pipeline_title"
        )
    with col2:
        section_mode = st.selectbox(
            "Section Mode",
            ["single", "auto"],
            key="dc_pipeline_section_mode",
            help="'single': Process as one section. 'auto': Detect sections in content."
        )

    st.markdown("---")

    # --- Run Button ---
    if st.button("Run Agent Pipeline", type="primary", key="dc_run_pipeline"):
        if not user_query or len(user_query.strip()) < 10:
            st.error("Please enter a query (at least 10 characters)")
            return

        if not agent_set:
            st.error("Please select an agent set")
            return

        if use_rag and not rag_collection:
            st.error("Please select a collection for RAG context")
            return

        payload = {
            "text_input": user_query,
            "agent_set_id": agent_set['id'],
            "title": title,
            "section_mode": section_mode,
            "use_rag": use_rag,
            "rag_collection": rag_collection,
            "rag_document_id": rag_document_id,
            "rag_top_k": rag_top_k
        }

        try:
            with st.spinner("Starting agent pipeline..."):
                response = api_client.post(
                    f"{config.fastapi_url}/api/agent-pipeline/run-async",
                    data=payload,
                    timeout=30
                )

            pipeline_id = response.get("pipeline_id")
            if pipeline_id:
                st.session_state.direct_chat_pipeline_id = pipeline_id
                st.success(f"Pipeline started: {pipeline_id}")
                time.sleep(1)
                st.rerun()
            else:
                st.error("Failed to start pipeline")
        except Exception as e:
            st.error(f"Failed to run pipeline: {e}")


def _show_pipeline_status_direct_chat(pipeline_id: str):
    """Show pipeline status in Direct Chat tab"""
    st.info(f"Active Pipeline: `{pipeline_id}`")

    try:
        status_response = api_client.get(
            f"{config.fastapi_url}/api/agent-pipeline/status/{pipeline_id}",
            timeout=10
        )

        status = status_response.get("status", "UNKNOWN")
        progress = status_response.get("progress", 0)
        progress_message = status_response.get("progress_message", "")

        status_emoji = {"COMPLETED": "✅", "PROCESSING": "⏳", "QUEUED": "📝", "FAILED": "❌"}.get(status, "❓")
        st.write(f"**Status:** {status_emoji} {status}")

        if status in ["PROCESSING", "QUEUED"]:
            st.progress(progress / 100)
            st.caption(progress_message)

            col1, col2 = st.columns(2)
            with col1:
                if st.button("Refresh Status", key="dc_refresh_status"):
                    st.rerun()
            with col2:
                if st.button("Cancel & Start New", key="dc_cancel_pipeline"):
                    del st.session_state.direct_chat_pipeline_id
                    st.rerun()

            time.sleep(5)
            st.rerun()

        elif status == "COMPLETED":
            st.success("Pipeline completed!")

            result_response = api_client.get(
                f"{config.fastapi_url}/api/agent-pipeline/result/{pipeline_id}",
                timeout=30
            )

            _display_pipeline_result_direct_chat(result_response)

            if st.button("Start New Pipeline", key="dc_new_pipeline"):
                del st.session_state.direct_chat_pipeline_id
                st.rerun()

        elif status == "FAILED":
            st.error(f"Pipeline failed: {status_response.get('error', 'Unknown error')}")
            if st.button("Start New Pipeline", key="dc_new_after_fail"):
                del st.session_state.direct_chat_pipeline_id
                st.rerun()

    except Exception as e:
        st.error(f"Failed to get pipeline status: {e}")
        if st.button("Clear & Start New", key="dc_clear_failed"):
            del st.session_state.direct_chat_pipeline_id
            st.rerun()


def _display_pipeline_result_direct_chat(result: dict):
    """Display pipeline result in Direct Chat"""
    # Summary metrics
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Sections", result.get("total_sections", 0))
    with col2:
        st.metric("Stages", result.get("total_stages_executed", 0))
    with col3:
        st.metric("Agents", result.get("total_agents_executed", 0))
    with col4:
        rag_used = result.get("rag_context_used", False)
        st.metric("RAG Context", "Yes" if rag_used else "No")

    if rag_used:
        st.caption(f"RAG Collection: {result.get('rag_collection', 'N/A')}")

    st.markdown("---")

    # Consolidated output
    st.subheader("Analysis Results")
    consolidated = result.get("consolidated_output", "")

    st.download_button(
        label="Download as Markdown",
        data=consolidated,
        file_name=f"{result.get('title', 'result')}.md",
        mime="text/markdown",
        key="dc_download_result"
    )

    with st.expander("View Full Output", expanded=True):
        st.markdown(consolidated)

    # Display citations if RAG was used and citations are available
    if rag_used:
        formatted_citations = result.get("formatted_citations", "")
        if formatted_citations:
            display_citations(formatted_citations)

