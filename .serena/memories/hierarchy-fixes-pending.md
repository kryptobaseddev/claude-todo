# Hierarchy Fixes Pending (Blocked on T328)

**Created**: 2025-12-19
**Blocked By**: T328 (Hierarchy Enhancement Phase 1)
**Action Required After T328**: Run bulk fix script to set type and parentId

## Epics Needing type=epic

| Task ID | Title |
|---------|-------|
| T328 | EPIC: Hierarchy Enhancement Phase 1 - Core (v0.15.0) |
| T339 | EPIC: Hierarchy Enhancement Phase 2 - Automation (v0.16.0) |
| T382 | Config System Integration & Completion |
| T429 | EPIC: Smart Archive System Enhancement |
| T451 | File Locking & Concurrency Safety |
| T457 | EPIC: Phase Discipline Documentation & Config Implementation |
| T481 | EPIC: LLM-Agent-First Spec v3.0 Compliance Checker Implementation |

## Implicit Children Needing parentId

### T328 Children (10 tasks)
- T329: T328.1 → parentId: T328
- T330: T328.2 → parentId: T328
- T331: T328.3 → parentId: T328
- T332: T328.4 → parentId: T328
- T333: T328.5 → parentId: T328
- T334: T328.6 → parentId: T328
- T335: T328.7 → parentId: T328
- T336: T328.8 → parentId: T328
- T337: T328.9 → parentId: T328
- T338: T328.10 → parentId: T328

### T339 Children (10 tasks)
- T340-T349: T339.1-T339.10 → parentId: T339

### T429 Children (18 tasks)
- T430-T447: T429.1-T429.18 → parentId: T429

### T481 Children (15 tasks)
- T482, T483-T488: T481.1-T481.7 → parentId: T481
- T489: T481.A (sub-epic) → parentId: T481
- T490-T496: T481.A.1-T481.A.7 → parentId: T489
- T497: T481.B (sub-epic) → parentId: T481
- T498-T503: T481.B.1-T481.D → parentId: T497

### T382 Children (7 tasks) - Config System
- T390-T396 → parentId: T382

### T457 Children (7 tasks) - Phase Discipline
- T458-T464 → parentId: T457

## Post-T328 Fix Commands

After T328 implements --type and --parent flags:

```bash
# Fix epic types
for id in T328 T339 T382 T429 T451 T457 T481; do
  claude-todo update "$id" --type epic
done

# Fix T328 children
for i in 329 330 331 332 333 334 335 336 337 338; do
  claude-todo update "T$i" --parent T328
done

# Fix T339 children  
for i in 340 341 342 343 344 345 346 347 348 349; do
  claude-todo update "T$i" --parent T339
done

# Fix T429 children
for i in $(seq 430 447); do
  claude-todo update "T$i" --parent T429
done

# Fix T382 children (config)
for i in 390 391 392 393 394 395 396; do
  claude-todo update "T$i" --parent T382
done

# Fix T457 children (phase discipline)
for i in 458 459 460 461 462 463 464; do
  claude-todo update "T$i" --parent T457
done

# Fix T481 hierarchy (complex - has sub-epics)
for i in 482 483 484 485 486 487 488 489 497; do
  claude-todo update "T$i" --parent T481
done
claude-todo update T489 --type task  # sub-epic
claude-todo update T497 --type task  # sub-epic
for i in 490 491 492 493 494 495 496; do
  claude-todo update "T$i" --parent T489
done
for i in 498 499 500 501 502 503; do
  claude-todo update "T$i" --parent T497
done
```

## Total Fixes Needed

- **7 epics** need type=epic
- **60+ tasks** need parentId set
- **2 sub-epics** (T489, T497) under T481
