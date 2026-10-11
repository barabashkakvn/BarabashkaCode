//+------------------------------------------------------------------+
//| VolumeTools.mqh                                                  |
//| Correct lot handling: round DOWN to SYMBOL_VOLUME_STEP, respect  |
//| MIN / MAX / LIMIT, and treat 0 as "do not trade".                |
//| Based on the checks from https://www.mql5.com/ru/articles/2555   |
//+------------------------------------------------------------------+
#property strict

//--- volume properties of a symbol (can be filled from the server or by hand)
struct VolumeSpec
  {
   double            min;     // SYMBOL_VOLUME_MIN
   double            max;     // SYMBOL_VOLUME_MAX
   double            step;    // SYMBOL_VOLUME_STEP
   double            limit;   // SYMBOL_VOLUME_LIMIT (0 = no limit)
  };

//+------------------------------------------------------------------+
//| Reads the volume properties of the symbol from the server        |
//+------------------------------------------------------------------+
bool VolumeSpecGet(const string symbol, VolumeSpec &spec)
  {
   if(!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, spec.min)   ||
      !SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX, spec.max)   ||
      !SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP, spec.step) ||
      !SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT, spec.limit))
     {
      PrintFormat("%s: no volume properties for %s, error %d", __FUNCTION__, symbol, GetLastError());
      return(false);
     }
// No guessing: without real properties we do not trade
   return(spec.min > 0.0 && spec.max > 0.0 && spec.step > 0.0);
  }

//+------------------------------------------------------------------+
//| Number of decimals in the step: 0.1 -> 1, 0.01 -> 2, 0.001 -> 3  |
//+------------------------------------------------------------------+
int VolumeDigits(const double step)
  {
   int digits = 0;
   while(digits < 8 && MathAbs(step * MathPow(10, digits) - MathRound(step * MathPow(10, digits))) > 1e-8)
      digits++;
   return(digits);
  }

//+------------------------------------------------------------------+
//| Requested lots -> valid lots, or 0.0 = do not send the order     |
//| 1. cut by MAX (and by the room left under LIMIT)                 |
//| 2. round DOWN to the step: risk never grows                      |
//| 3. below MIN -> 0.0, never "pull up" to the minimum              |
//+------------------------------------------------------------------+
double LotNormalize(const VolumeSpec &spec, double lots, const double used_volume = 0.0)
  {
   if(lots <= 0.0 || spec.step <= 0.0)
      return(0.0);
//--- 1. upper bounds
   lots = MathMin(lots, spec.max);
   if(spec.limit > 0.0)
      lots = MathMin(lots, spec.limit - used_volume);
//--- 2. down to the step; 1e-7 protects from 0.29/0.01 = 28.999999...
   lots = MathFloor(lots / spec.step + 1e-7) * spec.step;
//--- 3. too small: do not trade
   if(lots < spec.min - 1e-10)
      return(0.0);
   return(NormalizeDouble(lots, VolumeDigits(spec.step)));
  }

//+------------------------------------------------------------------+
//| Final check right before OrderSend (as in article 2555)          |
//+------------------------------------------------------------------+
bool CheckVolumeValue(const VolumeSpec &spec, const double volume, string &description)
  {
   if(volume < spec.min)
     {
      description = StringFormat("volume %.3f < SYMBOL_VOLUME_MIN %.3f", volume, spec.min);
      return(false);
     }
   if(volume > spec.max)
     {
      description = StringFormat("volume %.3f > SYMBOL_VOLUME_MAX %.3f", volume, spec.max);
      return(false);
     }
   long ratio = (long)MathRound(volume / spec.step);
   if(MathAbs(ratio * spec.step - volume) > 0.0000001)
     {
      description = StringFormat("volume %.3f is not a multiple of SYMBOL_VOLUME_STEP %.3f", volume, spec.step);
      return(false);
     }
   description = "OK";
   return(true);
  }

//+------------------------------------------------------------------+
//| Volume already used on the symbol: positions + pending orders    |
//| (for SYMBOL_VOLUME_LIMIT; works for netting and hedging)         |
//+------------------------------------------------------------------+
double VolumeUsed(const string symbol)
  {
   double used = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == symbol)
         used += PositionGetDouble(POSITION_VOLUME);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) > 0 && OrderGetString(ORDER_SYMBOL) == symbol)
         used += OrderGetDouble(ORDER_VOLUME_CURRENT);
   return(used);
  }
//+------------------------------------------------------------------+
