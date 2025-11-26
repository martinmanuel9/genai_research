from services.generate_docs_service import DocumentService
from services.rag_service import RAGService
from services.llm_service import LLMService
from services.agent_service import AgentService
import os


doc_service = DocumentService(
    rag_service=RAGService(),
    agent_service=AgentService(),
    llm_service=LLMService(),
    chroma_url=os.getenv("CHROMA_URL", "http://localhost:8000"),
    agent_api_url=os.getenv("FASTAPI_URL", "http://localhost:9020")
)

# doc service dependency
def document_service_dep() -> DocumentService:
    return doc_service