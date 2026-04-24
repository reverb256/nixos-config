"""
DFlash OpenAI-compatible server wrapper for Lucebox test_dflash.

Spawns test_dflash per request. Model loads from NVMe page cache
after first request (~1-2s after warmup). Streams tokens via SSE.

Usage:
    dflash-server --target /models/Qwen3.6-27B-Q4_K_M.gguf \
                   --draft /models/dflash/model.safetensors \
                   --port 1235
"""

import argparse
import asyncio
import json
import logging
import os
import struct
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
import uvicorn

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("dflash-server")

app = FastAPI(title="DFlash Server", version="0.1.0")

CONFIG = {
    "test_dflash_bin": "",
    "target_model": "",
    "draft_model": "",
    "ddtree_budget": 22,
    "kv_q4": True,
    "max_ctx_default": 32768,
    "n_gen_default": 4096,
    "tokenizer": None,
    "im_end_id": -1,
}


class QwenTokenizer:
    """Lazy-loaded tokenizer that caches after first use."""

    def __init__(self):
        self._tok = None

    def _load(self):
        if self._tok is None:
            from transformers import AutoTokenizer
            logger.info("Loading Qwen3.5 tokenizer...")
            self._tok = AutoTokenizer.from_pretrained(
                "Qwen/Qwen3.5-27B", trust_remote_code=True,
            )
            ids = self._tok.encode("<|im_end|>", add_special_tokens=False)
            CONFIG["im_end_id"] = ids[0] if ids else -1
            logger.info("Tokenizer loaded.")
        return self._tok

    def encode(self, text):
        return self._load().encode(text, add_special_tokens=False)

    def decode(self, ids):
        return self._load().decode(ids)

    def apply_chat_template(self, messages, **kw):
        return self._load().apply_chat_template(messages, tokenize=False, **kw)


CONFIG["tokenizer"] = QwenTokenizer()


def tokenize_to_file(text, path):
    ids = CONFIG["tokenizer"].encode(text)
    with open(path, "wb") as f:
        for t in ids:
            f.write(struct.pack("<i", int(t)))
    return len(ids)


async def generate_with_dflash(prompt_tokens, n_gen, in_path, out_path, max_ctx=0):
    """Spawn test_dflash and yield token IDs from the stream pipe."""
    if max_ctx <= 0:
        pad = 64
        max_ctx = ((prompt_tokens + n_gen + pad + 255) // 256) * 256

    r_fd, w_fd = os.pipe()

    cmd = [
        CONFIG["test_dflash_bin"],
        CONFIG["target_model"],
        CONFIG["draft_model"],
        in_path,
        str(n_gen),
        out_path,
        "--fast-rollback",
        "--ddtree",
        "--ddtree-budget={}".format(CONFIG["ddtree_budget"]),
        "--max-ctx={}".format(max_ctx),
        "--stream-fd={}".format(w_fd),
    ]

    env = dict(os.environ)
    if CONFIG["kv_q4"]:
        env["DFLASH27B_KV_Q4"] = "1"

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        pass_fds=(w_fd,),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    os.close(w_fd)

    loop = asyncio.get_event_loop()

    def _read_token():
        data = os.read(r_fd, 4)
        if not data or len(data) < 4:
            return None
        return struct.unpack("<i", data)[0]

    try:
        while True:
            tok_id = await loop.run_in_executor(None, _read_token)
            if tok_id is None:
                break
            yield tok_id
            if tok_id == CONFIG["im_end_id"]:
                break
    finally:
        os.close(r_fd)
        await proc.wait()
        stderr_data = await proc.stderr.read()
        if stderr_data:
            for line in stderr_data.decode(errors="replace").splitlines():
                logger.info("[test_dflash] %s", line)


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    stream = body.get("stream", False)
    max_tokens = body.get("max_tokens", CONFIG["n_gen_default"])
    max_ctx = body.get("max_context", 0)

    if not messages:
        return JSONResponse({"error": "messages required"}, status_code=400)

    prompt_text = CONFIG["tokenizer"].apply_chat_template(
        messages, add_generation_prompt=True,
    )

    request_id = "chatcmpl-{}".format(uuid.uuid4().hex[:12])
    model_name = body.get("model", "Qwen3.6-27B-DFlash")
    created = int(time.time())

    with tempfile.TemporaryDirectory() as tmp:
        in_bin = os.path.join(tmp, "prompt.bin")
        out_bin = os.path.join(tmp, "out.bin")
        n_tok = tokenize_to_file(prompt_text, in_bin)

        logger.info("[%s] prompt=%d tokens, max_gen=%d", request_id, n_tok, max_tokens)

        if not stream:
            tokens = []
            t0 = time.time()
            async for tok_id in generate_with_dflash(
                n_tok, max_tokens, in_bin, out_bin, max_ctx,
            ):
                tokens.append(tok_id)

            text = CONFIG["tokenizer"].decode(tokens)
            elapsed = time.time() - t0
            logger.info(
                "[%s] done: %d tokens in %.1fs (%.1f tok/s)",
                request_id, len(tokens), elapsed, len(tokens) / max(elapsed, 0.001),
            )

            return {
                "id": request_id,
                "object": "chat.completion",
                "created": created,
                "model": model_name,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": text},
                    "finish_reason": "stop",
                }],
                "usage": {
                    "prompt_tokens": n_tok,
                    "completion_tokens": len(tokens),
                    "total_tokens": n_tok + len(tokens),
                },
            }

        async def _stream():
            t0 = time.time()
            n = 0
            async for tok_id in generate_with_dflash(
                n_tok, max_tokens, in_bin, out_bin, max_ctx,
            ):
                n += 1
                chunk = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model_name,
                    "choices": [{
                        "index": 0,
                        "delta": {
                            "content": CONFIG["tokenizer"].decode([tok_id]),
                        },
                        "finish_reason": None,
                    }],
                }
                yield "data: {}\n\n".format(json.dumps(chunk))

            final = {
                "id": request_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model_name,
                "choices": [{
                    "index": 0,
                    "delta": {},
                    "finish_reason": "stop",
                }],
            }
            yield "data: {}\n\n".format(json.dumps(final))
            yield "data: [DONE]\n\n"

            elapsed = time.time() - t0
            logger.info(
                "[%s] stream done: %d tokens in %.1fs (%.1f tok/s)",
                request_id, n, elapsed, n / max(elapsed, 0.001),
            )

        return StreamingResponse(
            _stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{
            "id": "Qwen3.6-27B-DFlash",
            "object": "model",
            "created": 1777027556,
            "owned_by": "dflash",
        }],
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "model": "Qwen3.6-27B-DFlash",
        "backend": "dflash+ddtree",
    }


def main():
    ap = argparse.ArgumentParser(description="DFlash OpenAI-compatible server")
    ap.add_argument("--target", required=True, help="Path to target GGUF model")
    ap.add_argument("--draft", required=True, help="Path to DFlash draft safetensors")
    ap.add_argument("--bin", default="test_dflash", help="Path to test_dflash binary")
    ap.add_argument("--port", type=int, default=1235)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--ddtree-budget", type=int, default=22)
    ap.add_argument("--kv-q4", action="store_true", default=True)
    ap.add_argument("--max-ctx", type=int, default=32768)
    args = ap.parse_args()

    CONFIG["test_dflash_bin"] = args.bin
    CONFIG["target_model"] = args.target
    CONFIG["draft_model"] = args.draft
    CONFIG["ddtree_budget"] = args.ddtree_budget
    CONFIG["kv_q4"] = args.kv_q4
    CONFIG["max_ctx_default"] = args.max_ctx

    logger.info("DFlash server starting on %s:%d", args.host, args.port)
    logger.info("Target: %s", args.target)
    logger.info("Draft: %s", args.draft)
    logger.info("DDTree budget: %d", args.ddtree_budget)

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
