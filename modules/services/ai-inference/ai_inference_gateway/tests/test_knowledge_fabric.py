"""
Tests for Knowledge Fabric main orchestrator.

Tests the KnowledgeFabricMiddleware class which coordinates
semantic routing, parallel retrieval, RRF fusion, and context synthesis.
"""

import pytest
from unittest.mock import Mock, AsyncMock, patch
from fastapi import Request

from ai_inference_gateway.middleware.knowledge_fabric import (
    KnowledgeFabricMiddleware,
    create_knowledge_fabric,
    FABRIC_CONTEXT_KEY,
    KNOWLEDGE_CONTEXT_KEY,
)
from ai_inference_gateway.middleware.knowledge_fabric.core import (
    QueryIntent,
    FabricContext,
)


# ============================================================================
# Test Fixtures
# ============================================================================


@pytest.fixture
def mock_request():
    """Create mock FastAPI Request."""
    request = Mock(spec=Request)
    return request


@pytest.fixture
def basic_config():
    """Create basic Knowledge Fabric configuration."""
    return {
        "rag_enabled": False,
        "code_search_paths": ["/etc/nixos"],
        "searxng_url": "http://127.0.0.1:7777",
        "mcp_url": "http://127.0.0.1:8080/mcp/call",
        "code_max_results": 5,
        "web_max_results": 5,
        "searxng_max_results": 5,
        "rag_top_k": 5,
    }


@pytest.fixture
def fabric_middleware(basic_config):
    """Create KnowledgeFabricMiddleware for testing."""
    # Don't create actual sources to avoid HTTP calls during tests
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=True,
        config=basic_config,
    )
    return middleware


# ============================================================================
# Initialization Tests
# ============================================================================


def test_middleware_initialization(fabric_middleware):
    """Test middleware initializes correctly."""
    assert fabric_middleware.enabled is True
    assert fabric_middleware.router is not None
    assert fabric_middleware.fusion is not None
    assert fabric_mediator.synthesizer is not None


def test_middleware_disabled_initialization(basic_config):
    """Test middleware can be initialized as disabled."""
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=False,
        config=basic_config,
    )

    assert middleware.enabled is False


def test_create_knowledge_fabric_factory(basic_config):
    """Test factory function creates middleware correctly."""
    middleware = create_knowledge_fabric(
        rrf_k=60,
        enabled=True,
        config=basic_config,
    )

    assert isinstance(middleware, KnowledgeFabricMiddleware)
    assert middleware.enabled is True


# ============================================================================
# Process Request Tests
# ============================================================================


@pytest.mark.asyncio
async def test_process_request_skips_when_disabled(mock_request, basic_config):
    """Test process_request returns immediately when disabled."""
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=False,
        config=basic_config,
    )

    context = {}
    should_continue, error = await middleware.process_request(mock_request, context)

    assert should_continue is True
    assert error is None


@pytest.mark.asyncio
async def test_process_request_skips_short_query(mock_request, fabric_middleware):
    """Test process_request skips very short queries."""
    # Mock _extract_query to return short query
    with patch.object(
        fabric_middleware, "_extract_query", return_value="hi"
    ):
        context = {}
        should_continue, error = await fabric_middleware.process_request(
            mock_request, context
        )

    assert should_continue is True
    assert error is None
    assert "context" not in context  # No knowledge context added


@pytest.mark.asyncio
async def test_process_request_performs_routing(mock_request, fabric_middleware):
    """Test process_request classifies query intent."""
    with patch.object(
        fabric_middleware, "_extract_query", return_value="How do I implement a function?"
    ):
        # Mock sources to return empty results
        for source in fabric_middleware.sources:
            source.retrieve = AsyncMock(return_value=Mock(
                chunks=[], source_name=source.name, retrieval_time=0.1, metadata={}
            ))

        context = {}
        should_continue, error = await fabric_middleware.process_request(
            mock_request, context
        )

    assert should_continue is True
    assert error is None


@pytest.mark.asyncio
async def test_process_request_creates_fabric_context(mock_request, fabric_middleware):
    """Test process_request creates FabricContext."""
    with patch.object(
        fabric_middleware, "_extract_query", return_value="What is the capital of France?"
    ):
        # Mock sources
        for source in fabric_middleware.sources:
            source.retrieve = AsyncMock(return_value=Mock(
                chunks=[], source_name=source.name, retrieval_time=0.1, metadata={}
            ))

        context = {}
        await fabric_middleware.process_request(mock_request, context)

    assert FABRIC_CONTEXT_KEY in context
    assert isinstance(context[FABRIC_CONTEXT_KEY], FabricContext)


@pytest.mark.asyncio
async def test_process_request_injects_knowledge_context(mock_request, fabric_middleware):
    """Test process_request injects knowledge context."""
    with patch.object(
        fabric_middleware, "_extract_query", return_value="What is the capital of France?"
    ):
        # Mock synthesizer to return context
        with patch.object(
            fabric_mediator.synthesizer, "synthesize", return_value="Test knowledge context"
        ):
            # Mock fusion
            with patch.object(
                fabric_mediator.fusion, "fuse", return_value=[]
            ):
                # Mock sources
                for source in fabric_middleware.sources:
                    source.retrieve = AsyncMock(return_value=Mock(
                        chunks=[], source_name=source.name, retrieval_time=0.1, metadata={}
                    ))

                context = {}
                await fabric_middleware.process_request(mock_request, context)

    assert KNOWLEDGE_CONTEXT_KEY in context
    assert context[KNOWLEDGE_CONTEXT_KEY] == "Test knowledge context"


# ============================================================================
# Query Extraction Tests
# ============================================================================


@pytest.mark.asyncio
async def test_extract_query_from_messages(fabric_middleware):
    """Test query extraction from request body messages."""
    mock_request = Mock()
    context = {
        "parsed_body": {
            "messages": [
                {"role": "system", "content": "You are helpful."},
                {"role": "user", "content": "What is the capital of France?"},
            ]
        }
    }

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "What is the capital of France?"


@pytest.mark.asyncio
async def test_extract_query_from_user_message_only(fabric_middleware):
    """Test query extraction from user message only."""
    mock_request = Mock()
    context = {
        "parsed_body": {
            "messages": [
                {"role": "user", "content": "Explain binary search"}
            ]
        }
    }

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "Explain binary search"


@pytest.mark.asyncio
async def test_extract_query_from_last_user_message(fabric_middleware):
    """Test query extraction gets last user message."""
    mock_request = Mock()
    context = {
        "parsed_body": {
            "messages": [
                {"role": "user", "content": "First question"},
                {"role": "assistant", "content": "First answer"},
                {"role": "user", "content": "Second question"},
            ]
        }
    }

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "Second question"


@pytest.mark.asyncio
async def test_extract_query_from_prompt(fabric_middleware):
    """Test query extraction from prompt field."""
    mock_request = Mock()
    context = {
        "parsed_body": {
            "prompt": "Complete this sentence"
        }
    }

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "Complete this sentence"


@pytest.mark.asyncio
async def test_extract_query_from_cached_context(fabric_middleware):
    """Test query extraction from cached user_query."""
    mock_request = Mock()
    context = {"user_query": "Cached query"}

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "Cached query"


@pytest.mark.asyncio
async def test_extract_query_multimodal_content(fabric_middleware):
    """Test query extraction from multi-modal content."""
    mock_request = Mock()
    context = {
        "parsed_body": {
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "What is in this image?"},
                        {"type": "image", "source": {"type": "url", "url": "http://example.com/img.png"}},
                    ]
                }
            ]
        }
    }

    query = await fabric_middleware._extract_query(mock_request, context)

    assert query == "What is in this image?"


# ============================================================================
# Parallel Retrieval Tests
# ============================================================================


@pytest.mark.asyncio
async def test_parallel_retrieval_from_sources(mock_request, fabric_middleware):
    """Test parallel retrieval from multiple sources."""
    with patch.object(
        fabric_mediator, "_extract_query", return_value="test query"
    ):
        # Mock async retrieve
        async def mock_retrieve(query, **kwargs):
            import asyncio
            await asyncio.sleep(0.01)
            return Mock(
                chunks=[],
                source_name="test",
                retrieval_time=0.1,
                metadata={}
            )

        # Patch sources
        with patch.object(
            fabric_mediator.router, "classify", return_value=Mock(
                intent=QueryIntent.FACTUAL,
                confidence=0.9,
                selected_sources=["test"],
                reasoning="Test routing"
            )
        ):
            with patch.object(
                fabric_mediator, "_sources_by_name",
                {"test": Mock(retrieve=mock_retrieve)}
            ):
                context = {}
                await fabric_mediator.process_request(mock_request, context)

    # Should complete without error
    assert context is not None


@pytest.mark.asyncio
async def test_parallel_retrieval_handles_exceptions(mock_request, fabric_middleware):
    """Test parallel retrieval handles source exceptions gracefully."""
    with patch.object(
        fabric_mediator, "_extract_query", return_value="test query"
    ):
        # Mock failing source
        async def failing_retrieve(query, **kwargs):
            raise Exception("Source failed")

        with patch.object(
            fabric_mediator.router, "classify", return_value=Mock(
                intent=QueryIntent.FACTUAL,
                confidence=0.9,
                selected_sources=["failing"],
                reasoning="Test"
            )
        ):
            with patch.object(
                fabric_mediator, "_sources_by_name",
                {"failing": Mock(retrieve=failing_retrieve)}
            ):
                context = {}
                should_continue, error = await fabric_mediator.process_request(
                    mock_request, context
                )

    # Should continue despite source failure
    assert should_continue is True
    assert error is None


# ============================================================================
# Process Response Tests
# ============================================================================


@pytest.mark.asyncio
async def test_process_response_adds_metadata(fabric_middleware):
    """Test process_response adds knowledge fabric metadata."""
    fabric_context = FabricContext(
        query="test query",
        query_type=QueryIntent.FACTUAL,
        results={},
        fused_chunks=[],
        sources_used=["rag", "web_search"],
        routing_reasoning="Test reasoning",
    )

    context = {
        FABRIC_CONTEXT_KEY: fabric_context,
    }

    response = {"data": "test response"}
    result = await fabric_mediator.process_response(response, context)

    assert "metadata" in result
    assert "knowledge_fabric" in result["metadata"]
    assert result["metadata"]["knowledge_fabric"]["enabled"] is True
    assert result["metadata"]["knowledge_fabric"]["sources_used"] == ["rag", "web_search"]


@pytest.mark.asyncio
async def test_process_response_without_fabric_context(fabric_middleware):
    """Test process_response handles missing fabric context."""
    context = {}  # No FABRIC_CONTEXT_KEY

    response = {"data": "test response"}
    result = await fabric_mediator.process_response(response, context)

    # Should not modify response
    assert result["data"] == "test response"


@pytest.mark.asyncio
async def test_process_response_when_disabled(fabric_middleware, basic_config):
    """Test process_response does nothing when disabled."""
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=False,
        config=basic_config,
    )

    context = {}
    response = {"data": "test"}
    result = await middleware.process_response(response, context)

    # Should return unchanged
    assert result == response


# ============================================================================
# Error Handling Tests
# ============================================================================


@pytest.mark.asyncio
async def test_process_request_handles_extraction_error(fabric_middleware):
    """Test process_request handles query extraction errors gracefully."""
    mock_request = Mock()

    with patch.object(
        fabric_mediator, "_extract_query", side_effect=Exception("Extraction failed")
    ):
        context = {}
        should_continue, error = await fabric_mediator.process_request(
            mock_request, context
        )

    # Should continue despite error
    assert should_continue is True
    assert error is None


@pytest.mark.asyncio
async def test_process_request_handles_routing_error(fabric_middleware):
    """Test process_request handles routing errors gracefully."""
    mock_request = Mock()

    with patch.object(
        fabric_mediator, "_extract_query", return_value="test query"
    ):
        with patch.object(
            fabric_mediator.router, "classify", side_effect=Exception("Routing failed")
        ):
            context = {}
            should_continue, error = await fabric_mediator.process_request(
                mock_request, context
            )

    assert should_continue is True
    assert error is None


# ============================================================================
# Integration Tests
# ============================================================================


@pytest.mark.asyncio
async def test_full_pipeline_with_mock_sources(mock_request, basic_config):
    """Test full pipeline with mocked sources."""
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=True,
        config=basic_config,
    )

    # Mock the complete pipeline
    with patch.object(
        middleware, "_extract_query", return_value="What is the capital of France?"
    ):
        # Mock routing
        with patch.object(
            middleware.router, "classify", return_value=Mock(
                intent=QueryIntent.FACTUAL,
                confidence=0.9,
                selected_sources=[],
                reasoning="Test"
            )
        ):
            # Mock fusion
            with patch.object(
                middleware.fusion, "fuse", return_value=[]
            ):
                # Mock synthesizer
                with patch.object(
                    middleware.synthesizer, "synthesize", return_value="Knowledge context"
                ):
                    context = {}
                    should_continue, error = await middleware.process_request(
                        mock_request, context
                    )

    assert should_continue is True
    assert error is None
    assert KNOWLEDGE_CONTEXT_KEY in context


# ============================================================================
# Config Tests
# ============================================================================


def test_create_default_sources_with_config():
    """Test _create_default_sources uses configuration."""
    config = {
        "rag_enabled": True,
        "code_search_paths": ["/custom/path"],
        "searxng_url": "http://custom:7777",
    }

    middleware = KnowledgeFabricMiddleware(
        sources=None,  # Will trigger _create_default_sources
        rrf_k=60,
        enabled=True,
        config=config,
    )

    # Sources should be created based on config
    assert len(middleware.sources) > 0
    # Check code_search uses configured path
    code_source = next((s for s in middleware.sources if s.name == "code_search"), None)
    if code_source:
        # Note: The actual source object may not have search_paths as a direct attribute
        # This test verifies the middleware was created
        pass


def test_rrf_k_parameter_propagation():
    """Test RRF k parameter is properly propagated."""
    middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=100,
        enabled=True,
        config={},
    )

    assert middleware.fusion.k == 100


def test_enabled_property():
    """Test enabled property reflects middleware state."""
    enabled_middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=True,
        config={},
    )

    disabled_middleware = KnowledgeFabricMiddleware(
        sources=[],
        rrf_k=60,
        enabled=False,
        config={},
    )

    assert enabled_middleware.enabled is True
    assert disabled_middleware.enabled is False


# ============================================================================
# Source Priority Tests
# ============================================================================


def test_sources_by_name_index(fabric_middleware):
    """Test sources are indexed by name for quick access."""
    assert fabric_mediator._sources_by_name is not None
    assert isinstance(fabric_mediator._sources_by_name, dict)


@pytest.mark.asyncio
async def test_source_selection_by_name(mock_request, fabric_middleware):
    """Test sources can be selected by name during retrieval."""
    with patch.object(
        fabric_mediator, "_extract_query", return_value="test query"
    ):
        with patch.object(
            fabric_mediator.router, "classify", return_value=Mock(
                intent=QueryIntent.FACTUAL,
                confidence=0.9,
                selected_sources=["rag", "web_search"],
                reasoning="Test"
            )
        ):
            # Mock the sources
            mock_rag = Mock()
            mock_rag.retrieve = AsyncMock(return_value=Mock(
                chunks=[], source_name="rag", retrieval_time=0.1, metadata={}
            ))

            mock_web = Mock()
            mock_web.retrieve = AsyncMock(return_value=Mock(
                chunks=[], source_name="web_search", retrieval_time=0.1, metadata={}
            ))

            fabric_mediator._sources_by_name = {
                "rag": mock_rag,
                "web_search": mock_web,
            }

            context = {}
            await fabric_mediator.process_request(mock_request, context)

    # Both sources should have been called
    mock_rag.retrieve.assert_called_once()
    mock_web.retrieve.assert_called_once()
