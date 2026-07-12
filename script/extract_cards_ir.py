"""Extracts an intermediate representation of the Microsoft Teams Adaptive Card
models from the generated Pydantic classes in teams.py, plus a golden corpus of
serialized samples.

The upstream classes are machine-generated (packages/cards/core.py), so their
Pydantic metadata is the closest thing to the schema Microsoft's internal tool
consumes. Generating Ruby from it keeps teams_rb at parity by construction.

Run via the rake task, which resolves the teams.py checkout (sibling directory
by default, TEAMS_PY_PATH to override) and executes this script inside its uv
environment:

    bundle exec rake cards:generate

Writes: teams_rb/script/cards_ir.json and teams_rb/test/fixtures/cards_corpus.json
"""

import inspect
import json
import os
import sys

from pydantic import BaseModel
from pydantic_core import PydanticUndefined

import microsoft_teams.cards.core as core

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)))
FIXTURES_DIR = os.path.normpath(os.path.join(OUT_DIR, "..", "test", "fixtures"))


def collect_classes():
    classes = {}
    for name, cls in inspect.getmembers(core, inspect.isclass):
        if not issubclass(cls, BaseModel) or cls is BaseModel:
            continue
        if cls.__module__ != core.__name__:
            continue
        classes[name] = cls
    return classes


CLASSES = collect_classes()


def parent_name(cls):
    for base in cls.__bases__:
        if base.__name__ in CLASSES:
            return base.__name__
    return None


def own_annotations(cls):
    # inspect.get_annotations returns the class's own annotations and works
    # with PEP 649 deferred annotations (Python 3.14+).
    return inspect.get_annotations(cls)


def field_ir(cls, fname, field):
    own = fname in own_annotations(cls)

    if field.default is not PydanticUndefined:
        default = field.default
        has_default = True
    elif field.default_factory is not None:
        value = field.default_factory()
        default = (
            value.model_dump(by_alias=True, exclude_none=True)
            if isinstance(value, BaseModel)
            else value
        )
        has_default = True
    else:
        default = None
        has_default = False

    json.dumps(default)  # all defaults are JSON-safe; fail loudly if not

    return {
        "name": fname,
        "alias": field.serialization_alias or field.alias or fname,
        "default": default,
        "has_default": has_default,
        "mutable": isinstance(default, (dict, list)),
        "own": own,
    }


def depth(name):
    d = 0
    current = CLASSES[name]
    while (p := parent_name(current)) is not None:
        d += 1
        current = CLASSES[p]
    return d


def build_ir():
    ir = []
    for name in sorted(CLASSES, key=lambda n: (depth(n), n)):
        cls = CLASSES[name]
        ir.append(
            {
                "name": name,
                "parent": parent_name(cls),
                "doc": (cls.__doc__ or "").strip().split("\n")[0],
                "fields": [field_ir(cls, k, f) for k, f in cls.model_fields.items()],
            }
        )
    return ir


# --- Golden corpus -----------------------------------------------------------
# Specs are recursive: {"__class__": Name, "kwargs": {...}} nodes construct
# models; everything else passes through. The same specs are interpreted by the
# Ruby test to build the equivalent objects.

CORPUS_SPECS = [
    {"__class__": "TextBlock", "kwargs": {"text": "hi"}},
    {
        "__class__": "TextBlock",
        "kwargs": {"text": "styled", "size": "Large", "weight": "Bolder", "wrap": True, "color": "Attention"},
    },
    {"__class__": "Image", "kwargs": {"url": "https://example.com/x.png", "alt_text": "a picture"}},
    {
        "__class__": "AdaptiveCard",
        "kwargs": {
            "body": [
                {"__class__": "TextBlock", "kwargs": {"text": "hello"}},
                {"__class__": "Image", "kwargs": {"url": "https://example.com/x.png"}},
            ]
        },
    },
    {
        "__class__": "Container",
        "kwargs": {"items": [{"__class__": "TextBlock", "kwargs": {"text": "inner"}}], "style": "emphasis"},
    },
    {
        "__class__": "ColumnSet",
        "kwargs": {
            "columns": [
                {
                    "__class__": "Column",
                    "kwargs": {"items": [{"__class__": "TextBlock", "kwargs": {"text": "col"}}], "width": "stretch"},
                }
            ]
        },
    },
    {
        "__class__": "FactSet",
        "kwargs": {
            "facts": [
                {"__class__": "Fact", "kwargs": {"title": "Status", "value": "Green"}},
                {"__class__": "Fact", "kwargs": {"title": "Owner", "value": "Devran"}},
            ]
        },
    },
    {"__class__": "TextInput", "kwargs": {"id": "name", "label": "Name", "is_required": True}},
    {
        "__class__": "ChoiceSetInput",
        "kwargs": {
            "id": "pick",
            "choices": [{"__class__": "Choice", "kwargs": {"title": "Yes", "value": "y"}}],
        },
    },
    {
        "__class__": "ActionSet",
        "kwargs": {
            "actions": [
                {"__class__": "SubmitAction", "kwargs": {"title": "Send", "data": {"kind": "submit"}}},
                {"__class__": "OpenUrlAction", "kwargs": {"title": "Open", "url": "https://example.com"}},
            ]
        },
    },
    {"__class__": "ExecuteAction", "kwargs": {"title": "Run", "verb": "do-it", "data": {"a": 1}}},
    {"__class__": "ToggleInput", "kwargs": {"id": "opt", "title": "Enable?"}},
]


def build_spec(spec):
    if isinstance(spec, dict) and "__class__" in spec:
        cls = CLASSES[spec["__class__"]]
        kwargs = {k: build_spec(v) for k, v in spec.get("kwargs", {}).items()}
        unknown = set(kwargs) - set(cls.model_fields)
        if unknown:
            raise SystemExit(f"corpus spec for {spec['__class__']} has unknown fields: {unknown}")
        return cls(**kwargs)
    if isinstance(spec, list):
        return [build_spec(item) for item in spec]
    if isinstance(spec, dict):
        return {k: build_spec(v) for k, v in spec.items()}
    return spec


def build_corpus():
    corpus = []
    for spec in CORPUS_SPECS:
        instance = build_spec(spec)
        corpus.append(
            {"spec": spec, "expected": instance.model_dump(by_alias=True, exclude_none=True)}
        )
    return corpus


def main():
    ir = build_ir()
    with open(os.path.join(OUT_DIR, "cards_ir.json"), "w") as f:
        json.dump({"classes": ir}, f, indent=1)

    os.makedirs(FIXTURES_DIR, exist_ok=True)
    corpus = build_corpus()
    with open(os.path.join(FIXTURES_DIR, "cards_corpus.json"), "w") as f:
        json.dump(corpus, f, indent=1)

    fields = sum(len(c["fields"]) for c in ir)
    print(f"IR: {len(ir)} classes, {fields} fields; corpus: {len(corpus)} samples", file=sys.stderr)


if __name__ == "__main__":
    main()
