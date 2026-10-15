# TradeLab — System Architecture

Status: **proposed** (pre-Phase 1). Decisions marked *(open)* need confirmation before Phase 1 starts.

TradeLab is a locally hosted research, backtesting, paper-trading and education platform for US equities
day trading. It is built around one rule: **every number shown comes from deterministic code or a named data
provider. The local LLM explains, compares and teaches. It never produces prices, signals, statistics or
risk decisions.**

---

## 1. Guiding principles

| Principle | What it means in practice |
|---|---|
| Deterministic core, advisory AI | Indicators, strategies, backtests, risk checks and fills are pure Python with tests. The LLM gets read-only tools and cannot change state. |
| Provenance on every number | Each candle, quote and result carries `provider`, `feed` (e.g. `iex`, `sip`, `delayed-15m`, `simulated`), `as_of` and `received_at`. The UI shows them. |
| No silent substitution | If real-time data is unavailable, the feed is labelled delayed or stale, or the request fails. It never falls back quietly. |
| Point-in-time correctness | Backtests and replay only see data timestamped at or before the simulated clock. This is enforced structurally, not by convention. |
| Simulated means labelled | Paper trading and backtest outputs are tagged `SIMULATED` in the database, API and UI. There is no live-execution code path in v1. |
| Auditable | Orders, fills, risk decisions, strategy versions and AI tool calls go to append-only audit tables. |
| Local-first | It runs on one Windows PC. Secrets stay in `.env` on the backend and are never sent to the browser or the LLM. |

---

## 2. Technology stack

The stack you specified is sound. These are the additions and refinements, with reasons:

| Layer | Choice | Rationale |
|---|---|---|
| Frontend | React 18 + TypeScript + Vite | As requested. |
| Server state | TanStack Query | Caching, retries and invalidation for REST data. Avoids hand-rolled fetch state. |
| Client state | Zustand | Small and predictable. Enough for UI and session state. |
| Charts | TradingView **Lightweight Charts v5** (Apache-2.0) | Multi-pane support in v5 fits RSI/MACD/volume panes. **The license requires TradingView attribution**, which goes in the chart footer. |
| Tables | TanStack Table | Trade lists, journals and scanner results. |
| Backend | Python 3.12 + FastAPI + Uvicorn | 3.12 has the widest prebuilt Windows wheel support across the scientific stack. 3.13 also works. |
| Packaging | **uv** (Python), npm (frontend) | uv gives fast, lockfile-based, reproducible installs on Windows. |
| Validation | Pydantic v2 + pydantic-settings | One validation layer for API I/O, configuration and LLM tool arguments and outputs. |
| ORM / migrations | SQLAlchemy 2.0 (async) + asyncpg + **Alembic** | Typed models and versioned migrations. |
| Database | PostgreSQL 16 | As requested. TimescaleDB is optional later. Plain Postgres with good indexes copes easily with a few hundred symbols of 1-minute bars. |
| Quant | pandas, NumPy, SciPy, statsmodels | Indicators are written in-house and tested against reference values, so their behaviour is known exactly and cannot change through a third-party release. |
| Calendars | `exchange_calendars` | NYSE sessions, holidays, early closes and DST. |
| Logging | structlog (JSON to file, pretty in the console) | Structured, correlation-ID aware logs. |
| HTTP client | httpx (async) + tenacity | Timeouts, retries and backoff for providers and LM Studio. |
| Testing | pytest, pytest-asyncio, hypothesis; Vitest + Testing Library; Playwright (later) | Property tests suit the "no look-ahead" invariants. |
| Lint/format | ruff, mypy (strict on core packages); ESLint, Prettier, `tsc --noEmit` | |

**Not used, and why:**

- **Backtrader:** unmaintained.
- **vectorbt / vectorbt PRO:** fast, but vectorised and not event-driven, which makes realistic fills, bracket orders and daily loss limits harder. The PRO version is paid.
- **LangChain-style agent frameworks:** add a large dependency for a small, auditable tool loop that is better written directly.

---

## 3. High-level architecture

The backend is a **modular monolith**: one FastAPI process plus one background worker process, with strict
package boundaries and separate database schemas per domain. This keeps local setup simple (no service mesh,
no message broker) and still enforces the separation of research, backtesting and paper trading that you asked
for. Any module can be split into its own service later because modules talk only through defined service
interfaces.

```
┌──────────────────────────── Browser (React + Vite) ────────────────────────────┐
│ Dashboard │ Charts │ Scanner │ Backtests │ Paper Trading │ Journal │ AI Chat   │
│           │        │         │           │               │ Coach   │ Replay    │
└───────┬─────────────────────────────── REST (JSON) + WebSocket ───────┬───────┘
        │                                                                │
┌───────▼──────────────────────── FastAPI app (api process) ─────────────▼──────┐
│  api/ routers  ─  auth-less local only, bound to 127.0.0.1, CORS locked down   │
│ ┌──────────────┐ ┌─────────────┐ ┌──────────────┐ ┌───────────────┐            │
│ │ market_data  │ │ indicators  │ │ strategies   │ │ backtest      │            │
│ │ (providers,  │ │ (pure fns)  │ │ (signals)    │ │ (event engine,│            │
│ │  calendar,   │ └─────────────┘ └──────────────┘ │  walk-forward)│            │
│ │  cache)      │                                   └───────────────┘            │
│ └──────────────┘ ┌─────────────┐ ┌──────────────┐ ┌───────────────┐            │
│                  │ risk        │◄┤ paper        │ │ scanner       │            │
│                  │ (gatekeeper)│ │ (OMS, fills) │ └───────────────┘            │
│                  └─────────────┘ └──────────────┘                              │
│ ┌──────────────────────────────────────────────┐ ┌───────────────┐            │
│ │ ai: LM Studio client, tool registry (R/O),   │ │ analytics,    │            │
│ │ output validators, prompts, coach, replay    │ │ journal, audit│            │
│ └──────────────────────────────────────────────┘ └───────────────┘            │
└──────┬───────────────────────────────┬────────────────────────────┬───────────┘
       │ SQLAlchemy                    │ httpx                      │ httpx (stream)
┌──────▼──────┐          ┌─────────────▼───────────┐       ┌────────▼──────────┐
│ PostgreSQL  │◄─────────┤ worker process           │       │ LM Studio         │
│ schemas:    │          │ - live feed ingest (WS)  │       │ localhost:1234/v1 │
│ market,     │          │ - historical backfill    │       └───────────────────┘
│ research,   │          │ - paper order matching   │
│ backtest,   │          │ - scheduled scans        │       ┌───────────────────┐
│ paper,      │          │ - staleness monitor      ├──────►│ Market data APIs  │
│ ai, audit   │          └──────────────────────────┘       └───────────────────┘
└─────────────┘
```

Why a separate worker: the live feed, the paper-order matcher and long backtests must not block API requests
or die when the API process reloads during development. The worker talks to the API process through Postgres
(job tables plus `LISTEN/NOTIFY`) so no Redis or broker needs installing on Windows.

---

## 4. Repository layout

```
Tradelab/
├── backend/
│   ├── pyproject.toml            # uv-managed
│   ├── alembic.ini
│   ├── migrations/               # Alembic versions
│   ├── src/tradelab/
│   │   ├── main.py               # FastAPI app factory
│   │   ├── worker.py             # background worker entrypoint
│   │   ├── core/                 # config, logging, errors, clock, ids, db session
│   │   ├── domain/               # pure dataclasses/enums: Bar, Quote, Order, Fill, Signal…
│   │   ├── market_data/
│   │   │   ├── providers/        # base.py (Protocol), alpaca.py, massive.py, csv_import.py, simulated.py
│   │   │   ├── calendar.py       # exchange sessions, early closes
│   │   │   ├── corporate_actions.py
│   │   │   ├── repository.py     # candle storage & point-in-time queries
│   │   │   └── freshness.py      # staleness detection
│   │   ├── indicators/           # vwap, sma/ema, rsi, macd, atr, levels (S/R)
│   │   ├── strategies/           # base.py + orb, vwap_trend, ma_cross, rsi_mr, volume_breakout
│   │   ├── backtest/             # engine, fill models, cost models, metrics, walk_forward
│   │   ├── risk/                 # rules, sizing, limits, suspension state
│   │   ├── paper/                # OMS, matching engine, account ledger
│   │   ├── scanner/              # criteria, universe, runner
│   │   ├── analytics/            # performance attribution, exports
│   │   ├── journal/
│   │   ├── ai/
│   │   │   ├── client.py         # LM Studio (OpenAI-compatible) client, streaming
│   │   │   ├── tools/            # read-only tool registry + JSON schemas
│   │   │   ├── schemas.py        # structured output models (TradeSetup, etc.)
│   │   │   ├── guardrails.py     # number provenance checks, output validation
│   │   │   ├── prompts/          # versioned system prompts (analyst, coach)
│   │   │   └── coach/            # lessons, replay sessions
│   │   ├── audit/
│   │   └── api/                  # routers + websocket hubs (thin; call services)
│   └── tests/
│       ├── unit/  integration/  property/  fixtures/   # golden data files
├── frontend/
│   ├── package.json  vite.config.ts  tsconfig.json
│   └── src/
│       ├── app/                  # routing, providers, layout shell
│       ├── api/                  # typed client (generated from OpenAPI), ws client
│       ├── features/             # dashboard, chart, watchlist, scanner, backtest, paper, journal, ai, coach, analytics
│       ├── components/           # shared UI (DataBadge, FreshnessIndicator, SimulatedBanner…)
│       └── styles/
├── docs/                         # ARCHITECTURE, ROADMAP, DATA_PROVIDERS, BACKTEST_ASSUMPTIONS, user guides
├── scripts/                      # check-environment.ps1, dev.ps1 (start everything), db helpers
├── docker-compose.yml            # Postgres only (optional path)
├── .env.example
└── README.md
```

Frontend API types are **generated from FastAPI's OpenAPI schema** (`openapi-typescript`), so the frontend
and backend cannot drift apart silently.

---

## 5. Core module design

### 5.1 Market data

```python
class MarketDataProvider(Protocol):
    info: ProviderInfo   # name, feeds, latency class, history depth, rate limits, attribution text
    async def get_bars(self, symbol, timeframe, start, end, adjustment) -> BarSeries
    async def get_latest_quote(self, symbol) -> Quote | None
    async def get_corporate_actions(self, symbols, start, end) -> list[CorporateAction]
    def stream(self, symbols, channels) -> AsyncIterator[MarketEvent]
```

- **Capability flags.** Each provider declares what it supports (quotes, splits, live, SIP vs IEX). The UI and AI only offer features the active provider supports.
- **Provenance.** Every `Bar` and `Quote` carries `provider`, `feed`, `as_of` (exchange time) and `received_at`. A freshness service compares `now − as_of` with the expected cadence and flags `LIVE`, `DELAYED`, `STALE` or `CLOSED`.
- **Storage.** Raw unadjusted bars are stored once. Split and dividend adjustment is applied on read from a `corporate_actions` table, so adjusted series can always be rebuilt point-in-time.
- **Incomplete candles.** A bar is `final=false` until its interval closes plus a grace period. Strategies and backtests only consume final bars. The chart draws the forming bar distinctly.
- **Rate limiting.** A token-bucket limiter per provider, plus retry-after handling and a persistent backfill queue that resumes where it stopped.
- **Simulated provider.** For tests, demos and replay. Its data is always labelled `feed=simulated` and can never be selected as a "live" source.

### 5.2 Indicators

Pure functions on pandas Series/DataFrames with explicit warm-up handling. Values before warm-up are `NaN`,
never back-filled. Each indicator is tested against hand-computed fixtures. VWAP resets per session and uses
regular hours by default (configurable).

### 5.3 Strategy framework

```python
class Strategy(ABC):
    name: str; version: str
    Params: type[BaseModel]                     # validated, with documented ranges
    def warmup_bars(self, params) -> int
    def on_bar(self, ctx: BarContext) -> list[SignalIntent]   # ctx exposes ONLY history ≤ now
```

- `BarContext` wraps a read-only, append-only view, so future data cannot be indexed. Property tests check that shuffling or perturbing future bars never changes past signals.
- Signals are intents (`ENTER_LONG`, `EXIT`, stop and target levels), not orders. Orders are created downstream by the risk and execution layers, so the same strategy code drives backtests, paper trading, replay and the scanner.
- Strategy definitions and parameter sets are versioned and hashed. Every result references `(strategy, version, params_hash, data_range, cost_model_id)`.

### 5.4 Backtest engine (event-driven)

- **Clock.** Replays final bars in timestamp order across symbols. Signals generated on bar *t* fill no earlier than bar *t+1* (next-open by default, configurable).
- **Fill model.** Bid/ask aware when quotes exist. Otherwise a modelled spread based on liquidity bucket, plus a slippage model (fixed bps, ATR fraction, or volume-participation impact). Limit orders fill only if price trades *through* the limit (configurable). When a stop and a target are both touched inside one bar, the **worst case is assumed by default**.
- **Costs.** Commission models (per share, per order, % notional) plus SEC and FINRA TAF fees, all versioned.
- **Rules.** Session hours, no new entries in the last N minutes, forced flat at close (for day-trading strategies), halts and gaps.
- **Risk.** Uses the *same* risk engine as paper trading (sizing by stop distance, daily loss limit, max positions).
- **Validation.** Chronological train/validation/test splits, anchored and rolling walk-forward, out-of-sample reporting kept separate from in-sample. Every optimisation run records how many parameter combinations were tried (needed to judge overfitting, e.g. deflated Sharpe).
- **Metrics.** Win rate, average win and loss, profit factor, expectancy (with bootstrap confidence intervals), max drawdown, exposure, turnover and cost drag. Sharpe and Sortino are shown only above a minimum sample size, with a warning when the sample is small.
- **Transparency.** Every run stores an `assumptions` JSON document (fill model, costs, slippage, adjustments, data feed, gaps found) that the UI renders next to the results.

### 5.5 Risk engine (deterministic gatekeeper)

Every order, whether from the user, a strategy or replay, passes `RiskEngine.evaluate(order, account_state) → Approved | Rejected(reasons)`.

- Rules: max risk per trade (% equity), max daily loss, max drawdown from peak, max open positions, max exposure per position and in total, minimum risk/reward, and position size from stop distance.
- A breach sets a **suspension state** (persisted) that blocks new entries until the next session or a manual reset with a cooldown. The reset is UI-only.
- The AI module **has no import path to risk mutation functions**. Its tool registry exposes `get_risk_status` read-only. An architecture test enforces that `tradelab.ai` never imports write APIs.

### 5.6 Paper trading

- OMS with order states `NEW → ACCEPTED → PARTIALLY_FILLED → FILLED / CANCELLED / REJECTED / EXPIRED`. Market, limit, stop and bracket (OCO stop-loss plus take-profit) orders are supported.
- **Idempotency.** Every order requires a client order ID (UUID). A unique constraint plus a request-hash check prevents duplicates.
- **Matching.** Runs in the worker against the live or delayed feed using the same fill model as the backtester, so paper and backtest results are comparable. If the feed is delayed or stale, matching pauses and the UI says why. It never fills at an old price.
- **Ledger.** A double-entry style cash and position ledger (append-only). Realised and unrealised P&L and equity are derived from it, never stored as mutable totals.
- The starting balance is configurable (default $25,000), with account resets archived rather than deleted.

### 5.7 AI layer (LM Studio)

- **Client.** OpenAI-compatible `/v1/chat/completions` with streaming (SSE relayed to the browser over WebSocket). Model discovery uses `/v1/models`, enriched by LM Studio's `/api/v0/models` (load state, max context, quantisation) when available.
- **Settings.** Model, temperature, max tokens and context budget are configurable in the UI. Note: LM Studio fixes the context length **when the model is loaded**. TradeLab reads the loaded limit and budgets prompts to fit; it cannot change it per request.
- **Tool calling.** A registry of read-only tools such as `get_bars`, `get_indicators`, `get_quote`, `get_scanner_results`, `get_backtest_summary`, `get_strategy_definition`, `get_paper_positions`, `get_journal_entries` and `get_risk_status`. Arguments are validated with Pydantic, row counts are capped, and every call is audited. If a model lacks native tool calling, a fallback flow is used: the backend pre-fetches data and the model answers over it.
- **Structured outputs.** `response_format: json_schema` for `TradeSetupReview`, `StrategyComparison` and `TradeReview`. Invalid JSON gets one repair retry, then a visible error. Nothing is silently dropped.
- **Provenance guardrail.** Tool results are tagged with IDs. The UI renders *data* (from tools, with source badges) and *interpretation* (model text) as visually separate blocks. A validator flags numbers in model text that do not appear in any tool result in that turn.
- **No invented confidence.** The output schemas have no confidence or probability field. Historical performance fields can only be filled from backtest result IDs.
- **AI-proposed strategy changes** become *draft parameter sets*. They are accepted only after a backtest **and** an out-of-sample or walk-forward run, which the user triggers.

### 5.8 Scanner

Deterministic criteria (relative volume, gap %, momentum, ATR %, VWAP position, ORB state, ADX trend strength,
dollar-volume and spread filters) are composed into saved scans. Results record the data timestamp and feed.
The AI can only explain and compare stored result sets.

### 5.9 Coach and replay

Replay mode runs a session with a virtual clock. Only bars at or before the replay time are served (the same
point-in-time repository the backtester uses). The user places paper-replay trades and the coach reviews them
afterwards. Lessons are structured content (Markdown plus interactive chart states), and the coach prompts ask
the user to reason first before revealing an explanation.

---

## 6. Data model (initial schemas)

| Schema | Key tables |
|---|---|
| `market` | `instruments`, `bars_1m` (+ derived aggregates), `quotes_snapshot`, `corporate_actions`, `provider_runs`, `data_gaps` |
| `research` | `watchlists`, `strategy_definitions`, `parameter_sets`, `scans`, `scan_results` |
| `backtest` | `runs`, `run_assumptions`, `trades`, `equity_points`, `walk_forward_folds` |
| `paper` | `accounts`, `orders`, `fills`, `ledger_entries`, `positions_view` (view), `risk_settings`, `risk_events` |
| `journal` | `entries`, `tags`, `entry_trades` |
| `ai` | `conversations`, `messages`, `tool_calls`, `model_settings` |
| `audit` | `events` (append-only, hash-chained for tamper evidence) |

Timestamps are stored as `timestamptz` in UTC and displayed in America/New_York and your local time zone.
Money values use `NUMERIC` in the database and `Decimal` in the ledger and order path. Floats are used only in
the vectorised analytics path.

---

## 7. Real-time flow

1. The worker subscribes to the provider WebSocket (trades, quotes, minute bars), normalises events, stamps `received_at` and writes final bars.
2. The worker publishes over Postgres `NOTIFY`. The API process relays the event to browser WebSocket channels (`bars:{symbol}:{tf}`, `quotes:{symbol}`, `orders`, `risk`, `ai:{conversation}`).
3. The freshness monitor emits `feed_status` events. The UI shows a per-symbol badge such as `LIVE · IEX`, `DELAYED 15m`, `STALE 47s` or `MARKET CLOSED`.

---

## 8. Security and reliability

- The backend binds to `127.0.0.1` only. CORS allows only the Vite dev origin. There is no live-broker credential path in v1, and an architecture test asserts that no order-routing module exists.
- Secrets live in `backend/.env`, loaded by pydantic-settings and never serialised into API responses or LLM prompts. A redaction filter runs on logs.
- Every external call has a timeout, bounded retries and circuit-breaker style backoff.
- Migrations run through Alembic only, and CI runs `alembic upgrade head` against a scratch database.
- Tests cover unit, property (look-ahead invariants), integration (Postgres) and frontend component tests. A GitHub Actions workflow is added in Phase 1.

---

## 9. Running locally on Windows

- **Postgres:** either Docker Desktop (`docker compose up -d db`) or the native EDB installer *(open)*.
- **Backend:** `uv sync` then `uv run alembic upgrade head` then `uv run tradelab-api` and `uv run tradelab-worker`.
- **Frontend:** `npm install` then `npm run dev`.
- `scripts/dev.ps1` starts everything in split terminals. VS Code `launch.json` and recommended extensions are included.
