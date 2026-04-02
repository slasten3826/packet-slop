#!/usr/bin/env python3

from __future__ import annotations

import argparse
import math
import re
import subprocess
from contextlib import contextmanager
from pathlib import Path

import torch
from transformers import AutoConfig, AutoModelForCausalLM, AutoTokenizer

from dynamic_lora import DynamicLoRAStack, L3Summary


def parse_l3_summary(stdout: str) -> L3Summary:
    l3_match = re.search(r"l1_fp=\d+ l2=\d+x\d+ l3=(\d+)", stdout)
    if not l3_match:
        raise ValueError("failed to parse l3 length")
    l3_len = float(l3_match.group(1))

    tick_lines = re.findall(
        r"tick=(\d+) encoded=(\d+) active=(\d+) exhausted=(\d+) cycle_cells=(\d+) logic_cells=(\d+) runtime_cells=(\d+) readout=([0-9.]+) energy=([0-9.]+) manifest=([0-9.]+)",
        stdout,
    )
    if not tick_lines:
        raise ValueError("failed to parse tick summary")
    last = tick_lines[-1]
    _tick, _encoded, active, exhausted, cycle_cells, logic_cells, runtime_cells, readout, energy, manifest = last

    active_f = float(active)
    exhausted_f = float(exhausted)
    cycle_f = float(cycle_cells)
    logic_f = float(logic_cells)
    runtime_f = float(runtime_cells)
    readout_f = float(readout)
    energy_f = float(energy)
    manifest_f = float(manifest)

    # Coherence and load are not exported directly yet, so estimate them from stable readout
    # and field occupancy. Keep them bounded and smooth.
    coherence_mean = min(1.0, max(0.0, readout_f))
    load_mean = min(1.0, math.log1p(active_f) / math.log1p(50000.0))

    return L3Summary(
        cycle_mass=cycle_f / max(1.0, l3_len),
        logic_mass=logic_f / max(1.0, l3_len),
        runtime_mass=runtime_f / max(1.0, l3_len),
        coherence_mean=coherence_mean,
        load_mean=load_mean,
        manifest_pressure=min(1.0, manifest_f / 500.0),
        active_processes=min(1.0, active_f / 50000.0),
        exhausted_processes=min(1.0, exhausted_f / 50000.0),
        readout=readout_f,
        energy=min(1.0, math.log1p(energy_f) / math.log1p(500000.0)),
    )


def run_l3_stand(bootstrap_dump: Path) -> tuple[L3Summary, str]:
    cmd = [
        "lua",
        "/home/slasten/dev/packetLearning/packet-slop/stands/lua_l1_l2_l3_emergent_field_stand/main.lua",
        str(bootstrap_dump),
    ]
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    stdout = result.stdout
    return parse_l3_summary(stdout), stdout


@contextmanager
def lora_hooks(model, stack: DynamicLoRAStack, summary_tensor: torch.Tensor):
    handles = []

    def make_hook(layer_idx: int):
        def hook(_module, _inputs, output):
            hidden = output[0] if isinstance(output, tuple) else output
            adapted_map, _stats = stack(hidden, summary_tensor)
            adapted = adapted_map[layer_idx]
            if isinstance(output, tuple):
                return (adapted,) + output[1:]
            return adapted

        return hook

    for layer_idx in stack.target_layers:
        handles.append(model.model.layers[layer_idx].register_forward_hook(make_hook(layer_idx)))
    try:
        yield
    finally:
        for h in handles:
            h.remove()


def generate(model, tokenizer, prompt: str, max_new_tokens: int) -> str:
    inputs = tokenizer(prompt, return_tensors="pt")
    with torch.no_grad():
        output = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=False,
            temperature=None,
            top_p=None,
            use_cache=True,
        )
    return tokenizer.decode(output[0], skip_special_tokens=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--bootstrap-dump", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--rank", type=int, default=16)
    parser.add_argument("--summary-dim", type=int, default=256)
    parser.add_argument("--strength", type=float, default=1e-5)
    parser.add_argument("--max-new-tokens", type=int, default=32)
    args = parser.parse_args()

    summary, raw_stdout = run_l3_stand(Path(args.bootstrap_dump))

    config = AutoConfig.from_pretrained(args.model)
    tokenizer = AutoTokenizer.from_pretrained(args.model, use_fast=True)
    model = AutoModelForCausalLM.from_pretrained(
        args.model,
        dtype="auto",
        low_cpu_mem_usage=True,
    )
    model.eval()

    target_layers = [0, config.num_hidden_layers // 3, (2 * config.num_hidden_layers) // 3, config.num_hidden_layers - 1]
    stack = DynamicLoRAStack(
        hidden_size=int(config.hidden_size),
        summary_in_dim=10,
        summary_dim=args.summary_dim,
        rank=args.rank,
        target_layers=target_layers,
        strength=args.strength,
    )

    summary_tensor = summary.to_tensor()

    baseline = generate(model, tokenizer, args.prompt, args.max_new_tokens)
    with lora_hooks(model, stack, summary_tensor):
        adapted = generate(model, tokenizer, args.prompt, args.max_new_tokens)

    print("python_l3_dynamic_lora_compare")
    print(f"model={args.model}")
    print(f"bootstrap_dump={args.bootstrap_dump}")
    print(f"target_layers={target_layers}")
    print(f"rank={args.rank} summary_dim={args.summary_dim} strength={args.strength}")
    print(
        "summary cycle=%.4f logic=%.4f runtime=%.4f coherence=%.4f load=%.4f manifest=%.4f active=%.4f exhausted=%.4f readout=%.4f energy=%.4f"
        % (
            summary.cycle_mass,
            summary.logic_mass,
            summary.runtime_mass,
            summary.coherence_mean,
            summary.load_mean,
            summary.manifest_pressure,
            summary.active_processes,
            summary.exhausted_processes,
            summary.readout,
            summary.energy,
        )
    )
    print("")
    print("baseline:")
    print(baseline)
    print("")
    print("adapted:")
    print(adapted)
    print("")
    print("l3_stand_tail:")
    for line in raw_stdout.strip().splitlines()[-5:]:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
