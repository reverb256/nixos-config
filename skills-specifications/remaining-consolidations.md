# Remaining Skills Consolidation Specifications

**Overview**: Consolidations for HuggingFace, Game Design, and Notion skills
**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## 1. HuggingFace Skills (10→9)

### Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `huggingface:datasets` | hugging-face-datasets, hugging-face-dataset-viewer | 2→1 |

**Keep Separate** (distinct functionality):
- huggingface-cli (tool operations)
- huggingface-evaluation (metrics)
- huggingface-tool-builder (MCP tools)
- huggingface-paper-publisher (publishing)
- huggingface-trackio (experiment tracking)
- huggingface-jobs (training jobs)
- huggingface-model-trainer (training)
- huggingface-gradio (UI building)

---

### huggingface:datasets

**Skill Manifest**:
```yaml
name: huggingface:datasets
description: Complete HuggingFace Datasets expertise including dataset viewing, loading, processing, and management.

triggers:
  - "HF dataset for..."
  - "View HuggingFace dataset..."
  - "Process dataset..."
  - "Load dataset from HF..."
```

**Content Structure**:

#### 1.1 Dataset Discovery & Viewing

```python
from huggingface_hub import list_datasets

# Search datasets
datasets = list_datasets(search="text", filter="medium")
for dataset in datasets:
    print(f"{dataset.id}: {dataset.description}")

# View dataset info
from datasets import load_dataset_builder
info = load_dataset_builder("imdb")
print(info.info.description)
print(info.info.features)
```

#### 1.2 Loading & Processing

```python
from datasets import load_dataset

# Load dataset
dataset = load_dataset("imdb")
train = dataset["train"]
test = dataset["test"]

# Process
def preprocess(example):
    return {"text": example["text"].lower()}

dataset = dataset.map(preprocess)

# Filter
dataset = dataset.filter(lambda x: len(x["text"]) > 100)

# Split
dataset = dataset.train_test_split(test_size=0.2)
```

#### 1.3 Dataset Viewer Features

- Preview first N rows
- View schema and features
- Statistics (size, splits)
- Download options
- Format conversion (parquet, json, csv)

#### 1.4 Best Practices

- Use `load_dataset_builder()` before loading large datasets
- Use streaming for datasets larger than memory
- Cache processed datasets locally
- Use `dataset.save_to_disk()` for persistence

---

## 2. Game Design Skills (5→2)

### Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `game:design` | game-ui-design, game-designer | 2→1 |
| `game:animation` | dramatic-2000ms-plus, micro-interactions, emotional-narrative | 3→1 |

---

### 2.1 game:design

**Skill Manifest**:
```yaml
name: game:design
description: Complete game design expertise including UI design, player feedback, game feel, and core mechanics.

triggers:
  - "Game UI for..."
  - "Game mechanics for..."
  - "Player feedback..."
  - "Game feel..."
```

**Content Structure**:

#### Game UI Principles

1. **Visibility**: Important info always visible
2. **Feedback**: Actions have clear responses
3. **Consistency**: Similar things work similarly
4. **Affordance**: Buttons look clickable
5. **Forgiveness**: Easy to undo mistakes

#### Game Feel Framework

| Element | Description | Examples |
|---------|-------------|----------|
| **Input** | How player acts | Buttons, gestures, timing |
| **Response** | What happens | Animation, sound, screen shake |
| **Context** | Game state relevance | Combo counter, danger level |
| **Polish** | Extra juice | Particles, screen effects |

#### Design Patterns

**Progressive Disclosure**:
```
Tutorial Layer 1: Basic controls
Tutorial Layer 2: Advanced moves
Tutorial Layer 3: Strategies
Tutorial Layer 4: Meta-game
```

**Flow Channel**:
```
Challenge ↑
     │
     │    Flow Channel
     │   ╱      ╲
     │  ╱        ╲
     │ ╱          ╲
     └──────────────→ Skill
  Bored  ←───────→  Anxious
```

---

### 2.2 game:animation

**Skill Manifest**:
```yaml
name: game:animation
description: Game animation expertise including dramatic sequences, micro-interactions, and emotional narrative through motion.

triggers:
  - "Game animation for..."
  - "Micro-interaction..."
  - "Emotional scene..."
  - "Dramatic moment..."
```

**Content Structure**:

#### Animation Principles (12 Principles Adapted for Games)

1. **Squash & Stretch**: Conveys weight/flexibility
2. **Anticipation**: Prepares player for action
3. **Staging**: Clear focus on important elements
4. **Straight Ahead/Pose to Pose**: Workflow choice
5. **Follow Through/Overlapping**: Natural movement
6. **Slow In/Out**: Ease into/out of movements
7. **Arcs**: Natural motion paths
8. **Secondary Action**: Adds depth
9. **Timing**: Spacing determines weight
10. **Exaggeration**: Clarity over realism
11. **Solid Drawing**: 3D form understanding
12. **Appeal**: Design quality

#### Micro-interactions

```yaml
Button States:
  idle:      { scale: 1.0, opacity: 0.8 }
  hover:     { scale: 1.1, opacity: 1.0 }
  pressed:   { scale: 0.95, opacity: 1.0 }
  disabled:  { scale: 1.0, opacity: 0.5 }

Transition Timing:
  idle → hover:     150ms ease-out
  hover → idle:     200ms ease-in
  any → pressed:    50ms linear
  pressed → hover:  100ms ease-out
```

#### Emotional Narrative Through Animation

| Emotion | Motion Characteristics | Color/Lighting |
|---------|----------------------|----------------|
| Joy | Bouncy, upward, expanding | Bright, warm |
| Sadness | Downward, slow, heavy | Desaturated, cool |
| Anger | Sharp, fast, trembling | Red, high contrast |
| Fear | Shaking, small, jerky | Dark, shadows |
| Surprise | Exaggerated, snap | Bright flash |

#### Dramatic Timing (2000ms+)

**Slow Motion Moments**:
```yaml
# Trigger conditions
- Critical hit landed
- Boss defeated
- Story revelation
- Player death

# Implementation
time_scale = 0.2  # 5x slower
duration = 2000ms
camera_shake = true
sound_pitch = 0.8
```

**Extended Animations**:
- Opening sequence: 2000-5000ms
- Victory animation: 1500-3000ms
- Defeat animation: 2000-4000ms
- Level transition: 1000-2000ms

---

## 3. Notion Skills (10→9)

### Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `Notion:search` | Notion:find, Notion:search | 2→1 |

**Keep Separate** (distinct functionality):
- Notion:create-database-row
- Notion:create-page
- Notion:create-task
- Notion:database-query
- Notion:tasks:build
- Notion:tasks:explain-diff
- Notion:tasks:plan
- Notion:tasks:setup

---

### Notion:search

**Skill Manifest**:
```yaml
name: Notion:search
description: Complete Notion search expertise finding pages, databases, and content across workspaces.

triggers:
  - "Search Notion for..."
  - "Find in Notion..."
  - "Notion page for..."
  - "Locate Notion..."
```

**Content Structure**:

#### 1.1 Search Methods

```python
# Using Notion API
from notion_client import Client

notion = Client(auth="your-token")

# Search across workspace
results = notion.search(
    query="my query",
    filter={
        "property": "object",
        "value": "page"  # or "database"
    }
)

# Search with sort
results = notion.search(
    query="project",
    sort={
        "direction": "ascending",
        "timestamp": "last_edited_time"
    }
)
```

#### 1.2 Search Strategies

| Query Type | Example | Use Case |
|------------|---------|----------|
| Title search | "Marketing Plan" | Find specific page |
| Content search | "Q4 goals" | Find mentions |
| Tag search | "#important" | Filter by tags |
| Database filter | property:value | Structured search |

#### 1.3 Advanced Filtering

```python
# Filter by database properties
response = notion.databases.query(
    database_id="db_id",
    filter={
        "and": [
            {"property": "Status", "select": {"equals": "In Progress"}},
            {"property": "Priority", "number": {"greater_than": 3}}
        ]
    }
)
```

#### 1.4 Best Practices

- Use specific search terms (3+ words)
- Filter by object type (page vs database)
- Use property filters for databases
- Cache frequently accessed pages
- Use sort for relevant results first

---

## Summary of All Consolidations

| Category | Before | After | Reduction |
|----------|--------|-------|------------|
| Documentation | 3 | 1 | -2 |
| NixOS | 2 | 1 | -1 |
| Docker | 3 | 1 | -2 |
| Kubernetes | 4 | 1 | -3 |
| Marketing | 30+ | 8 | -22 |
| ComfyUI | 12 | 4 | -8 |
| Pinecone | 7 | 3 | -4 |
| HuggingFace | 10 | 9 | -1 |
| Games | 5 | 2 | -3 |
| Notion | 10 | 9 | -1 |
| **TOTAL** | **~90** | **~40** | **~-50** |

---

## Implementation Priority

### Phase 1: Core Development (High Impact, Low Risk)
1. Documentation: `documentation:complete`
2. NixOS: `nixos:complete`
3. Docker: `docker:complete`
4. Kubernetes: `kubernetes:core`

### Phase 2: Domain Consolidations (Medium Impact, Medium Risk)
5. Marketing: 8 consolidated skills
6. ComfyUI: 4 consolidated skills
7. Pinecone: 3 consolidated skills

### Phase 3: Minor Consolidations (Low Impact, Low Risk)
8. HuggingFace: `huggingface:datasets`
9. Games: 2 consolidated skills
10. Notion: `Notion:search`

---

## Testing Checklist for Each Consolidated Skill

After implementation, verify:

- [ ] All unique content from source skills is preserved
- [ ] No duplicate explanations remain
- [ ] Clear naming convention (category:feature)
- [ ] Trigger conditions are comprehensive
- [ ] Examples are runnable/valid
- [ ] Cross-references to related skills work
- [ ] Quick reference table is accurate
- [ ] References/links are valid

---

## Migration Command Template

```bash
# For each consolidation
echo "Merging [source skills] → [target skill]"

# 1. Backup existing skills
mkdir -p skills-backup
cp -r skills/[source]* skills-backup/

# 2. Create consolidated skill
# (Use specification document as guide)

# 3. Test new skill
# (Verify all use cases work)

# 4. Update skill invocations
# (Search codebase for old skill names)

# 5. Remove old skills
rm -rf skills/[source]*
```

---

## References

- Documentation Writing: https://diataxis.fr/
- NixOS: https://nixos.org/manual/nixos/stable/
- Docker: https://docs.docker.com/
- Kubernetes: https://kubernetes.io/docs/
- Pinecone: https://docs.pinecone.io/
