# PropGuard — a prop-firm compliance guard layer for MT5 Expert Advisors

**What it is:** a small, self-contained MetaTrader 5 demo EA that shows the three guards an automated strategy needs to stay inside proprietary-trading-firm rules. The trading "strategy" is a deliberately trivial moving-average cross — **the point is the guard layer, not the signal.**

Most funded-account failures are not strategy failures. They are *rule* failures: a daily-loss limit measured on equity when the trader assumed balance; a news-window execution ban the EA never heard of; an overall drawdown line the EA rode straight through. PropGuard demonstrates how to prevent each one.

## The three guards

**1. Daily-loss guard** — tracks equity against an anchor captured at the broker's server midnight, and when the day's loss reaches a configurable percentage it flattens this EA's positions and blocks new entries until the next server day. Equity-anchored (floating P&L included) because that is how most firms measure it.

**2. Overall max-loss halt** — a static line measured from the starting balance. Set it *inside* the firm's hard limit (e.g. a 9% guard for a 10% firm rule) so the EA stops before the breach, not at it. Once tripped it flattens and stays halted until a manual restart — by design.

**3. News-window guard** — uses MT5's built-in economic calendar to block new entries for a configurable window before and after high-importance events on either of the symbol's currencies. Existing positions are left to their stop-loss/take-profit (force-closing them can itself land inside a news window — a nuance many EAs get wrong).

## How to try it

1. Open it in MetaEditor, compile (F7) — should be 0 errors, 0 warnings.
2. Drop it on any demo chart, or run it in the Strategy Tester.
3. Watch the **Experts / Journal** log: every guard decision is printed with the exact numbers (anchor, floor, equity, event time).

## What this demonstrates about how I work

Every guard logs its reasoning. Every threshold is an input, not a magic number. The guard layer runs *before* the entry logic on each tick, and the overall halt overrides everything. This is the same discipline I bring to client work: make the protective logic explicit, configurable, and auditable — then prove it behaves with a written test.

## Notes & limits

This is a teaching/demo module, not a finished trading product. The MA cross is a placeholder. The calendar guard "fails open" (logs a warning and allows trading) if a broker's server has no calendar data — a deliberate choice you would revisit per client. Free to read, learn from, and adapt; no warranty.

---
*Built by Dror Munk — MT5/MQL5 EA development with prop-firm compliance and backtest validation. Available for retrofits, audits, and custom builds.*
