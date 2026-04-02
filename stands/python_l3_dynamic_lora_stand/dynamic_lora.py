#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import torch
from torch import Tensor, nn


@dataclass
class L3Summary:
    cycle_mass: float
    logic_mass: float
    runtime_mass: float
    coherence_mean: float
    load_mean: float
    manifest_pressure: float
    active_processes: float
    exhausted_processes: float
    readout: float
    energy: float

    def to_tensor(self, device: torch.device | None = None) -> Tensor:
        return torch.tensor(
            [
                self.cycle_mass,
                self.logic_mass,
                self.runtime_mass,
                self.coherence_mean,
                self.load_mean,
                self.manifest_pressure,
                self.active_processes,
                self.exhausted_processes,
                self.readout,
                self.energy,
            ],
            dtype=torch.float32,
            device=device,
        )


class L3SummaryEncoder(nn.Module):
    def __init__(self, in_dim: int, summary_dim: int) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, summary_dim * 2),
            nn.SiLU(),
            nn.Linear(summary_dim * 2, summary_dim),
            nn.LayerNorm(summary_dim),
        )

    def forward(self, summary: Tensor) -> Tensor:
        return self.net(summary)


class DynamicLoRALayer(nn.Module):
    def __init__(
        self,
        summary_dim: int,
        hidden_size: int,
        rank: int,
        alpha: float = 16.0,
        strength: float = 1e-3,
    ) -> None:
        super().__init__()
        self.hidden_size = hidden_size
        self.rank = rank
        self.scale = (alpha / rank) * strength
        self.down_proj = nn.Linear(summary_dim, rank * hidden_size)
        self.up_proj = nn.Linear(summary_dim, hidden_size * rank)

    def make_adapter(self, summary_latent: Tensor) -> tuple[Tensor, Tensor]:
        down = self.down_proj(summary_latent).view(self.rank, self.hidden_size)
        up = self.up_proj(summary_latent).view(self.hidden_size, self.rank)
        return down, up

    def forward(self, hidden: Tensor, summary_latent: Tensor) -> tuple[Tensor, dict[str, float]]:
        down, up = self.make_adapter(summary_latent)
        down = down.to(device=hidden.device, dtype=hidden.dtype)
        up = up.to(device=hidden.device, dtype=hidden.dtype)
        delta = (hidden @ down.t()) @ up.t()
        delta = delta * self.scale
        adapted = hidden + delta
        stats = {
            "down_norm": float(down.norm().item()),
            "up_norm": float(up.norm().item()),
            "delta_norm": float(delta.norm().item()),
            "adapted_norm": float(adapted.norm().item()),
        }
        return adapted, stats


class DynamicLoRAStack(nn.Module):
    def __init__(
        self,
        hidden_size: int,
        summary_in_dim: int,
        summary_dim: int,
        rank: int,
        target_layers: Iterable[int],
        strength: float = 1e-3,
    ) -> None:
        super().__init__()
        self.target_layers = list(target_layers)
        self.summary_encoder = L3SummaryEncoder(summary_in_dim, summary_dim)
        self.layers = nn.ModuleDict(
            {
                str(layer_idx): DynamicLoRALayer(
                    summary_dim=summary_dim,
                    hidden_size=hidden_size,
                    rank=rank,
                    strength=strength,
                )
                for layer_idx in self.target_layers
            }
        )

    def forward(self, hidden: Tensor, summary: Tensor) -> tuple[dict[int, Tensor], dict[int, dict[str, float]]]:
        summary = summary.to(device=hidden.device, dtype=torch.float32)
        summary_latent = self.summary_encoder(summary).to(device=hidden.device)
        outputs: dict[int, Tensor] = {}
        stats: dict[int, dict[str, float]] = {}
        for layer_idx in self.target_layers:
            adapted, layer_stats = self.layers[str(layer_idx)](hidden, summary_latent)
            outputs[layer_idx] = adapted
            stats[layer_idx] = layer_stats
        return outputs, stats
