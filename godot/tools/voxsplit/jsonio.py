"""Serializador JSON determinista y legible para `parts.json` y el sidecar.

`json.dumps` con `indent` deja una línea por número, lo que hace ilegibles las cajas y
los pivotes. Este módulo escribe en línea cualquier objeto o lista cuya forma compacta
quepa en `max_inline` caracteres, de modo que ``"boxes": [[15, 13, 29, 24, 35, 38]]``
ocupe una sola línea y el diff de una regresión sea legible.

La salida es determinista: no reordena claves y redondea los flotantes de forma estable.
"""

from __future__ import annotations

import math
from typing import Any

__all__ = ["dumps", "clean_float", "clean"]

#: Decimales con los que se escriben los flotantes calculados (milímetro a escala de metros).
FLOAT_DIGITS = 6


def clean_float(value: float, digits: int = FLOAT_DIGITS) -> float:
    """Redondea y normaliza un flotante: sin `-0.0` y sin colas de coma flotante."""
    if not math.isfinite(value):
        raise ValueError(f"valor no finito en el JSON: {value!r}")
    rounded = round(float(value), digits)
    if rounded == 0.0:
        return 0.0
    if rounded == int(rounded) and abs(rounded) < 1e15:
        return float(int(rounded))
    return rounded


def clean(value: Any, digits: int = FLOAT_DIGITS) -> Any:
    """Aplica `clean_float` recursivamente a listas, tuplas y diccionarios."""
    if isinstance(value, bool) or value is None or isinstance(value, (str, int)):
        return value
    if isinstance(value, float):
        return clean_float(value, digits)
    if isinstance(value, dict):
        return {k: clean(v, digits) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean(v, digits) for v in value]
    return value


def _scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        cleaned = clean_float(value)
        if cleaned == int(cleaned):
            return str(int(cleaned))
        return repr(cleaned)
    if isinstance(value, str):
        return _quote(value)
    raise TypeError(f"tipo no serializable: {type(value).__name__}")


def _quote(text: str) -> str:
    out = ['"']
    for ch in text:
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20:
            out.append(f"\\u{ord(ch):04x}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _compact(value: Any) -> str:
    """Forma compacta de un valor, en una sola línea."""
    if isinstance(value, dict):
        inner = ", ".join(f"{_quote(str(k))}: {_compact(v)}" for k, v in value.items())
        return "{" + inner + "}"
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(_compact(v) for v in value) + "]"
    return _scalar(value)


def _render(value: Any, indent: int, level: int, max_inline: int) -> str:
    compact = _compact(value)
    if len(compact) + level * indent <= max_inline or not isinstance(value, (dict, list, tuple)):
        return compact
    pad = " " * (indent * (level + 1))
    close_pad = " " * (indent * level)
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [f"{pad}{_quote(str(k))}: {_render(v, indent, level + 1, max_inline)}"
                 for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + close_pad + "}"
    if not value:
        return "[]"
    items = [f"{pad}{_render(v, indent, level + 1, max_inline)}" for v in value]
    return "[\n" + ",\n".join(items) + "\n" + close_pad + "]"


def dumps(value: Any, indent: int = 2, max_inline: int = 110) -> str:
    """Serializa `value` a JSON legible y determinista, terminado en `\\n`."""
    return _render(clean(value), indent, 0, max_inline) + "\n"
