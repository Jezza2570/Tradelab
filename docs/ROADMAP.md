# TradeLab — Development Roadmap

Each phase ends with:

- passing tests that were actually run
- a short usage guide
- updated documentation
- a demo checklist you can follow

Each phase is delivered as a branch with focused commits. Nothing is reported as working unless a test or a
manual verification step shows it.

Legend: **DoD** = Definition of Done.

---

## Phase 0 — Assessment & architecture *(this step)*

- Environment assessment, architecture, data-provider research and roadmap.
- Windows environment-check script (`scripts/check-environment.ps1`).
- Decisions needed from you are listed at the end of this file.

## Phase 1 — Foundation, database, LM Studio, basic dashboard

**Build**

- Monorepo skeleton (`backend/`, `frontend/`, `docs/`, `scripts/`). Tooling: uv, ruff, mypy, ESLint, Prettier, pre-commit.
- `core/`: settings (pydantic-settings, `.env.example`), structlog JSON logging with request IDs, error envelope, UTC clock abstraction (injectable, for replay and tests).
- PostgreSQL connection, SQLAlchemy async session, Alembic baseline migration: schemas plus the `audit.events`, `ai.model_settings` and `market.instruments` tables.
- `GET /health` reports database, LM Studio and provider status.
- LM Studio integration:
  - model discovery
  - connection status with periodic probe
  - model selection persisted in the database
  - temperature and max-token settings, plus a context budget read from the loaded model
  - streaming chat over WebSocket
  - timeout, unavailable-model and malformed-response handling
- Frontend:
  - dark terminal-style app shell, routing, TanStack Query
  - status bar showing LM Studio, DB and data-feed badges
  - settings page for model selection
  - a basic AI chat panel with streaming (no tools yet)
  - placeholder dashboard grid
- `docker-compose.yml` (Postgres) and/or native setup notes, `scripts/dev.ps1`, VS Code settings, GitHub Actions CI.

**Tests**

- Settings validation.
- LM Studio client against a mock server: discovery, streaming, timeout, 404 model, malformed chunks.
- Health endpoint.
- Migration up/down.
- Frontend component tests for the status badges and chat stream rendering.

**DoD:** `scripts/dev.ps1` brings up the app. The status bar shows LM Studio connected or disconnected accurately. You can pick a model and stream a chat reply. All tests pass in CI.

## Phase 2 — Historical market data, charts, indicators

- Provider abstraction plus an **Alpaca** provider, a **CSV/Parquet import** provider and a **Simulated** provider (labelled).
- NYSE calendar (sessions, holidays, early closes), corporate actions, adjusted-on-read bars.
- Backfill jobs in the worker with a rate limiter, resumable queue and gap detection.
- Live/delayed stream ingest, freshness monitor, WebSocket relay.
- Indicators: SMA/EMA, session VWAP, RSI, MACD, ATR, volume MA, pivot-based support/resistance. All are tested against hand-computed fixtures.
- Chart: Lightweight Charts v5 with candles, volume pane, overlays, RSI and MACD panes, timeframe switcher (1m/5m/15m/1h/1D), and the forming bar drawn distinctly.
- Watchlists, provenance and freshness badges, attribution footer.

**DoD:** load a year of 1-minute history for a watchlist, browse it on charts with indicators, see live or delayed updates clearly labelled, and see detected data gaps listed.

## Phase 3 — Strategy framework & backtesting

- Strategy base class, parameter schemas, versioning and hashing.
- The five strategies: ORB, VWAP Trend, MA Crossover, RSI Mean Reversion, Volume Breakout. Each has documented entry and exit rules.
- Event-driven backtester with:
  - fill models (next-open, spread, slippage)
  - commission and regulatory fees
  - stop and target handling with worst-case intrabar ordering
  - forced end-of-day exits
  - shared risk engine (minimal version)
- Metrics with bootstrap confidence intervals, equity curve, trade-by-trade report, assumptions document.
- UI: backtest configurator, results page, trade markers on the chart.
- `docs/BACKTEST_ASSUMPTIONS.md`.

**Tests**

- Property tests: perturbing future bars never changes past signals or fills.
- Golden-file regression backtests.
- Cost and fill unit tests.

**DoD:** run each strategy over a chosen range and get a reproducible result (same inputs give the same hash and the same numbers), with every assumption visible.

## Phase 4 — Paper trading & risk management

- Full risk engine: per-trade risk, daily loss, max drawdown, max positions, exposure, R:R, stop-based sizing, persisted suspension.
- OMS: market, limit, stop and bracket orders, idempotent client order IDs.
- Matching engine in the worker using the same fill model as the backtester. Pauses on a stale feed.
- Append-only ledger, positions, realised and unrealised P&L, equity curve.
- UI:
  - order ticket with a live risk preview (size, $ risk, R:R)
  - positions and orders blotter
  - "SIMULATED" banners
- Trade journal (linked to fills, tags, screenshots of chart state).
- Audit log viewer.

**DoD:** place, modify and cancel paper orders against the live or delayed feed. Breaching the daily loss limit suspends trading. Duplicate submissions are rejected. All of it is audited.

## Phase 5 — AI research assistant, scanner, trading coach

- Read-only tool registry with schema validation, row caps and auditing. A tool-calling loop with a fallback for models without native tool support.
- Structured outputs: `TradeSetupReview`, `StrategyComparison`, `TradeReview`. Repair-retry, then a visible error.
- Provenance guardrail: data and interpretation are rendered separately, and the numbers in model text are cross-checked against tool results.
- Scanner: deterministic criteria, saved scans, scheduled runs, results with timestamps. AI can explain and compare results.
- Coach: lesson library, replay mode with hidden future bars, post-trade review, recurring-mistake detection (deterministic pattern stats first, LLM narrative second).
- AI-proposed parameter changes become drafts and are accepted only after a backtest plus an out-of-sample run.

**DoD:** ask "what setups are on my watchlist?" and get an answer built only from tool data, with sources shown. Replay a past session blind and get a review.

## Phase 6 — Advanced analytics, walk-forward, hardening

- Walk-forward (anchored and rolling) and train/validation/test workflows. Parameter-search accounting (number of trials, deflated Sharpe, out-of-sample decay).
- Analytics dashboard:
  - returns and daily/weekly P&L
  - breakdowns by strategy, time of day, instrument and market regime (volatility and trend buckets)
  - cost drag
  - strategy comparison
  - CSV/Parquet/JSON export
- Performance work (caching, aggregate tables), Playwright end-to-end tests, backup and restore scripts, user guide.

**DoD:** a strategy report states clearly whether any edge survives realistic costs out-of-sample, with confidence intervals.

---

## Decisions needed before Phase 1

1. **Market data provider:** Alpaca free (recommended), a paid provider, or CSV import only to start.
2. **PostgreSQL on Windows:** Docker Desktop or the native installer.
3. **Your hardware and LM Studio models:** run `scripts/check-environment.ps1` and share the output, so the AI layer can be tuned to your model's context size and tool-calling ability.
