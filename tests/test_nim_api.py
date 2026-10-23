#!/usr/bin/env python3
"""
Automated Test Client for OpenAI-Compatible NVIDIA NIM Endpoints.
Supports both isolated Docker and Kubernetes (K3s) deployments.
Includes handling for Chain-of-Thought reasoning models (e.g., DeepSeek-R1).
"""

import argparse
import re
import sys
import requests

def get_models(base_url, timeout=10):
    """Retrieve the list of available models from the NIM endpoint."""
    try:
        response = requests.get(f"{base_url}/models", timeout=timeout)
        response.raise_for_status()
        models = [m["id"] for m in response.json().get("data", [])]
        return models
    except Exception as e:
        print(f"❌ Error querying models from {base_url}/models: {e}")
        print("💡 Suggestion: Ensure host IP is correct, container is running, and firewall allows port 8000.")
        sys.exit(1)

def format_response_content(content, hide_think=False):
    """Optionally strip or separate <think> tags from reasoning models."""
    think_match = re.search(r"<think>(.*?)</think>", content, flags=re.DOTALL)
    if not think_match:
        return content.strip()

    thinking_process = think_match.group(1).strip()
    final_answer = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()

    if hide_think:
        return final_answer if final_answer else content.strip()
    else:
        output_parts = []
        if thinking_process:
            output_parts.append(f"🧠 [Thinking Process / Chain-of-Thought]:\n{thinking_process}")
        if final_answer:
            output_parts.append(f"💬 [Final Answer]:\n{final_answer}")
        return "\n\n".join(output_parts)

def test_endpoint(base_url, model_id, prompt, max_tokens=1024, temperature=0.3, timeout=90, hide_think=False):
    """Send a prompt to the OpenAI-compatible chat completions endpoint."""
    url = f"{base_url}/chat/completions"
    headers = {"Content-Type": "application/json"}
    payload = {
        "model": model_id,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=timeout)
        response.raise_for_status()
        data = response.json()
        raw_content = data["choices"][0]["message"]["content"]
        formatted_content = format_response_content(raw_content, hide_think=hide_think)

        print(f"\n✅ --- Test Prompt: \"{prompt}\" ---")
        print(f"Model: {model_id}")
        print("Response:")
        print(formatted_content)
        print("-" * 60)
        return True
    except Exception as e:
        print(f"❌ Test failed for prompt \"{prompt}\": {e}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Automated & Flexible Test Client for NVIDIA NIM / OpenAI-Compatible Endpoints"
    )
    parser.add_argument("--host", default="localhost", help="API Host (e.g. localhost, 34.x.x.x). Exclude http://")
    parser.add_argument("--port", default="8000", help="API Port (default: 8000)")
    parser.add_argument("--model", default=None, help="Model ID. If omitted, first discovered model is used automatically.")
    parser.add_argument("--prompt", default=None, help="Custom prompt to test. If omitted, standard test suite executes.")
    parser.add_argument("--max-tokens", type=int, default=1024, help="Maximum completion tokens (default: 1024)")
    parser.add_argument("--temperature", type=float, default=0.2, help="Sampling temperature (default: 0.2)")
    parser.add_argument("--timeout", type=int, default=90, help="Request timeout in seconds (default: 90)")
    parser.add_argument("--hide-think", action="store_true", help="Hide internal <think> blocks from reasoning models.")

    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}/v1"
    print(f"🔗 Connecting to: {base_url}")

    # 1. Discover available models
    available_models = get_models(base_url, timeout=args.timeout)
    if not available_models:
        print("⚠️ No models detected on this endpoint!")
        sys.exit(1)

    print(f"📦 Detected models: {', '.join(available_models)}")

    # 2. Select target model
    if args.model:
        if args.model not in available_models:
            print(f"⚠️ Specified model '{args.model}' not found in active endpoint list.")
            print(f"🔄 Falling back to first available model: '{available_models[0]}'")
            model_to_use = available_models[0]
        else:
            model_to_use = args.model
    else:
        model_to_use = available_models[0]

    print(f"🚀 Using model: {model_to_use}\n")

    # 3. Execute prompt(s)
    if args.prompt:
        test_endpoint(
            base_url,
            model_to_use,
            args.prompt,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
            timeout=args.timeout,
            hide_think=args.hide_think,
        )
    else:
        # Standard test suite (General, Reasoning/Math, Coding)
        suite = [
            "What is the capital of France? Answer in one word.",
            "If 5 machines produce 5 widgets in 5 minutes, how many minutes will 100 machines need to produce 100 widgets?",
            "Write a concise Python function that checks if an integer is even.",
        ]
        for prompt in suite:
            test_endpoint(
                base_url,
                model_to_use,
                prompt,
                max_tokens=args.max_tokens,
                temperature=args.temperature,
                timeout=args.timeout,
                hide_think=args.hide_think,
            )
