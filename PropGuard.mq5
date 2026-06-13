//+------------------------------------------------------------------+
//|                                                    PropGuard.mq5  |
//|        Prop-firm compliance guard module — open demo / portfolio |
//|                                                                  |
//|  Author : Dror Munk                                              |
//|  Purpose: Demonstrates the three guards that keep an automated   |
//|           strategy inside proprietary-trading-firm rules:        |
//|             1. Daily-loss guard  (equity-anchored, server-day)   |
//|             2. Max-loss halt     (static, from start balance)    |
//|             3. News-window guard (blocks entries around events)  |
//|                                                                  |
//|  This is a self-contained DEMONSTRATION EA. Its "strategy" is a  |
//|  deliberately trivial moving-average cross — the point is the    |
//|  GUARD LAYER, not the signal. Drop it on a demo chart and watch  |
//|  the Experts log narrate every guard decision.                   |
//|                                                                  |
//|  MIT-style: free to read, learn from, and adapt. No warranty.    |
//+------------------------------------------------------------------+
#property copyright "Dror Munk"
#property version   "1.00"
#property description "Demo: daily-loss guard + static max-loss halt + news-window filter."
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- Strategy inputs (intentionally minimal — this is a demo signal) ---
input group           "Demo strategy (MA cross)"
input int             InpFastMA          = 20;      // Fast MA period
input int             InpSlowMA          = 50;      // Slow MA period
input double          InpLots            = 0.10;    // Fixed lot size (demo)
input int             InpStopLossPts     = 300;     // Stop loss (points)
input int             InpTakeProfitPts   = 600;     // Take profit (points)

//--- Guard 1: daily loss -------------------------------------------------
input group           "Guard 1 — daily loss"
input bool            InpUseDailyGuard   = true;    // Enable daily-loss guard
input double          InpDailyLossPct    = 4.0;     // Max daily loss (% of day-start equity)
//   NOTE: most firms measure the daily limit on EQUITY (floating P&L included),
//   reset at the broker's server midnight. Both choices are configurable below.

//--- Guard 2: max loss ---------------------------------------------------
input group           "Guard 2 — overall max loss"
input bool            InpUseMaxGuard     = true;    // Enable static max-loss halt
input double          InpMaxLossPct      = 9.0;     // Max overall loss (% of start balance)
//   Set this INSIDE the firm's hard line (e.g. 9% guard for a 10% firm rule)
//   so the EA flattens before the firm's breach, not at it.

//--- Guard 3: news window ------------------------------------------------
input group           "Guard 3 — news window"
input bool            InpUseNewsGuard    = true;    // Enable news-window guard
input int             InpNewsMinsBefore  = 2;       // Block this many minutes BEFORE an event
input int             InpNewsMinsAfter   = 2;       // Block this many minutes AFTER an event
input ENUM_CALENDAR_EVENT_IMPORTANCE InpMinImportance = CALENDAR_IMPORTANCE_HIGH; // Min event importance to block
//   Uses MT5's built-in economic calendar. Blocks NEW entries inside the window.
//   Existing positions are left to their SL/TP (closing them can itself fall
//   inside a news window — a nuance many EAs get wrong).

input group           "General"
input long            InpMagic           = 70010;   // Magic number

//--- State ---
double   g_dayStartEquity = 0.0;
double   g_startBalance   = 0.0;
int      g_curDay         = -1;
bool     g_dailyBlocked   = false;   // tripped for the rest of today
bool     g_haltedForGood  = false;   // overall max-loss halt (manual reset)
int      g_fastHandle, g_slowHandle;
string   g_sym;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sym = _Symbol;
   trade.SetExpertMagicNumber(InpMagic);

   g_fastHandle = iMA(g_sym, _Period, InpFastMA, 0, MODE_SMA, PRICE_CLOSE);
   g_slowHandle = iMA(g_sym, _Period, InpSlowMA, 0, MODE_SMA, PRICE_CLOSE);
   if(g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
     {
      Print("PropGuard: failed to create MA handles");
      return(INIT_FAILED);
     }

   g_startBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_curDay         = CurrentServerDay();

   PrintFormat("PropGuard started. StartBalance=%.2f  DayStartEquity=%.2f  "
               "DailyGuard=%s(%.1f%%)  MaxGuard=%s(%.1f%%)  NewsGuard=%s(-%d/+%d min)",
               g_startBalance, g_dayStartEquity,
               (InpUseDailyGuard?"on":"off"), InpDailyLossPct,
               (InpUseMaxGuard?"on":"off"),   InpMaxLossPct,
               (InpUseNewsGuard?"on":"off"),  InpNewsMinsBefore, InpNewsMinsAfter);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
//| Server-day index (days since epoch, server time)                 |
//+------------------------------------------------------------------+
int CurrentServerDay()
  {
   return (int)(TimeCurrent() / 86400);
  }

//+------------------------------------------------------------------+
//| Roll the daily anchor at server midnight                         |
//+------------------------------------------------------------------+
void HandleDailyRollover()
  {
   int today = CurrentServerDay();
   if(today != g_curDay)
     {
      g_curDay         = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyBlocked   = false;
      PrintFormat("PropGuard: new server day. DayStartEquity reset to %.2f", g_dayStartEquity);
     }
  }

//+------------------------------------------------------------------+
//| Count this EA's open positions on this symbol                    |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == g_sym)
            n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Flatten everything this EA owns on this symbol                   |
//+------------------------------------------------------------------+
void FlattenAll(string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == g_sym)
            trade.PositionClose(ticket);
     }
   PrintFormat("PropGuard: FLATTEN ALL (%s)", why);
  }

//+------------------------------------------------------------------+
//| GUARD 2 — static overall max-loss halt                           |
//| Returns true if the halt is (or has been) tripped.               |
//+------------------------------------------------------------------+
bool CheckMaxLossGuard()
  {
   if(!InpUseMaxGuard) return false;
   if(g_haltedForGood) return true;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double floor  = g_startBalance * (1.0 - InpMaxLossPct / 100.0);
   if(equity <= floor)
     {
      g_haltedForGood = true;
      FlattenAll("overall max-loss halt");
      PrintFormat("PropGuard: MAX-LOSS HALT. Equity %.2f <= floor %.2f (%.1f%% of %.2f). "
                  "EA halted; manual restart required.",
                  equity, floor, InpMaxLossPct, g_startBalance);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| GUARD 1 — daily-loss guard (equity-anchored, server day)         |
//| Returns true if new entries are blocked for the rest of today.   |
//+------------------------------------------------------------------+
bool CheckDailyGuard()
  {
   if(!InpUseDailyGuard) return false;
   if(g_dailyBlocked)    return true;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double floor  = g_dayStartEquity * (1.0 - InpDailyLossPct / 100.0);
   if(equity <= floor)
     {
      g_dailyBlocked = true;
      FlattenAll("daily-loss guard");
      PrintFormat("PropGuard: DAILY GUARD tripped. Equity %.2f <= daily floor %.2f "
                  "(%.1f%% of day-start %.2f). New entries blocked until next server day.",
                  equity, floor, InpDailyLossPct, g_dayStartEquity);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| GUARD 3 — news-window guard                                      |
//| Returns true if NOW is inside a blackout window for this symbol. |
//+------------------------------------------------------------------+
bool InNewsWindow()
  {
   if(!InpUseNewsGuard) return false;

   // Map the symbol's two currencies to calendar countries.
   string base  = SymbolInfoString(g_sym, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(g_sym, SYMBOL_CURRENCY_PROFIT);

   datetime now  = TimeCurrent();
   datetime from = now - InpNewsMinsAfter  * 60; // events that started up to X min ago
   datetime to   = now + InpNewsMinsBefore * 60; // events starting within X min

   MqlCalendarValue values[];
   // Pull calendar values in the window for both currencies; if the calendar
   // is unavailable (some brokers/servers), fail OPEN with a logged warning
   // rather than freezing trading silently.
   if(!PullCalendar(base, from, to, values) && !PullCalendar(quote, from, to, values))
      return false;

   for(int i = 0; i < ArraySize(values); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance < InpMinImportance)          continue;

      datetime evt = values[i].time;
      if(evt >= now - InpNewsMinsAfter * 60 && evt <= now + InpNewsMinsBefore * 60)
        {
         PrintFormat("PropGuard: NEWS WINDOW active (event at %s, importance %d). Entries blocked.",
                     TimeToString(evt, TIME_MINUTES), ev.importance);
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Helper: pull calendar values for one currency into 'out'         |
//+------------------------------------------------------------------+
bool PullCalendar(string currency, datetime from, datetime to, MqlCalendarValue &out[])
  {
   if(currency == "") return false;
   MqlCalendarValue tmp[];
   int n = CalendarValueHistory(tmp, from, to, NULL, currency);
   if(n <= 0) return false;
   int base = ArraySize(out);
   ArrayResize(out, base + n);
   for(int i = 0; i < n; i++) out[base + i] = tmp[i];
   return true;
  }

//+------------------------------------------------------------------+
//| Demo signal: +1 long cross, -1 short cross, 0 none               |
//+------------------------------------------------------------------+
int DemoSignal()
  {
   double fast[2], slow[2];
   if(CopyBuffer(g_fastHandle, 0, 1, 2, fast) < 2) return 0;
   if(CopyBuffer(g_slowHandle, 0, 1, 2, slow) < 2) return 0;
   // fast[1]=older bar, fast[0]=last closed bar
   bool crossedUp   = (fast[1] <= slow[1] && fast[0] >  slow[0]);
   bool crossedDown = (fast[1] >= slow[1] && fast[0] <  slow[0]);
   if(crossedUp)   return  1;
   if(crossedDown) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
void OpenTrade(int dir)
  {
   double price = (dir > 0) ? SymbolInfoDouble(g_sym, SYMBOL_ASK)
                            : SymbolInfoDouble(g_sym, SYMBOL_BID);
   double pt    = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   double sl    = (dir > 0) ? price - InpStopLossPts   * pt : price + InpStopLossPts   * pt;
   double tp    = (dir > 0) ? price + InpTakeProfitPts * pt : price - InpTakeProfitPts * pt;

   bool ok = (dir > 0) ? trade.Buy (InpLots, g_sym, price, sl, tp, "PropGuard demo")
                       : trade.Sell(InpLots, g_sym, price, sl, tp, "PropGuard demo");
   if(ok) PrintFormat("PropGuard: opened %s %.2f lots @ %.5f", (dir>0?"BUY":"SELL"), InpLots, price);
  }

//+------------------------------------------------------------------+
//| Main tick — guard layer runs BEFORE any entry logic              |
//+------------------------------------------------------------------+
void OnTick()
  {
   HandleDailyRollover();

   // Guard 2 first: an overall halt overrides everything and persists.
   if(CheckMaxLossGuard()) return;

   // Guard 1: daily guard can flatten + block for the day.
   bool dailyBlocked = CheckDailyGuard();

   // Trade only once per fully-closed bar (keeps the demo clean).
   static datetime lastBar = 0;
   datetime thisBar = iTime(g_sym, _Period, 0);
   if(thisBar == lastBar) return;
   lastBar = thisBar;

   if(dailyBlocked) return;                 // blocked for the rest of today
   if(CountMyPositions() > 0) return;       // one position at a time (demo)
   if(InNewsWindow()) return;               // Guard 3: no entries in news window

   int sig = DemoSignal();
   if(sig != 0) OpenTrade(sig);
  }
//+------------------------------------------------------------------+
