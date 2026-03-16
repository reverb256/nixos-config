#!/usr/bin/env python3
"""
Text-to-Speech Handler

Supports multiple TTS backends:
- Pollinations.ai (free, cloud-based, multiple voices)
- Qwen3-TTS models (local, via HuggingFace transformers)

Based on:
- Pollinations TTS API: https://text.pollinations.ai
- OpenAI API reference: https://platform.openai.com/docs/api-reference/audio/createSpeech
"""

import logging
import asyncio
import io
from pathlib import Path
from typing import Optional, Dict, Any, Literal, Union, TYPE_CHECKING
from dataclasses import dataclass
from urllib.parse import quote

import httpx
from fastapi import HTTPException
from pydantic import BaseModel, Field

# Type checking imports - these are only imported when actually used
if TYPE_CHECKING:
    import numpy as np

logger = logging.getLogger(__name__)


# ============================================================================
# REQUEST/RESPONSE MODELS (OpenAI compatible)
# ============================================================================

TTSAudioFormat = Literal["mp3", "opus", "aac", "flac", "wav", "pcm16"]


class TTSRequest(BaseModel):
    """Text-to-speech request (OpenAI compatible format)."""

    model: str = Field(
        description="TTS model to use",
        pattern="^(tts-1|tts-1-hd|pollinations-tts|qwen3-tts|Qwen3-TTS|Qwen/Qwen3-TTS).*"
    )
    input: str = Field(..., description="Text to synthesize")
    voice: str = Field(
        default="alloy",
        description="Voice to use (for compatibility, mapped to internal voices)"
    )
    response_format: TTSAudioFormat = Field(
        default="mp3",
        description="Audio output format"
    )
    speed: float = Field(
        default=1.0,
        ge=0.25,
        le=4.0,
        description="Speed of audio playback"
    )


class TTSResponse(BaseModel):
    """TTS response (OpenAI compatible format)."""

    id: str = Field(description="Unique identifier for the speech generation")
    object: Literal["speech"] = "speech"
    created: int = Field(description="Unix timestamp of creation")
    model: str = Field(description="Model used")
    content: bytes = Field(description="Audio data (for binary response)")
    # For JSON response with base64
    b64_json: Optional[str] = Field(default=None, description="Base64 encoded audio")


# ============================================================================
# TTS MODEL CONFIGURATION
# ============================================================================

QWEN3_TTS_MODELS = {
    # Pollinations.ai TTS (cloud, free, OpenAI-compatible voices)
    "tts-1": {
        "model_id": "pollinations-tts-1",
        "sample_rate": 24000,
        "max_tokens": 4096,
        "description": "Pollinations TTS - OpenAI compatible, free cloud service",
        "quality": "standard",
        "language": "en",
        "backend": "pollinations",
    },
    "tts-1-hd": {
        "model_id": "pollinations-tts-1-hd",
        "sample_rate": 24000,
        "max_tokens": 4096,
        "description": "Pollinations TTS HD - Higher quality",
        "quality": "high",
        "language": "en",
        "backend": "pollinations",
    },
    "pollinations-tts": {
        "model_id": "pollinations-tts",
        "sample_rate": 24000,
        "max_tokens": 4096,
        "description": "Pollinations.ai free TTS service",
        "quality": "standard",
        "language": "en",
        "backend": "pollinations",
    },
    # Qwen3-TTS models (local, via transformers)
    "qwen3-tts-12hz-0.6b": {
        "model_id": "Qwen/Qwen3-TTS-12Hz-0.6B-Base",
        "sample_rate": 12000,
        "max_tokens": 2048,
        "description": "Lightweight TTS model, faster inference (local, requires transformers)",
        "quality": "standard",
        "language": "en",
        "backend": "local",
    },
    "qwen3-tts-12hz-1.7b": {
        "model_id": "Qwen/Qwen3-TTS-12Hz-1.7B-Base",
        "sample_rate": 12000,
        "max_tokens": 2048,
        "description": "Full TTS model, better quality (local, requires transformers)",
        "quality": "high",
        "language": "en",
        "backend": "local",
    },
    "qwen3-tts-12hz-1.7b-customvoice": {
        "model_id": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
        "sample_rate": 12000,
        "max_tokens": 2048,
        "description": "Voice cloning capabilities (local, requires transformers)",
        "quality": "high",
        "supports_voice_cloning": True,
        "language": "en",
        "backend": "local",
    },
    "qwen3-tts-12hz-1.7b-voicedesign": {
        "model_id": "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
        "sample_rate": 12000,
        "max_tokens": 2048,
        "description": "Procedural voice generation (local, requires transformers)",
        "quality": "high",
        "supports_procedural_voices": True,
        "language": "en",
        "backend": "local",
    },
}


# Voice mapping (OpenAI voices → Pollinations voices)
# Pollinations supports many voices including:
# - OpenAI voices: alloy, echo, fable, onyx, nova, shimmer
# - Additional voices: various male/female options
VOICE_MAPPING = {
    "alloy": "alloy",
    "echo": "echo",
    "fable": "fable",
    "onyx": "onyx",
    "nova": "nova",
    "shimmer": "shimmer",
    # Additional Pollinations voices
    "rachel": "rachel",
    "drew": "drew",
    "clyde": "clyde",
    "sarah": "sarah",
    "jessie": "jessie",
    "joe": "joe",
    "emily": "emily",
    "bill": "bill",
    "michael": "michael",
    "matthew": "matthew",
    "linda": "linda",
    "charlotte": "charlotte",
    "james": "james",
    "daniel": "daniel",
    "kate": "kate",
    "elizabeth": "elizabeth",
    # Male voices
    "adam": "adam",
    "narrator": "narrator",
    "fin": "fin",
    # Female voices
    "bfem": "bfem",
    "bfm": "bfm",
    "gfem": "gfem",
    "gfm": "gfm",
    "mfem": "mfem",
    "mfm": "mfm",
}

# Pollinations TTS backend URL
POLLINATIONS_TTS_URL = "https://text.pollinations.ai"


# =============================================================================
# TTS HANDLER
# =============================================================================

@dataclass
class TTSHandler:
    """Handler for TTS models via Pollinations.ai or local models."""

    backend_url: str
    pollinations_url: str = POLLINATIONS_TTS_URL
    timeout: int = 60
    enable_local_models: bool = False

    def __post_init__(self):
        self._client: Optional[httpx.AsyncClient] = None

    @property
    def client(self) -> httpx.AsyncClient:
        """Lazy-initialized async HTTP client."""
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=self.timeout,
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
                follow_redirects=True
            )
        return self._client

    async def close(self):
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None

    def get_model_config(self, model_name: str) -> Optional[Dict[str, Any]]:
        """Get configuration for a TTS model."""
        # Normalize model name
        model_key = model_name.lower().replace("qwen/qwen3-tts-", "qwen3-tts-")
        model_key = model_key.replace("qwen/qwen3-", "qwen3-")

        # Try exact match first
        if model_key in QWEN3_TTS_MODELS:
            return QWEN3_TTS_MODELS[model_key]

        # Try fuzzy match
        for key, config in QWEN3_TTS_MODELS.items():
            if model_key in key or key in model_key:
                return config

        # Default to pollinations if no match
        return {
            "model_id": "pollinations-tts",
            "sample_rate": 24000,
            "max_tokens": 4096,
            "description": "Pollinations.ai free TTS service",
            "quality": "standard",
            "language": "en",
            "backend": "pollinations",
        }

    async def generate_speech_pollinations(
        self,
        text: str,
        voice: str = "alloy",
        speed: float = 1.0,
        response_format: str = "mp3"
    ) -> tuple[bytes, str, int]:
        """
        Generate speech from text using Pollinations.ai TTS.

        Returns:
            (audio_data, content_type, sample_rate)
        """
        # Normalize voice name
        if voice not in VOICE_MAPPING and voice not in ["default"]:
            logger.warning(f"Unknown voice '{voice}', using 'alloy'")
            voice = "alloy"
        elif voice == "default":
            voice = "alloy"

        # URL encode the text
        encoded_text = quote(text, safe='')

        # Pollinations TTS URL format:
        # https://text.pollinations.ai/{encoded_text}?model=openai&voice={voice}
        tts_url = f"{self.pollinations_url}/{encoded_text}"

        # Build query parameters
        params = {
            "model": "openai",  # Use OpenAI voice model
            "voice": voice,
        }

        # Add speed if not default
        if speed != 1.0:
            params["speed"] = str(speed)

        logger.info(f"Pollinations TTS request: voice={voice}, speed={speed}, text_len={len(text)}")

        try:
            response = await self.client.get(tts_url, params=params)
            response.raise_for_status()

            audio_data = response.content
            content_type = response.headers.get("content-type", get_content_type(response_format))

            # Pollinations typically returns 24kHz audio
            sample_rate = 24000

            logger.info(f"Pollinations TTS success: {len(audio_data)} bytes, content-type={content_type}")

            return audio_data, content_type, sample_rate

        except httpx.HTTPStatusError as e:
            logger.error(f"Pollinations TTS HTTP error: {e.response.status_code} - {e.response.text[:200]}")
            raise HTTPException(
                status_code=e.response.status_code,
                detail=f"Pollinations TTS error: {e.response.text[:200]}"
            )
        except Exception as e:
            logger.error(f"Pollinations TTS error: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"TTS generation failed: {str(e)}"
            )

    async def generate_speech(
        self,
        text: str,
        model: str,
        voice: str = "alloy",
        speed: float = 1.0,
        response_format: str = "mp3"
    ) -> tuple[bytes, str, int]:
        """
        Generate speech from text using the best available backend.

        Returns:
            (audio_data, content_type, sample_rate)
        """
        # Get model config to determine backend
        model_config = self.get_model_config(model)
        backend = model_config.get("backend", "pollinations")

        if backend == "pollinations":
            return await self.generate_speech_pollinations(text, voice, speed, response_format)

        # Local model support (transformers, etc.)
        if not self.enable_local_models:
            raise HTTPException(
                status_code=501,
                detail=f"Local TTS models not yet enabled. "
                      f"Set enable_local_models=True or use a Pollinations model (tts-1, tts-1-hd, pollinations-tts)."
            )

        # Local Qwen3-TTS model
        return await self.generate_speech_qwen3(
            text=text,
            model=model,
            model_config=model_config,
            voice=voice,
            speed=speed,
            response_format=response_format
        )

    async def generate_speech_qwen3(
        self,
        text: str,
        model: str,
        model_config: Dict[str, Any],
        voice: str = "alloy",
        speed: float = 1.0,
        response_format: str = "mp3"
    ) -> tuple[bytes, str, int]:
        """
        Generate speech from text using local Qwen3-TTS models via transformers.

        Qwen3-TTS uses a transformer-based architecture for speech synthesis.
        The models are available on HuggingFace and use the Qwen3TTSForConditionalGeneration class.

        Returns:
            (audio_data, content_type, sample_rate)
        """
        import torch
        import numpy as np
        import io

        model_id = model_config["model_id"]
        sample_rate = model_config["sample_rate"]

        logger.info(f"Loading Qwen3-TTS model: {model_id}")

        try:
            # Import the Qwen3-TTS model classes
            from transformers import AutoTokenizer, AutoModelForCausalLM
            from transformers.generation import GenerationConfig

            # Load model and tokenizer in a thread pool to avoid blocking
            loop = asyncio.get_event_loop()

            def load_model_components():
                # Load the Qwen3-TTS model
                # These models use a specific architecture for TTS
                model = AutoModelForCausalLM.from_pretrained(
                    model_id,
                    torch_dtype=torch.float16,
                    device_map="auto",
                    trust_remote_code=True
                )
                tokenizer = AutoTokenizer.from_pretrained(
                    model_id,
                    trust_remote_code=True
                )
                return model, tokenizer

            model, tokenizer = await loop.run_in_executor(None, load_model_components)

            logger.info(f"Model loaded, generating speech for text: {text[:50]}...")

            # Qwen3-TTS models have a specific text-to-speech method
            def generate_audio():
                with torch.no_grad():
                    # Check if model has a dedicated TTS method
                    if hasattr(model, 'generate_speech'):
                        # Use the built-in TTS generation method
                        audio_array = model.generate_speech(
                            text=text,
                            voice=voice,
                            speed=speed
                        )
                    elif hasattr(model, 'tts'):
                        # Alternative TTS method
                        audio_array = model.tts(
                            text=text,
                            speaker=voice
                        )
                    else:
                        # Use the generate method with TTS-specific parameters
                        # Qwen3-TTS models accept text input and output audio
                        inputs = tokenizer(text, return_tensors="pt")

                        # Move inputs to the same device as model
                        if hasattr(model, 'device'):
                            device = model.device
                        else:
                            device = next(model.parameters()).device

                        inputs = {k: v.to(device) for k, v in inputs.items()}

                        # Generate with TTS parameters
                        generation_config = GenerationConfig(
                            max_new_tokens=2048,
                            do_sample=True,
                            temperature=0.7,
                            top_p=0.9,
                        )

                        outputs = model.generate(
                            **inputs,
                            generation_config=generation_config
                        )

                        # The output needs to be decoded to audio
                        # For Qwen3-TTS, the output is audio tokens that need to be decoded
                        if hasattr(model, 'decode_audio'):
                            audio_array = model.decode_audio(outputs)
                        elif hasattr(tokenizer, 'decode_audio'):
                            audio_array = tokenizer.decode_audio(outputs)
                        else:
                            # Fallback: convert output to numpy array
                            audio_array = outputs[0].cpu().numpy()

                return audio_array

            audio_array = await loop.run_in_executor(None, generate_audio)

            # Ensure we have a numpy array
            if not isinstance(audio_array, np.ndarray):
                if torch.is_tensor(audio_array):
                    audio_array = audio_array.cpu().numpy()
                else:
                    audio_array = np.array(audio_array)

            # Normalize audio if it's floating point
            if audio_array.dtype in [np.float32, np.float64]:
                if np.max(np.abs(audio_array)) > 1.0:
                    audio_array = audio_array / np.max(np.abs(audio_array))
                audio_array = (audio_array * 32767).astype(np.int16)

            # Apply speed adjustment if needed
            if speed != 1.0 and speed > 0:
                original_length = len(audio_array)
                new_length = int(original_length / speed)
                if new_length > 0:
                    indices = np.linspace(0, original_length - 1, new_length)
                    audio_array = np.interp(indices, np.arange(original_length), audio_array).astype(np.int16)

            # Convert to requested format
            audio_bytes, content_type = self._convert_audio_format(
                audio_array, sample_rate, response_format
            )

            logger.info(f"Qwen3-TTS success: {len(audio_bytes)} bytes, format={response_format}")

            return audio_bytes, content_type, sample_rate

        except ImportError as e:
            logger.error(f"Missing dependencies for local TTS: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Local TTS requires transformers and torch. Missing: {e}"
            )
        except OSError as e:
            # Model download errors
            logger.error(f"Failed to load Qwen3-TTS model: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to load TTS model. Ensure you have internet access for the first download: {e}"
            )
        except Exception as e:
            logger.error(f"Qwen3-TTS generation failed: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Local TTS generation failed: {str(e)}"
            )

        except ImportError as e:
            logger.error(f"Missing dependencies for local TTS: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Local TTS requires transformers, torch, and torchaudio. Missing: {e}"
            )
        except Exception as e:
            logger.error(f"Qwen3-TTS generation failed: {e}")
            raise HTTPException(
                status_code=500,
                detail=f"Local TTS generation failed: {str(e)}"
            )

    def _convert_audio_format(
        self,
        audio_array: any,
        sample_rate: int,
        output_format: str
    ) -> tuple[bytes, str]:
        """
        Convert audio array to the requested format.

        Returns:
            (audio_bytes, content_type)
        """
        import numpy as np
        import io

        # Ensure audio_array is a numpy array
        if not isinstance(audio_array, np.ndarray):
            audio_array = np.array(audio_array, dtype=np.int16)

        if output_format == "wav":
            # Write WAV file
            buffer = io.BytesIO()
            import wave
            with wave.open(buffer, 'wb') as wav_file:
                wav_file.setnchannels(1)  # Mono
                wav_file.setsampwidth(2)  # 16-bit
                wav_file.setframerate(sample_rate)
                wav_file.writeframes(audio_array.tobytes())
            return buffer.getvalue(), "audio/wav"

        elif output_format == "mp3":
            # Try to use pydub for MP3 conversion (requires ffmpeg)
            try:
                from pydub import AudioSegment
                import io

                # Create AudioSegment from raw audio data
                audio_segment = AudioSegment(
                    data=audio_array.tobytes(),
                    sample_width=audio_array.dtype.itemsize,
                    frame_rate=sample_rate,
                    channels=1
                )

                buffer = io.BytesIO()
                audio_segment.export(buffer, format="mp3", bitrate="128k")
                return buffer.getvalue(), "audio/mpeg"

            except ImportError:
                # Fallback to WAV if pydub not available
                logger.warning("pydub not available, falling back to WAV format")
                return self._convert_audio_format(audio_array, sample_rate, "wav")

        elif output_format == "flac":
            # Try to use soundfile for FLAC
            try:
                import soundfile
                buffer = io.BytesIO()
                soundfile.write(buffer, audio_array, sample_rate, format='FLAC')
                return buffer.getvalue(), "audio/flac"
            except ImportError:
                # Fallback to WAV
                logger.warning("soundfile not available, falling back to WAV format")
                return self._convert_audio_format(audio_array, sample_rate, "wav")

        else:
            # Default to WAV for unsupported formats
            return self._convert_audio_format(audio_array, sample_rate, "wav")


# =============================================================================
# TTS SERVICE (singleton)
# =============================================================================

_tts_handler: Optional[TTSHandler] = None


def get_tts_handler(backend_url: str) -> TTSHandler:
    """Get or create the TTS handler singleton."""
    global _tts_handler
    if _tts_handler is None or _tts_handler.backend_url != backend_url:
        _tts_handler = TTSHandler(backend_url=backend_url)
    return _tts_handler


async def close_tts_handler():
    """Close the TTS handler connection."""
    global _tts_handler
    if _tts_handler:
        await _tts_handler.close()
        _tts_handler = None


# =============================================================================
# CONTENT TYPE MAPPING
# =============================================================================

AUDIO_CONTENT_TYPES = {
    "mp3": "audio/mpeg",
    "opus": "audio/opus;codecs=opus",
    "aac": "audio/aac",
    "flac": "audio/flac",
    "wav": "audio/wav",
    "pcm16": "audio/pcm;codec=pcm-16",
}

AUDIO_EXTENSIONS = {
    "mp3": ".mp3",
    "opus": ".opus",
    "aac": ".aac",
    "flac": ".flac",
    "wav": ".wav",
    "pcm16": ".pcm",
}


def get_content_type(format: str) -> str:
    """Get content type for audio format."""
    return AUDIO_CONTENT_TYPES.get(format, "audio/wav")


def get_audio_extension(format: str) -> str:
    """Get file extension for audio format."""
    return AUDIO_EXTENSIONS.get(format, ".wav")
