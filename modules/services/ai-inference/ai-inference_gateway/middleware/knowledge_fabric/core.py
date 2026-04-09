"""
Knowledge Fabric Core Module

Defines base classes and interfaces for knowledge sources.
"""

from dataclasses import dataclass
from enum import Flag, auto
from typing import Any, Dict, List, Optional


class SourceCapability(Flag):
    """Capabilities of a knowledge source."""
    FACTUAL = auto()          # Provides factual information
    REALTIME = auto()         # Provides real-time data
    COMPARATIVE = auto()      # Can compare multiple sources
    ANALYTICAL = auto()       # Provides analysis
    CODE = auto()             # Provides code examples
    ACADEMIC = auto()         # Academic sources
    TECHNICAL = auto()        # Technical documentation


class SourcePriority:
    """Priority levels for knowledge sources."""
    HIGHEST = 100
    HIGH = 75
    MEDIUM = 50
    LOW = 25
    LOWEST = 0


@dataclass
class KnowledgeChunk:
    """A chunk of knowledge from a source."""
    content: str
    source: str
    score: float = 1.0
    metadata: Dict[str, Any] = None
    capabilities: SourceCapability = SourceCapability.FACTUAL

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}


@dataclass
class KnowledgeResult:
    """Result from a knowledge source query."""
    source_name: str
    chunks: List[KnowledgeChunk]
    query: str
    retrieval_time: float
    metadata: Dict[str, Any] = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

    @property
    def success(self) -> bool:
        """Check if retrieval was successful."""
        return len(self.chunks) > 0 and 'error' not in self.metadata

    @property
    def error(self) -> Optional[str]:
        """Get error message if any."""
        return self.metadata.get('error')
