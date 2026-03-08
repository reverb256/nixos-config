# Skills Consolidation Specifications Index

**Date**: 2026-03-07
**Status**: Complete
**Total Reduction**: ~90 skills → ~40 skills (-50 skills)

---

## Specification Documents

| Specification | File | Skills Affected |
|---------------|------|-----------------|
| Documentation | `documentation-complete.md` | 3 → 1 |
| NixOS | `nixos-complete.md` | 2 → 1 |
| Docker | `docker-complete.md` | 3 → 1 |
| Kubernetes | `kubernetes-core.md` | 4 → 1 |
| Marketing | `marketing-consolidated.md` | 35 → 8 |
| ComfyUI | `comfyui-consolidated.md` | 12 → 4 |
| Pinecone | `pinecone-consolidated.md` | 7 → 3 |
| Remaining | `remaining-consolidations.md` | 11 → 7 |

---

## Consolidation Summary

### High-Impact Merges (4 skills, -10 total)

1. **`documentation:complete`** (3→1, -2)
   - Merges: technical-writing, documentation-writer, writing-clearly-and-concisely
   - Key: Diátaxis framework + clarity principles + API docs

2. **`nixos:complete`** (2→1, -1)
   - Merges: nixos-best-practices, nix-ecosystem
   - Key: Flakes, modules, testing workflow

3. **`docker:complete`** (3→1, -2)
   - Merges: docker-best-practices, docker-patterns, docker-compose-orchestration
   - Key: Multi-stage builds, security, compose patterns

4. **`kubernetes:core`** (4→1, -3)
   - Merges: kubernetes-architect, k8s-manifest-generator, k8s-security-policies, k8s-helm
   - Key: Architecture, manifests, RBAC, Helm

### Domain Consolidations (3 groups, -34 total)

5. **Marketing Skills** (35→8, -27)
   - `marketing:seo` (4→1)
   - `marketing:cro` (6→1)
   - `marketing:content` (5→1)
   - `marketing:growth` (4→1)
   - `marketing:outbound` (5→1)
   - `marketing:analytics` (4→1)
   - `marketing:product` (4→1)
   - `marketing:psychology` (3→1)

6. **ComfyUI Skills** (12→4, -8)
   - `comfyui:core` (4→1)
   - `comfyui:workflow` (4→1)
   - `comfyui:pipelines` (3→1)
   - `comfyui:dev` (1→1)

7. **Pinecone Skills** (7→3, -4)
   - `pinecone:guide` (4→1)
   - `pinecone:usage` (3→1)
   - `pinecone:mcp` (1→1)

### Minor Consolidations (3 groups, -6 total)

8. **HuggingFace** (2→1, -1)
   - `huggingface:datasets` merges datasets + dataset-viewer

9. **Game Design** (5→2, -3)
   - `game:design` (2→1)
   - `game:animation` (3→1)

10. **Notion** (2→1, -1)
    - `Notion:search` merges find + search

---

## Naming Convention

All consolidated skills use the format: `category:feature`

**Examples**:
- `documentation:complete`
- `nixos:complete`
- `docker:complete`
- `kubernetes:core`
- `marketing:seo`
- `comfyui:core`

---

## Next Steps

1. **Review Specifications**: Read each spec file for detailed implementation guidance

2. **Create Consolidated Skills**: Use specs as blueprints for new skill files

3. **Test Thoroughly**: Verify each consolidated skill covers all use cases

4. **Update References**: Find and replace old skill names in codebases

5. **Remove Old Skills**: Delete source skills after validation

6. **Document Changes**: Update skill registries and documentation

---

## Notes

- Skills that are **embedded or remote-loaded** (like the original documentation skills) cannot be directly edited locally
- These specifications serve as **blueprints** for creating custom plugins or contributing to official repositories
- Local project skills (in `/etc/nixos/skills/`) can be directly modified using these specifications
