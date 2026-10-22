//+------------------------------------------------------------------+
//|                                                    CloseLoop.mq5 |
//|                             Copyright © 2026, Volodymyr Karputov |
//|                      https://www.mql5.com/en/users/barabashkakvn |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, Volodymyr Karputov"
#property link      "https://www.mql5.com/en/users/barabashkakvn"
#property version "1.006"
#property description "Creates five positions, pending orders or chart objects (0.01 ... 0.05) and deletes"
#property description "them in one loop: from 0 up (wrong), from the end, a while loop or a tickets array."
//+------------------------------------------------------------------+
//| One item every hour from InpStartHour (wide spread at night):    |
//| item 0 gets 0.01, item 1 - 0.02, and so on, so the number shows  |
//| the index the item had. Items: Buy positions, Buy Limit orders   |
//| far below the price, or buttons on the chart.                    |
//| One hour after the last one all items of this EA are deleted in  |
//| the way chosen by InpLoop.                                       |
//| while loops: one "manual" position (magic 0) opens first.        |
//| Tickets array: two positions are closed "outside the EA" first,  |
//| then the array is cleaned and the rest is closed by its tickets. |
//| Docs: https://www.mql5.com/en/docs/trading/positionstotal        |
//|       https://www.mql5.com/en/docs/trading/orderstotal           |
//|       https://www.mql5.com/en/docs/objects/objectstotal          |
//|       https://www.mql5.com/en/docs/array/arrayremove             |
//+------------------------------------------------------------------+
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\Trade.mqh>
CPositionInfo  m_position;        // position object
COrderInfo     m_order;           // pending order object
CTrade         m_trade;           // trading object
//+------------------------------------------------------------------+
//| Delete loop                                                      |
//+------------------------------------------------------------------+
enum ENUM_CLOSE_LOOP
  {
   LOOP_FROM_ZERO      = 0,       // Wrong: for(int i = 0; i < Total(); i++)
   LOOP_FROM_END       = 1,       // Right: for(int i = Total() - 1; i >= 0; i--)
   LOOP_WHILE_ANY      = 2,       // Risky: while(PositionsTotal() > 0) close index 0
   LOOP_WHILE_OURS     = 3,       // Risky: the same while with the symbol and magic filter
   LOOP_ARRAY_FORWARD  = 4,       // Tickets array, dead tickets removed from 0 up (wrong)
   LOOP_ARRAY_BACKWARD = 5,       // Tickets array, dead tickets removed from the end (right)
  };
//+------------------------------------------------------------------+
//| What the loop deletes                                            |
//+------------------------------------------------------------------+
enum ENUM_TARGET
  {
   TARGET_POSITIONS = 0,          // Positions: PositionsTotal()
   TARGET_ORDERS    = 1,          // Pending orders: OrdersTotal()
   TARGET_OBJECTS   = 2,          // Chart objects: ObjectsTotal()
  };
//--- input parameters
input ENUM_CLOSE_LOOP InpLoop      = LOOP_FROM_ZERO;     // Delete loop
input ENUM_TARGET     InpTarget    = TARGET_POSITIONS;   // What to delete
input int             InpStartHour = 3;                  // First item not before this hour, server time
input int             InpItems     = 5;                  // Items to create
input double          InpLot       = 0.01;               // Lot of item 0 (item N: lot * (N + 1))
input int             InpPauseMin  = 60;                 // Minutes between steps
input int             InpOrderStep = 300;                // Buy Limit N: Ask - step * (N + 1), points
input bool            InpManual    = false;              // Open one "manual" position (magic 0, lot 0.10) first
input int             InpGuard     = 100000;             // while loop: stop after this many passes
input ulong           InpMagic     = 6006;               // Magic number
//
const string   PREFIX      = "CloseLoop_";            // name prefix of our chart objects
const string   STATE_FILE  = "CloseLoop_state.txt";   // Common\Files: "count stage" for the recording script
const double   MANUAL_LOT  = 0.10;                    // lot of the "manual" position
//--- stages of the test, also written to the state file
const int      STAGE_CREATE   = 0;    // items are being created
const int      STAGE_OUTSIDE  = 1;    // tickets array: two positions closed outside the EA
const int      STAGE_CLEANED  = 2;    // tickets array: dead tickets removed
const int      STAGE_DONE     = 3;    // the delete loop has run
int      m_created   = 0;         // items created so far
datetime m_last_step = 0;         // time of the last step
int      m_stage     = STAGE_CREATE;
string   m_state     = "waiting for the first tick";   // state line of the chart comment
ulong    m_shown     = 0;         // GetTickCount64() of the last Comment()
int      m_count     = 0;         // our items at the last Comment()
datetime m_bar       = 0;         // open time of the current bar (the recording script pauses on a new bar)
ulong    m_tickets[];             // tickets array mode: tickets of our positions
int      m_passes    = 0;         // while modes: passes of the loop
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTarget == TARGET_POSITIONS && AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("A hedging account is needed: on a netting account five Buy orders make one position");
      return(INIT_FAILED);
     }
   if(InpStartHour < 0 || InpStartHour > 23 || InpItems < 3 || InpPauseMin < 1 || InpOrderStep < 1 || InpGuard < 1)
      return(INIT_PARAMETERS_INCORRECT);
   if((InpLoop >= LOOP_WHILE_ANY || InpManual) && InpTarget != TARGET_POSITIONS)
     {
      Print("while loops, the tickets array and the manual position work with positions only");
      return(INIT_PARAMETERS_INCORRECT);
     }
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   if(InpLot < min || InpLot * InpItems > max || MathAbs(InpLot / step - MathRound(InpLot / step)) > 1e-8)
     {
      PrintFormat("Lot %.2f does not fit %s: min %.2f, max %.2f, step %.2f", InpLot, Symbol(), min, max, step);
      return(INIT_PARAMETERS_INCORRECT);
     }
   m_trade.SetExpertMagicNumber(InpMagic);
   ShowItems();
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
//--- the chart comment is redrawn once per real second: an even load keeps the visual tester speed steady
   if(GetTickCount64() - m_shown >= 1000)
      ShowItems();
   if(m_stage == STAGE_DONE)
      return;
   datetime now = TimeCurrent();
   if(m_created > 0 && now < m_last_step + InpPauseMin * 60)
      return;
   if(m_created == 0)
     {
      MqlDateTime t;
      TimeToStruct(now, t);
      if(t.hour < InpStartHour)
         return;
     }
//--- one item per hour: lot = InpLot * (index + 1)
   if(m_created < InpItems)
     {
      if(m_created == 0 && InpManual)
         OpenManual();
      if(CreateItem(m_created))
        {
         m_created++;
         m_last_step = now;
         m_state = StringFormat("created %d of %d", m_created, InpItems);
         ShowItems();
        }
      return;
     }
   m_last_step = now;
//--- tickets array: first two positions are closed outside the EA, then the array is cleaned
   bool is_array = (InpLoop == LOOP_ARRAY_FORWARD || InpLoop == LOOP_ARRAY_BACKWARD);
   if(is_array && m_stage == STAGE_CREATE)
     {
      CloseOutside();
      m_stage = STAGE_OUTSIDE;
      m_state = "two positions closed outside the EA, the array still has " + IntegerToString(ArraySize(m_tickets));
      ShowItems();
      return;
     }
   if(is_array && m_stage == STAGE_OUTSIDE)
     {
      if(InpLoop == LOOP_ARRAY_FORWARD)
         CleanArrayForward();
      else
         CleanArrayBackward();
      m_stage = STAGE_CLEANED;
      int real = CountItems();
      PrintFormat("After cleaning: the array has %d tickets, real positions: %d", ArraySize(m_tickets), real);
      m_state = StringFormat("array cleaned: %d tickets, real positions: %d %s", ArraySize(m_tickets), real,
                             ArraySize(m_tickets) == real ? "OK" : "MISMATCH");
      ShowItems();
      return;
     }
//--- delete everything in one loop
   m_stage = STAGE_DONE;
   switch(InpLoop)
     {
      case LOOP_FROM_ZERO:
         DeleteFromZero();
         break;
      case LOOP_FROM_END:
         DeleteFromEnd();
         break;
      case LOOP_WHILE_ANY:
         WhileAny();
         break;
      case LOOP_WHILE_OURS:
         WhileOurs();
         break;
      default:
         CloseByArray();
     }
   int left = CountItems();
   PrintFormat("After the loop: %d of %d %s left, PositionsTotal() = %d", left, InpItems, ItemsName(), PositionsTotal());
   m_state = StringFormat("after the loop: %d left", left);
   ShowItems();
  }
//+------------------------------------------------------------------+
//| A "manual" position: magic 0, lot 0.10, opened before ours       |
//+------------------------------------------------------------------+
void OpenManual(void)
  {
   m_trade.SetExpertMagicNumber(0);
   if(m_trade.Buy(MANUAL_LOT, Symbol(), 0.0, 0.0, 0.0, "manual, magic 0") && m_trade.ResultRetcode() == TRADE_RETCODE_DONE)
      PrintFormat("Opened a manual position (magic 0): #%I64u, lot %.2f", m_trade.ResultOrder(), MANUAL_LOT);
   m_trade.SetExpertMagicNumber(InpMagic);
  }
//+------------------------------------------------------------------+
//| Trade comment: the tester has no magic column, the comment shows |
//| whose position or order it is                                    |
//+------------------------------------------------------------------+
string TradeComment(void)
  {
   return("CloseLoop, magic " + IntegerToString(InpMagic));
  }
//+------------------------------------------------------------------+
//| Creates item number k: a Buy, a Buy Limit or a button            |
//+------------------------------------------------------------------+
bool CreateItem(const int k)
  {
   double lot = NormalizeDouble(InpLot * (k + 1), 2);
   if(InpTarget == TARGET_POSITIONS)
     {
      if(!m_trade.Buy(lot, Symbol(), 0.0, 0.0, 0.0, TradeComment()) || m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
         return(false);
      ulong ticket = m_trade.ResultOrder();   // on a hedging account the position ticket = the opening order ticket
      int n = ArraySize(m_tickets);
      ArrayResize(m_tickets, n + 1);
      m_tickets[n] = ticket;
      PrintFormat("Opened position %d: #%I64u, lot %.2f", k, ticket, lot);
      return(true);
     }
   if(InpTarget == TARGET_ORDERS)
     {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double price = NormalizeDouble(ask - InpOrderStep * (k + 1) * Point(), Digits());
      if(!m_trade.BuyLimit(lot, price, Symbol(), 0.0, 0.0, ORDER_TIME_GTC, 0, TradeComment()) ||
         m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
         return(false);
      PrintFormat("Placed Buy Limit %d: #%I64u, lot %.2f at %s", k, m_trade.ResultOrder(), lot, DoubleToString(price, Digits()));
      return(true);
     }
   string name = PREFIX + IntegerToString(k);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return(false);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 240);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30 + k * 56);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 160);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 46);
   ObjectSetString(0, name, OBJPROP_TEXT, DoubleToString(lot, 2));
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 16);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'0,114,178');
   ChartRedraw();
   PrintFormat("Created object %d: %s, text %.2f", k, name, lot);
   return(true);
  }
//+------------------------------------------------------------------+
//| Wrong: deleting item i moves the next one down to index i,       |
//| and i++ jumps over it                                            |
//+------------------------------------------------------------------+
void DeleteFromZero()
  {
   PrintFormat("--- Wrong loop: for(int i = 0; i < %s; i++)", TotalName());
   for(int i = 0; i < Total(); i++)
      DeleteAt(i);
  }
//+------------------------------------------------------------------+
//| Right: deleting item i moves only the items above i,             |
//| and those have already been processed                            |
//+------------------------------------------------------------------+
void DeleteFromEnd()
  {
   PrintFormat("--- Right loop: for(int i = %s - 1; i >= 0; i--)", TotalName());
   for(int i = Total() - 1; i >= 0; i--)
      DeleteAt(i);
  }
//+------------------------------------------------------------------+
//| Risky: closes whatever is at index 0 until nothing is left -     |
//| the manual position (magic 0) is closed too                      |
//+------------------------------------------------------------------+
void WhileAny()
  {
   Print("--- Risky loop: while(PositionsTotal() > 0) close index 0");
   m_passes = 0;
   while(PositionsTotal() > 0)
     {
      if(++m_passes > InpGuard)
        {
         PrintFormat("Guard: %d passes and PositionsTotal() = %d - the loop would never end", InpGuard, PositionsTotal());
         break;
        }
      if(!m_position.SelectByIndex(0))
         continue;
      PrintFormat("pass %d: close index 0: #%I64u, magic %I64d, lot %.2f%s", m_passes, m_position.Ticket(),
                  m_position.Magic(), m_position.Volume(), m_position.Magic() == (long)InpMagic ? "" : "  <- NOT OURS");
      m_trade.PositionClose(m_position.Ticket());
     }
  }
//+------------------------------------------------------------------+
//| Risky: the same while with the filter - when index 0 is not      |
//| ours, nothing changes and the loop never ends                    |
//+------------------------------------------------------------------+
void WhileOurs()
  {
   Print("--- Risky loop: while(PositionsTotal() > 0) close index 0 if it is ours");
   m_passes = 0;
   while(PositionsTotal() > 0)
     {
      if(++m_passes > InpGuard)
        {
         PrintFormat("Guard: %d passes and PositionsTotal() = %d - the loop would never end", InpGuard, PositionsTotal());
         break;
        }
      string id;
      double lot;
      if(!Ours(0, id, lot))
        {
         if(m_passes <= 3)
            PrintFormat("pass %d: index 0 is not ours - skip, PositionsTotal() = %d", m_passes, PositionsTotal());
         continue;
        }
      m_trade.PositionClose(m_position.Ticket());
     }
  }
//+------------------------------------------------------------------+
//| Tickets array: two positions (0.02 and 0.03) are closed as if by |
//| a stop loss or by hand - the array does not know about it        |
//+------------------------------------------------------------------+
void CloseOutside(void)
  {
   for(int k = 1; k <= 2 && k < ArraySize(m_tickets); k++)
     {
      if(!PositionSelectByTicket(m_tickets[k]))
         continue;
      PrintFormat("Closed outside the EA (stop loss or by hand): #%I64u, lot %.2f", m_tickets[k], PositionGetDouble(POSITION_VOLUME));
      m_trade.PositionClose(m_tickets[k]);
     }
  }
//+------------------------------------------------------------------+
//| Wrong: removing element i moves the next one down to index i,    |
//| and i++ jumps over it - a dead ticket stays in the array         |
//+------------------------------------------------------------------+
void CleanArrayForward(void)
  {
   Print("--- Wrong: for(int i = 0; i < ArraySize(tickets); i++) remove dead tickets");
   for(int i = 0; i < ArraySize(m_tickets); i++)
      if(!PositionSelectByTicket(m_tickets[i]))
        {
         PrintFormat("i = %d: #%I64u is gone - ArrayRemove", i, m_tickets[i]);
         ArrayRemove(m_tickets, i, 1);
        }
  }
//+------------------------------------------------------------------+
//| Right: from the end, removing element i moves only the elements  |
//| above i, and those have already been checked                     |
//+------------------------------------------------------------------+
void CleanArrayBackward(void)
  {
   Print("--- Right: for(int i = ArraySize(tickets) - 1; i >= 0; i--) remove dead tickets");
   for(int i = ArraySize(m_tickets) - 1; i >= 0; i--)
      if(!PositionSelectByTicket(m_tickets[i]))
        {
         PrintFormat("i = %d: #%I64u is gone - ArrayRemove", i, m_tickets[i]);
         ArrayRemove(m_tickets, i, 1);
        }
  }
//+------------------------------------------------------------------+
//| Closes every ticket left in the array                            |
//+------------------------------------------------------------------+
void CloseByArray(void)
  {
   PrintFormat("--- Close by the array: %d tickets", ArraySize(m_tickets));
   for(int i = ArraySize(m_tickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(m_tickets[i]))
        {
         PrintFormat("#%I64u: no such position - a dead ticket was left in the array", m_tickets[i]);
         continue;
        }
      PrintFormat("close #%I64u, lot %.2f", m_tickets[i], PositionGetDouble(POSITION_VOLUME));
      m_trade.PositionClose(m_tickets[i]);
     }
   ArrayFree(m_tickets);
  }
//+------------------------------------------------------------------+
//| PositionsTotal(), OrdersTotal() or ObjectsTotal()                |
//+------------------------------------------------------------------+
int Total(void)
  {
   if(InpTarget == TARGET_POSITIONS)
      return(PositionsTotal());
   if(InpTarget == TARGET_ORDERS)
      return(OrdersTotal());
   return(ObjectsTotal(0));
  }
//+------------------------------------------------------------------+
//| Name of the Total() function for the journal and the chart       |
//+------------------------------------------------------------------+
string TotalName(void)
  {
   if(InpTarget == TARGET_POSITIONS)
      return("PositionsTotal()");
   if(InpTarget == TARGET_ORDERS)
      return("OrdersTotal()");
   return("ObjectsTotal()");
  }
//+------------------------------------------------------------------+
//| Name of the items for the journal                                |
//+------------------------------------------------------------------+
string ItemsName(void)
  {
   if(InpTarget == TARGET_POSITIONS)
      return("positions");
   if(InpTarget == TARGET_ORDERS)
      return("orders");
   return("objects");
  }
//+------------------------------------------------------------------+
//| Name of the delete loop for the chart                            |
//+------------------------------------------------------------------+
string LoopName(void)
  {
   switch(InpLoop)
     {
      case LOOP_FROM_ZERO:
         return("Wrong loop: i = 0 ... " + TotalName() + " - 1");
      case LOOP_FROM_END:
         return("Right loop: i = " + TotalName() + " - 1 ... 0");
      case LOOP_WHILE_ANY:
         return("Risky loop: while(PositionsTotal() > 0) close index 0");
      case LOOP_WHILE_OURS:
         return("Risky loop: while(PositionsTotal() > 0) + symbol and magic filter");
      case LOOP_ARRAY_FORWARD:
         return("Tickets array: dead tickets removed from 0 up");
     }
   return("Tickets array: dead tickets removed from the end");
  }
//+------------------------------------------------------------------+
//| Is the item with this index ours; its ticket or name and lot     |
//+------------------------------------------------------------------+
bool Ours(const int index, string &id, double &lot)
  {
   if(InpTarget == TARGET_POSITIONS)
     {
      if(!m_position.SelectByIndex(index) || m_position.Symbol() != Symbol() || m_position.Magic() != InpMagic)
         return(false);
      id = "#" + IntegerToString(m_position.Ticket());
      lot = m_position.Volume();
      return(true);
     }
   if(InpTarget == TARGET_ORDERS)
     {
      if(!m_order.SelectByIndex(index) || m_order.Symbol() != Symbol() || m_order.Magic() != InpMagic)
         return(false);
      id = "#" + IntegerToString(m_order.Ticket());
      lot = m_order.VolumeInitial();
      return(true);
     }
   id = ObjectName(0, index);
   if(StringFind(id, PREFIX) != 0)
      return(false);
   lot = StringToDouble(ObjectGetString(0, id, OBJPROP_TEXT));
   return(true);
  }
//+------------------------------------------------------------------+
//| Deletes the item with this index if it is ours                   |
//+------------------------------------------------------------------+
void DeleteAt(const int index)
  {
   string id;
   double lot;
   if(!Ours(index, id, lot))
      return;
   PrintFormat("i = %d, %s = %d: delete %s, %.2f", index, TotalName(), Total(), id, lot);
   bool done;
   if(InpTarget == TARGET_POSITIONS)
      done = m_trade.PositionClose(m_position.Ticket());
   else
      if(InpTarget == TARGET_ORDERS)
         done = m_trade.OrderDelete(m_order.Ticket());
      else
         done = ObjectDelete(0, id);
   if(!done)
      PrintFormat("Delete %s failed, retcode %u, error %d", id, m_trade.ResultRetcode(), GetLastError());
   ChartRedraw();
  }
//+------------------------------------------------------------------+
//| Counts the items of this EA                                      |
//+------------------------------------------------------------------+
int CountItems(void)
  {
   int count = 0;
   string id;
   double lot;
   for(int i = Total() - 1; i >= 0; i--)
      if(Ours(i, id, lot))
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
//| Shows the list of items with their indexes on the chart and      |
//| writes "count stage bar" for the recording script                |
//+------------------------------------------------------------------+
void ShowItems(void)
  {
   string text = LoopName() + "\nServer time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) +
                 "\nState: " + m_state + "\n" + TotalName() + " = " + IntegerToString(Total());
   if(m_passes > 0)
      text += "\nwhile passes: " + IntegerToString(m_passes);
   string id;
   double lot;
   int count = 0;
   for(int i = 0; i < Total(); i++)
      if(Ours(i, id, lot))
        {
         text += StringFormat("\n  index %d: %s, %.2f", i, id, lot);
         count++;
        }
      else
         if(InpTarget == TARGET_POSITIONS && m_position.SelectByIndex(i))
            text += StringFormat("\n  index %d: #%I64u, %.2f  NOT OURS (magic %I64d)", i, m_position.Ticket(),
                                 m_position.Volume(), m_position.Magic());
   if(InpLoop == LOOP_ARRAY_FORWARD || InpLoop == LOOP_ARRAY_BACKWARD)
     {
      text += StringFormat("\nTickets array: %d", ArraySize(m_tickets));
      for(int i = 0; i < ArraySize(m_tickets); i++)
         text += StringFormat("\n  [%d] #%I64u%s", i, m_tickets[i], PositionSelectByTicket(m_tickets[i]) ? "" : "  - no such position");
     }
   Comment(text);
   m_shown = GetTickCount64();
   m_count = count;
   WriteState();
  }
//+------------------------------------------------------------------+
//| Visual tester only: "count stage bar" for the recording script   |
//+------------------------------------------------------------------+
void WriteState(void)
  {
   if(!MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   int handle = FileOpen(STATE_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, IntegerToString(m_count) + " " + IntegerToString(m_stage) + " " + IntegerToString((long)m_bar));
   FileClose(handle);
  }
//+------------------------------------------------------------------+
