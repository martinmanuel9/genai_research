"""
Unified Agent Manager Component

Single component for managing ALL agents and agent sets in the system.
All agents and agent sets are database-backed.

Supports:
- Individual Agents: Actor, Critic, Contradiction Detection, Gap Analysis, Custom
- Agent Sets: Orchestration pipelines combining multiple agents
- Full CRUD operations for both agents and agent sets
"""

import streamlit as st
from config.settings import config
from app_lib.api.client import api_client
import json
from datetime import datetime
from typing import Optional, Dict, List
from collections import Counter

# API endpoints - unified database-backed system
TEST_PLAN_AGENT_API = f"{config.fastapi_url}/api/test-plan-agents"
AGENT_SET_API = f"{config.fastapi_url}/api/agent-sets"


def render_unified_agent_manager():
    """
    Main entry point for Unified Agent Manager.
    Manages both individual agents and agent sets (orchestration pipelines).
    """
    st.title("Agent & Orchestration Manager")
    st.markdown("""
    **Agents**: Individual AI agents with specific roles (Actor, Critic, QA, etc.)
    
    **Agent Sets**: Orchestration pipelines that combine multiple agents in stages
    """)

    # Top-level navigation: Agents vs Agent Sets
    main_tab1, main_tab2 = st.tabs(["Individual Agents", "Agent Sets and Pipelines"])

    with main_tab1:
        # Sub-tabs for agent management
        agent_tab1, agent_tab2, agent_tab3, agent_tab4 = st.tabs([
            "View Agents",
            "Create Agent",
            "Manage Agents",
            "Help & Info"
        ])

        with agent_tab1:
            render_agent_list_view()

        with agent_tab2:
            render_create_agent_form()

        with agent_tab3:
            render_manage_agents_view()

        with agent_tab4:
            render_help_info()

    with main_tab2:
        # Sub-tabs for agent set management
        set_tab1, set_tab2, set_tab3 = st.tabs([
            "View Agent Sets",
            "Create Agent Set",
            "Analytics"
        ])

        with set_tab1:
            render_view_agent_sets()

        with set_tab2:
            render_create_agent_set()

        with set_tab3:
            render_agent_set_analytics()


def fetch_agents_cached(agent_type_filter: str = "All", include_inactive: bool = False, force_refresh: bool = False):
    """
    Fetch agents with session state caching for better UX.

    Args:
        agent_type_filter: Filter by agent type or "All"
        include_inactive: Include inactive agents
        force_refresh: Force refresh from API

    Returns:
        Tuple of (agents list, total_count)
    """
    # Create cache key based on filters
    cache_key = f"agents_{agent_type_filter}_{include_inactive}"

    # Check if we need to fetch (first time or forced refresh)
    if force_refresh or cache_key not in st.session_state:
        params = {"include_inactive": include_inactive}
        if agent_type_filter != "All":
            params["agent_type"] = agent_type_filter

        try:
            response = api_client.get(TEST_PLAN_AGENT_API, params=params)
            if response and "agents" in response:
                agents = response["agents"]
                total_count = response.get("total_count", len(agents))

                # Cache the results
                st.session_state[cache_key] = {
                    "agents": agents,
                    "total_count": total_count,
                    "timestamp": datetime.now()
                }
                return agents, total_count
            else:
                return [], 0
        except Exception as e:
            st.error(f"Error loading agents: {str(e)}")
            return [], 0
    else:
        # Return cached results
        cached = st.session_state[cache_key]
        return cached["agents"], cached["total_count"]


def render_agent_list_view():
    """
    Display list of agents with filtering options and auto-load.
    """
    st.subheader("Agent List")

    # Filters
    col1, col2, col3 = st.columns([2, 1, 1])

    with col1:
        agent_type_filter = st.selectbox(
            "Filter by Agent Type",
            ["All", "actor", "critic", "contradiction", "gap_analysis", "general", "rule_development"],
            key="agent_type_filter",
            help="Filter agents by their type"
        )

    with col2:
        include_inactive = st.checkbox("Include Inactive", value=False, key="include_inactive")

    with col3:
        force_refresh = st.button("Refresh", use_container_width=True)

    # Fetch agents (cached on first load, refreshed on button click)
    try:
        with st.spinner("Loading agents..." if force_refresh else None):
            agents, total_count = fetch_agents_cached(
                agent_type_filter,
                include_inactive,
                force_refresh=force_refresh
            )

        if agents:
            st.success(f"Found {total_count} agent(s)")

            # Display agents grouped by type
            agent_types = {}
            for agent in agents:
                agent_type = agent["agent_type"]
                if agent_type not in agent_types:
                    agent_types[agent_type] = []
                agent_types[agent_type].append(agent)

            # Render each agent type group
            for agent_type, type_agents in agent_types.items():
                with st.expander(f"**{agent_type.upper()}** ({len(type_agents)} agents)", expanded=True):
                    for agent in type_agents:
                        render_agent_card(agent)
        else:
            st.info("No agents found. Create one using the 'Create Agent' tab.")

    except Exception as e:
        st.error(f"Error loading agents: {str(e)}")


def render_agent_card(agent: Dict):
    """
    Render a single agent card with details and quick actions.
    """
    # Status badge
    status_color = "[ACTIVE]" if agent["is_active"] else "[INACTIVE]"
    default_badge = "System Default" if agent["is_system_default"] else "Custom"

    col1, col2 = st.columns([3, 1])

    with col1:
        st.markdown(f"### {status_color} {agent['name']}")
        workflow_badge = agent.get('workflow_type', 'general').replace('_', ' ').title()
        st.markdown(f"*{default_badge}* | **{workflow_badge}** | Model: **{agent['model_name']}**")

    with col2:
        st.markdown(f"**ID:** {agent['id']}")
        st.markdown(f"**Active:** {'Yes' if agent['is_active'] else 'No'}")

    # Details in columns
    detail_col1, detail_col2 = st.columns(2)

    with detail_col1:
        st.markdown(f"**Temperature:** {agent['temperature']}")
        st.markdown(f"**Max Tokens:** {agent['max_tokens']}")

        if agent.get('description'):
            st.markdown(f"**Description:** {agent['description']}")

    with detail_col2:
        st.markdown(f"**Created:** {agent.get('created_at', 'N/A')[:10]}")
        st.markdown(f"**Updated:** {agent.get('updated_at', 'N/A')[:10]}")
        if agent.get('created_by'):
            st.markdown(f"**Created By:** {agent['created_by']}")

    # Expandable prompts
    with st.expander("View Prompts"):
        st.text_area("System Prompt", agent['system_prompt'], height=150, disabled=True, key=f"sys_{agent['id']}")
        st.text_area("User Prompt Template", agent['user_prompt_template'], height=150, disabled=True, key=f"usr_{agent['id']}")

    st.markdown("---")


def render_create_agent_form():
    """
    Form to create a new agent with template auto-population.
    """
    st.subheader("Create a New Agent")

    st.info("💡 **Tip**: Select a workflow type and agent type below, and we'll auto-populate the form with a proven template you can customize!")

    # Fetch system default agents for template loading
    try:
        response = api_client.get(TEST_PLAN_AGENT_API, params={"include_inactive": False})
        all_agents = response.get("agents", []) if response else []
        system_defaults = [a for a in all_agents if a.get("is_system_default", False)]
    except:
        system_defaults = []

    # Workflow type selection (helps users understand purpose)
    workflow_type = st.selectbox(
        "Workflow Type",
        ["document_analysis", "test_plan_generation", "general"],
        help="Select the workflow this agent will be used for",
        key="create_workflow_type"
    )

    # Show workflow-specific guidance
    workflow_info = {
        "document_analysis": {
            "description": "Single agent document compliance checks and analysis",
            "placeholders": "{data_sample}",
            "examples": "Compliance Checker, Requirements Extractor, Technical Reviewer"
        },
        "test_plan_generation": {
            "description": "Multi-agent pipeline for test plan generation",
            "placeholders": "{section_title}, {section_content}, {actor_outputs}, {critic_output}",
            "examples": "Actor, Critic, Contradiction Detector, Gap Analyzer"
        },
        "general": {
            "description": "General purpose agent with flexible configuration",
            "placeholders": "Custom placeholders as needed",
            "examples": "Custom analyzer, specialized reviewer"
        }
    }

    info = workflow_info[workflow_type]
    st.info(f"""
    **{workflow_type.upper().replace('_', ' ')}**

    {info['description']}

    **Required Placeholders:** `{info['placeholders']}`

    **Examples:** {info['examples']}
    """)

    # Agent type selection - filtered by workflow type
    agent_type_options = {
        "document_analysis": ["compliance", "custom"],
        "test_plan_generation": ["actor", "critic", "contradiction", "gap_analysis"],
        "general": ["general", "rule_development", "custom"]
    }

    agent_type = st.selectbox(
        "Agent Type",
        agent_type_options.get(workflow_type, ["custom"]),
        help="Select the specific role this agent will play",
        key="create_agent_type"
    )

    # Show type-specific info
    type_info = {
        "actor": "Extracts testable requirements from document sections with detailed analysis",
        "critic": "Synthesizes and deduplicates outputs from multiple actor agents",
        "contradiction": "Detects contradictions and conflicts in test procedures",
        "gap_analysis": "Identifies missing requirements and test coverage gaps",
        "general": "General purpose agent for systems/quality/test engineering",
        "rule_development": "Specialized in document analysis and test plan creation",
        "compliance": "Evaluates documents for compliance with requirements and standards",
        "custom": "Custom agent with user-defined behavior"
    }
    st.caption(f"**{agent_type.upper()}**: {type_info.get(agent_type, '')}")

    # Find matching system default template
    template_agent = None
    for agent in system_defaults:
        if agent.get('workflow_type') == workflow_type and agent.get('agent_type') == agent_type:
            template_agent = agent
            break

    # Set default values from template
    default_model = template_agent.get('model_name', 'gpt-4') if template_agent else 'gpt-4'
    default_temp = template_agent.get('temperature', 0.7) if template_agent else 0.7
    default_max_tokens = template_agent.get('max_tokens', 4000) if template_agent else 4000
    default_description = template_agent.get('description', '') if template_agent else ''
    default_system_prompt = template_agent.get('system_prompt', '') if template_agent else ''
    default_user_prompt = template_agent.get('user_prompt_template', '') if template_agent else ''

    if template_agent:
        st.success(f"Template loaded: **{template_agent['name']}**")
        st.caption(f"Form is pre-filled with this template. Customize as needed and give it a unique name.")
    else:
        st.warning("No system template found for this combination. You'll need to write prompts from scratch.")

    with st.form("create_agent_form"):
        col1, col2 = st.columns(2)

        with col1:
            name = st.text_input(
                "Agent Name *",
                placeholder="e.g., 'My Custom Actor Agent'",
                help="Give your agent a unique name"
            )

            available_models = config.get_available_models()
            model_index = available_models.index(default_model) if default_model in available_models else 0
            model_name = st.selectbox(
                "LLM Model *",
                available_models,
                index=model_index,
                help="Select the language model to use"
            )

            temperature = st.slider(
                "Temperature",
                0.0, 1.0,
                float(default_temp),
                0.1,
                help="Lower = more focused, Higher = more creative"
            )

            max_tokens = st.number_input(
                "Max Tokens",
                100, 32000,
                int(default_max_tokens),
                100,
                help="Maximum response length"
            )

        with col2:
            description = st.text_area(
                "Description",
                value=default_description,
                height=100,
                placeholder="Brief description of this agent's purpose"
            )
            is_active = st.checkbox("Active", value=True, help="Whether this agent is active")
            created_by = st.text_input("Created By", placeholder="Your name (optional)")

        system_prompt = st.text_area(
            "System Prompt *",
            value=default_system_prompt,
            height=200,
            placeholder="Define the agent's role, expertise, and behavior...",
            help="Core instructions that define the agent's personality and capabilities"
        )

        user_prompt_template = st.text_area(
            "User Prompt Template *",
            value=default_user_prompt,
            height=200,
            placeholder="Template for user interactions. Use appropriate placeholders.",
            help="Template that will be filled with actual data during execution"
        )

        # Submit button
        submitted = st.form_submit_button("Create Agent", type="primary", use_container_width=True)

        if submitted:
            # Validation
            if not name or len(name.strip()) < 3:
                st.error("Agent name must be at least 3 characters")
            elif not system_prompt or len(system_prompt.strip()) < 10:
                st.error("System prompt must be at least 10 characters")
            elif not user_prompt_template or len(user_prompt_template.strip()) < 10:
                st.error("User prompt template must be at least 10 characters")
            else:
                # Prepare payload
                payload = {
                    "name": name.strip(),
                    "agent_type": agent_type,
                    "workflow_type": workflow_type,
                    "model_name": model_name,
                    "system_prompt": system_prompt.strip(),
                    "user_prompt_template": user_prompt_template.strip(),
                    "temperature": temperature,
                    "max_tokens": max_tokens,
                    "is_active": is_active,
                    "is_system_default": False,
                    "description": description.strip() if description else None,
                    "created_by": created_by.strip() if created_by else None
                }

                try:
                    with st.spinner("Creating agent..."):
                        response = api_client.post(TEST_PLAN_AGENT_API, data=payload)

                        if response:
                            st.success(f"Agent '{name}' created successfully!")
                            # Clear cache to force refresh
                            for key in list(st.session_state.keys()):
                                if key.startswith("agents_"):
                                    del st.session_state[key]
                        else:
                            st.error("Failed to create agent")
                except Exception as e:
                    st.error(f"Error creating agent: {str(e)}")


def render_manage_agents_view():
    """
    Manage existing agents (edit, delete, clone, activate/deactivate).
    """
    st.subheader("Manage Existing Agents")

    # Add refresh button
    col1, col2 = st.columns([4, 1])
    with col2:
        force_refresh = st.button("🔄 Refresh List", use_container_width=True)

    # Fetch all agents
    agents, _ = fetch_agents_cached("All", include_inactive=True, force_refresh=force_refresh)

    if not agents:
        st.info("No agents found. Create one in the 'Create Agent' tab.")
        return

    # Agent selection
    agent_options = {f"{agent['name']} (ID: {agent['id']})": agent for agent in agents}
    selected_option = st.selectbox(
        "Select Agent to Manage",
        ["--Select Agent--"] + list(agent_options.keys()),
        key="manage_agent_selector"
    )

    if selected_option == "--Select Agent--":
        return

    agent = agent_options[selected_option]

    # Management actions
    action = st.radio(
        "Action",
        ["View Details", "Edit", "Clone", "Activate/Deactivate", "Delete"],
        horizontal=True,
        key="manage_agent_action"
    )

    if action == "View Details":
        render_view_details(agent)
    elif action == "Edit":
        render_edit_agent(agent)
    elif action == "Clone":
        render_clone_agent(agent)
    elif action == "Activate/Deactivate":
        render_toggle_active(agent)
    elif action == "Delete":
        render_delete_agent(agent)


def render_view_details(agent: Dict):
    """View full agent details."""
    st.subheader(f"Agent Details: {agent['name']}")

    col1, col2 = st.columns(2)

    with col1:
        st.json({
            "ID": agent['id'],
            "Name": agent['name'],
            "Type": agent['agent_type'],
            "Workflow": agent.get('workflow_type', 'N/A'),
            "Model": agent['model_name'],
            "Temperature": agent['temperature'],
            "Max Tokens": agent['max_tokens'],
            "Active": agent['is_active'],
            "System Default": agent['is_system_default']
        })

    with col2:
        st.json({
            "Created": agent.get('created_at'),
            "Updated": agent.get('updated_at'),
            "Created By": agent.get('created_by'),
            "Description": agent.get('description')
        })

    st.text_area("System Prompt", agent['system_prompt'], height=200, disabled=True)
    st.text_area("User Prompt Template", agent['user_prompt_template'], height=200, disabled=True)

    if agent.get('metadata'):
        st.json(agent['metadata'])


def render_edit_agent(agent: Dict):
    """Edit agent form."""
    st.subheader(f"Edit Agent: {agent['name']}")

    with st.form("edit_agent_form"):
        col1, col2 = st.columns(2)

        with col1:
            new_name = st.text_input("Agent Name", value=agent['name'])

            # Workflow type selection
            workflow_options = ["document_analysis", "test_plan_generation", "general"]
            current_workflow = agent.get('workflow_type', 'general')
            workflow_index = workflow_options.index(current_workflow) if current_workflow in workflow_options else 2
            new_workflow_type = st.selectbox(
                "Workflow Type",
                workflow_options,
                index=workflow_index,
                help="Select the workflow this agent will be used for"
            )

            new_model = st.selectbox(
                "Model",
                config.get_available_models(),
                index=config.get_available_models().index(agent['model_name']) if agent['model_name'] in config.get_available_models() else 0
            )
            new_temperature = st.slider("Temperature", 0.0, 1.0, agent['temperature'], 0.1)
            new_max_tokens = st.number_input("Max Tokens", 100, 32000, agent['max_tokens'], 100)

        with col2:
            new_description = st.text_area("Description", value=agent.get('description', ''), height=100)
            new_is_active = st.checkbox("Active", value=agent['is_active'])

        new_system_prompt = st.text_area("System Prompt", value=agent['system_prompt'], height=200)
        new_user_prompt = st.text_area("User Prompt Template", value=agent['user_prompt_template'], height=200)

        submitted = st.form_submit_button("Update Agent", type="primary")

        if submitted:
            payload = {
                "name": new_name,
                "workflow_type": new_workflow_type,
                "model_name": new_model,
                "system_prompt": new_system_prompt,
                "user_prompt_template": new_user_prompt,
                "temperature": new_temperature,
                "max_tokens": new_max_tokens,
                "is_active": new_is_active,
                "description": new_description if new_description else None
            }

            try:
                with st.spinner("Updating agent..."):
                    api_client.put(f"{TEST_PLAN_AGENT_API}/{agent['id']}", data=payload)
                    st.success("Agent updated successfully!")
                    # Clear cache
                    for key in list(st.session_state.keys()):
                        if key.startswith("agents_"):
                            del st.session_state[key]
                    st.rerun()
            except Exception as e:
                st.error(f"Error updating agent: {str(e)}")


def render_clone_agent(agent: Dict):
    """Clone agent form."""
    st.subheader(f"Clone Agent: {agent['name']}")
    st.info("Create a copy of this agent with a new name")

    with st.form("clone_agent_form"):
        new_name = st.text_input("New Agent Name", placeholder=f"{agent['name']} (Copy)")
        created_by = st.text_input("Created By", placeholder="Your name (optional)")

        submitted = st.form_submit_button("Clone Agent", type="primary")

        if submitted:
            if not new_name or len(new_name.strip()) < 3:
                st.error("New name must be at least 3 characters")
            else:
                payload = {"new_name": new_name.strip(), "created_by": created_by.strip() if created_by else None}
                try:
                    with st.spinner("Cloning agent..."):
                        api_client.post(f"{TEST_PLAN_AGENT_API}/{agent['id']}/clone", data=payload)
                        st.success(f"Agent cloned as '{new_name}'!")
                        for key in list(st.session_state.keys()):
                            if key.startswith("agents_"):
                                del st.session_state[key]
                        st.rerun()
                except Exception as e:
                    st.error(f"Error cloning agent: {str(e)}")


def render_toggle_active(agent: Dict):
    """Toggle agent active status."""
    st.subheader(f"Toggle Active Status: {agent['name']}")

    current_status = "Active" if agent['is_active'] else "Inactive"
    new_status = "Inactive" if agent['is_active'] else "Active"
    new_is_active = not agent['is_active']

    st.info(f"Current status: **{current_status}**")
    st.warning(f"This will change the status to: **{new_status}**")

    if st.button(f"Confirm: Set to {new_status}", type="primary"):
        try:
            with st.spinner(f"Setting agent to {new_status}..."):
                # Use the activate endpoint with is_active boolean
                api_client.post(f"{TEST_PLAN_AGENT_API}/{agent['id']}/activate", data={"is_active": new_is_active})
                st.success(f"Agent is now {new_status}")
                for key in list(st.session_state.keys()):
                    if key.startswith("agents_"):
                        del st.session_state[key]
                st.rerun()
        except Exception as e:
            st.error(f"Error updating status: {str(e)}")


def render_delete_agent(agent: Dict):
    """Delete agent with two-step workflow: deactivate first, then permanent delete."""
    st.subheader(f"Delete Agent: {agent['name']}")

    if agent['is_system_default']:
        st.error("Cannot delete system default agents")
        return

    # Two-step delete process
    if agent['is_active']:
        st.warning("**STEP 1: Deactivate First**")
        st.info("This agent is currently active. You must deactivate it before permanently deleting it.")

        with st.expander("Agent Details", expanded=True):
            st.json({
                "ID": agent['id'],
                "Name": agent['name'],
                "Type": agent['agent_type'],
                "Status": "ACTIVE",
                "Created": agent.get('created_at')
            })

        if st.button("Deactivate Agent", type="primary"):
            try:
                with st.spinner("Deactivating agent..."):
                    # Use the activate endpoint with is_active=False
                    api_client.post(f"{TEST_PLAN_AGENT_API}/{agent['id']}/activate", data={"is_active": False})
                    st.success("Agent deactivated. You can now permanently delete it if needed.")
                    # Clear cache
                    for key in list(st.session_state.keys()):
                        if key.startswith("agents_") or key == "manage_agent_selector":
                            del st.session_state[key]
                    st.rerun()
            except Exception as e:
                st.error(f"Error deactivating agent: {str(e)}")

    else:
        # Agent is already deactivated, allow permanent deletion
        st.error("**STEP 2: Permanent Deletion**")
        st.warning("This agent is deactivated. You can now permanently delete it if needed.")
        st.warning("**⚠️ PERMANENT ACTION**: Deleting an agent cannot be undone.")

        with st.expander("Agent to be deleted", expanded=True):
            st.json({
                "ID": agent['id'],
                "Name": agent['name'],
                "Type": agent['agent_type'],
                "Status": "INACTIVE",
                "Created": agent.get('created_at')
            })

        confirm_name = st.text_input(f"Type '{agent['name']}' to confirm permanent deletion:")
        confirm_check = st.checkbox("I understand this action is permanent and cannot be undone")

        if confirm_name == agent['name'] and confirm_check:
            if st.button("⚠️ Permanently Delete Agent", type="secondary"):
                try:
                    with st.spinner("Permanently deleting agent..."):
                        # Use soft_delete=false for permanent deletion
                        api_client.delete(f"{TEST_PLAN_AGENT_API}/{agent['id']}?soft_delete=false")
                        st.success("Agent permanently deleted")
                        # Clear all agent-related cache and selector state
                        for key in list(st.session_state.keys()):
                            if key.startswith("agents_") or key == "manage_agent_selector":
                                del st.session_state[key]
                        st.rerun()
                except Exception as e:
                    st.error(f"Error deleting agent: {str(e)}")


def render_help_info():
    """Display help and best practices."""
    st.subheader("Agent Management Guide")

    st.markdown("""
    ## Understanding Workflow Type vs Agent Type

    ### Workflow Type (PURPOSE)
    **What workflow will use this agent?**

    - **Document Analysis**: Single-agent compliance checks on existing documents
      - Endpoint: `/api/agent/compliance-check`
      - Placeholders: `{data_sample}`
      - Use case: Analyze a document for compliance, extract requirements, technical review

    - **Test Plan Generation**: Multi-agent pipeline to create test plans
      - Endpoint: `/api/doc/generate_optimized_test_plan`
      - Placeholders: `{section_title}`, `{section_content}`, `{actor_outputs}`, `{critic_output}`
      - Use case: Generate comprehensive test plans from military standards

    - **General**: Flexible agents for custom workflows
      - Placeholders: Custom as needed
      - Use case: Your own specialized workflows

    ### Agent Type (ROLE)
    **What role does this agent play within its workflow?**

    #### For Test Plan Generation:
    - **Actor**: Extracts testable requirements (runs first, in parallel)
    - **Critic**: Synthesizes actor outputs (runs after actors)
    - **Contradiction**: Detects conflicts across sections
    - **Gap Analysis**: Identifies missing test coverage

    #### For Document Analysis:
    - **Compliance**: Evaluates compliance with standards
    - **Custom**: Specialized analysis (requirements extraction, technical review, etc.)

    #### For General:
    - **General**: Multi-purpose engineering agent
    - **Rule Development**: Specialized in document analysis
    - **Custom**: User-defined behavior

    ## Creating Agents

    ### Quick Start (Recommended)
    1. Select **Workflow Type** (document_analysis, test_plan_generation, or general)
    2. Select **Agent Type** (role within that workflow)
    3. Form auto-populates with proven template
    4. Customize the template and give it a unique name
    5. Click Create!

    ### Alternative: Clone Existing Agent
    Instead of creating from scratch, go to "Manage Agents" → Select agent → "Clone"

    ## Best Practices

    ### System Prompts
    - Define clear expertise areas
    - Include analysis frameworks
    - Specify output formats
    - Reference relevant standards
    - Use bullet points for clarity

    ### User Prompt Templates
    - **CRITICAL**: Use correct placeholders for your workflow type
    - Document Analysis → `{data_sample}`
    - Test Plan Generation → `{section_title}`, `{section_content}`, etc.
    - Provide clear instructions
    - Specify desired output structure

    ### Temperature Settings
    - **0.1-0.3**: Consistent, factual (compliance checks)
    - **0.4-0.7**: Balanced (general work)
    - **0.8-1.0**: Creative (brainstorming)

    ### Model Selection
    - **GPT-4**: Recommended for most use cases
    - **GPT-4o**: Faster, good for simpler tasks
    - **Claude**: Alternative for specific tasks
    - Consider cost vs. quality trade-offs

    ## Management Tips
    - Use system default agents as templates
    - Clone agents before making major changes
    - Review agent performance regularly
    - Deactivate unused agents
    - Test after making changes
    """)

# ======================================================================
# AGENT SET MANAGEMENT FUNCTIONS
# ======================================================================

def render_view_agent_sets():
    """View and manage existing agent sets with detailed agent information"""
    st.subheader("Existing Agent Sets")

    # Filter options
    col1, col2, col3 = st.columns([2, 1, 1])
    with col1:
        search_term = st.text_input("Search by name", key="agent_set_search")
    with col2:
        show_inactive = st.checkbox("Show inactive", value=False, key="show_inactive_sets")
    with col3:
        if st.button("🔄 Refresh", use_container_width=True):
            # Clear any cached data and force rerun
            for key in list(st.session_state.keys()):
                if key.startswith(("clone_set_", "edit_set_", "delete_set_")):
                    st.session_state.pop(key)
            st.rerun()

    # Fetch agent sets with include_inactive parameter
    try:
        response = api_client.get(AGENT_SET_API, params={"include_inactive": show_inactive})
        agent_sets = response.get("agent_sets", [])
    except Exception as e:
        st.error(f"Failed to load agent sets: {e}")
        return

    if not agent_sets:
        if show_inactive:
            st.info("No agent sets found (including inactive). Create your first agent set using the 'Create Agent Set' tab!")
        else:
            st.info("No active agent sets found. Try checking 'Show inactive' or create a new agent set!")
        return

    # Apply search filter
    filtered_sets = agent_sets
    if search_term:
        filtered_sets = [s for s in filtered_sets if search_term.lower() in s.get('name', '').lower()]

    # Show filter stats
    active_count = len([s for s in filtered_sets if s.get('is_active', True)])
    inactive_count = len([s for s in filtered_sets if not s.get('is_active', True)])
    st.write(f"**Total Agent Sets:** {len(filtered_sets)} (Active: {active_count}, Inactive: {inactive_count})")

    # Fetch all agents for detailed display
    try:
        agents_response = api_client.get(TEST_PLAN_AGENT_API)
        all_agents = agents_response.get("agents", [])
        agent_map = {a['id']: a for a in all_agents}
    except Exception as e:
        st.warning(f"Could not load agent details: {e}")
        agent_map = {}

    # Display agent sets
    for agent_set in filtered_sets:
        prefix = "[System Default]" if agent_set.get('is_system_default') else "[Custom]"
        status = "[INACTIVE]" if not agent_set.get('is_active', True) else ""
        with st.expander(f"{prefix} {status} {agent_set['name']}", expanded=False):
            col1, col2 = st.columns([3, 1])

            with col1:
                st.write(f"**Description:** {agent_set.get('description', 'No description')}")
                st.write(f"**Type:** {agent_set.get('set_type', 'sequence')}")
                st.write(f"**Usage Count:** {agent_set.get('usage_count', 0)}")
                st.write(f"**Active:** {'Yes' if agent_set.get('is_active') else 'No'}")
                st.write(f"**System Default:** {'Yes' if agent_set.get('is_system_default') else 'No'}")

                # Show pipeline configuration with detailed agent info
                st.write("**Pipeline Stages:**")
                stages = agent_set.get('set_config', {}).get('stages', [])
                for idx, stage in enumerate(stages, 1):
                    st.markdown(f"**Stage {idx}: {stage.get('stage_name')}**")
                    st.write(f"- Execution Mode: {stage.get('execution_mode')}")
                    if stage.get('description'):
                        st.caption(f"{stage.get('description')}")

                    # Show agent details
                    agent_ids = stage.get('agent_ids', [])
                    if agent_ids:
                        agent_counts = Counter(agent_ids)
                        st.write(f"- Agents ({len(agent_ids)} total):")

                        for agent_id, count in agent_counts.items():
                            agent = agent_map.get(agent_id)
                            if agent:
                                with st.container(border=True):
                                    st.markdown(f"**{agent['name']}** (x{count})")

                                    col_a, col_b = st.columns(2)
                                    with col_a:
                                        st.write(f"Type: {agent.get('agent_type', 'N/A')}")
                                        st.write(f"Model: {agent.get('model_name', 'N/A')}")
                                        st.write(f"Temperature: {agent.get('temperature', 0.0)}")
                                    with col_b:
                                        st.write(f"Max Tokens: {agent.get('max_tokens', 'N/A')}")
                                        st.write(f"Active: {'Yes' if agent.get('is_active') else 'No'}")

                                    # Show prompts
                                    with st.expander(f"View Prompts - {agent['name']}"):
                                        st.markdown("**System Prompt:**")
                                        st.code(agent.get('system_prompt', 'No system prompt'), language="text")
                                        st.markdown("**User Prompt Template:**")
                                        st.code(agent.get('user_prompt_template', 'No user prompt template'), language="text")
                            else:
                                st.warning(f"Agent ID {agent_id} not found (x{count})")
                    st.markdown("---")

            with col2:
                st.write("**Actions:**")

                # Clone button
                if st.button("Clone", key=f"clone_{agent_set['id']}"):
                    st.session_state[f'clone_set_{agent_set["id"]}'] = True

                # Edit button (not for system defaults)
                if not agent_set.get('is_system_default'):
                    if st.button("Edit", key=f"edit_{agent_set['id']}"):
                        st.session_state[f'edit_set_{agent_set["id"]}'] = True

                # Activate/Deactivate button
                if agent_set.get('is_active'):
                    if st.button("Deactivate", key=f"deactivate_{agent_set['id']}"):
                        if deactivate_agent_set(agent_set['id']):
                            st.rerun()
                else:
                    if st.button("Activate", key=f"activate_{agent_set['id']}"):
                        if activate_agent_set(agent_set['id']):
                            st.rerun()

                # Delete button (not for system defaults)
                if not agent_set.get('is_system_default'):
                    if st.button("Delete", key=f"delete_{agent_set['id']}", type="secondary"):
                        st.session_state[f'delete_set_{agent_set["id"]}'] = True

            # Handle clone dialog
            if st.session_state.get(f'clone_set_{agent_set["id"]}'):
                st.write("---")
                st.subheader("Clone Agent Set")
                new_name = st.text_input(
                    "New name for cloned set:",
                    value=f"{agent_set['name']} (Copy)",
                    key=f"clone_name_{agent_set['id']}"
                )

                if not new_name or len(new_name.strip()) < 3:
                    st.warning("Name must be at least 3 characters")

                col_a, col_b = st.columns(2)
                with col_a:
                    if st.button("Confirm Clone", key=f"confirm_clone_{agent_set['id']}", type="primary", disabled=not new_name or len(new_name.strip()) < 3):
                        if clone_agent_set(agent_set['id'], new_name.strip()):
                            st.session_state.pop(f'clone_set_{agent_set["id"]}')
                            st.rerun()
                with col_b:
                    if st.button("Cancel Clone", key=f"cancel_clone_{agent_set['id']}"):
                        st.session_state.pop(f'clone_set_{agent_set["id"]}')
                        st.rerun()

            # Handle edit dialog
            if st.session_state.get(f'edit_set_{agent_set["id"]}'):
                st.write("---")
                st.info("Edit functionality: Use the form below to modify the agent set")
                # TODO: Add full edit implementation
                if st.button("Cancel Edit", key=f"cancel_edit_{agent_set['id']}"):
                    st.session_state.pop(f'edit_set_{agent_set["id"]}')
                    st.rerun()

            # Handle delete confirmation dialog
            if st.session_state.get(f'delete_set_{agent_set["id"]}'):
                st.write("---")

                # Two-step delete process
                if agent_set.get('is_active', True):
                    # Step 1: Deactivate first
                    st.warning("**STEP 1: Deactivate First**")
                    st.info(f"This agent set is currently active. You must deactivate it before permanently deleting it.")

                    col_a, col_b = st.columns(2)
                    with col_a:
                        if st.button("Deactivate Agent Set", key=f"deactivate_for_delete_{agent_set['id']}", type="primary"):
                            if deactivate_agent_set(agent_set['id']):
                                st.success("Agent set deactivated. Refresh to see the permanent delete option.")
                                st.session_state.pop(f'delete_set_{agent_set["id"]}')
                                st.rerun()
                    with col_b:
                        if st.button("Cancel", key=f"cancel_delete_{agent_set['id']}"):
                            st.session_state.pop(f'delete_set_{agent_set["id"]}')
                            st.rerun()
                else:
                    # Step 2: Permanent deletion for inactive sets
                    st.error("**STEP 2: Permanent Deletion**")
                    st.warning(f"This agent set is deactivated. You can now permanently delete it if needed.")
                    st.warning("**⚠️ PERMANENT ACTION**: Deleting an agent set cannot be undone.")

                    confirm_name = st.text_input(
                        f"Type '{agent_set['name']}' to confirm permanent deletion:",
                        key=f"delete_confirm_name_{agent_set['id']}"
                    )

                    col_a, col_b = st.columns(2)
                    with col_a:
                        if confirm_name == agent_set['name']:
                            if st.button("⚠️ Permanently Delete Agent Set", key=f"confirm_delete_{agent_set['id']}", type="secondary"):
                                if delete_agent_set(agent_set['id'], permanent=True):
                                    # Clean up all session state related to this agent set
                                    st.session_state.pop(f'delete_set_{agent_set["id"]}', None)
                                    st.session_state.pop(f'clone_set_{agent_set["id"]}', None)
                                    st.session_state.pop(f'edit_set_{agent_set["id"]}', None)
                                    st.rerun()
                        else:
                            st.button("⚠️ Permanently Delete Agent Set", key=f"confirm_delete_{agent_set['id']}", type="secondary", disabled=True)
                    with col_b:
                        if st.button("Cancel", key=f"cancel_delete_final_{agent_set['id']}"):
                            st.session_state.pop(f'delete_set_{agent_set["id"]}')
                            st.rerun()


def render_create_agent_set():
    """Create a new agent set"""
    st.subheader("Create New Agent Set")

    # Fetch available agents (outside form)
    try:
        agents_response = api_client.get(TEST_PLAN_AGENT_API)
        available_agents = agents_response.get("agents", [])
        active_agents = [a for a in available_agents if a.get('is_active', True)]
    except Exception as e:
        st.error(f"Failed to load agents: {e}")
        active_agents = []

    if not active_agents:
        st.error("No active agents available. Please create agents first in the 'Individual Agents' tab.")
        return

    # Initialize stages in session state
    if 'new_set_stages' not in st.session_state:
        st.session_state.new_set_stages = []

    # Stage builder (OUTSIDE FORM - has buttons)
    st.markdown("---")
    st.subheader("Pipeline Stages")
    st.info("Add stages to define your pipeline. Each stage can have multiple agents.")

    # Display current stages
    for idx, stage in enumerate(st.session_state.new_set_stages):
        with st.container(border=True):
            st.write(f"**Stage {idx + 1}: {stage['stage_name']}**")
            st.write(f"- Agents: {len(stage['agent_ids'])} ({stage['execution_mode']})")
            if stage.get('description'):
                st.caption(stage['description'])

    # Add stage section (OUTSIDE FORM)
    with st.expander("Add New Stage", expanded=len(st.session_state.new_set_stages) == 0):
        stage_name = st.text_input(
            "Stage Name",
            placeholder="e.g., actor, critic, qa",
            key="new_stage_name"
        )

        stage_desc = st.text_input(
            "Stage Description (optional)",
            placeholder="e.g., 3 actor agents analyze sections in parallel",
            key="new_stage_desc"
        )

        execution_mode = st.selectbox(
            "Execution Mode",
            options=["parallel", "sequential", "batched"],
            help="parallel: all agents run concurrently, sequential: one after another",
            key="new_stage_mode"
        )

        # Agent selector with counts
        agent_options = {f"{a['name']} (ID: {a['id']})": a['id'] for a in active_agents}
        selected_agent_keys = st.multiselect(
            "Select Agents for this Stage",
            options=list(agent_options.keys()),
            help="You can select the same agent multiple times by selecting it once and specifying count below",
            key="new_stage_agents"
        )

        # Allow duplicating agents
        if selected_agent_keys:
            agent_count = st.number_input(
                "Number of instances for first selected agent",
                min_value=1,
                max_value=10,
                value=1,
                help="Use this to run the same agent multiple times (e.g., 3 actor agents)",
                key="new_stage_count"
            )

        if st.button("Add Stage to Pipeline", key="add_stage_btn"):
            if stage_name and selected_agent_keys:
                # Build agent_ids list (with duplicates if count > 1)
                agent_ids = []
                first_agent_id = agent_options[selected_agent_keys[0]]
                agent_ids.extend([first_agent_id] * int(agent_count))
                # Add other agents once
                for key in selected_agent_keys[1:]:
                    agent_ids.append(agent_options[key])

                new_stage = {
                    "stage_name": stage_name,
                    "agent_ids": agent_ids,
                    "execution_mode": execution_mode,
                    "description": stage_desc if stage_desc else None
                }
                st.session_state.new_set_stages.append(new_stage)
                st.success(f"Added stage: {stage_name}")
                st.rerun()
            else:
                st.error("Please provide stage name and select at least one agent")

    # Clear stages button (OUTSIDE FORM)
    if st.session_state.new_set_stages:
        if st.button("Clear All Stages", key="clear_stages"):
            st.session_state.new_set_stages = []
            st.rerun()

    # Agent set creation form (ONLY basic info and submit)
    st.markdown("---")
    st.subheader("Create Agent Set")
    with st.form("create_agent_set_form"):
        set_name = st.text_input(
            "Set Name *",
            placeholder="e.g., My Custom Pipeline",
            help="Unique name for this agent set"
        )

        description = st.text_area(
            "Description",
            placeholder="Describe the purpose and use case for this agent set...",
            help="Optional description"
        )

        set_type = st.selectbox(
            "Set Type",
            options=["sequence", "parallel", "custom"],
            help="sequence: stages run in order, parallel: all agents run at once"
        )

        # Submit button
        submitted = st.form_submit_button("Create Agent Set", type="primary")

        if submitted:
            if not set_name:
                st.error("Please provide a set name")
            elif not st.session_state.new_set_stages:
                st.error("Please add at least one stage")
            else:
                # Create agent set
                set_config = {
                    "stages": st.session_state.new_set_stages
                }

                payload = {
                    "name": set_name,
                    "description": description,
                    "set_type": set_type,
                    "set_config": set_config,
                    "is_system_default": False,
                    "is_active": True
                }

                try:
                    response = api_client.post(AGENT_SET_API, data=payload)
                    st.success(f"Agent set '{set_name}' created successfully!")
                    st.session_state.new_set_stages = []
                    st.rerun()
                except Exception as e:
                    st.error(f"Failed to create agent set: {e}")


def render_agent_set_analytics():
    """Show analytics for agent sets"""
    st.subheader("Agent Set Analytics")

    try:
        # Get most used sets
        response = api_client.get(f"{AGENT_SET_API}/most-used/top?limit=10")
        top_sets = response.get("agent_sets", [])

        if top_sets:
            st.write("**Most Used Agent Sets:**")
            for idx, agent_set in enumerate(top_sets, 1):
                col1, col2 = st.columns([4, 1])
                with col1:
                    st.write(f"{idx}. **{agent_set['name']}**")
                    st.caption(agent_set.get('description', 'No description'))
                with col2:
                    st.metric("Usage", agent_set.get('usage_count', 0))
        else:
            st.info("No usage data yet. Start generating documents with agent sets!")

    except Exception as e:
        st.error(f"Failed to load analytics: {e}")


# Helper functions for agent set operations
def clone_agent_set(set_id: int, new_name: str) -> bool:
    """Clone an existing agent set. Returns True on success, False on failure."""
    try:
        response = api_client.post(
            f"{AGENT_SET_API}/{set_id}/clone",
            data={"new_name": new_name}
        )
        if response:
            st.success(f"Agent set cloned as '{new_name}'")
            return True
        else:
            st.error("Failed to clone agent set: No response from API")
            return False
    except Exception as e:
        st.error(f"Failed to clone agent set: {e}")
        return False


def delete_agent_set(set_id: int, permanent: bool = False) -> bool:
    """
    Delete an agent set.

    Args:
        set_id: The ID of the agent set to delete
        permanent: If True, permanently delete. If False, just deactivate (soft delete)

    Returns:
        True on success, False on failure
    """
    try:
        if permanent:
            # Permanent deletion
            response = api_client.delete(f"{AGENT_SET_API}/{set_id}?soft_delete=false")
        else:
            # Soft delete (deactivate)
            response = api_client.delete(f"{AGENT_SET_API}/{set_id}")

        if response:
            st.success(f"Agent set {'permanently deleted' if permanent else 'deactivated'} successfully")
            return True
        else:
            st.error("Failed to delete agent set: No response from API")
            return False
    except Exception as e:
        st.error(f"Failed to delete agent set: {e}")
        return False


def activate_agent_set(set_id: int) -> bool:
    """Activate an agent set. Returns True on success, False on failure."""
    try:
        response = api_client.put(
            f"{AGENT_SET_API}/{set_id}",
            data={"is_active": True}
        )
        if response:
            st.success("Agent set activated")
            return True
        else:
            st.error("Failed to activate agent set: No response from API")
            return False
    except Exception as e:
        st.error(f"Failed to activate agent set: {e}")
        return False


def deactivate_agent_set(set_id: int) -> bool:
    """Deactivate an agent set. Returns True on success, False on failure."""
    try:
        response = api_client.put(
            f"{AGENT_SET_API}/{set_id}",
            data={"is_active": False}
        )
        if response:
            st.success("Agent set deactivated")
            return True
        else:
            st.error("Failed to deactivate agent set: No response from API")
            return False
    except Exception as e:
        st.error(f"Failed to deactivate agent set: {e}")
        return False
