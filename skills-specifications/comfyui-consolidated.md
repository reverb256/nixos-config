# ComfyUI Skills Consolidation Specification

**Overview**: Consolidate 12 ComfyUI skills into 4 category-based skills
**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `comfyui:core` | comfyui-api, comfyui-inventory, comfyui-research, comfyui-troubleshooter | 4→1 |
| `comfyui:workflow` | comfyui-workflow-builder, comfyui-prompt-engineer, comfyui-prompt-interview, comfyui-character-gen | 4→1 |
| `comfyui:pipelines` | comfyui-video-pipeline, comfyui-voice-pipeline, comfyui-lora-training | 3→1 |
| `comfyui:dev` | comfyui-nodes-dev | 1→1 |

**Total**: 12 source skills → 4 consolidated skills

---

## 1. comfyui:core

### Skill Manifest
```yaml
name: comfyui:core
description: Core ComfyUI expertise including API interaction, node inventory management, research capabilities, and troubleshooting.

triggers:
  - "ComfyUI API..."
  - "List ComfyUI nodes..."
  - "Research ComfyUI models..."
  - "ComfyUI not working..."
  - "ComfyUI error..."
```

### Content Structure

#### 1.1 ComfyUI API Interaction

**Basic API Pattern**:
```python
import requests

COMFYUI_URL = "http://127.0.0.1:8188"

def queue_workflow(workflow_json):
    """Queue a workflow for execution"""
    response = requests.post(
        f"{COMFYUI_URL}/prompt",
        json={"prompt": workflow_json}
    )
    return response.json()

def get_history(prompt_id):
    """Get execution history for a prompt"""
    response = requests.get(
        f"{COMFYUI_URL}/history/{prompt_id}"
    )
    return response.json()

def get_queue_info():
    """Get current queue status"""
    response = requests.get(f"{COMFYUI_URL}/queue")
    return response.json()

def get_system_stats():
    """Get system performance stats"""
    response = requests.get(f"{COMFYUI_URL}/system_stats")
    return response.json()
```

**WebSocket Monitoring**:
```python
import websocket
import json

def monitor_progress(prompt_id):
    ws = websocket.create_connection(
        f"ws://127.0.0.1:8188/ws?clientId={client_id}"
    )
    for message in ws:
        data = json.loads(message)
        if data.get('type') == 'executing':
            node_id = data.get('data', {}).get('node')
            if node_id is None:
                print("Workflow complete!")
                break
            print(f"Executing node: {node_id}")
```

#### 1.2 Node Inventory Management

**Listing Available Nodes**:
```python
def get_object_info():
    """Get all available nodes and their inputs/outputs"""
    response = requests.get(f"{COMFYUI_URL}/object_info")
    return response.json()

# Example: Find all KSampler nodes
object_info = get_object_info()
ksamplers = {
    k: v for k, v in object_info.items()
    if 'KSampler' in k
}
```

**Node Categories**:
- **Sampling**: KSampler, KSamplerAdvanced
- **Loaders**: CheckpointLoader, VAELoader, LoraLoader
- **Conditioning**: CLIPTextEncode, ConditioningCombine
- **Latent**: LatentComposite, LatentUpscale
- **Image**: ImageScale, ImageBlend, ImageCrop
- **Mask**: MaskToImage, ImageToMask
- **Output**: SaveImage, PreviewImage, LoadImage
- **Advanced**: ControlNet, IPAdapter, ANS

#### 1.3 ComfyUI Research

**Model Sources**:
- **Civitai**: https://civitai.com (LoRAs, checkpoints)
- **HuggingFace**: https://huggingface.co (official models)
- **ComfyUI Nodes**: https://github.com/comfyanonymous/ComfyUI_nodes

**Finding Custom Nodes**:
```bash
# Search GitHub for custom nodes
# Search query: "ComfyUI nodes" + topic (e.g., "controlnet")

# Popular custom node packs:
- ComfyUI_IPAdapter_plus
- ComfyUI-Inspire-Pack
- ComfyUI_Custom_Nodes_Zuco
- ComfyUI_Comfyroll_CustomNodes
```

**Model Installation**:
```bash
# Checkpoints
models/checkpoints/
models/vae/
models/loras/
models/embeddings/
models/controlnet/

# Custom nodes in:
ComfyUI/custom_nodes/
```

#### 1.4 Troubleshooting

**Common Issues & Solutions**:

| Issue | Cause | Solution |
|-------|-------|----------|
| "Model not found" | Wrong path | Check `model_paths.yaml` |
| Out of memory | Resolution too high | Lower resolution, enable tiled VAE |
| Slow generation | CPU mode | Check GPU is being used |
| NaN errors | Corrupted model | Redownload model |
| Wrong colorspace | Missing VAE | Ensure VAE is loaded |

**Debug Workflow**:
```python
# Enable detailed logging
import logging
logging.basicConfig(level=logging.DEBUG)

# Check node connections
# - Verify output types match input types
# - Check required vs optional inputs
# - Ensure default values are valid
```

---

## 2. comfyui:workflow

### Skill Manifest
```yaml
name: comfyui:workflow
description: ComfyUI workflow building expertise including workflow construction, prompt engineering, guided interviews, and character generation.

triggers:
  - "Build ComfyUI workflow..."
  - "ComfyUI prompt for..."
  - "Character in ComfyUI..."
  - "Optimize ComfyUI prompt..."
```

### Content Structure

#### 2.1 Workflow Builder Pattern

**Basic Text-to-Image Workflow**:
```json
{
  "1": {
    "class_type": "CheckpointLoaderSimple",
    "inputs": {
      "ckpt_name": "v1-5-pruned.ckpt"
    }
  },
  "2": {
    "class_type": "CLIPTextEncode",
    "inputs": {
      "text": "beautiful landscape, masterpiece",
      "clip": ["1", 1]
    }
  },
  "3": {
    "class_type": "CLIPTextEncode",
    "inputs": {
      "text": "ugly, blurry, low quality",
      "clip": ["1", 1]
    }
  },
  "4": {
    "class_type": "KSampler",
    "inputs": {
      "model": ["1", 0],
      "positive": ["2", 0],
      "negative": ["3", 0],
      "seed": 123456,
      "steps": 20,
      "cfg": 7,
      "sampler_name": "euler_a",
      "scheduler": "normal",
      "denoise": 1.0
    }
  },
  "5": {
    "class_type": "VAEDecode",
    "inputs": {
      "samples": ["4", 0],
      "vae": ["1", 2]
    }
  },
  "6": {
    "class_type": "SaveImage",
    "inputs": {
      "images": ["5", 0],
      "filename_prefix": "output"
    }
  }
}
```

#### 2.2 Prompt Engineering

**Positive Prompt Structure**:
```
[Subject] + [Action/Pose] + [Environment] + [Style] + [Quality Tags]

Example:
"beautiful woman, standing in a garden,
surrounded by flowers, soft lighting,
anime style, studio Ghibli, masterpiece,
best quality, highly detailed"
```

**Negative Prompt Template**:
```
"ugly, blurry, low quality, distorted,
deformed, watermark, text, bad anatomy,
bad hands, extra fingers, missing fingers"
```

**Prompt Modifiers by Style**:
| Style | Positive Keywords | Negative Keywords |
|-------|------------------|-------------------|
| Photorealistic | raw photo, dslr, 8k | painting, cartoon, anime |
| Anime | anime, manga, cel shaded | photorealistic, 3d render |
| Oil Painting | oil painting, brush strokes | digital, photo, flat color |
| 3D Render | 3d, octane render, unreal | painting, sketch, 2d |

#### 2.3 Character Generation

**Character Prompt Template**:
```
[Character Name], [Appearance Details],
[Clothing], [Pose], [Expression],
[Setting], [Art Style], [Quality Tags]

Example:
"Adventurer, female with long silver hair,
wearing leather armor and cape,
holding a sword, confident smile,
standing on a cliff at sunset,
fantasy art, detailed background,
masterpiece, best quality"
```

**Consistency Techniques**:
- Use fixed seed for base character
- Reference images with IPAdapter
- ControlNet for pose consistency
- LoRA training for specific character

#### 2.4 Workflow Optimization

**Batch Processing**:
```json
{
  "class_type": "KSampler",
  "inputs": {
    "seed": 0,  // 0 = random each time
    "steps": 20,
    "denoise": 1.0
  }
}
```

**Quality vs Speed**:
| Quality | Steps | CFG | Sampler | Time |
|---------|-------|-----|---------|------|
| Draft | 10-15 | 6-7 | euler_a | Fast |
| Good | 20-25 | 7-8 | ddim++ | Medium |
| Best | 30-50 | 8-12 | ddim, uni_pc | Slow |

---

## 3. comfyui:pipelines

### Skill Manifest
```yaml
name: comfyui:pipelines
description: ComfyUI pipeline expertise for video generation, voice synthesis, and LoRA training.

triggers:
  - "Generate video in ComfyUI..."
  - "Voice in ComfyUI..."
  - "Train LoRA in ComfyUI..."
  - "Animate image..."
```

### Content Structure

#### 3.1 Video Pipeline

**Image-to-Video Workflow**:
```python
video_workflow = {
    "1": {
        "class_type": "CheckpointLoaderSimple",
        "inputs": {"ckpt_name": "svd_xt.safetensors"}
    },
    "2": {
        "class_type": "VAEDecode",
        "inputs": {"samples": ["4", 0], "vae": ["1", 2]}
    },
    "3": {
        "class_type": "VHS_SaveAudio",
        "inputs": {"audio": "output/audio.wav"}
    },
    "4": {
        "class_type": "SVD_img2vid_Conditioning",
        "inputs": {
            "init_image": "input.png",
            "width": 1024,
            "height": 576,
            "frames": 24,
            "motion_bucket_id": 127
        }
    }
}
```

**Video Settings**:
- **Frames**: 16-24 for short clips
- **FPS**: 8-24 for generated video
- **Motion Bucket**: 1-255 (1 = less motion, 255 = more)
- **Resolution**: 512x512 to 1024x576

#### 3.2 Voice Pipeline

**TTS Generation**:
```python
voice_workflow = {
    "1": {
        "class_type": "CoquiTTSGenerator",
        "inputs": {
            "text": "Hello, this is a test.",
            "model": "tts_models/multilingual/multi-dataset/xtts_v2",
            "language": "en",
            "speaker_wav": "reference.wav"
        }
    },
    "2": {
        "class_type": "VHS_SaveAudio",
        "inputs": {
            "audio": ["1", 0],
            "filename_prefix": "output/voice"
        }
    }
}
```

**Voice Cloning**:
```bash
# Required:
# - Reference audio (3-10 seconds)
# - Clean audio, no background noise
# - Single speaker
# - Consistent tone
```

#### 3.3 LoRA Training

**Training Workflow**:
```python
training_workflow = {
    "1": {
        "class_type": "LoraLoader",
        "inputs": {
            "lora_name": "my_lora.safetensors",
            "strength_model": 1.0,
            "strength_clip": 1.0
        }
    },
    "2": {
        "class_type": "LoraTrainingNode",
        "inputs": {
            "training_images": "training_data/*.png",
            "output_name": "my_lora",
            "rank": 128,
            "learning_rate": 0.0001,
            "epochs": 10,
            "batch_size": 1
        }
    }
}
```

**Dataset Preparation**:
```
training_data/
├── image_001.png
├── image_001.txt  # Caption: "Description of image"
├── image_002.png
├── image_002.txt
└── ...
```

**Training Parameters**:
- **Rank**: 32-256 (higher = more capacity, larger file)
- **Learning Rate**: 0.0001 - 0.00001
- **Epochs**: 10-100 depending on dataset size
- **Resolution**: Match base model (512 or 768)

---

## 4. comfyui:dev

### Skill Manifest
```yaml
name: comfyui:dev
description: ComfyUI custom node development including server-side V3 custom nodes.

triggers:
  - "Create ComfyUI node..."
  - "ComfyUI custom node..."
  - "Develop ComfyUI extension..."
```

### Content Structure

#### 4.1 Custom Node Structure

```
my_comfy_nodes/
├── __init__.py          # Node registration
├── nodes.py             # Node implementations
├── requirements.txt     # Dependencies
└── config.json          # Metadata
```

#### 4.2 Node Implementation Template

```python
# nodes.py
import torch
from comfy import model_management

class MyCustomNode:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "input_image": ("IMAGE",),
                "strength": ("FLOAT", {
                    "default": 1.0,
                    "min": 0.0,
                    "max": 10.0,
                    "step": 0.1
                }),
                "mode": (["mode_a", "mode_b"],),
            },
            "optional": {
                "optional_input": ("STRING", {"default": "default_value"}),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("output_image",)
    FUNCTION = "process"
    CATEGORY = "image/processing"

    def process(self, input_image, strength, mode, optional_input=""):
        # Process the image
        output = input_image * strength

        # Return tensor(s)
        return (output,)

# Node mapping
NODE_CLASS_MAPPINGS = {
    "MyCustomNode": MyCustomNode,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "MyCustomNode": "My Custom Processing Node"
}
```

#### 4.3 Common Node Patterns

**Image Processing Node**:
```python
def process_image(image):
    # image shape: [batch, height, width, channels]
    batch, h, w, c = image.shape

    # Process
    result = torch.nn.functional.relu(image)

    return (result,)
```

**Latent Processing Node**:
```python
def process_latent(latent):
    # latent shape: [batch, channels, height//8, width//8]
    result = latent * 1.5
    return (result,)
```

**Text Processing Node**:
```python
def process_text(clip, text):
    tokens = clip.tokenize(text)
    return (tokens,)
```

#### 4.4 Testing & Validation

```python
# Test your node
def test_my_node():
    # Create dummy input
    dummy_image = torch.zeros((1, 512, 512, 3))

    # Run node
    node = MyCustomNode()
    output = node.process(dummy_image, strength=1.0, mode="mode_a")

    # Validate output
    assert output[0].shape == dummy_image.shape
    print("Node test passed!")
```

---

## Quick Reference

| Task | Use This Skill |
|------|---------------|
| Connect to ComfyUI API | comfyui:core |
| Find available nodes | comfyui:core |
| Build generation workflow | comfyui:workflow |
| Create character | comfyui:workflow |
| Generate video | comfyui:pipelines |
| Clone voice | comfyui:pipelines |
| Train custom LoRA | comfyui:pipelines |
| Develop custom node | comfyui:dev |

---

## References

- ComfyUI GitHub: https://github.com/comfyanonymous/ComfyUI
- ComfyUI Examples: https://github.com/comfyanonymous/ComfyUI_examples
- Civitai Models: https://civitai.com
- ComfyUI Node Registry: https://comfyui-node-registries.github.io/
