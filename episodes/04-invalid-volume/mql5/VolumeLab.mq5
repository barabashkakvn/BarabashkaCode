//+------------------------------------------------------------------+
//|                                                    VolumeLab.mq5 |
//|                             Copyright © 2026, Volodymyr Karputov |
//|                      https://www.mql5.com/en/users/barabashkakvn |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026, Volodymyr Karputov"
#property link      "https://www.mql5.com/en/users/barabashkakvn"
#property version "1.004"
#property description "Runs the same requested lots through a WRONG and a RIGHT calculation."
#property description "Nothing is traded, everything goes to the journal."
#property script_show_inputs
//+------------------------------------------------------------------+
//| Script: the same requested lots through a WRONG and a RIGHT      |
//| calculation. Nothing is traded, everything goes to the journal.  |
//|                                                                  |
//| Six typical symbol specifications are set by hand, so the result |
//| is the same everywhere; the last row uses the real properties of |
//| the chart symbol and the volume already used on it.              |
//| Checks: https://www.mql5.com/ru/articles/2555                    |
//+------------------------------------------------------------------+
#include "VolumeTools.mqh"

input double InpLots = 0.05;   // Lots to check on the chart symbol

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- typical symbol specifications (set by hand, so the result is the same everywhere)
   VolumeSpec fx     = {0.01,  100.0, 0.01,  0.0};   // EURUSD, XAUUSD at most brokers
   VolumeSpec coarse = {0.10,  50.0,  0.10,  0.0};   // indices / some gold contracts
   VolumeSpec crypto = {0.001, 10.0,  0.001, 0.0};   // BTCUSD, ETHUSD
   VolumeSpec capped = {0.01,  100.0, 0.01,  1.0};   // SYMBOL_VOLUME_LIMIT = 1 lot
   Print("=== VolumeLab: same request, wrong vs right ===");
   Row("1. step 0.01",          fx,     0.05);
   Row("2. step 0.01",          fx,     0.29);
   Row("3. step 0.1",           coarse, 0.25);
   Row("4. crypto step 0.001",  crypto, 0.004);
   Row("5. below minimum",      fx,     0.003);
   Row("6. limit 1.0, used 1.0", capped, 0.30, 1.0);
//--- the chart symbol with real server properties
   VolumeSpec real;
   if(!VolumeSpecGet(_Symbol, real))
      return;
   PrintFormat("=== %s: min %g, max %g, step %g, limit %g, used %g ===",
               _Symbol, real.min, real.max, real.step, real.limit, VolumeUsed(_Symbol));
   Row(_Symbol, real, InpLots, VolumeUsed(_Symbol));
  }

//+------------------------------------------------------------------+
//| HOW NOT TO DO IT: typical home-made lot "protection"             |
//+------------------------------------------------------------------+
double LotsWrong(const VolumeSpec &spec, double lots, const double used_volume = 0.0)
  {
   double step = spec.step;
   if(step <= 0.0)
      step = 0.1;                                     // (1) guessing the step
   lots = MathRound(lots / step) * step;              // (2) nearest step: can go UP
   if(step == 0.01)
      lots = MathRound(lots / 0.1) * 0.1;             // (3) "gold trades in 0.1"
   if(spec.limit > 0.0 && used_volume + lots > spec.limit)
      lots = 0.0;                                     // "no room left"...
   lots = MathMax(lots, spec.min);                    // (4) ...and 0 becomes MIN again
   return(NormalizeDouble(lots, 2));                  // (5) step 0.001 -> 0.00
  }

//+------------------------------------------------------------------+
//| One row of the report                                            |
//+------------------------------------------------------------------+
void Row(const string title, const VolumeSpec &spec, const double lots, const double used = 0.0)
  {
   int    d     = VolumeDigits(spec.step);
   double wrong = LotsWrong(spec, lots, used);
   double right = LotNormalize(spec, lots, used);
   string why;
   string verdict = CheckVolumeValue(spec, wrong, why) ? "accepted" : "INVALID VOLUME (" + why + ")";
   if(why == "OK" && wrong > lots + 1e-10)
      verdict = StringFormat("accepted, but risk x%.2f", wrong / lots);
   if(why == "OK" && spec.limit > 0.0 && used + wrong > spec.limit)
      verdict = "accepted by us, LIMIT exceeded on server";
   PrintFormat("%-26s | step %-5s min %-5s | ask %-6s | wrong %-6s %-40s | right %s",
               title,
               DoubleToString(spec.step, d), DoubleToString(spec.min, d),
               DoubleToString(lots, d + 1),
               DoubleToString(wrong, 3), verdict,
               right > 0.0 ? DoubleToString(right, d) : "0 = do not trade");
  }
//+------------------------------------------------------------------+
