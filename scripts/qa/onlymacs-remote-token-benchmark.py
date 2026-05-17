#!/usr/bin/env python3
import argparse
import json
import sys
import time
import urllib.error
import urllib.request


DEFAULT_PROMPT = (
    "Generate a concise synthetic throughput sample. "
    "Write plain text only, avoid Markdown, and continue until the token budget is reached."
)


def estimated_tokens(byte_count: int) -> int:
    if byte_count <= 0:
        return 0
    return max(1, byte_count // 4)


def generated_text_from_raw(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                parts.append(generated_text_from_raw(item.get("text")))
                parts.append(generated_text_from_raw(item.get("content")))
        return "".join(parts)
    return ""


def generated_fields(payload):
    content = []
    reasoning = []
    for choice in payload.get("choices", []) or []:
        delta = choice.get("delta") or {}
        message = choice.get("message") or {}
        for container in (delta, message):
            reasoning.append(generated_text_from_raw(container.get("reasoning")))
            reasoning.append(generated_text_from_raw(container.get("reasoning_content")))
            reasoning.append(generated_text_from_raw(container.get("thinking")))
            content.append(generated_text_from_raw(container.get("content")))
        content.append(generated_text_from_raw(choice.get("text")))
    return "".join(content), "".join(reasoning)


def parse_json_arg(value):
    if value is None:
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def build_payload(args):
    payload = {
        "model": args.model,
        "route_scope": "swarm",
        "prefer_remote": True,
        "stream": True,
        "max_tokens": args.max_tokens,
        "messages": [
            {
                "role": "system",
                "content": "You are benchmarking model output throughput. Return generated text only.",
            },
            {
                "role": "user",
                "content": args.prompt,
            },
        ],
    }
    if args.reasoning_effort:
        payload["reasoning_effort"] = args.reasoning_effort
    if args.reasoning is not None:
        payload["reasoning"] = parse_json_arg(args.reasoning)
    if args.think is not None:
        payload["think"] = parse_json_arg(args.think)
    return payload


def print_metric(name, value):
    print(f"{name}: {value}")


def main():
    parser = argparse.ArgumentParser(
        description="Benchmark OnlyMacs remote generated-token throughput without counting SSE envelope bytes."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:4318", help="OnlyMacs bridge base URL")
    parser.add_argument("--model", required=True, help="Exact model id to request")
    parser.add_argument("--max-tokens", type=int, default=256, help="Synthetic output token budget")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT, help="Synthetic benchmark prompt")
    parser.add_argument("--reasoning-effort", default="", help="Optional OpenAI-compatible reasoning_effort")
    parser.add_argument("--reasoning", default=None, help="Optional JSON or string reasoning control")
    parser.add_argument("--think", default=None, help="Optional JSON or bool Ollama think control, for example true")
    parser.add_argument("--timeout", type=float, default=900, help="HTTP timeout in seconds")
    args = parser.parse_args()

    payload = build_payload(args)
    url = args.base_url.rstrip("/") + "/v1/chat/completions"
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
        method="POST",
    )

    raw_sse_bytes = 0
    content_bytes = 0
    reasoning_bytes = 0
    first_generated_at = None
    started_at = time.perf_counter()

    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            headers = response.headers
            for raw_line in response:
                now = time.perf_counter()
                raw_sse_bytes += len(raw_line)
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[len("data:") :].strip()
                if not data or data == "[DONE]":
                    continue
                try:
                    payload = json.loads(data)
                except json.JSONDecodeError:
                    continue
                content, reasoning = generated_fields(payload)
                generated_now = bool(content or reasoning)
                if generated_now and first_generated_at is None:
                    first_generated_at = now
                content_bytes += len(content.encode("utf-8"))
                reasoning_bytes += len(reasoning.encode("utf-8"))
    except urllib.error.HTTPError as exc:
        sys.stderr.write(f"OnlyMacs benchmark request failed with HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')}\n")
        return 1
    except urllib.error.URLError as exc:
        sys.stderr.write(f"OnlyMacs benchmark request failed: {exc}\n")
        return 1

    finished_at = time.perf_counter()
    total_wall = max(finished_at - started_at, 0.000001)
    first_latency = None if first_generated_at is None else first_generated_at - started_at
    generated_bytes = content_bytes + reasoning_bytes
    generated_tokens = estimated_tokens(generated_bytes)
    after_first_elapsed = None
    if first_generated_at is not None:
        after_first_elapsed = max(finished_at - first_generated_at, 0.000001)

    print("OnlyMacs remote token benchmark")
    print_metric("provider_id", headers.get("X-OnlyMacs-Provider-ID", ""))
    print_metric("provider_name", headers.get("X-OnlyMacs-Provider-Name", ""))
    print_metric("owner_member_name", headers.get("X-OnlyMacs-Owner-Member-Name", ""))
    print_metric("resolved_model", headers.get("X-OnlyMacs-Resolved-Model", args.model))
    print_metric("first_token_latency_s", "n/a" if first_latency is None else f"{first_latency:.3f}")
    print_metric("total_wall_time_s", f"{total_wall:.3f}")
    print_metric("generated_content_bytes", content_bytes)
    print_metric("reasoning_bytes", reasoning_bytes)
    print_metric("generated_tokens_estimate", generated_tokens)
    print_metric(
        "generated_tokens_per_second_after_first_token",
        "n/a" if after_first_elapsed is None else f"{generated_tokens / after_first_elapsed:.2f}",
    )
    print_metric("generated_tokens_per_second_total", f"{generated_tokens / total_wall:.2f}")
    print_metric("raw_sse_bytes", raw_sse_bytes)
    print_metric("raw_sse_bytes_per_second", f"{raw_sse_bytes / total_wall:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
