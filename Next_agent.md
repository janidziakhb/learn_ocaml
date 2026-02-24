# Next Agent Handoff

**Date:** 2026-02-24  
**Branch:** `future`  
**Repo:** `/home/brai/dataset/dataset_extension`

## Scope Completed

- Inspected `dataset_extension/schema` and mapped all current Liquid Graph schema definitions.
- Cross-checked schema definitions against active runtime graph typing in `dataset_extension/rustworkx_mongo_types.py`.
- Checked compile status for schema and package.

## Current Schema Map

### `dataset_extension/schema/node_schema.py`

- Defines:
  - `ProjectionTag = Literal["brai", "lean", "rocq", "agda"]`
  - `CompletelyOrdinary = Literal["lambda", "pi", "app", "var", ":", "let", "definition"]`
  - `NodeSchemaBase` with:
    - `projects_to: set[ProjectionTag]`
    - `fixed_outdegree: int | None`
    - `supports_binding_into: bool`
- Status:
  - `OrdinaryNodeSchema` is declared but empty/incomplete.
  - File currently fails compile (indentation/incomplete class body).

### `dataset_extension/schema/liquid_graph_schema.py`

- Defines:
  - `Named` (`canonical_name`)
  - `ReferenceInfo(Named)` (`location: ObjectId`)
  - `DefinitionClass`:
    - `"definition" | "type" | "axiom" | "prop_definition" | "playground"`
  - `DefinitionInfo(Named)`:
    - `definition_type`, `projections`, optional `term_text`/`type_text`
  - `GeneratedBy`:
    - `"human" | "derived" | "tactic" | "metaprogramming" | "llm" | "brai"`
  - `RWXMongoLabel`:
    - Required: `label`, `schema_id`, `generated_by`, `projects_to`
    - Optional: `definition_type`, `reference_info`, `unhandled_payload`
- Intent:
  - Looks like a normalized schema design (`schema_id` references node-schema DB, plus denormalized convenience fields).

### `dataset_extension/schema/README.md`

- Notes this schema system is WIP and describes a schema-for-schema-database approach.

### `dataset_extension/schema/__init__.py`

- Empty.

## Integration Status (Important)

- `dataset_extension.schema.*` is currently not wired into runtime modules.
- Active runtime type remains `dataset_extension/rustworkx_mongo_types.py::RWXMongoLabel`.
- There is a model mismatch between the new schema layer and runtime:
  - Runtime label expects flat fields like `canonical_name`, optional `location`, and a different `definition_type` shape.
  - New schema expects `schema_id` + nested `DefinitionInfo`/`ReferenceInfo` and `projects_to`.

## Known Breakages

- `python -m compileall -q dataset_extension` currently fails on:
  - `dataset_extension/schema/node_schema.py` (incomplete `OrdinaryNodeSchema`)
  - `dataset_extension/edge_statistics.py` (existing incomplete function body)

## Packaging/Distribution Note

- `pyproject.toml` sdist include section currently lists only:
  - `dataset_extension/*.py`
  - `dataset_extension/py.typed`
- This likely excludes `dataset_extension/schema/*.py` from sdist builds unless include rules are expanded.

## Prioritized Next Actions

1. Make `dataset_extension/schema/node_schema.py` compilable by finishing `OrdinaryNodeSchema` (or removing placeholder safely).
2. Decide canonical graph-label model:
   - Option A: migrate runtime to `schema/liquid_graph_schema.py`
   - Option B: keep runtime model and treat schema files as design docs only
3. If migrating, create explicit adapter/conversion functions between:
   - `rustworkx_mongo_types.RWXMongoLabel`
   - `schema.liquid_graph_schema.RWXMongoLabel`
4. Update packaging includes in `pyproject.toml` so schema files ship in sdist/wheel as intended.
5. Run:
   - `python -m compileall -q dataset_extension`
   - `uv run pytest --collect-only -q`
   after changes.

## Pair Programming Topics: LiquidGraph Class Implementation

Use this as the implementation plan for the pairing session. Each topic includes a concrete deliverable and starter code.

### 1) Architecture choice and class boundary (Req. 1)

**Goal**
- Decide composition vs inheritance and freeze the public API boundary.

**Recommendation**
- Use composition: `LiquidGraph` owns a `rustworkx.PyDiGraph` plus sidecar metadata/indexes.

**Deliverables**
- New module `dataset_extension/liquid_graph.py`.
- Clear constructor that accepts:
  - signature registry
  - optional schema version
  - optional underlying graph (for import path).

**Starter code**
```python
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
import rustworkx as rx

from dataset_extension.signature_registry import SignatureRegistry


@dataclass
class LiquidGraph:
    registry: SignatureRegistry
    schema_version: str
    graph: rx.PyDiGraph = field(default_factory=lambda: rx.PyDiGraph(multigraph=True))

    # sidecar indexes: deterministic ordering + role metadata
    edge_order_out: dict[tuple[int, str], list[int]] = field(default_factory=dict)
    edge_order_in: dict[tuple[int, str], list[int]] = field(default_factory=dict)
    top_level_nodes: set[int] = field(default_factory=set)

    def to_rustworkx(self) -> rx.PyDiGraph:
        return self.graph
```

### 2) Canonical label payload decision and adapter layer

**Goal**
- Resolve mismatch between:
  - `dataset_extension/rustworkx_mongo_types.RWXMongoLabel`
  - `dataset_extension/schema/liquid_graph_schema.RWXMongoLabel`

**Deliverables**
- Decide canonical runtime payload for v1.
- If no migration this sprint: implement adapters both directions.

**Starter code**
```python
from typing import TypedDict, NotRequired
from bson import ObjectId


class LegacyLabel(TypedDict):
    label: str
    generated_by: str
    definition_type: NotRequired[str]
    canonical_name: NotRequired[str]
    location: NotRequired[ObjectId]


class LiquidLabel(TypedDict):
    label: str
    schema_id: ObjectId
    generated_by: str
    projects_to: set[str]
    definition_type: NotRequired[dict[str, object]]
    reference_info: NotRequired[dict[str, object]]


def legacy_to_liquid(node: LegacyLabel, schema_id: ObjectId, projects_to: set[str]) -> LiquidLabel:
    out: LiquidLabel = {
        "label": node["label"],
        "schema_id": schema_id,
        "generated_by": node["generated_by"],
        "projects_to": projects_to,
    }
    if "canonical_name" in node and "definition_type" in node:
        out["definition_type"] = {
            "canonical_name": node["canonical_name"],
            "definition_type": node["definition_type"],
            "projections": projects_to,
        }
    if "canonical_name" in node and "location" in node:
        out["reference_info"] = {
            "canonical_name": node["canonical_name"],
            "location": node["location"],
        }
    return out
```

### 3) Make schema modules compilable

**Goal**
- Unblock implementation by fixing schema syntax failures.

**Deliverables**
- Complete `OrdinaryNodeSchema` in `dataset_extension/schema/node_schema.py`.
- Export schema symbols in `dataset_extension/schema/__init__.py`.
- Pass `python -m compileall -q dataset_extension/schema`.

**Starter code**
```python
# dataset_extension/schema/node_schema.py
class OrdinaryNodeSchema(NodeSchemaBase):
    label: CompletelyOrdinary
```

```python
# dataset_extension/schema/__init__.py
from dataset_extension.schema.node_schema import ProjectionTag, NodeSchemaBase, OrdinaryNodeSchema
from dataset_extension.schema.liquid_graph_schema import DefinitionInfo, GeneratedBy, RWXMongoLabel

__all__ = [
    "ProjectionTag",
    "NodeSchemaBase",
    "OrdinaryNodeSchema",
    "DefinitionInfo",
    "GeneratedBy",
    "RWXMongoLabel",
]
```

### 4) Signature registry with versioning (Req. 4, 5, 11)

**Goal**
- Create authoritative map from `label -> schema`.

**Deliverables**
- `dataset_extension/signature_registry.py` with:
  - schema dataclasses
  - versioned registry
  - lookup API.
- At least one initial version constant (e.g. `"liquid-v0"`).

**Starter code**
```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Language = Literal["agda", "rocq", "lean", "brai"]


@dataclass(frozen=True)
class EdgeSpec:
    edge_label: str
    variadic: bool


@dataclass(frozen=True)
class NodeSignature:
    arity: list[EdgeSpec]
    binding_arity: list[EdgeSpec]
    unique: bool
    language_projections: set[Language]


@dataclass
class SignatureRegistry:
    version: str
    by_label: dict[str, NodeSignature]

    def get(self, label: str) -> NodeSignature:
        try:
            return self.by_label[label]
        except KeyError as exc:
            raise KeyError(f"Unknown node label '{label}' in registry '{self.version}'") from exc
```

### 5) Core LiquidGraph invariants and node constructors (Req. 8, 9, 12)

**Goal**
- Enforce mandatory fields and one top-level node.

**Deliverables**
- `add_node_checked(payload)` that enforces minimum fields.
- Top-level tracking and exactly-one validator.
- Convenience helpers for major node classes.

**Starter code**
```python
TOP_LEVEL_LABELS = {"def", "prop-def", "type-def", "axiom", "command"}


def _require_fields(payload: dict[str, object], fields: list[str]) -> None:
    missing = [f for f in fields if f not in payload]
    if missing:
        raise ValueError(f"Missing required fields: {missing}")


def add_node_checked(self, payload: dict[str, object]) -> int:
    _require_fields(payload, ["label", "schema_id", "generated_by"])
    if payload["label"] == "open":
        _require_fields(payload, ["typed", "discard", "unifiable"])
    node_idx = self.graph.add_node(payload)
    if payload["label"] in TOP_LEVEL_LABELS:
        self.top_level_nodes.add(node_idx)
    return node_idx


def validate_top_level(self) -> None:
    if len(self.top_level_nodes) != 1:
        raise ValueError(f"Expected exactly one top-level node, got {len(self.top_level_nodes)}")
```

### 6) Deterministic variadic ordering (`collect`/`bcollect`) (Req. 6, 7)

**Goal**
- Preserve canonical order of repeated edge-label groups.

**Deliverables**
- Edge insertion wrapper that updates order indexes.
- Retrieval methods:
  - `collect(node_idx, edge_label) -> list[int]`
  - `bcollect(node_idx, edge_label) -> list[int]`

**Starter code**
```python
def add_edge_checked(self, src: int, dst: int, edge_label: str) -> int:
    edge_idx = self.graph.add_edge(src, dst, edge_label)
    self.edge_order_out.setdefault((src, edge_label), []).append(edge_idx)
    self.edge_order_in.setdefault((dst, edge_label), []).append(edge_idx)
    return edge_idx


def collect(self, node_idx: int, edge_label: str) -> list[int]:
    return list(self.edge_order_out.get((node_idx, edge_label), []))


def bcollect(self, node_idx: int, edge_label: str) -> list[int]:
    return list(self.edge_order_in.get((node_idx, edge_label), []))
```

### 7) Arity + binding-arity validator engine

**Goal**
- Implement single validation pass over all nodes using signature registry.

**Deliverables**
- `validate(strict=True)` returning structured report.
- Error type carrying node index, node label, and exact mismatch.

**Starter code**
```python
from dataclasses import dataclass


@dataclass
class ValidationIssue:
    node_idx: int
    node_label: str
    message: str


@dataclass
class ValidationReport:
    issues: list[ValidationIssue]

    @property
    def ok(self) -> bool:
        return len(self.issues) == 0


def validate(self, strict: bool = True) -> ValidationReport:
    issues: list[ValidationIssue] = []
    for n in self.graph.node_indices():
        payload = self.graph[n]
        node_label = payload["label"]
        sig = self.registry.get(node_label)

        # outgoing arity checks
        for spec in sig.arity:
            seen = len(self.collect(n, spec.edge_label))
            if not spec.variadic and seen != 1:
                issues.append(ValidationIssue(n, node_label, f"Expected exactly 1 '{spec.edge_label}' out edge, got {seen}"))

        # incoming binding-arity checks
        for spec in sig.binding_arity:
            seen = len(self.bcollect(n, spec.edge_label))
            if not spec.variadic and seen != 1:
                issues.append(ValidationIssue(n, node_label, f"Expected exactly 1 '{spec.edge_label}' binding edge, got {seen}"))

    # global checks
    if len(self.top_level_nodes) != 1:
        issues.append(ValidationIssue(-1, "graph", f"Expected one top-level node, got {len(self.top_level_nodes)}"))

    report = ValidationReport(issues)
    if strict and not report.ok:
        first = report.issues[0]
        raise ValueError(f"Validation failed at node {first.node_idx}: {first.message}")
    return report
```

### 8) Top-level class-specific constraint validators (Req. 13–15)

**Goal**
- Enforce edge target-type constraints for `def`, `prop-def`, `type-def`.

**Deliverables**
- Per-label validation hooks:
  - `_validate_def_node(node_idx)`
  - `_validate_prop_def_node(node_idx)`
  - `_validate_type_def_node(node_idx)`
- Called from `validate()`.

**Starter code**
```python
def _target_label(self, edge_idx: int) -> str:
    _, dst = self.graph.get_edge_endpoints_by_index(edge_idx)
    return self.graph[dst]["label"]


def _assert_targets(self, node_idx: int, edge_label: str, allowed: set[str], issues: list[ValidationIssue]) -> None:
    for e in self.collect(node_idx, edge_label):
        got = self._target_label(e)
        if got not in allowed:
            issues.append(
                ValidationIssue(node_idx, self.graph[node_idx]["label"], f"Edge '{edge_label}' points to '{got}', allowed={sorted(allowed)}")
            )


def _validate_def_node(self, node_idx: int, issues: list[ValidationIssue]) -> None:
    self._assert_targets(node_idx, "defDeclPair", {":"}, issues)
    self._assert_targets(node_idx, "defArgDecl", {":"}, issues)
    self._assert_targets(node_idx, "defAxiom", {"reference"}, issues)
    self._assert_targets(node_idx, "defCommand", {"reference"}, issues)
```

### 9) Round-trip + compatibility tests (Req. 1, 10)

**Goal**
- Add tests for graph-level round-trip and validation guarantees.

**Deliverables**
- New test module `tests/liquid_graph/test_liquid_graph.py`.
- Baseline tests:
  - valid graph passes
  - invalid arity fails
  - top-level cardinality check
  - rustworkx round-trip preservation.

**Starter code**
```python
def test_single_top_level_required(registry):
    lg = LiquidGraph(registry=registry, schema_version=registry.version)
    lg.add_node_checked({"label": "def", "schema_id": "x", "generated_by": "human"})
    lg.add_node_checked({"label": "axiom", "schema_id": "y", "generated_by": "human"})
    try:
        lg.validate(strict=True)
        assert False, "Expected failure for multiple top-level nodes"
    except ValueError:
        pass


def test_round_trip_identity(registry):
    lg = LiquidGraph(registry=registry, schema_version=registry.version)
    d = lg.add_node_checked({"label": "def", "schema_id": "x", "generated_by": "human"})
    r = lg.to_rustworkx()
    lg2 = LiquidGraph(registry=registry, schema_version=registry.version, graph=r)
    assert len(list(lg2.graph.node_indices())) == 1
    assert lg2.graph[d]["label"] == "def"
```

### 10) Packaging + integration hardening

**Goal**
- Ensure schema and LiquidGraph modules are shipped and discoverable.

**Deliverables**
- Update `pyproject.toml` sdist include patterns.
- Add minimal docs for registry versioning + validation policy.
- Add one command snippet in docs for local sanity checks.

**Starter code**
```toml
[tool.hatch.build.targets.sdist]
include = [
  "dataset_extension/*.py",
  "dataset_extension/schema/*.py",
  "dataset_extension/py.typed",
]
```

```bash
python -m compileall -q dataset_extension
uv run pytest --collect-only -q
```

### Suggested Session Order (2-hour block)

1. Topics 1-2 (architecture + canonical payload decision)
2. Topic 3 (unblock compile)
3. Topics 4-6 (registry + class skeleton + edge ordering)
4. Topics 7-8 (validators)
5. Topics 9-10 (tests + packaging cleanup)

## Tangible Outcomes of First Pairing Session

1. `LiquidGraph` implementation direction finalized (composition vs inheritance) and recorded in handoff.
2. Canonical runtime label model decision made (or adapter strategy approved if deferred).
3. `dataset_extension/schema/node_schema.py` fixed to compile (no schema syntax errors).
4. `dataset_extension/signature_registry.py` created with versioned label→signature mapping.
5. `dataset_extension/liquid_graph.py` created with:
   - checked node insertion
   - checked edge insertion
   - top-level node tracking
6. Deterministic edge ordering support implemented (`collect` / `bcollect` sidecar indexes).
7. Validation engine implemented (`validate(strict=True)`) for arity + binding arity + top-level count.
8. Initial top-level node constraint checks added for `def` / `prop-def` / `type-def` targets.
9. New tests added (happy path + failure path + round-trip skeleton) under `tests/liquid_graph/`.
10. Packaging update prepared/applied so `dataset_extension/schema/*.py` is included in sdist.
11. End-of-session verification run completed:
   - `python -m compileall -q dataset_extension`
   - `uv run pytest --collect-only -q`
12. Updated `.planning/NEXT_AGENT_HANDOFF.md` with what was implemented, what remains, and next priorities.

## Useful File References

- `dataset_extension/schema/node_schema.py`
- `dataset_extension/schema/liquid_graph_schema.py`
- `dataset_extension/schema/README.md`
- `dataset_extension/rustworkx_mongo_types.py`
- `dataset_extension/mongodb_api.py`
- `dataset_extension/edge_statistics.py`
- `dataset_extension/liquid_graph.py` (proposed new module)
- `pyproject.toml`
