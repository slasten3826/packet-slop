#!/usr/bin/env python3

from __future__ import annotations

import argparse

import torch
from transformers import AutoConfig

from dynamic_lora import DynamicLoRAStack, L3Summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Path to local HF-compatible model directory")
    parser.add_argument("--rank", type=int, default=16)
    parser.add_argument("--summary-dim", type=int, default=256)
    parser.add_argument("--seq-len", type=int, default=128)
    parser.add_argument("--batch-size", type=int, default=1)
    args = parser.parse_args()

    config = AutoConfig.from_pretrained(args.model)
    hidden_size = int(config.hidden_size)
    num_layers = int(config.num_hidden_layers)
    target_layers = [0, num_layers // 3, (2 * num_layers) // 3, num_layers - 1]

    summary = L3Summary(
        cycle_mass=0.62,
        logic_mass=0.24,
        runtime_mass=0.14,
        coherence_mean=0.71,
        load_mean=0.38,
        manifest_pressure=0.19,
        active_processes=2048.0,
        exhausted_processes=512.0,
        readout=0.66,
        energy=153.4,
    )

    hidden = torch.randn(args.batch_size, args.seq_len, hidden_size, dtype=torch.float32)
    stack = DynamicLoRAStack(
        hidden_size=hidden_size,
        summary_in_dim=10,
        summary_dim=args.summary_dim,
        rank=args.rank,
        target_layers=target_layers,
    )
    outputs, stats = stack(hidden, summary.to_tensor())

    print("python_l3_dynamic_lora_stand")
    print(f"model={args.model}")
    print(f"hidden_size={hidden_size} num_layers={num_layers}")
    print(f"target_layers={target_layers}")
    print(f"rank={args.rank} summary_dim={args.summary_dim}")
    print(f"hidden_shape={tuple(hidden.shape)}")
    for layer_idx in target_layers:
        layer_stats = stats[layer_idx]
        print(
            "layer=%d down_norm=%.3f up_norm=%.3f delta_norm=%.3f adapted_norm=%.3f"
            % (
                layer_idx,
                layer_stats["down_norm"],
                layer_stats["up_norm"],
                layer_stats["delta_norm"],
                layer_stats["adapted_norm"],
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
