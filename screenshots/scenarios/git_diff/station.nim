proc calibrate(reading: float, offset: float): float =
  ## Apply the correction measured at the reference station.
  reading + offset

proc publish(station: string, temperature: float) =
  echo station, ": ", temperature, " C"

let temperature = calibrate(18.5, 0.2)
publish("North pier", temperature)
