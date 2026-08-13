import contextlib
import importlib.util
import io
import json
import os
import tempfile
import threading
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


class FakeResponse:
    def __init__(self, status=200, body=b'{"usage":{"total_tokens":3}}', headers=None):
        self.status = status
        self._body = body
        self.headers = headers or {"Content-Type": "application/json"}

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return self._body


class NimProxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(__file__).parents[1] / "scripts" / "nim-proxy.py"
        cls._state_dir = tempfile.TemporaryDirectory()
        cls._old_env = {
            "STATE_FILE": os.environ.get("STATE_FILE"),
            "MAX_CONCURRENCY": os.environ.get("MAX_CONCURRENCY"),
        }
        os.environ["STATE_FILE"] = str(Path(cls._state_dir.name) / "state.json")
        os.environ["MAX_CONCURRENCY"] = "4"
        cls.module = cls._load_module("nim_proxy_test_module")

    @classmethod
    def tearDownClass(cls):
        for name, value in cls._old_env.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        cls._state_dir.cleanup()

    @classmethod
    def _load_module(cls, name):
        spec = importlib.util.spec_from_file_location(name, cls.source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def setUp(self):
        self.module.ctl = self.module.AIMDController()
        self.module.NIM_SLOTS = self.module.threading.BoundedSemaphore(
            self.module.MAX_CONCURRENCY
        )

    def make_handler(self):
        handler = self.module.Handler.__new__(self.module.Handler)
        handler.path = "/v1/chat/completions"
        handler.command = "POST"
        handler.headers = {}
        handler.wfile = io.BytesIO()
        handler.send_response = mock.Mock()
        handler.send_header = mock.Mock()
        handler.end_headers = mock.Mock()
        handler._json = mock.Mock()
        return handler

    def available_slots(self):
        acquired = 0
        while self.module.NIM_SLOTS.acquire(blocking=False):
            acquired += 1
        for _ in range(acquired):
            self.module.NIM_SLOTS.release()
        return acquired

    def test_uses_threaded_server_and_positive_bounded_slots(self):
        self.assertIn("ThreadingHTTPServer", self.source.read_text())
        self.assertIsInstance(self.module.NIM_SLOTS, self.module.threading.BoundedSemaphore)
        self.assertEqual(self.module.MAX_CONCURRENCY, 4)
        self.assertIn("os.replace", self.source.read_text())

    def test_busy_slot_returns_without_consuming_another_slot(self):
        acquired = sum(
            self.module.NIM_SLOTS.acquire(blocking=False)
            for _ in range(self.module.MAX_CONCURRENCY)
        )
        self.assertEqual(acquired, self.module.MAX_CONCURRENCY)
        try:
            handler = self.make_handler()
            handler._proxy(b"{}")
            handler._json.assert_called_once()
            self.assertEqual(handler._json.call_args.args[0], 429)
            self.assertEqual(self.available_slots(), 0)
        finally:
            for _ in range(acquired):
                self.module.NIM_SLOTS.release()

    def test_proxy_success_releases_slot(self):
        handler = self.make_handler()
        with mock.patch.object(self.module.urllib.request, "urlopen",
                               return_value=FakeResponse()):
            handler._proxy(b"{}")
        handler.send_response.assert_called_once_with(200)
        self.assertEqual(self.available_slots(), self.module.MAX_CONCURRENCY)
        self.assertEqual(self.module.ctl.consecutive_429, 0)

    def test_proxy_http_429_records_backoff_and_releases_slot(self):
        handler = self.make_handler()
        error = urllib.error.HTTPError(
            handler.path, 429, "rate limited", {}, io.BytesIO(b'{"error":"slow"}')
        )
        with mock.patch.object(self.module.urllib.request, "urlopen",
                               side_effect=error):
            handler._proxy(b"{}")
        handler.send_response.assert_called_once_with(429)
        self.assertEqual(self.module.ctl.consecutive_429, 1)
        self.assertEqual(self.available_slots(), self.module.MAX_CONCURRENCY)

    def test_proxy_http_error_releases_slot(self):
        handler = self.make_handler()
        error = urllib.error.HTTPError(
            handler.path, 500, "server error", {}, io.BytesIO(b'{"error":"bad"}')
        )
        with mock.patch.object(self.module.urllib.request, "urlopen",
                               side_effect=error):
            handler._proxy(b"{}")
        handler.send_response.assert_called_once_with(500)
        self.assertEqual(self.available_slots(), self.module.MAX_CONCURRENCY)

    def test_proxy_url_error_releases_slot(self):
        handler = self.make_handler()
        with mock.patch.object(self.module.urllib.request, "urlopen",
                               side_effect=urllib.error.URLError("offline")):
            handler._proxy(b"{}")
        handler._json.assert_called_once()
        self.assertEqual(handler._json.call_args.args[0], 502)
        self.assertEqual(self.available_slots(), self.module.MAX_CONCURRENCY)

    def test_proxy_unexpected_error_releases_slot(self):
        handler = self.make_handler()
        with mock.patch.object(self.module.urllib.request, "urlopen",
                               side_effect=RuntimeError("boom")):
            handler._proxy(b"{}")
        handler._json.assert_called_once()
        self.assertEqual(handler._json.call_args.args[0], 500)
        self.assertEqual(self.available_slots(), self.module.MAX_CONCURRENCY)

    def test_aimd_controller_starts_and_backs_off(self):
        controller = self.module.AIMDController()
        initial = controller.rpm_target
        controller.record_429()
        self.assertLess(controller.rpm_target, initial)
        controller.record_success()
        self.assertEqual(controller.consecutive_429, 0)

    def test_concurrent_state_updates_remain_valid(self):
        controller = self.module.AIMDController()
        workers = [threading.Thread(target=controller.record_success)
                   for _ in range(12)]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join()
        self.assertEqual(len(controller.rpm_entries), len(workers))
        saved = json.loads(Path(os.environ["STATE_FILE"]).read_text())
        self.assertIn("consecutive_429", saved)

    def test_state_persistence_is_valid_and_atomic(self):
        controller = self.module.AIMDController()
        controller.record_success(tokens=7)
        state_path = Path(os.environ["STATE_FILE"])
        self.assertTrue(state_path.exists())
        saved = json.loads(state_path.read_text())
        self.assertIn("rpm_target", saved)
        self.assertIn("tpm_target", saved)
        self.assertEqual(list(state_path.parent.glob(".nim-proxy-*")), [])

    def test_invalid_concurrency_value_fails_clearly(self):
        old = os.environ["MAX_CONCURRENCY"]
        try:
            for invalid in ("0", "not-a-number"):
                os.environ["MAX_CONCURRENCY"] = invalid
                with self.assertRaisesRegex(ValueError, "MAX_CONCURRENCY"):
                    self._load_module(f"nim_proxy_invalid_{invalid.replace('-', '_')}")
        finally:
            os.environ["MAX_CONCURRENCY"] = old


if __name__ == "__main__":
    unittest.main()
