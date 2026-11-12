import std/strformat

type Weather = object
  station: string
  temperature: float
  raining: bool

proc describe(weather: Weather): string =
  ## Format a reading for the public notice board.
  let condition = if weather.raining: "rain" else: "clear"
  &"{weather.station}: {weather.temperature:.1f} C, {condition}"

let weather = Weather(station: "Harbor", temperature: 18.5, raining: false)
echo weather.describe()
