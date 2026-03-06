from .redis_client import RedisClient

__all__ = ["RedisClient"]

# Optional imports
try:
    from .metrics import MetricsHelper

    __all__.append("MetricsHelper")
except ImportError:
    pass
