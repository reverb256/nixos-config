{
  lib,
  python3Packages,
  transformers,
  torch,
  accelerate,
  stdenv,
}:
let
  pythonEnv = python3Packages.python.withPackages (
    ps: [
      ps.transformers
      ps.torch
      ps.accelerate
      ps.fastapi
      ps.uvicicorn
      ps.pydantic
      ps.safetensors
    ]
  );
in
stdenv.mkDerivation rec {
  pname = "privacy-filter";
  version = "0.1.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin

    # Create Python server script
    cat > $out/bin/privacy-filter-server <<'EOF'
#!${pythonEnv}/bin/python
"""
OpenAI Privacy Filter - PII Detection and Masking API

Privacy categories detected:
- NAME_PEDIA: Person names
- DATE_TIME: Dates and times
- LOCATION: Locations and addresses
- AGE: Ages
- ID_NUM: ID numbers (SSN, passport, etc.)
- EMAIL: Email addresses
- PHONE_NUM: Phone numbers
- URL: URLs and web addresses
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import pipeline
import torch
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Privacy Filter API",
    description="PII detection and masking using OpenAI privacy-filter model",
    version="0.1.0"
)

# Load model on GPU if available
device = 0 if torch.cuda.is_available() else -1
logger.info(f"Loading model on device: {device}")

try:
    classifier = pipeline(
        task="token-classification",
        model="openai/privacy-filter",
        device=device,
        aggregation_strategy="simple"
    )
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise

class TextInput(BaseModel):
    text: str

class MaskedOutput(BaseModel):
    text: str
    entities: list

class EntityInfo(BaseModel):
    entity: str
    score: float
    word: str
    start: int | None
    end: int | None

@app.post("/filter", response_model=MaskedOutput)
async def filter_pii(input: TextInput) -> MaskedOutput:
    """
    Detect and mask PII in text.

    Returns:
        - text: Input text with PII replaced by [REDACTED]
        - entities: List of detected PII entities with metadata
    """
    try:
        results = classifier(input.text)
        entities = [
            EntityInfo(
                entity=r.get("entity_group", r.get("entity", "UNKNOWN")),
                score=float(r["score"]),
                word=r["word"],
                start=r.get("start"),
                end=r.get("end")
            )
            for r in results
        ]

        # Mask entities with [REDACTED] (process in reverse to maintain indices)
        masked_text = input.text
        for entity in reversed(entities):
            if entity.start is not None and entity.end is not None:
                masked_text = masked_text[:entity.start] + "[REDACTED]" + masked_text[entity.end:]

        return MaskedOutput(text=masked_text, entities=[e.dict() for e in entities])
    except Exception as e:
        logger.error(f"Error processing text: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "model": "openai/privacy-filter", "device": device}

@app.get("/")
async def root():
    """API information."""
    return {
        "name": "Privacy Filter API",
        "version": "0.1.0",
        "model": "openai/privacy-filter",
        "endpoints": {
            "/filter": "POST - Detect and mask PII in text",
            "/health": "GET - Health check"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    chmod +x $out/bin/privacy-filter-server
  '';

  meta = {
    description = "OpenAI Privacy Filter - PII detection and masking API server";
    homepage = "https://huggingface.co/openai/privacy-filter";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "privacy-filter-server";
  };
}
