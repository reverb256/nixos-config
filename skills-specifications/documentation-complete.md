# Documentation Skill Consolidation Specification

**Target Name**: `documentation:complete`
**Sources to Merge**:
- `technical-writing`
- `documentation-writer` (Diátaxis framework)
- `writing-clearly-and-concisely`

**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Skill Manifest

```yaml
name: documentation:complete
description: Expert technical writing and documentation using the Diátaxis framework, clarity principles, and industry best practices.

triggers:
  - User requests documentation writing
  - User asks to improve existing docs
  - User wants API documentation
  - User needs README or guides
  - "Write documentation for..."
  - "Improve these docs..."
  - "Create a guide for..."
  - "Document this code..."
```

---

## Consolidated Content Structure

### 1. Diátaxis Framework (from documentation-writer)

**Core Principle**: Documentation falls into four types, each serving a different need:

| Type | Purpose | When to Use |
|------|---------|-------------|
| **Tutorials** | Learning-oriented | Beginners need to accomplish a specific goal |
| **How-to Guides** | Problem-oriented | Users need to solve a specific problem |
| **Reference** | Information-oriented | Users need precise information |
| **Explanation** | Understanding-oriented | Users need background and context |

**Diátaxis Checklist**:
- [ ] Does this cover all four types?
- [ ] Is the beginner path clear?
- [ ] Can users quickly find answers?
- [ ] Is the "why" explained alongside the "how"?

### 2. Technical Writing Best Practices (from technical-writing)

**API Documentation Template**:
```markdown
# {API Name}

## Overview
Brief description of what this API does and when to use it.

## Authentication
How to authenticate requests (if applicable).

## Endpoints

### {Endpoint Name}
**Method**: `GET|POST|PUT|DELETE`

**URL**: `/path/to/endpoint`

**Description**: What this endpoint does

**Request Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| param1 | string | Yes | Description |

**Response**:
```json
{
  "field": "description"
}
```

**Error Codes**:
| Code | Description |
|------|-------------|
| 400 | Bad request |
| 401 | Unauthorized |

## Examples

### cURL
\`\`\`bash
curl -X POST https://api.example.com/endpoint \\
  -H "Authorization: Bearer TOKEN" \\
  -d '{"key": "value"}'
\`\`\`

### Python
\`\`\`python
import requests

response = requests.post(
    "https://api.example.com/endpoint",
    headers={"Authorization": "Bearer TOKEN"},
    json={"key": "value"}
)
\`\`\`
```

**Code Documentation Standards**:
- Every public function/class needs a docstring
- Include: purpose, parameters, returns, raises, examples
- Use imperative mood ("Return the value" not "Returns the value")
- Document edge cases and non-obvious behaviors

### 3. Writing Clearly and Concisely (from writing-clearly-and-concisely)

**Clarity Principles**:

1. **One Idea Per Sentence**
   - Bad: "The function processes the data and returns the result which is used by the caller to display information."
   - Good: "The function processes the data and returns a result. The caller uses this result to display information."

2. **Active Voice Over Passive**
   - Bad: "The data is processed by the function."
   - Good: "The function processes the data."

3. **Simple Words Over Complex**
   - Bad: "Utilize this functionality to accomplish the task."
   - Good: "Use this function to complete the task."

4. **Specific Over Vague**
   - Bad: "This might take a while."
   - Good: "This takes about 30 seconds."

5. **Omit Needless Words**
   - Bad: "In order to start the process, you need to click the button."
   - Good: "Click the button to start."

**Word Choice Guidelines**:
| Avoid | Prefer |
|-------|--------|
| utilize | use |
| in order to | to |
| prior to | before |
| subsequent to | after |
| methodology | method |
| leverage | use (unless mechanical advantage) |

---

## When to Use This Skill

Trigger this skill when:

1. **Creating New Documentation**
   - "Write documentation for this API"
   - "Create a README for this project"
   - "Document how to use this feature"

2. **Improving Existing Documentation**
   - "These docs are unclear, can you fix them?"
   - "Rewrite this section"
   - "Make this documentation clearer"

3. **Reviewing Documentation**
   - "Review our documentation"
   - "What's missing from these docs?"
   - "Is this documentation complete?"

4. **Planning Documentation**
   - "What documentation do we need?"
   - "Create a documentation outline"
   - "What should we document first?"

---

## Documentation Workflow

### Phase 1: Assess
1. Identify the audience (beginner, intermediate, advanced)
2. Determine the documentation type(s) needed (Diátaxis)
3. Review existing materials
4. Identify gaps

### Phase 2: Plan
1. Create an outline using Diátaxis types
2. Define the scope (what to include, what to exclude)
3. Identify necessary examples and diagrams
4. Plan for maintenance (how to keep docs current)

### Phase 3: Draft
1. Write content following clarity principles
2. Include code examples in relevant languages
3. Add diagrams for complex concepts
4. Use consistent formatting and terminology

### Phase 4: Review
1. Check against Diátaxis framework
2. Verify clarity principles are followed
3. Test instructions (follow your own guide)
4. Get feedback from actual users

### Phase 5: Refine
1. Simplify complex explanations
2. Add missing examples
3. Fix unclear sections
4. Update based on feedback

---

## Quality Checklist

Before considering documentation complete:

### Content Quality
- [ ] All four Diátaxis types are represented (if applicable)
- [ ] Explanations include both "how" and "why"
- [ ] Examples are realistic and runnable
- [ ] Edge cases are documented
- [ ] Common errors are explained

### Clarity Quality
- [ ] Sentences are short and simple
- [ ] Active voice is used consistently
- [ ] Technical terms are defined on first use
- [ ] No unnecessary jargon
- [ ] No needless words

### Structure Quality
- [ ] Logical progression from basic to advanced
- [ ] Clear headings and hierarchy
- [ ] Scannable with bullet points and tables
- [ ] Consistent formatting throughout
- [ ] Working cross-references

### Accessibility
- [ ] Clear link text (not "click here")
- [ ] Alt text for images
- [ ] Code examples have syntax highlighting
- [ ] Contrast ratios meet WCAG standards

---

## Common Documentation Patterns

### README Structure
```markdown
# Project Name

## About
One-sentence description

## Features
- Feature 1
- Feature 2

## Installation
\`\`\`bash
command to install
\`\`\`

## Quick Start
\`\`\`bash
command to run
\`\`\`

## Usage
Basic usage example

## Documentation
Link to full docs

## Contributing
How to contribute

## License
License info
```

### Code Comment Template
```python
def function_name(param1, param2):
    """
    Brief description of what the function does.

    Args:
        param1 (type): Description of param1
        param2 (type): Description of param2

    Returns:
        type: Description of return value

    Raises:
        ErrorType: When this error occurs

    Example:
        >>> function_name("value", 42)
        "result"
    """
    pass
```

### Troubleshooting Section
```markdown
## Troubleshooting

### "Error message here"
**Cause**: Why this happens

**Solution**: How to fix it

### "Another error"
**Cause**: Different cause

**Solutions**:
1. Solution A
2. Solution B (try if A doesn't work)
```

---

## Integration Notes

When implementing this consolidated skill:

1. **Preserve all unique content** from each source skill
2. **Remove redundancies** (e.g., if all three cover active voice, keep one best explanation)
3. **Maintain cross-references** between sections
4. **Keep original examples** that are specific to each domain
5. **Add integration notes** for when to use Diátaxis vs general technical writing

---

## Testing the Consolidated Skill

After implementation, verify:

1. [ ] Can create API documentation
2. [ ] Can write a README
3. [ ] Can improve unclear text
4. [ ] Can apply Diátaxis framework
5. [ ] Can explain when to use each documentation type
6. [ ] Can review existing docs for completeness

---

## Migration Path for Existing Skills

Once `documentation:complete` is implemented:

1. **Deprecate** `technical-writing` → reference `documentation:complete`
2. **Deprecate** `documentation-writer` → reference `documentation:complete`
3. **Deprecate** `writing-clearly-and-concisely` → reference `documentation:complete`
4. **Update** any triggers or skill invocations to use the new name
5. **Archive** old skills after a transition period

---

## References

- Diátaxis Framework: https://diataxis.fr/
- Google Developer Documentation Style Guide
- Microsoft Writing Style Guide
- docs.python.org style guide
