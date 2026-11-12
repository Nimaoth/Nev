when defined(windows):
  proc forecast(station: string): string =
    let readings = @[18, 19, 17, 20]

    proc average(): float =
      var total = 0
      for reading in readings:
        total += reading
      total.float / readings.len.float

    proc classify(value: float): string =
      if value < 10:
        "cold"
      elif value < 20:
        "mild"
      else:
        "warm"

    station & ": " & classify(average())

  echo forecast("Harbor")
