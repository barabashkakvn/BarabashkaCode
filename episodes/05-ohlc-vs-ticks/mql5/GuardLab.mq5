//+------------------------------------------------------------------+
//|                                                     GuardLab.mq5 |
//|                             Copyright © 2026, Volodymyr Karputov |
//|                      https://www.mql5.com/en/users/barabashkakvn |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, Volodymyr Karputov"
#property link      "https://www.mql5.com/en/users/barabashkakvn"
#property version "1.001"
#property description "Loss guard in the Strategy Tester: run it in \"1 minute OHLC\" and in"
#property description "\"Every tick based on real ticks\" and compare the journal and the CSV."
//+------------------------------------------------------------------+
//| One position at the entry hour, one loss limit in money.         |
//| The guard closes the position as soon as the loss reaches the    |
//| limit. The journal shows how far past the limit it really closed |
//| and the CSV (Common\Files) keeps every tick for the chart.       |
//| Idea:   https://www.mql5.com/en/forum/518423                     |
//| Modes:  https://www.mql5.com/en/docs/runtime/testing#ticks       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade   m_trade;                 // trading object
//--- input parameters
input ENUM_ORDER_TYPE InpType   = ORDER_TYPE_SELL;   // Direction (Buy or Sell)
input double          InpLots   = 1.0;               // Lots
input int             InpHour   = 3;                 // Entry hour, server time
input double          InpLimit  = 500.0;             // Loss limit, account currency
input int             InpLogMin = 60;                // Minutes of ticks to log after entry
input ulong           InpMagic  = 518423;            // Magic number
//
double   m_start      = 0.0;      // equity at entry
datetime m_entry      = 0;        // entry time
bool     m_done       = false;    // the experiment is over
double   m_worst      = 0.0;      // worst loss the guard has seen
double   m_hit_loss   = 0.0;      // loss on the tick that fired the guard
datetime m_hit_time   = 0;        // time of that tick
double   m_hit_bid    = 0.0;      // bid of that tick
long     m_ticks      = 0;        // OnTick calls in total
int      m_min_ticks  = 0;        // ticks in the current minute
int      m_max_ticks  = 0;        // most ticks seen in one minute
datetime m_minute     = 0;        // current minute
long     m_log_time[];            // tick log: time in ms
double   m_log_bid[];             // tick log: bid
double   m_log_eq[];              // tick log: equity
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   m_trade.SetExpertMagicNumber(InpMagic);
   if(InpType != ORDER_TYPE_BUY && InpType != ORDER_TYPE_SELL)
      return(INIT_PARAMETERS_INCORRECT);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   string mode = (m_max_ticks <= 4) ? "ohlc" : "ticks";
   double closed = AccountInfoDouble(ACCOUNT_BALANCE) - m_start;
   PrintFormat("=== GuardLab | %s | mode looks like: %s ===", Symbol(), mode);
   PrintFormat("OnTick calls: %I64d, most ticks in one minute: %d", m_ticks, m_max_ticks);
   PrintFormat("Entry: %s, limit: %.2f", TimeToString(m_entry, TIME_DATE | TIME_SECONDS), InpLimit);
   if(m_hit_time == 0)
      Print("The guard did not fire");
   else
      PrintFormat("Guard fired at %s, bid %.5f, loss %.2f = %.0f%% of the limit",
                  TimeToString(m_hit_time, TIME_DATE | TIME_SECONDS), m_hit_bid, m_hit_loss, 100.0 * m_hit_loss / InpLimit);
   PrintFormat("Closed with %.2f = %.0f%% of the limit (worst loss seen: %.2f)",
               -closed, -100.0 * closed / InpLimit, m_worst);
   SaveLog("GuardLab_" + Symbol() + "_" + mode + ".csv");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(Symbol(), tick))
      return;
   CountTick(tick.time);
   if(m_done)
      return;
   MqlDateTime t;
   TimeToStruct(tick.time, t);
   if(m_entry == 0)
     {
      if(t.hour != InpHour)
         return;
      m_start = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_trade.PositionOpen(Symbol(), InpType, InpLots, (InpType == ORDER_TYPE_BUY) ? tick.ask : tick.bid, 0.0, 0.0))
         m_entry = tick.time;
      return;
     }
//--- the guard: the loss is checked only when a tick arrives
   double loss = m_start - AccountInfoDouble(ACCOUNT_EQUITY);
   if(loss > m_worst)
      m_worst = loss;
   if(tick.time < m_entry + InpLogMin * 60)
      LogTick(tick.time_msc, tick.bid, m_start - loss);
   if(loss >= InpLimit)
     {
      m_hit_loss = loss;
      m_hit_time = tick.time;
      m_hit_bid = tick.bid;
      m_trade.PositionClose(Symbol());
      m_done = true;
     }
  }
//+------------------------------------------------------------------+
//| Counts OnTick calls and the busiest minute                       |
//+------------------------------------------------------------------+
void CountTick(const datetime time)
  {
   m_ticks++;
   datetime minute = time - time % 60;
   if(minute != m_minute)
     {
      m_minute = minute;
      m_min_ticks = 0;
     }
   m_min_ticks++;
   if(m_min_ticks > m_max_ticks)
      m_max_ticks = m_min_ticks;
  }
//+------------------------------------------------------------------+
//| Adds one tick to the log                                         |
//+------------------------------------------------------------------+
void LogTick(const long time_msc, const double bid, const double equity)
  {
   int n = ArraySize(m_log_time);
   ArrayResize(m_log_time, n + 1, 100000);
   ArrayResize(m_log_bid, n + 1, 100000);
   ArrayResize(m_log_eq, n + 1, 100000);
   m_log_time[n] = time_msc;
   m_log_bid[n] = bid;
   m_log_eq[n] = equity;
  }
//+------------------------------------------------------------------+
//| Writes the tick log to Common\Files                              |
//+------------------------------------------------------------------+
void SaveLog(const string file_name)
  {
   int handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("FileOpen(%s) failed, error %d", file_name, GetLastError());
      return;
     }
   FileWrite(handle, "time_msc", "bid", "equity", "start", "limit", "hit_time");
   int n = ArraySize(m_log_time);
   for(int i = 0; i < n; i++)
      FileWrite(handle, m_log_time[i], DoubleToString(m_log_bid[i], _Digits), DoubleToString(m_log_eq[i], 2),
                DoubleToString(m_start, 2), DoubleToString(InpLimit, 2), (long)m_hit_time);
   FileClose(handle);
   PrintFormat("Tick log: %d rows -> Common\\Files\\%s", n, file_name);
  }
//+------------------------------------------------------------------+
