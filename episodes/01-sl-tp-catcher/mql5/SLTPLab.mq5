//+------------------------------------------------------------------+
//|                                                     SLTPLab.mq5 |
//|                             Copyright © 2026, Volodymyr Karputov |
//|                      https://www.mql5.com/en/users/barabashkakvn |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, Volodymyr Karputov"
#property link      "https://www.mql5.com/en/users/barabashkakvn"
#property version "1.001"
#property description "Test bench for SLTPCatcher: opens six positions on three symbols with different magic"
#property description "numbers, then catches closes by Stop Loss and Take Profit in OnTradeTransaction."
//+------------------------------------------------------------------+
//| Positions (one test day, server time; lot = number of the row):  |
//|  0.01 EURUSD Buy  magic 1001  SL/TP 150 points                   |
//|  0.02 EURUSD Sell magic 1002  SL/TP 150 points                   |
//|  0.03 GBPUSD Buy  magic 777   SL/TP 150 points                   |
//|  0.04 USDJPY Sell magic 0     SL/TP 150 points ("manual")        |
//|  0.05 EURUSD Buy  magic 42    no SL/TP, closed by this EA        |
//|  0.06 GBPUSD Buy  magic 555   SL moved above the open price      |
//| The catcher must report every SL and TP and ignore the close     |
//| made by the EA. InpCatch: two wrong ways and the right one.      |
//| Docs: https://www.mql5.com/en/docs/event_handlers/ontradetransaction |
//|       https://www.mql5.com/en/docs/trading/historyselectbyposition   |
//|       https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#define ROWS 6                    // positions in the test
CTrade         m_trade;           // trading object
//+------------------------------------------------------------------+
//| How the catcher reads the deal                                   |
//+------------------------------------------------------------------+
enum ENUM_CATCH
  {
   CATCH_NO_HISTORY  = 0,         // Wrong: HistoryDealGetInteger without selecting the history
   CATCH_BY_POSITION = 1,         // Wrong: HistorySelectByPosition, then the deal by ticket (SLTPCatcher 1.002)
   CATCH_DEAL_SELECT = 2,         // Right: HistoryDealSelect, then DEAL_REASON (SLTPCatcher 1.003)
  };
//--- input parameters
input ENUM_CATCH InpCatch     = CATCH_DEAL_SELECT;    // How to read the closing deal
input int        InpStartHour = 3;                  // First positions not before this hour, server time
input int        InpPoints    = 150;                // SL and TP distance, points
input int        InpTrailFrom = 60;                 // 0.06: move SL when profit reaches this, points
input int        InpTrailTo   = 10;                 // 0.06: new SL above the open price, points
//
const string   STATE_FILE  = "SLTPLab_state.txt";   // Common\Files: "opened closed caught bar" for the recording script
const double   LOT         = 0.01;                  // lot of row 0 (row N: LOT * (N + 1))
string         m_symbols[ROWS] = {"EURUSD", "EURUSD", "GBPUSD", "USDJPY", "EURUSD", "GBPUSD"};
ENUM_ORDER_TYPE m_types[ROWS]  = {ORDER_TYPE_BUY, ORDER_TYPE_SELL, ORDER_TYPE_BUY, ORDER_TYPE_SELL, ORDER_TYPE_BUY, ORDER_TYPE_BUY};
ulong          m_magics[ROWS]  = {1001, 1002, 777, 0, 42, 555};
int            m_hours[ROWS]   = {0, 0, 1, 1, 2, 2};   // hours after InpStartHour
int            m_opened  = 0;     // rows opened so far
int            m_closed  = 0;     // closing deals seen
int            m_caught  = 0;     // closes reported as SL or TP
bool           m_closed_by_ea = false;
string         m_lines[];         // chart comment: one line per closing deal
datetime       m_bar     = 0;     // open time of the current bar
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("A hedging account is needed: rows 0.01 and 0.02 are a Buy and a Sell of one symbol");
      return(INIT_FAILED);
     }
   if(InpStartHour < 0 || InpStartHour > 20 || InpPoints < 10 || InpTrailFrom <= InpTrailTo || InpTrailTo < 1)
      return(INIT_PARAMETERS_INCORRECT);
   for(int i = 0; i < ROWS; i++)
      if(!SymbolSelect(m_symbols[i], true))
        {
         PrintFormat("Symbol %s is not available", m_symbols[i]);
         return(INIT_FAILED);
        }
   Show();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- in the visual tester the list stays on the chart after the test
   if(!MQLInfoInteger(MQL_VISUAL_MODE))
      Comment("");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- a new bar: tell the recording script (it pauses on the bar after an event)
   datetime bar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(bar != m_bar)
     {
      m_bar = bar;
      WriteState();
     }
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
//--- open the rows by the schedule
   while(m_opened < ROWS && now.hour >= InpStartHour + m_hours[m_opened])
     {
      OpenRow(m_opened);
      m_opened++;
      Show();
     }
//--- row 0.05: one hour later the EA closes it itself (DEAL_REASON_EXPERT, not SL/TP)
   if(!m_closed_by_ea && now.hour >= InpStartHour + m_hours[4] + 1)
     {
      ulong ticket = RowTicket(4);
      if(ticket > 0 && m_trade.PositionClose(ticket))
         m_closed_by_ea = true;
     }
//--- row 0.06: SL above the open price once the profit is big enough
   ulong ticket = RowTicket(5);
   if(ticket > 0 && PositionSelectByTicket(ticket))
     {
      double point = SymbolInfoDouble(m_symbols[5], SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbols[5], SYMBOL_DIGITS);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = NormalizeDouble(open + InpTrailTo * point, digits);
      if(SymbolInfoDouble(m_symbols[5], SYMBOL_BID) - open >= InpTrailFrom * point && PositionGetDouble(POSITION_SL) < sl)
         m_trade.PositionModify(ticket, sl, PositionGetDouble(POSITION_TP));
     }
  }
//+------------------------------------------------------------------+
//| Fires on every trade event of the account                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(InpCatch == CATCH_NO_HISTORY)
      CatchNoHistory(trans);
   else
      if(InpCatch == CATCH_BY_POSITION)
         CatchByPosition(trans);
      else
         CatchByDeal(trans);
  }
//+------------------------------------------------------------------+
//| Wrong: the deal is read without selecting the history first.     |
//| HistoryDealGetInteger returns 0 = DEAL_REASON_CLIENT and         |
//| GetLastError() = 4755 (deal not found): no close is ever caught  |
//+------------------------------------------------------------------+
void CatchNoHistory(const MqlTradeTransaction &trans)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   ResetLastError();
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   int error = GetLastError();
   if(!IsClose(trans))
      return;
   m_closed++;
   string line = StringFormat("deal #%I64u %s: reason = %s, error %d", trans.deal, trans.symbol, ReasonName(reason), error);
   if(reason == DEAL_REASON_SL || reason == DEAL_REASON_TP)
     {
      m_caught++;
      line = "CAUGHT " + line;
      Alert(line);
     }
   else
      line = "missed " + line;
   Print(line);
   AddLine(line);
  }
//+------------------------------------------------------------------+
//| Wrong: SLTPCatcher 1.002. HistorySelectByPosition() returns true,|
//| but right after it the deal by ticket gives 0 and error 4755:    |
//| DEAL_ENTRY is never DEAL_ENTRY_OUT, the code stays silent        |
//+------------------------------------------------------------------+
void CatchByPosition(const MqlTradeTransaction &trans)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistorySelectByPosition(trans.position))
      return;
   ResetLastError();
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   int  error = GetLastError();
   if(entry != DEAL_ENTRY_OUT)
     {
      if(IsClose(trans))
        {
         m_closed++;
         string line = StringFormat("missed deal #%I64u %s: entry = %I64d, reason = %s, error %d", trans.deal, trans.symbol, entry, ReasonName(reason), error);
         Print(line);
         AddLine(line);
        }
      return;
     }
   m_closed++;
   if(reason == DEAL_REASON_SL || reason == DEAL_REASON_TP)
     {
      m_caught++;
      Alert("CAUGHT deal #", trans.deal);
     }
  }
//+------------------------------------------------------------------+
//| Right: the same code as SLTPCatcher.mq5 1.003                    |
//+------------------------------------------------------------------+
void CatchByDeal(const MqlTradeTransaction &trans)
  {
// We only care about freshly added deals
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
// Select the deal itself: right after HistorySelectByPosition() the deal
// properties by ticket are not readable yet (0 and error 4755 in the tester)
   if(!HistoryDealSelect(trans.deal))
      return;
// Keep only closing deals made by the server because of SL or TP
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   m_closed++;
   if(reason != DEAL_REASON_SL && reason != DEAL_REASON_TP)
     {
      AddLine(StringFormat("skip  %s %.2f: %s", trans.symbol, HistoryDealGetDouble(trans.deal, DEAL_VOLUME), ReasonName(reason)));
      return;
     }
   m_caught++;
   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long   magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string exit   = DealRow(trans.deal, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), false);
   string line   = StringFormat("%s    %s %.2f  magic %I64d  profit %+.2f", reason == DEAL_REASON_SL ? "SL" : "TP", symbol,
                                HistoryDealGetDouble(trans.deal, DEAL_VOLUME), magic, HistoryDealGetDouble(trans.deal, DEAL_PROFIT));
// Load all deals of this position (open + close) and find the opening deal
   if(!HistorySelectByPosition(trans.position))
      return;
   ulong open_deal = 0;
   for(int i = 0; i < HistoryDealsTotal() && open_deal == 0; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         open_deal = deal;
     }
// Two rows, same columns as the terminal Deals tab: entry deal, then exit deal
   string msg = StringFormat("%s | %s | magic %I64d\n%s\n%s",
                             reason == DEAL_REASON_SL ? "SL" : "TP",
                             symbol, magic,
                             DealRow(open_deal, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), true),
                             exit);
   Alert(msg);
   Print(msg);
   AddLine(line);
  }
//+------------------------------------------------------------------+
//| One Deals-tab row: time, ticket, type, direction, volume, price, |
//| then S/L and T/P (entry) or commission, swap and profit (exit)   |
//+------------------------------------------------------------------+
string DealRow(const ulong deal, const int digits, const bool entry)
  {
   string type = EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE));
   StringReplace(type, "DEAL_TYPE_", "");
   StringToLower(type);
   string row = StringFormat("%s | #%I64u | %-4s %-3s %.2f @ %s",
                             TimeToString((datetime)HistoryDealGetInteger(deal, DEAL_TIME), TIME_SECONDS),
                             deal, type, entry ? "in" : "out",
                             HistoryDealGetDouble(deal, DEAL_VOLUME),
                             DoubleToString(HistoryDealGetDouble(deal, DEAL_PRICE), digits));
   if(entry)
      return row + StringFormat(" | S/L %s | T/P %s",
                                DoubleToString(HistoryDealGetDouble(deal, DEAL_SL), digits),
                                DoubleToString(HistoryDealGetDouble(deal, DEAL_TP), digits));
   return row + StringFormat(" | commission %.2f | swap %.2f | profit %.2f",
                             HistoryDealGetDouble(deal, DEAL_COMMISSION),
                             HistoryDealGetDouble(deal, DEAL_SWAP),
                             HistoryDealGetDouble(deal, DEAL_PROFIT));
  }
//+------------------------------------------------------------------+
//| Wrong mode: is the deal a close? Counted by the open positions,  |
//| because the deal itself cannot be read without the history       |
//+------------------------------------------------------------------+
bool IsClose(const MqlTradeTransaction &trans)
  {
   return(!PositionSelectByTicket(trans.position));
  }
//+------------------------------------------------------------------+
//| Open row N with its symbol, direction, magic and lot             |
//+------------------------------------------------------------------+
void OpenRow(const int row)
  {
   string symbol = m_symbols[row];
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   bool   buy = (m_types[row] == ORDER_TYPE_BUY);
   double price = buy ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   double base = buy ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   int    points = (row == 5) ? InpPoints * 4 : InpPoints;   // 0.06: far TP, the SL is moved up later
   double sl = 0.0, tp = 0.0;
   if(row != 4)
     {
      sl = NormalizeDouble(buy ? base - points * point : base + points * point, digits);
      tp = NormalizeDouble(buy ? base + points * point : base - points * point, digits);
     }
   m_trade.SetExpertMagicNumber(m_magics[row]);
   if(!m_trade.PositionOpen(symbol, m_types[row], LOT * (row + 1), price, sl, tp, StringFormat("row %.2f", LOT * (row + 1))))
      PrintFormat("Row %.2f %s: open failed, retcode %u", LOT * (row + 1), symbol, m_trade.ResultRetcode());
  }
//+------------------------------------------------------------------+
//| Ticket of the open position of row N (0 - not open)              |
//+------------------------------------------------------------------+
ulong RowTicket(const int row)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magics[row]
         && PositionGetString(POSITION_SYMBOL) == m_symbols[row])
         return(ticket);
     }
   return(0);
  }
//+------------------------------------------------------------------+
//| DEAL_REASON_SL -> "SL", DEAL_REASON_CLIENT -> "CLIENT"           |
//+------------------------------------------------------------------+
string ReasonName(const ENUM_DEAL_REASON reason)
  {
   string name = EnumToString(reason);
   StringReplace(name, "DEAL_REASON_", "");
   return(name);
  }
//+------------------------------------------------------------------+
//| Chart comment line + state file                                  |
//+------------------------------------------------------------------+
void AddLine(const string line)
  {
   int n = ArraySize(m_lines);
   ArrayResize(m_lines, n + 1);
   m_lines[n] = line;
   Show();
  }
//+------------------------------------------------------------------+
//| Chart comment: mode, counters and one line per closing deal      |
//+------------------------------------------------------------------+
void Show()
  {
   string text = StringFormat("%s\nopened %d of %d   closed %d   caught SL/TP %d\n",
                              InpCatch == CATCH_NO_HISTORY ? "Wrong: no HistorySelect" : InpCatch == CATCH_BY_POSITION ? "Wrong: HistorySelectByPosition, then the deal (1.002)" : "Right: HistoryDealSelect + DEAL_REASON (1.003)",
                              m_opened, ROWS, m_closed, m_caught);
   for(int i = 0; i < ArraySize(m_lines); i++)
      text += "\n" + m_lines[i];
   Comment(text);
   WriteState();
  }
//+------------------------------------------------------------------+
//| Common\Files\SLTPLab_state.txt: "opened closed caught bar"       |
//+------------------------------------------------------------------+
void WriteState()
  {
   int handle = FileOpen(STATE_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;
   FileWriteString(handle, StringFormat("%d %d %d %I64d", m_opened, m_closed, m_caught, (long)m_bar));
   FileClose(handle);
  }
//+------------------------------------------------------------------+
