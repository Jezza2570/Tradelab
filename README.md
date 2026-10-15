# TradeLab

A locally hosted, AI-assisted platform for researching, backtesting and paper trading US equities. It is built
for learning: the strategies, statistics and risk rules are deterministic code, and a local LLM running in
LM Studio explains them and coaches you.

> **No live trading.** Every trade and result in TradeLab is simulated and labelled that way.

## Status

Phase 0 (architecture and planning) is done. Phase 1 has not started.

- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Market data providers](docs/DATA_PROVIDERS.md)

## Check your environment (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-environment.ps1
```

The script reports your CPU, RAM, GPU/VRAM, disk, developer tools and the models LM Studio is serving. It saves
the report to `tradelab-environment.txt`.
