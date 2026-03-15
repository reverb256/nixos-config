"""
SearXNG Integration for AI Inference Gateway

Direct integration with local SearXNG instance providing:
- Privacy-respecting metasearch
- Auto-improving search with query learning
- Result caching and ranking optimization
- Adaptive engine selection based on query type
"""

import asyncio
import json
import logging
import hashlib
import time
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional
from urllib.parse import urlencode, urlparse

import httpx

logger = logging.getLogger(__name__)

# SearXNG configuration
SEARXNG_URL = "http://127.0.0.1:7777"
SEARCH_ENDPOINT = "/search"

# Learning storage
LEARNING_CACHE_PATH = "/var/cache/ai-inference/mcp/searxng_learning.json"


class SearxngIntegration:
    """
    SearXNG integration with auto-improving features:

    1. Query Pattern Learning: Tracks common search patterns to suggest refinements
    2. Result Ranking Optimization: Learns which results get selected
    3. Adaptive Engine Selection: Chooses best engines based on query category
    4. Popularity Caching: Prioritizes frequently accessed results
    """

    def __init__(self, cache_ttl: int = 300):
        self.cache_ttl = cache_ttl
        self.client = httpx.AsyncClient(timeout=30.0)

        # Learning data
        self.query_patterns: Counter = Counter()  # Track query patterns
        self.successful_queries: List[str] = []  # Track successful queries
        self.result_clicks: Counter = Counter()  # Track clicked results (simulated)
        self.engine_performance: Dict[str, Dict] = defaultdict(
            lambda: {"attempts": 0, "successes": 0, "avg_results": 0}
        )

        # Response cache with popularity tracking
        self.response_cache: Dict[str, Dict] = {}

        # Load learning data from disk
        self._load_learning_data()

    def _load_learning_data(self):
        """Load learning data from disk."""
        try:
            import os
            if os.path.exists(LEARNING_CACHE_PATH):
                with open(LEARNING_CACHE_PATH, "r") as f:
                    data = json.load(f)
                    self.query_patterns = Counter(data.get("query_patterns", {}))
                    self.successful_queries = data.get("successful_queries", [])
                    self.result_clicks = Counter(data.get("result_clicks", {}))
                    self.engine_performance = defaultdict(
                        lambda: {"attempts": 0, "successes": 0, "avg_results": 0},
                        data.get("engine_performance", {})
                    )
                logger.info(f"Loaded learning data: {len(self.successful_queries)} queries")
        except Exception as e:
            logger.warning(f"Could not load learning data: {e}")

    def _save_learning_data(self):
        """Save learning data to disk."""
        try:
            import os
            os.makedirs(os.path.dirname(LEARNING_CACHE_PATH), exist_ok=True)
            data = {
                "query_patterns": dict(self.query_patterns),
                "successful_queries": self.successful_queries,
                "result_clicks": dict(self.result_clicks),
                "engine_performance": self.engine_performance,
                "last_updated": time.time(),
            }
            with open(LEARNING_CACHE_PATH, "w") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            logger.warning(f"Could not save learning data: {e}")

    def _cache_key(self, query: str, category: str = "general") -> str:
        """Generate cache key for search query."""
        key_data = f"{category}:{query.lower().strip()}"
        return hashlib.sha256(key_data.encode()).hexdigest()[:16]

    def _extract_query_pattern(self, query: str) -> str:
        """Extract meaningful pattern from query for learning."""
        # Remove common words
        stop_words = {"the", "a", "an", "in", "on", "at", "to", "for", "with", "about"}
        words = query.lower().split()
        meaningful_words = [w for w in words if len(w) > 3 and w not in stop_words]
        return " ".join(meaningful_words[:5])  # First 5 meaningful words

    def _suggest_refinement(self, query: str, results: List[Dict]) -> Optional[str]:
        """Suggest query refinement based on results and learning."""
        if not results:
            return None

        # Check if this is a technical query that could be more specific
        technical_keywords = ["how", "what", "why", "when", "where", "install", "configure", "setup"]
        query_lower = query.lower()

        if any(kw in query_lower for kw in technical_keywords):
            # Extract potential topic
            for result in results[:3]:
                title = result.get("title", "").lower()
                snippet = result.get("content", result.get("snippet", "")).lower()
                text = f"{title} {snippet}"

                # Look for more specific terms
                if "nixos" in text and "flake" not in query_lower:
                    return f"{query} nixos flake"
                elif "kubernetes" in text and "deployment" not in query_lower:
                    return f"{query} kubernetes deployment"
                elif "api" in text and "example" not in query_lower:
                    return f"{query} api example"

        return None

    def _get_optimal_engines(self, category: str) -> List[str]:
        """Select optimal search engines based on category and learning."""
        # Default engines by category
        category_engines = {
            "general": ["google", "bing", "duckduckgo"],
            "images": ["google images", "bing images"],
            "videos": ["youtube", "peerTube"],
            "news": ["google news", "bing news"],
            "science": ["google scholar", "semantic scholar"],
            "it": ["stackoverflow", "github"],
            "files": ["kickass", "btdb"],
            "music": ["spotify", "soundcloud"],
            "map": ["openstreetmap", "google maps"],
        }

        # Get base engines
        engines = category_engines.get(category, category_engines["general"])

        # Learn from past performance
        engine_scores = {}
        for engine in engines:
            perf = self.engine_performance.get(engine, {"attempts": 0, "successes": 0, "avg_results": 0})
            if perf.get("attempts", 0) > 0:
                # Score: success rate * average results (more results is better)
                score = (perf.get("successes", 0) / perf["attempts"]) * min(perf.get("avg_results", 0) / 10, 1.0)
                engine_scores[engine] = score
            else:
                engine_scores[engine] = 0.5  # Default score

        # Sort by score and return top 3
        sorted_engines = sorted(engine_scores.items(), key=lambda x: x[1], reverse=True)
        return [e[0] for e in sorted_engines[:3]]

    async def search(
        self,
        query: str,
        category: str = "general",
        language: str = "all",
        max_results: int = 10,
        time_range: Optional[str] = None,
        use_cache: bool = True,
        learning_enabled: bool = True,
    ) -> Dict[str, Any]:
        """
        Perform search with auto-improving features.

        Returns:
            Dict with:
            - results: List of search results
            - suggestions: Query refinement suggestions
            - engines_used: Which engines were queried
            - cached: Whether results came from cache
        """
        cache_key = self._cache_key(query, category)

        # Check cache first
        if use_cache and cache_key in self.response_cache:
            cached = self.response_cache[cache_key]
            if time.time() < cached["expiry"]:
                # Update popularity for cache hit
                cached["popularity"] += 1
                logger.info(f"Cache HIT: {query} (popularity: {cached['popularity']})")
                return {
                    "results": cached["results"],
                    "cached": True,
                    "engines_used": cached["engines_used"],
                }

        # Select optimal engines based on learning
        engines = self._get_optimal_engines(category)

        # Build request parameters
        params = {
            "q": query,
            "format": "json",
            "engines": ",".join(engines),
        }

        if category != "general":
            params["categories"] = category

        if language != "all":
            params["language"] = language

        if time_range:
            params["time_range"] = time_range

        # Track query pattern
        pattern = self._extract_query_pattern(query)
        self.query_patterns[pattern] += 1

        try:
            response = await self.client.get(
                f"{SEARXNG_URL}/search",
                params=params,
            )
            response.raise_for_status()

            data = response.json()
            results = data.get("results", [])

            # Update engine performance tracking
            for engine in engines:
                self.engine_performance[engine]["attempts"] += 1
            self.engine_performance["|".join(engines)]["successes"] += 1
            self.engine_performance["|".join(engines)]["avg_results"] = len(results)

            if results:
                # Track successful query
                self.successful_queries.append(query)
                if learning_enabled:
                    self._save_learning_data()

                # Generate suggestions based on results
                suggestions = []
                refinement = self._suggest_refinement(query, results)
                if refinement:
                    suggestions.append({
                        "type": "refinement",
                        "suggestion": refinement,
                        "reason": "More specific search",
                    })

                # Cache results with popularity tracking
                self.response_cache[cache_key] = {
                    "results": results[:max_results],
                    "expiry": time.time() + self.cache_ttl,
                    "popularity": 1,
                    "engines_used": engines,
                    "query": query,
                    "timestamp": time.time(),
                }

                return {
                    "results": results[:max_results],
                    "suggestions": suggestions,
                    "engines_used": engines,
                    "cached": False,
                }
            else:
                return {
                    "results": [],
                    "suggestions": [
                        {
                            "type": "refinement",
                            "suggestion": query.replace("how to", "").strip(),
                            "reason": "Try removing 'how to' prefix",
                        },
                        {
                            "type": "general",
                            "suggestion": "Try broader search terms",
                            "reason": "Query may be too specific",
                        }
                    ],
                    "engines_used": engines,
                    "cached": False,
                }

        except httpx.HTTPStatusError as e:
            logger.error(f"SearXNG HTTP error: {e.response.status_code}")
            return {
                "results": [],
                "error": f"SearXNG returned HTTP {e.response.status_code}",
                "suggestions": [
                    {
                        "type": "check_service",
                        "suggestion": "Check if SearXNG is running: systemctl status searx",
                        "reason": "Service unavailable",
                    }
                ],
                "cached": False,
            }
        except httpx.ConnectError:
            logger.error(f"SearXNG connection error")
            return {
                "results": [],
                "error": "Cannot connect to SearXNG service",
                "suggestions": [
                    {
                        "type": "check_service",
                        "suggestion": "Start SearXNG: systemctl start searx",
                        "reason": "Service not running",
                    },
                    {
                        "type": "check_config",
                        "suggestion": "Verify SearXNG is enabled in NixOS config",
                        "reason": "Service may not be enabled",
                    }
                ],
                "cached": False,
            }
        except Exception as e:
            logger.exception(f"Unexpected error in SearXNG search: {e}")
            return {
                "results": [],
                "error": str(e),
                "cached": False,
            }

    async def get_learning_stats(self) -> Dict[str, Any]:
        """Get statistics about learned search patterns."""
        return {
            "total_queries": len(self.successful_queries),
            "query_patterns": dict(self.query_patterns.most_common(20)),
            "engine_performance": dict(self.engine_performance),
            "cache_size": len(self.response_cache),
            "top_cached_queries": sorted(
                [
                    {"query": r["query"], "popularity": r["popularity"], "engines": r["engines_used"]}
                    for r in sorted(
                        self.response_cache.values(),
                        key=lambda x: x["popularity"],
                        reverse=True
                    )
                ][:10]
            ),
        }

    def clear_cache(self):
        """Clear all cached responses."""
        self.response_cache.clear()
        logger.info("SearXNG cache cleared")

    async def close(self):
        """Close resources."""
        await self.client.aclose()


# Global instance
_searxng_instance: Optional[SearxngIntegration] = None


def get_searxng(cache_ttl: int = 300) -> SearxngIntegration:
    """Get or create global SearXNG instance."""
    global _searxng_instance
    if _searxng_instance is None:
        _searxng_instance = SearxngIntegration(cache_ttl=cache_ttl)
    return _searxng_instance
