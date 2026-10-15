# Market Data Providers — Assessment

Researched October 2026. Prices change often, so **confirm on each vendor's pricing page before subscribing.**
All figures are for individual, non-professional use.

## Comparison

| Provider | Cost | Real-time equities | Intraday history | Quotes (bid/ask) | Corporate actions | Notes |
|---|---|---|---|---|---|---|
| **Alpaca – Free/Basic** | $0 | IEX only (~2–3% of US volume); WebSocket capped at 30 symbols | Back to 2016, but the latest 15 min is withheld | IEX quotes only (spreads look wider than NBBO) | Yes (corporate actions API) | Free paper account required. 200 historical calls/min. Best free starting point. |
| **Alpaca – Algo Trader Plus** | ~$99/mo | Full SIP (all exchanges), unlimited symbols | Back to 2016, no delay | SIP NBBO | Yes | Same API as free, so upgrading is a config change. |
| **Massive (formerly Polygon.io) – Starter / Developer** | ~$29 / ~$79/mo | 15-min delayed | 5 yrs / 10 yrs | Developer adds trades; quotes need Advanced | Splits and dividends endpoints | Unlimited calls. Good for deep historical research. |
| **Massive – Advanced** | ~$199/mo | Real-time | 20+ yrs | Yes | Yes | Covers the full feature set, at a price. |
| **Databento** | Usage-based or ~$199/mo plan (Jan 2025 figure) | Yes | ~7 yrs OHLCV on plan | Yes (L1 and above) | Yes | Institutional-grade, normalised, pay per GB. Excellent for high-quality backtest data. |
| **CSV / Parquet import** | $0 | — | Whatever you supply | If supplied | Manual | Always available. Useful for offline work and reproducible test fixtures. |
| Yahoo (yfinance) | $0 | No | 1-minute bars only ~7–30 days back | No | Partial | Unofficial scraper, against Yahoo ToS, breaks without notice. **Not recommended** except for ad-hoc daily data. |
| Alpha Vantage free | $0 | No | Limited | No | Some | ~25 requests/day free. Too restrictive. |

## Recommendation

1. **Phase 1–2: Alpaca free (IEX)** as the primary provider, plus a **CSV/Parquet importer** and a **simulated provider** for tests.
   - Limitation shown in the UI: *"IEX feed: prices and volume reflect a single exchange. Volume, relative volume and spreads will differ from the consolidated tape."* This matters for volume-based strategies (Volume Breakout, RVOL scans), so the backtester labels results by feed.
   - Historical bars from Alpaca's free tier are SIP-consolidated for anything older than 15 minutes, which makes them good enough for backtesting.
2. **Upgrade path:** Alpaca Algo Trader Plus (if you want real-time SIP for paper trading) or Massive/Databento (for deeper or higher-quality history). This is a config change because of the provider abstraction.
3. The provider interface is built so that a second provider can be added without touching strategies or the backtester.

## Limitations TradeLab will surface

- Feed type (IEX vs SIP vs delayed) on every chart, quote and scan.
- Survivorship bias: free sources usually lack delisted symbols, so backtests on today's universe overstate results. This is flagged in the assumptions panel.
- Corporate-action adjustment method and source.
- Gaps detected in history (missing minutes and sessions) are listed per run.
- Pre-market and after-hours data is sparse on IEX, so it is excluded by default.

## Sources

- [Alpaca – About Market Data API](https://docs.alpaca.markets/docs/about-market-data-api)
- [Massive (Polygon) pricing summary, 2026](https://apicostcalc.com/polygon.html)
- [Databento – US Equities](https://databento.com/blog/introducing-databento-us-equities)
