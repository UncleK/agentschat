from __future__ import annotations

import hashlib
import json
import re
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


APP_DIR = Path(__file__).resolve().parents[1]
LIB_DIR = APP_DIR / "lib"
L10N_DIR = LIB_DIR / "l10n"
GENERATED_DIR = L10N_DIR / "generated"
RUNTIME_CATALOG_PATH = GENERATED_DIR / "runtime_message_catalog.dart"

SKIP_FILES = {
    LIB_DIR / "core" / "locale" / "app_localization_extensions.dart",
    LIB_DIR / "core" / "locale" / "app_locale.dart",
}


@dataclass(frozen=True)
class MessageDefinition:
    key: str
    en_template: str
    zh_template: str
    placeholders: tuple[str, ...]


@dataclass(frozen=True)
class ConvertedString:
    template: str
    placeholder_names: tuple[str, ...]
    placeholder_expressions: tuple[str, ...]


def main() -> None:
    message_definitions: "OrderedDict[str, MessageDefinition]" = OrderedDict()
    skipped_calls: list[tuple[Path, str]] = []

    target_files = sorted(
        path
        for path in LIB_DIR.rglob("*.dart")
        if "l10n" not in path.parts and path not in SKIP_FILES
    )

    for path in target_files:
        source = path.read_text(encoding="utf-8")
        rewritten = source
        changed = False
        skipped: list[str] = []
        for function_name in ("localizedText", "localizedAppText"):
            rewritten, function_changed, function_skipped = rewrite_localized_calls(
                rewritten,
                function_name=function_name,
                path=path,
                message_definitions=message_definitions,
            )
            changed = changed or function_changed
            skipped.extend(function_skipped)
        if changed:
            path.write_text(rewritten, encoding="utf-8")
        skipped_calls.extend((path, reason) for reason in skipped)

    update_arb_files(message_definitions.values())
    generate_runtime_catalog()

    print(f"processed files: {len(target_files)}")
    print(f"generated messages: {len(message_definitions)}")
    if skipped_calls:
        print("skipped calls:")
        for path, reason in skipped_calls:
            print(f"  {path.relative_to(APP_DIR)} :: {reason}")


def rewrite_localized_calls(
    source: str,
    *,
    function_name: str,
    path: Path,
    message_definitions: "OrderedDict[str, MessageDefinition]",
) -> tuple[str, bool, list[str]]:
    replacements: list[tuple[int, int, str]] = []
    skipped: list[str] = []

    call_prefix = f"{function_name}("
    for start, end, call_source in find_function_calls(source, call_prefix):
        inner = call_source[len(call_prefix) : -1]
        args = parse_named_arguments(inner)
        if "en" not in args or "zhHans" not in args:
            skipped.append(f"missing en/zhHans at offset {start}")
            continue

        en_string = convert_string_expression(args["en"])
        zh_string = convert_string_expression(
            args["zhHans"],
            placeholder_names=en_string.placeholder_names if en_string else None,
            placeholder_expressions=en_string.placeholder_expressions if en_string else None,
        )
        if en_string is None or zh_string is None:
            skipped.append(f"non-literal localizedText call at offset {start}")
            continue
        if en_string.placeholder_names != zh_string.placeholder_names:
            skipped.append(f"placeholder mismatch at offset {start}")
            continue

        existing_key = parse_string_literal_value(args.get("key"))
        key = existing_key or build_message_key(en_string.template)
        existing_definition = message_definitions.get(key)
        next_definition = MessageDefinition(
            key=key,
            en_template=en_string.template,
            zh_template=zh_string.template,
            placeholders=en_string.placeholder_names,
        )
        if existing_definition is None:
            message_definitions[key] = next_definition
        elif existing_definition != next_definition:
            skipped.append(f"conflicting template for key {key} at offset {start}")
            continue

        if existing_key is not None:
            continue

        new_call = build_localized_text_call(
            function_name=function_name,
            key=key,
            en_expression=args["en"],
            zh_expression=args["zhHans"],
            placeholder_names=en_string.placeholder_names,
            placeholder_expressions=en_string.placeholder_expressions,
        )
        replacements.append((start, end, new_call))

    if not replacements:
        return source, False, skipped

    rewritten_chunks: list[str] = []
    cursor = 0
    for start, end, replacement in replacements:
        rewritten_chunks.append(source[cursor:start])
        rewritten_chunks.append(replacement)
        cursor = end
    rewritten_chunks.append(source[cursor:])
    return "".join(rewritten_chunks), True, skipped


def build_localized_text_call(
    *,
    function_name: str,
    key: str,
    en_expression: str,
    zh_expression: str,
    placeholder_names: tuple[str, ...],
    placeholder_expressions: tuple[str, ...],
) -> str:
    parts = [f"key: '{key}'"]
    if placeholder_names:
        args_items = ", ".join(
            f"'{name}': {expression}"
            for name, expression in zip(
                placeholder_names,
                placeholder_expressions,
                strict=True,
            )
        )
        parts.append(f"args: <String, Object?>{{{args_items}}}")
    parts.append(f"en: {en_expression}")
    parts.append(f"zhHans: {zh_expression}")
    return f"{function_name}({', '.join(parts)})"


def update_arb_files(message_definitions: Iterable[MessageDefinition]) -> None:
    arb_files = sorted(
        path
        for path in L10N_DIR.glob("*.arb")
        if path.name.startswith("app_")
    )
    arb_documents: dict[Path, OrderedDict[str, object]] = {}
    locale_tags: dict[Path, str] = {}

    for path in arb_files:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
        arb_documents[path] = data
        locale_tags[path] = normalize_locale_tag(str(data.get("@@locale", "")))

    for definition in message_definitions:
        for path, document in arb_documents.items():
            locale_tag = locale_tags[path]
            document[definition.key] = localized_value_for_locale(locale_tag, definition)
            if path.name == "app_en.arb" and definition.placeholders:
                document[f"@{definition.key}"] = OrderedDict(
                    [
                        (
                            "placeholders",
                            OrderedDict(
                                (name, OrderedDict()) for name in definition.placeholders
                            ),
                        ),
                    ]
                )

    for path, document in arb_documents.items():
        path.write_text(
            json.dumps(document, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def generate_runtime_catalog() -> None:
    locale_documents: list[tuple[str, OrderedDict[str, object]]] = []
    for path in sorted(L10N_DIR.glob("*.arb")):
        if not path.name.startswith("app_"):
            continue
        document = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
        locale_tag = normalize_locale_tag(str(document.get("@@locale", "")))
        locale_documents.append((locale_tag, document))

    GENERATED_DIR.mkdir(parents=True, exist_ok=True)

    lines = [
        "// Generated by tool/migrate_localized_text_to_arb.py. Do not edit by hand.",
        "",
        "import 'package:flutter/widgets.dart';",
        "",
        "const Map<String, Map<String, String>> _runtimeMessageCatalog = <String, Map<String, String>>{",
    ]
    for locale_tag, document in locale_documents:
        lines.append(f"  '{escape_dart_string(locale_tag)}': <String, String>{{")
        for key, value in document.items():
            if key.startswith("@"):
                continue
            lines.append(
                f"    '{escape_dart_string(key)}': '{escape_dart_string(str(value))}',"
            )
        lines.append("  },")
    lines.extend(
        [
            "};",
            "",
            "String? lookupRuntimeMessage({",
            "  required Locale locale,",
            "  required String key,",
            "  Map<String, Object?> args = const <String, Object?>{},",
            "}) {",
            "  for (final localeTag in _candidateLocaleTags(locale)) {",
            "    final template = _runtimeMessageCatalog[localeTag]?[key];",
            "    if (template != null) {",
            "      return _formatRuntimeMessage(template, args);",
            "    }",
            "  }",
            "  return null;",
            "}",
            "",
            "Iterable<String> _candidateLocaleTags(Locale locale) sync* {",
            "  final exactTag = _localeTag(locale);",
            "  yield exactTag;",
            "  if (locale.languageCode.isNotEmpty) {",
            "    yield locale.languageCode;",
            "  }",
            "  if (exactTag != 'en') {",
            "    yield 'en';",
            "  }",
            "}",
            "",
            "String _localeTag(Locale locale) {",
            "  if (locale.scriptCode != null && locale.scriptCode!.isNotEmpty) {",
            "    return '${locale.languageCode}-${locale.scriptCode}';",
            "  }",
            "  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {",
            "    return '${locale.languageCode}-${locale.countryCode}';",
            "  }",
            "  return locale.languageCode;",
            "}",
            "",
            "String _formatRuntimeMessage(",
            "  String template,",
            "  Map<String, Object?> args,",
            ") {",
            "  return template.replaceAllMapped(RegExp(r'\\{(\\w+)\\}'), (match) {",
            "    final value = args[match.group(1)];",
            "    return value?.toString() ?? match.group(0)!;",
            "  });",
            "}",
            "",
        ]
    )
    RUNTIME_CATALOG_PATH.write_text("\n".join(lines), encoding="utf-8")


def localized_value_for_locale(locale_tag: str, definition: MessageDefinition) -> str:
    if locale_tag in {"zh", "zh-Hans", "zh-Hant"}:
        return definition.zh_template
    return definition.en_template


def normalize_locale_tag(locale_value: str) -> str:
    normalized = locale_value.replace("_", "-").strip()
    if not normalized:
        return "en"
    return normalized


def build_message_key(template: str) -> str:
    normalized_words = re.findall(r"[A-Za-z0-9]+", template.replace("{", " ").replace("}", " "))
    base_words = normalized_words[:10] or ["message"]
    base = "msg" + "".join(word[:1].upper() + word[1:] for word in base_words)
    if len(base) > 64:
        base = base[:64]
    digest = hashlib.sha1(template.encode("utf-8")).hexdigest()[:8]
    return f"{base}{digest}"


def convert_string_expression(
    expression: str,
    *,
    placeholder_names: tuple[str, ...] | None = None,
    placeholder_expressions: tuple[str, ...] | None = None,
) -> ConvertedString | None:
    expression = expression.strip()
    if len(expression) < 2 or expression[0] not in {"'", '"'} or expression[-1] != expression[0]:
        return None

    quote = expression[0]
    body = expression[1:-1]
    template_parts: list[str] = []
    placeholder_lookup: dict[str, str] = {}
    ordered_placeholder_names: list[str] = []
    ordered_placeholder_expressions: list[str] = []
    supplied_names = list(placeholder_names or ())
    supplied_expression_lookup = {
        expression: name
        for name, expression in zip(
            placeholder_names or (),
            placeholder_expressions or (),
            strict=True,
        )
    }
    supplied_index = 0
    index = 0

    while index < len(body):
        char = body[index]
        if char == "\\":
            template_parts.append(unescape_dart_character(body[index + 1] if index + 1 < len(body) else ""))
            index += 2
            continue
        if char != "$":
            template_parts.append(char)
            index += 1
            continue

        if index + 1 < len(body) and body[index + 1] == "{":
            expression_value, index = consume_braced_interpolation(body, index + 2)
        else:
            expression_value, index = consume_identifier_interpolation(body, index + 1)

        if expression_value in placeholder_lookup:
            placeholder_name = placeholder_lookup[expression_value]
        else:
            if expression_value in supplied_expression_lookup:
                placeholder_name = supplied_expression_lookup[expression_value]
            elif supplied_index < len(supplied_names):
                placeholder_name = supplied_names[supplied_index]
            else:
                placeholder_name = create_placeholder_name(
                    expression_value,
                    existing_names=tuple(ordered_placeholder_names),
                )
            supplied_index += 1
            placeholder_lookup[expression_value] = placeholder_name
            ordered_placeholder_names.append(placeholder_name)
            ordered_placeholder_expressions.append(expression_value)
        template_parts.append(f"{{{placeholder_name}}}")

    if placeholder_names is not None and set(ordered_placeholder_names) != set(supplied_names):
        return None

    placeholder_name_list = (
        tuple(dict.fromkeys(placeholder_names))
        if placeholder_names is not None
        else tuple(ordered_placeholder_names)
    )
    return ConvertedString(
        template="".join(template_parts),
        placeholder_names=placeholder_name_list,
        placeholder_expressions=tuple(ordered_placeholder_expressions),
    )


def parse_string_literal_value(expression: str | None) -> str | None:
    if expression is None:
        return None
    converted = convert_string_expression(expression)
    if converted is None or converted.placeholder_names:
        return None
    return converted.template


def create_placeholder_name(expression: str, *, existing_names: tuple[str, ...]) -> str:
    words = re.findall(r"[A-Za-z0-9]+", expression.replace("!", " "))
    if not words:
        words = ["value"]
    cleaned_words = [word for word in words if word.lower() not in {"this"}]
    if not cleaned_words:
        cleaned_words = ["value"]
    candidate = cleaned_words[0][0].lower() + cleaned_words[0][1:]
    candidate += "".join(word[:1].upper() + word[1:] for word in cleaned_words[1:6])
    if len(candidate) > 48:
        candidate = candidate[:48]
    if not re.match(r"^[A-Za-z_]", candidate):
        candidate = f"value{candidate}"
    existing = set(existing_names)
    if candidate not in existing:
        return candidate
    suffix = hashlib.sha1(expression.encode("utf-8")).hexdigest()[:6]
    return f"{candidate}{suffix}"


def consume_braced_interpolation(body: str, start_index: int) -> tuple[str, int]:
    depth = 1
    index = start_index
    in_string: str | None = None
    escape = False
    parts: list[str] = []

    while index < len(body):
        char = body[index]
        if in_string:
            parts.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == in_string:
                in_string = None
            index += 1
            continue

        if char in {"'", '"'}:
            in_string = char
            parts.append(char)
            index += 1
            continue
        if char == "{":
            depth += 1
            parts.append(char)
            index += 1
            continue
        if char == "}":
            depth -= 1
            if depth == 0:
                return "".join(parts).strip(), index + 1
            parts.append(char)
            index += 1
            continue

        parts.append(char)
        index += 1

    raise ValueError("Unclosed interpolation expression")


def consume_identifier_interpolation(body: str, start_index: int) -> tuple[str, int]:
    identifier_match = re.match(r"[A-Za-z_][A-Za-z0-9_]*", body[start_index:])
    if identifier_match is None:
        raise ValueError(f"Unsupported interpolation near: {body[start_index:start_index + 20]}")
    identifier = identifier_match.group(0)
    return identifier, start_index + len(identifier)


def unescape_dart_character(value: str) -> str:
    mapping = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "'": "'",
        '"': '"',
        "\\": "\\",
        "$": "$",
    }
    return mapping.get(value, value)


def find_function_calls(source: str, needle: str) -> list[tuple[int, int, str]]:
    calls: list[tuple[int, int, str]] = []
    cursor = 0
    while True:
        start = source.find(needle, cursor)
        if start == -1:
            break
        index = start + len(needle)
        depth = 1
        in_string: str | None = None
        escape = False
        while index < len(source):
            char = source[index]
            if in_string:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == in_string:
                    in_string = None
                index += 1
                continue
            if char in {"'", '"'}:
                in_string = char
                index += 1
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    calls.append((start, index + 1, source[start : index + 1]))
                    cursor = index + 1
                    break
            index += 1
        else:
            raise ValueError(f"Unclosed function call for {needle!r}")
    return calls


def parse_named_arguments(argument_source: str) -> OrderedDict[str, str]:
    parts: list[str] = []
    start = 0
    paren_depth = 0
    brace_depth = 0
    bracket_depth = 0
    in_string: str | None = None
    escape = False

    for index, char in enumerate(argument_source):
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == in_string:
                in_string = None
            continue
        if char in {"'", '"'}:
            in_string = char
            continue
        if char == "(":
            paren_depth += 1
            continue
        if char == ")":
            paren_depth -= 1
            continue
        if char == "{":
            brace_depth += 1
            continue
        if char == "}":
            brace_depth -= 1
            continue
        if char == "[":
            bracket_depth += 1
            continue
        if char == "]":
            bracket_depth -= 1
            continue
        if char == "," and paren_depth == brace_depth == bracket_depth == 0:
            parts.append(argument_source[start:index])
            start = index + 1

    parts.append(argument_source[start:])

    result: OrderedDict[str, str] = OrderedDict()
    for part in parts:
        if ":" not in part:
            continue
        name, value = part.split(":", 1)
        result[name.strip()] = value.strip()
    return result


def escape_dart_string(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
        .replace("$", "\\$")
    )


if __name__ == "__main__":
    main()
