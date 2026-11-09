# Calculator

Maths, units, currency, dates, time zones and number bases in the Floating Bar
(DESIGN.md §3.17). It's one search provider: `=` scopes to it, and in root search it
answers when the query is clearly a calculation (an operator and a digit, or a
conversion phrase). ↵ copies the answer (without thousands separators).

| File | What |
|---|---|
| `Expression.swift` | `MathExpression`: tokenizer + recursive-descent parser. No `NSExpression`. Percent rules (`200 + 10%` = 220, `15% of 80`), implicit multiplication, functions, constants, hex/bin/oct literals, `1,000`. |
| `Units.swift` | `UnitTable` (KKit's own table: length, mass, temperature, volume, area, data, time, speed, angle, energy, power, pressure), `UnitConversion`, `ConversionSplitter` ("A in/to/as B"). |
| `Currency.swift` | `ExchangeRates`, `ExchangeRateSource` (`OpenExchangeRateSource`: open.er-api.com, no key), `ExchangeRateStore` (saved as `rates.json`, refreshed when a day old and a currency query needs it), `CurrencyQuery`. |
| `DateMath.swift` | "today + 45 days", "3 weeks from now", "days until dec 25". |
| `TimeZoneMath.swift` | "time in tokyo", "5pm PST in IST", "9am london to new york". |
| `CalculatorEngine.swift` | Tries each kind in turn and formats the answer (`NumberStyle`). |
| `CalculatorProvider.swift` | The Floating Bar provider; shows "Getting exchange rates…" first when none are saved. |

- Commands: `calculator.open` (opens the bar with `=`), `calculator.refreshRates`.
- Settings: answer as you type, decimal places, thousands separators, your currency,
  daily rate updates.
- Network: only open.er-api.com, only when a currency conversion needs rates.
- Not yet: ⌘↵ to paste the answer into the frontmost app (needs the paste service, M3).
