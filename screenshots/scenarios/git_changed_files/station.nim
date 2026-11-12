proc calibrate(reading: float, offset: float): float =
  reading + offset

let temperature = calibrate(18.5, 0.2)
echo "Harbor temperature: ", temperature
