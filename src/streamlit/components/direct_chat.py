import streamlit as st
from config.settings import config
from config.constants import MODEL_KEY_MAP as model_key_map, MODEL_DESCRIPTIONS as model_descriptions
from lib.api.client import api_client
from services.chromadb_service import chromadb_service
from services.chat_service import chat_service
from components.upload_documents import render_upload_component, browse_documents
from components.history import Chat_History
from typing import List, Dict, Any

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
    chat_tab, doc_upload_tab, history_tab = st.tabs([
        "Chat with AI", "Upload Documents", "Chat History"
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

