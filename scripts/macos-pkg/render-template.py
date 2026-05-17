#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import sys


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit("usage: render-template.py <template> <output> [KEY=VALUE ...]")

    template_path = pathlib.Path(sys.argv[1])
    output_path = pathlib.Path(sys.argv[2])
    rendered = template_path.read_text()

    for arg in sys.argv[3:]:
      if "=" not in arg:
        raise SystemExit(f"invalid replacement: {arg}")
      key, value = arg.split("=", 1)
      rendered = rendered.replace(f"{{{{{key}}}}}", value)

    output_path.write_text(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
