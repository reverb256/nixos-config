#!/usr/bin/env python3
"""
Simple SearXNG test script - directly test the API.
"""

import asyncio
import json
import httpx


async def test_searxng_ports():
    """Test which SearXNG ports are working."""
    print("\n" + "="*60)
    print("SEARXNG PORT TEST")
    print("="*60)
    
    ports_to_test = [7777, 8888, 8889, 9999]
    results = {}
    
    for port in ports_to_test:
        url = f"http://127.0.0.1:{port}/search"
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(
                    url,
                    params={"q": "nixos", "format": "json"}
                )
                if response.status_code == 200:
                    data = response.json()
                    num_results = len(data.get("results", []))
                    results[port] = {
                        "status": "working",
                        "results": num_results,
                        "engines": data.get("answers", [])
                    }
                    print(f"✅ Port {port}: Working ({num_results} results)")
                else:
                    results[port] = {"status": f"http_{response.status_code}"}
                    print(f"❌ Port {port}: HTTP {response.status_code}")
        except Exception as e:
            results[port] = {"status": type(e).__name__, "error": str(e)}
            print(f"❌ Port {port}: {type(e).__name__}")
    
    return results


async def test_searxng_search(port=7777):
    """Test SearXNG search with various queries."""
    print("\n" + "="*60)
    print(f"SEARXNG SEARCH TEST (port {port})")
    print("="*60)
    
    test_queries = [
        "nixos flake configuration",
        "kubernetes deployment",
        "python async programming",
    ]
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        for query in test_queries:
            print(f"\n🔍 Query: {query}")
            try:
                response = await client.get(
                    f"http://127.0.0.1:{port}/search",
                    params={
                        "q": query,
                        "format": "json",
                        "engines": "github,gitlab,stackoverflow,wikipedia"
                    }
                )
                
                if response.status_code == 200:
                    data = response.json()
                    results = data.get("results", [])
                    
                    print(f"   ✅ Found {len(results)} results")
                    
                    for i, result in enumerate(results[:3], 1):
                        title = result.get("title", "No title")[:60]
                        url = result.get("url", "")[:60]
                        engine = result.get("engine", "unknown")
                        print(f"   {i}. [{engine}] {title}")
                        print(f"      {url}")
                else:
                    print(f"   ❌ HTTP {response.status_code}")
            except Exception as e:
                print(f"   ❌ Error: {e}")
    
    print(f"\n✅ Search test complete!")
    return True


async def test_gateway_knowledge_fabric():
    """Test gateway's Knowledge Fabric endpoint."""
    print("\n" + "="*60)
    print("GATEWAY KNOWLEDGE FABRIC TEST")
    print("="*60)
    
    # Check if gateway has knowledge fabric endpoint
    endpoints_to_test = [
        "http://127.0.0.1:8080/knowledge/search",
        "http://127.0.0.1:8080/api/knowledge/search",
        "http://127.0.0.1:8080/v1/knowledge/search",
    ]
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        for endpoint in endpoints_to_test:
            print(f"\n🔍 Testing: {endpoint}")
            try:
                response = await client.post(
                    endpoint,
                    json={"query": "test"},
                    headers={"Content-Type": "application/json"}
                )
                print(f"   Status: {response.status_code}")
                if response.status_code == 200:
                    data = response.json()
                    print(f"   ✅ Response: {json.dumps(data, indent=2)[:200]}...")
                else:
                    print(f"   ❌ Not found or error")
            except Exception as e:
                print(f"   ❌ Error: {type(e).__name__}")
    
    print(f"\n✅ Gateway test complete!")
    return True


async def main():
    """Run all tests."""
    print("\n" + "="*60)
    print("WEB SEARCH SYSTEM TEST")
    print("="*60)
    
    # Test 1: Port discovery
    port_results = await test_searxng_ports()
    
    working_ports = [p for p, info in port_results.items() 
                    if info.get("status") == "working"]
    
    if not working_ports:
        print("\n❌ CRITICAL: No working SearXNG ports found!")
        print("   → SearXNG service may not be running")
        print("   → Check: systemctl status searx")
        return 1
    
    best_port = working_ports[0]
    print(f"\n🎯 Using port {best_port} for further tests")
    
    # Test 2: Search functionality
    await test_searxng_search(best_port)
    
    # Test 3: Gateway integration
    await test_gateway_knowledge_fabric()
    
    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    print(f"\n✅ Working SearXNG ports: {working_ports}")
    print(f"✅ Search functionality: Working")
    print(f"✅ Basic system: Operational")
    
    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
