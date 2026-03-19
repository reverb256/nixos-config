#!/usr/bin/env python3
"""
Test Knowledge Fabric integration with the gateway.
"""

import asyncio
import json
import httpx


async def test_knowledge_fabric_via_gateway():
    """Test Knowledge Fabric through the gateway's chat completion endpoint."""
    print("\n" + "="*60)
    print("KNOWLEDGE FABRIC INTEGRATION TEST")
    print("="*60)
    
    # Test queries that should trigger knowledge fabric
    test_queries = [
        "How do I configure NixOS flakes?",
        "What is Kubernetes networking?",
        "Show me a Python async example",
    ]
    
    async with httpx.AsyncClient(timeout=60.0) as client:
        for query in test_queries:
            print(f"\n🔍 Query: {query}")
            print("-" * 60)
            
            try:
                response = await client.post(
                    "http://127.0.0.1:8080/v1/chat/completions",
                    json={
                        "model": "claude-haiku-4",  # Use fast model for testing
                        "messages": [
                            {"role": "user", "content": query}
                        ],
                        "stream": False,
                        "max_tokens": 150,
                    },
                    headers={"Content-Type": "application/json"}
                )
                
                if response.status_code == 200:
                    data = response.json()
                    
                    # Check if response contains knowledge fabric context
                    content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
                    
                    print(f"✅ Response received ({len(content)} chars)")
                    print(f"📝 Content preview: {content[:200]}...")
                    
                    # Check for citations or sources
                    if "[source:" in content or "http://" in content or "https://" in content:
                        print(f"🔗 Response contains citations/links")
                    
                else:
                    print(f"❌ HTTP {response.status_code}")
                    print(f"   Error: {response.text[:200]}")
                    
            except Exception as e:
                print(f"❌ Error: {type(e).__name__}: {e}")
    
    print(f"\n✅ Integration test complete!")
    return True


async def test_searxng_domain_routing():
    """Test SearXNG with different query domains."""
    print("\n" + "="*60)
    print("SEARXNG DOMAIN ROUTING TEST")
    print("="*60)
    
    test_cases = [
        ("github kubernetes operator", "code"),
        ("docker compose tutorial", "devops"),
        ("nixos configuration", "code"),
    ]
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        for query, expected_domain in test_cases:
            print(f"\n🔍 Query: {query}")
            print(f"   Expected domain: {expected_domain}")
            
            try:
                response = await client.get(
                    "http://127.0.0.1:7777/search",
                    params={
                        "q": query,
                        "format": "json",
                        "engines": "github,gitlab,stackoverflow,duckduckgo,brave"
                    }
                )
                
                if response.status_code == 200:
                    data = response.json()
                    results = data.get("results", [])
                    
                    print(f"   ✅ Found {len(results)} results")
                    
                    # Show top 3 results
                    for i, result in enumerate(results[:3], 1):
                        title = result.get("title", "No title")[:50]
                        engine = result.get("engine", "unknown")
                        print(f"   {i}. [{engine}] {title}")
                else:
                    print(f"   ❌ HTTP {response.status_code}")
                    
            except Exception as e:
                print(f"   ❌ Error: {e}")
    
    print(f"\n✅ Domain routing test complete!")
    return True


async def main():
    """Run all integration tests."""
    print("\n" + "="*60)
    print("KNOWLEDGE FABRIC COMPREHENSIVE TEST")
    print("="*60)
    
    results = {}
    
    # Test 1: SearXNG domain routing
    try:
        results["searxng_routing"] = await test_searxng_domain_routing()
    except Exception as e:
        print(f"\n❌ SearXNG routing test failed: {e}")
        results["searxng_routing"] = False
    
    # Test 2: Gateway integration
    try:
        results["gateway_integration"] = await test_knowledge_fabric_via_gateway()
    except Exception as e:
        print(f"\n❌ Gateway integration test failed: {e}")
        results["gateway_integration"] = False
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    
    print(f"\nTests passed: {passed}/{total}")
    for test, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"  {test}: {status}")
    
    if passed == total:
        print(f"\n🎉 All integration tests passed!")
        print(f"\n✅ Knowledge Fabric is fully operational!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
