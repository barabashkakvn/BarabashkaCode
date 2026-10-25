//+------------------------------------------------------------------+
//|                                                  SLTPCatcher.mq5 |
//|                             Copyright © 2026, Volodymyr Karputov |
//|                      https://www.mql5.com/en/users/barabashkakvn |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, Volodymyr Karputov"
#property link      "https://www.mql5.com/en/users/barabashkakvn"
#property version "1.003"
#property description "Alerts and prints a full report whenever ANY position (any "
#property description "symbol, any magic number) is closed by Stop Loss or Take Profit."
//+------------------------------------------------------------------+
//| 1.003: the closing deal is selected with HistoryDealSelect().    |
//| 1.002 read it right after HistorySelectByPosition() and in the   |
//| tester got 0 (DEAL_REASON_CLIENT) and error 4755 for every deal. |
//| Docs: https://www.mql5.com/en/docs/event_handlers/ontradetransaction |
//|       https://www.mql5.com/en/docs/trading/historydealselect         |
//|       https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties |
//+------------------------------------------------------------------+
//| Fires on every trade event of the account                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
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
   if(reason != DEAL_REASON_SL && reason != DEAL_REASON_TP)
      return;
   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long   magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string exit   = DealRow(trans.deal, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS), false);
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
