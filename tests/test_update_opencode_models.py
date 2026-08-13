import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).parents[1] / "scripts" / "update-opencode-models.py"
SPEC = importlib.util.spec_from_file_location("update_opencode_models", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class OpenCodeConfigTests(unittest.TestCase):
    def test_generated_config_keeps_local_and_nvidia_providers(self):
        config = MODULE.generate_opencode_config(["qwen3.5-9b", "qwen3.5-35b-a3b"])

        self.assertIn("gateway", config["provider"])
        self.assertIn("nvidia-nim", config["provider"])
        self.assertIn("lmstudio", config["provider"])
        self.assertNotIn("zai-coding-plan", config["provider"])

    def test_existing_client_metadata_is_preserved(self):
        existing = {
            "provider": {"switchyard": {"name": "Local route registry"}},
            "mcp": {"local-tools": {"type": "local"}},
            "plugin": ["portfolio-plugin"],
            "agent": {"reviewer": {"model": "gateway/qwen3.5-9b"}},
        }

        config = MODULE.generate_opencode_config(["qwen3.5-9b"], existing)

        self.assertIn("switchyard", config["provider"])
        self.assertEqual(config["mcp"], existing["mcp"])
        self.assertEqual(config["plugin"], existing["plugin"])
        self.assertEqual(config["agent"], existing["agent"])

    def test_no_removed_provider_names_are_generated(self):
        config = MODULE.generate_opencode_config(["qwen3.5-4b"])
        serialized = str(config).lower()

        self.assertNotIn("zai", serialized)
        self.assertNotIn("glm-", serialized)
        self.assertNotIn("web-search-prime", serialized)
        self.assertNotIn("web-reader", serialized)

    def test_generated_config_is_json_serializable(self):
        import json

        config = MODULE.generate_opencode_config(["qwen3.5-4b"])
        self.assertEqual(json.loads(json.dumps(config)), config)


if __name__ == "__main__":
    unittest.main()
