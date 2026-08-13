import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


class NimProxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(__file__).parents[1] / "scripts" / "nim-proxy.py"
        cls.module_name = "nim_proxy_test_module"
        cls._state_dir = tempfile.TemporaryDirectory()
        os.environ.setdefault("STATE_FILE", str(Path(cls._state_dir.name) / "state.json"))
        spec = importlib.util.spec_from_file_location(cls.module_name, cls.source)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    @classmethod
    def tearDownClass(cls):
        cls._state_dir.cleanup()

    def test_uses_threaded_server_and_bounded_slots(self):
        self.assertIn("ThreadingHTTPServer", self.source.read_text())
        self.assertIsInstance(self.module.NIM_SLOTS, self.module.threading.BoundedSemaphore)
        self.assertEqual(self.module.MAX_CONCURRENCY, 4)

    def test_busy_slot_returns_without_consuming_another_slot(self):
        acquired = sum(
            self.module.NIM_SLOTS.acquire(blocking=False)
            for _ in range(self.module.MAX_CONCURRENCY)
        )
        self.assertEqual(acquired, self.module.MAX_CONCURRENCY)
        try:
            self.assertFalse(self.module.NIM_SLOTS.acquire(blocking=False))
        finally:
            for _ in range(acquired):
                self.module.NIM_SLOTS.release()

    def test_aimd_controller_starts_and_backs_off(self):
        controller = self.module.AIMDController()
        initial = controller.rpm_target
        controller.record_429()
        self.assertLess(controller.rpm_target, initial)
        controller.record_success()
        self.assertEqual(controller.consecutive_429, 0)


if __name__ == "__main__":
    unittest.main()
