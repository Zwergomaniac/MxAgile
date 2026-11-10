"""Synthetic MPRv2 models and Git histories for merge-safety tests. Contains no real project data."""

from __future__ import annotations

import base64
import hashlib
import shutil
import sqlite3
import struct
import subprocess
import uuid
from pathlib import Path

NAMESPACE = uuid.UUID("12345678-1234-5678-1234-567812345678")


class I64(int):
    """Marks a value that must be written as BSON int64."""


def bson(value) -> bytes:
    def element(key: str, item) -> bytes:
        name = key.encode() + b"\0"
        if isinstance(item, bool):
            return b"\x08" + name + (b"\x01" if item else b"\x00")
        if isinstance(item, I64):
            return b"\x12" + name + struct.pack("<q", item)
        if isinstance(item, int):
            return b"\x10" + name + struct.pack("<i", item)
        if isinstance(item, float):
            return b"\x01" + name + struct.pack("<d", item)
        if isinstance(item, str):
            data = item.encode() + b"\0"
            return b"\x02" + name + struct.pack("<i", len(data)) + data
        if isinstance(item, (bytes, bytearray)):
            return b"\x05" + name + struct.pack("<i", len(item)) + b"\x00" + bytes(item)
        if item is None:
            return b"\x0a" + name
        if isinstance(item, dict):
            return b"\x03" + name + document(item.items())
        if isinstance(item, list):
            return b"\x04" + name + document((str(index), child) for index, child in enumerate(item))
        raise TypeError(type(item))

    def document(pairs) -> bytes:
        body = b"".join(element(key, item) for key, item in pairs)
        return struct.pack("<i", len(body) + 5) + body + b"\0"

    return document(value.items())


def guid(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, "|".join(parts)))


def ident(*parts: str) -> bytes:
    return uuid.uuid5(NAMESPACE, "|".join(parts)).bytes


def _noisy(value):
    """mxcli-style re-serialization: reversed key order, int64 widths, reversed order-free graph arrays, dropped defaults."""
    if isinstance(value, dict):
        return {key: _noisy(child) for key, child in reversed(list(value.items())) if child not in ("", False, None)}
    if isinstance(value, list):
        return list(value)
    if type(value) is int:
        return I64(value)
    return value


def microflow(name: str, expression: str = "true", salt: str = "", noise: bool = False) -> bytes:
    """A small but structurally realistic microflow unit. `noise` re-serializes without changing the semantics."""
    salt = "n" if noise and not salt else salt

    def i(role: str) -> bytes:
        return ident("mf", name, role, salt)

    start, split, end = i("start"), i("split"), i("end")
    objects = [3,
               {"$ID": start, "$Type": "Microflows$StartEvent", "RelativeMiddlePoint": "100;200", "Size": "20;20"},
               {"$ID": split, "$Type": "Microflows$ExclusiveSplit", "Caption": "Guard",
                "SplitCondition": {"$ID": i("cond"), "$Type": "Microflows$ExpressionSplitCondition", "Expression": expression}},
               {"$ID": end, "$Type": "Microflows$EndEvent", "RelativeMiddlePoint": "400;200", "Size": "20;20"}]
    flows = [3, {"$ID": i("f1"), "$Type": "Microflows$SequenceFlow", "OriginPointer": start, "DestinationPointer": split},
             {"$ID": i("f2"), "$Type": "Microflows$SequenceFlow", "OriginPointer": split, "DestinationPointer": end}]
    document = {"$ID": i("root"), "$Type": "Microflows$Microflow", "Name": name, "Documentation": "", "MarkAsUsed": False, "Version": 3,
                "ObjectCollection": {"$ID": i("oc"), "$Type": "Microflows$MicroflowObjectCollection", "Objects": objects}, "Flows": flows}
    if noise:
        document = _noisy(document)
        document["ObjectCollection"]["Objects"] = [objects[0], *reversed(objects[1:])]
        document["Flows"] = [flows[0], *reversed(flows[1:])]
    return bson(document)


def domain_model(entities: dict[str, list[str]]) -> bytes:
    return bson({"$ID": ident("dm"), "$Type": "DomainModels$DomainModel",
                 "Entities": [3, *({"$ID": ident("ent", n), "$Type": "DomainModels$Entity", "Name": n,
                                    "Attributes": [3, *({"$ID": ident("attr", n, a), "$Type": "DomainModels$Attribute", "Name": a} for a in attrs)]}
                                   for n, attrs in entities.items())]})


def navigation(items: dict[str, str]) -> bytes:
    return bson({"$ID": ident("nav"), "$Type": "Navigation$NavigationDocument", "Name": "Navigation",
                 "Items": [3, *({"$ID": ident("item", n), "$Type": "Navigation$Item", "Name": n, "Page": page} for n, page in items.items())]})


def module_unit(name: str) -> bytes:
    return bson({"$ID": ident("module", name), "$Type": "Projects$ModuleImpl", "Name": name})


MODULE = guid("module", "App")


class Model:
    def __init__(self, product: str = "10.24.11.1", fmt: str = "v2"):
        self.product, self.fmt = product, fmt
        self.units: dict[str, dict] = {}
        self.orphans: dict[str, bytes] = {}
        self.hash_overrides: dict[str, str] = {}
        self.missing_files: set[str] = set()
        self.add(MODULE, None, module_unit("App"), "Modules")

    def copy(self) -> "Model":
        other = Model(self.product, self.fmt)
        other.units = {key: dict(value) for key, value in self.units.items()}
        other.orphans = dict(self.orphans)
        other.hash_overrides = dict(self.hash_overrides)
        other.missing_files = set(self.missing_files)
        return other

    def add(self, unit: str, container: str | None, data: bytes, containment: str = "Documents") -> "Model":
        self.units[unit] = {"container": container, "containment": containment, "data": data}
        return self

    def put_microflow(self, name: str, line: str = "base", **kwargs) -> str:
        unit = guid("mf", name, line)
        self.add(unit, MODULE, microflow(name, **kwargs))
        return unit

    def set_microflow(self, unit: str, name: str, **kwargs) -> "Model":
        return self.add(unit, MODULE, microflow(name, **kwargs))

    def remove(self, unit: str) -> "Model":
        self.units.pop(unit, None)
        return self

    def write(self, root: Path) -> None:
        for stale in root.glob("*.mpr"):
            stale.unlink()
        shutil.rmtree(root / "mprcontents", ignore_errors=True)
        database = sqlite3.connect(root / "Model.mpr")
        try:
            column = "ContentsHash TEXT" if self.fmt == "v2" else "Contents BLOB"
            database.execute(f"create table Unit (UnitID BLOB, ContainerID BLOB, ContainmentName TEXT, TreeConflict INTEGER, {column}, ContentsConflicts TEXT)")
            database.execute("create table _MetaData (_FormatVersion INTEGER, _ProductVersion TEXT, _BuildVersion TEXT, _SchemaHash TEXT)")
            database.execute("create table _Transaction (LastTransactionID TEXT)")
            database.execute("insert into _MetaData values (?,?,?,?)", (2 if self.fmt == "v2" else 1, self.product, self.product, "{SHA256}fixture"))
            database.execute("insert into _Transaction values (?)", (str(uuid.uuid4()),))
            for unit, spec in sorted(self.units.items()):
                digest = self.hash_overrides.get(unit) or base64.b64encode(hashlib.sha256(spec["data"]).digest()).decode()
                container = uuid.UUID(spec["container"]).bytes_le if spec["container"] else None
                database.execute("insert into Unit values (?,?,?,?,?,?)", (uuid.UUID(unit).bytes_le, container, spec["containment"], 0,
                                                                          digest if self.fmt == "v2" else spec["data"], ""))
            database.commit()
        finally:
            database.close()
        if self.fmt == "v2":
            for unit, data in [(u, s["data"]) for u, s in self.units.items() if u not in self.missing_files] + list(self.orphans.items()):
                path = root / "mprcontents" / unit[:2] / unit[2:4] / f"{unit}.mxunit"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)


class Repo:
    def __init__(self, root: Path):
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        self.git("init", "--quiet", "-b", "main")
        self.git("config", "core.autocrlf", "false")

    def git(self, *arguments: str, check: bool = True, cwd: Path | None = None) -> str:
        result = subprocess.run(["git", "-C", str(cwd or self.root), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *arguments],
                                capture_output=True, text=True)
        if check and result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def commit(self, model: Model, message: str, parents: tuple[str, ...] = (), ref: str | None = None) -> str:
        model.write(self.root)
        self.git("add", "--all")
        tree = self.git("write-tree")
        arguments = ["commit-tree", tree, "-m", message]
        for parent in parents:
            arguments += ["-p", parent]
        sha = self.git(*arguments)
        if ref:
            self.git("update-ref", f"refs/heads/{ref}", sha)
        return sha
