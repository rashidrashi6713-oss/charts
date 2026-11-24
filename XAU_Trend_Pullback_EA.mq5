//+------------------------------------------------------------------+
//| XAU_Trend_Pullback_EA.mq5                                        |
//| Simple trend + RSI pullback EA. DEMO / TESTING ONLY.             |
//| No profit guarantee. Backtest in Strategy Tester first.          |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#include <Trade/Trade.mqh>

CTrade trade;

input double RiskPercent  = 1.0;    // Risk per trade (% of balance)
input int    FastEMA      = 50;     // Fast EMA
input int    SlowEMA      = 200;    // Slow EMA (trend filter)
input int    RSIPeriod    = 14;
input double RSIBuyLevel  = 40.0;   // Buy when RSI crosses up through this (uptrend)
input double RSISellLevel = 60.0;   // Sell when RSI crosses down through this (downtrend)
input int    ATRPeriod    = 14;
input double ATR_SL_Mult  = 1.5;    // Stop loss = ATR * this
input double RewardRisk   = 2.0;    // Take profit = SL distance * this
input double MaxSpreadPts = 60;     // Skip trade if spread (points) is higher
input ulong  MagicNumber  = 240101;
input bool   DemoOnly     = true;   // Refuse to run on live accounts

int hFast, hSlow, hRSI, hATR;
datetime lastBar = 0;

int OnInit()
{
   if(DemoOnly && AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("DemoOnly is ON: this is not a demo account. Stopping.");
      return INIT_FAILED;
   }
   hFast = iMA(_Symbol, PERIOD_CURRENT, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, PERIOD_CURRENT, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
}

bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

double CalcLots(double slDistance)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickValue <= 0 || tickSize <= 0 || slDistance <= 0) return 0;

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}

void OnTick()
{
   // Act once per new bar, on closed-bar data
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == lastBar) return;
   lastBar = barTime;

   if(HasPosition()) return;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts) return;

   double fast[], slow[], rsi[], atr[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);  ArraySetAsSeries(atr, true);
   if(CopyBuffer(hFast, 0, 0, 3, fast) < 3) return;
   if(CopyBuffer(hSlow, 0, 0, 3, slow) < 3) return;
   if(CopyBuffer(hRSI,  0, 0, 3, rsi)  < 3) return;
   if(CopyBuffer(hATR,  0, 0, 3, atr)  < 3) return;

   double slDist = atr[1] * ATR_SL_Mult;
   double tpDist = slDist * RewardRisk;
   double lots   = CalcLots(slDist);
   if(lots <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   bool upTrend   = fast[1] > slow[1];
   bool downTrend = fast[1] < slow[1];
   bool buySig    = upTrend   && rsi[2] < RSIBuyLevel  && rsi[1] >= RSIBuyLevel;
   bool sellSig   = downTrend && rsi[2] > RSISellLevel && rsi[1] <= RSISellLevel;

   if(buySig)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      trade.Buy(lots, _Symbol, ask,
                NormalizeDouble(ask - slDist, digits),
                NormalizeDouble(ask + tpDist, digits), "XAU pullback buy");
   }
   else if(sellSig)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      trade.Sell(lots, _Symbol, bid,
                 NormalizeDouble(bid + slDist, digits),
                 NormalizeDouble(bid - tpDist, digits), "XAU pullback sell");
   }
}
