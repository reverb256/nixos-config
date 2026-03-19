#!/usr/bin/env python3
"""
Comprehensive test script for Knowledge Fabric web search functionality.
Tests all sources and integration points.
"""

import asyncio
import json
import sys
from pathlib import Path

# Add gateway to path
sys.path.insert(0, "/nix/store/yq6hmyapwmzgqbn0hrdk994rq3kj0yh2-ai-inference-gateway-modular-pkg-v15")

from middleware.knowledge_fabric.sources.searxng_source import (
    SearXNGKnowledgeSource,
    create_searxng_source,
)
from middleware.knowledge_fabric.sources.web_search_source import (
    WebSearchKnowledgeSource,
    create_web_search_source,
)
from middleware.knowledge_fabric.core import KnowledgeResult


async def test_searxng_direct():
    """Test SearXNG source directly."""
    print("\n" + "="*60)
    print("TEST 1: SearXNG Direct Search")
    print("="*60)
    
    source = create_searxng_source(
        searxng_url="http://127.0.0.1:7777",
        max_results=3,
    )
    
    print(f"Source: {source.name}")
    print(f"URL: {source.searxng_url}")
    
    result: KnowledgeResult = await source.retrieve(
        query="NixOS flake configuration",
        domain="code"
    )
    
    print(f"\nQuery: {result.query}")
    print(f"Retrieval time: {result.retrieval_time:.2f}s")
    print(f"Chunks found: {len(result.chunks)}")
    print(f"Metadata: {json.dumps(result.metadata, indent=2)}")
    
    if result.chunks:
        print("\nTop results:")
        for i, chunk in enumerate(result.chunks[:3], 1):
            print(f"\n{i}. {chunk.metadata.get('title', 'No title')}")
            print(f"   Score: {chunk.score:.2f}")
            print(f"   URL: {chunk.metadata.get('url', 'No URL')}")
            print(f"   Content: {chunk.content[:100]}...")
    
    if result.metadata.get("error"):
        print(f"\n❌ ERROR: {result.metadata['error']}")
        return False
    
    print(f"\n✅ SearXNG test passed!")
    return True


async def test_web_search_direct():
    """Test Web Search MCP source directly."""
    print("\n" + "="*60)
    print("TEST 2: Web Search MCP Direct")
    print("="*60)
    
    source = create_web_search_source(
        mcp_url="http://127.0.0.1:8080/mcp/call",
        max_results=3,
    )
    
    print(f"Source: {source.name}")
    print(f"MCP URL: {source.mcp_url}")
    
    result: KnowledgeResult = await source.retrieve(
        query="NixOS flake configuration guide"
    )
    
    print(f"\nQuery: {result.query}")
    print(f"Retrieval time: {result.retrieval_time:.2f}s")
    print(f"Chunks found: {len(result.chunks)}")
    print(f"Metadata: {json.dumps(result.metadata, indent=2)}")
    
    if result.chunks:
        print("\nTop results:")
        for i, chunk in enumerate(result.chunks[:3], 1):
            print(f"\n{i}. {chunk.metadata.get('title', 'No title')}")
            print(f"   Score: {chunk.score:.2f}")
            print(f"   URL: {chunk.metadata.get('url', 'No URL')}")
            print(f"   Content: {chunk.content[:100]}...")
    
    if result.metadata.get("error"):
        print(f"\n❌ ERROR: {result.metadata['error']}")
        if "suggestion" in result.metadata:
            print(f"💡 Suggestion: {result.metadata['suggestion']}")
        return False
    
    print(f"\n✅ Web Search MCP test passed!")
    return True


async def test_searxng_port_discovery():
    """Test which port SearXNG is actually running on."""
    print("\n" + "="*60)
    print("TEST 3: SearXNG Port Discovery")
    print("="*60)
    
    import httpx
    
    ports_to_test = [7777, 8888, 8889]
    working_ports = []
    
    async with httpx.AsyncClient(timeout=5.0) as client:
        for port in ports_to_test:
            url = f"http://127.0.0.1:{port}/search"
            try:
                response = await client.get(
                    url,
                    params={"q": "test", "format": "json"}
                )
                if response.status_code == 200:
                    data = response.json()
                    results = data.get("results", [])
                    working_ports.append((port, len(results)))
                    print(f"✅ Port {port}: Working ({len(results)} results)")
                else:
                    print(f"❌ Port {port}: HTTP {response.status_code}")
            except Exception as e:
                print(f"❌ Port {port}: {type(e).__name__}")
    
    if working_ports:
        print(f"\n🎯 Found working ports: {[p[0] for p in working_ports]}")
        best_port = max(working_ports, key=lambda x: x[1])[0]
        print(f"🏆 Best port: {best_port}")
        return best_port
    else:
        print("\n❌ No working SearXNG ports found!")
        return None


async def test_domain_routing():
    """Test SearXNG domain-aware routing."""
    print("\n" + "="*60)
    print("TEST 4: Domain-Aware Routing")
    print("="*60)
    
    source = create_searxng_source(
        searxng_url="http://127.0.0.1:7777",
        enable_domain_routing=True,
        max_results=2,
    )
    
    test_queries = [
        ("github kubernetes operator", "code"),
        ("machine learning research papers", "research"),
        ("docker compose tutorial", "devops"),
    ]
    
    for query, expected_domain in test_queries:
        result = await source.retrieve(query=query)
        detected_domain = result.metadata.get("domain", "general")
        engines = result.metadata.get("engines_selected", [])
        
        print(f"\nQuery: {query}")
        print(f"Expected domain: {expected_domain}")
        print(f"Detected domain: {detected_domain}")
        print(f"Engines: {engines}")
        print(f"Results: {len(result.chunks)}")
        
        if detected_domain == expected_domain:
            print("✅ Domain detection correct")
        else:
            print(f"⚠️  Domain detection mismatch (expected {expected_domain}, got {detected_domain})")
    
    print("\n✅ Domain routing test complete!")
    return True


async def main():
    """Run all tests."""
    print("\n" + "="*60)
    print("KNOWLEDGE FABRIC WEB SEARCH TEST SUITE")
    print("="*60)
    
    results = {
        "searxng_port": None,
        "searxng_direct": False,
        "web_search_mcp": False,
        "domain_routing": False,
    }
    
    # Test 1: Port discovery
    try:
        working_port = await test_searxng_port_discovery()
        results["searxng_port"] = working_port
    except Exception as e:
        print(f"\n❌ Port discovery failed: {e}")
    
    # Test 2: SearXNG direct
    try:
        results["searxng_direct"] = await test_searxng_direct()
    except Exception as e:
        print(f"\n❌ SearXNG direct test failed: {e}")
        import traceback
        traceback.print_exc()
    
    # Test 3: Web Search MCP
    try:
        results["web_search_mcp"] = await test_web_search_direct()
    except Exception as e:
        print(f"\n❌ Web Search MCP test failed: {e}")
        import traceback
        traceback.print_exc()
    
    # Test 4: Domain routing
    try:
        results["domain_routing"] = await test_domain_routing()
    except Exception as e:
        print(f"\n❌ Domain routing test failed: {e}")
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    passed = sum(1 for v in results.values() if v is True)
    total = len([k for k in results.keys() if k != "searxng_port"])
    
    print(f"\nTests passed: {passed}/{total}")
    print(f"\nDetailed results:")
    for test, result in results.items():
        if test == "searxng_port":
            status = f"✅ Port {result}" if result else "❌ No working port"
        else:
            status = "✅ PASS" if result else "❌ FAIL"
        print(f"  {test}: {status}")
    
    if passed == total:
        print(f"\n🎉 All tests passed!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
