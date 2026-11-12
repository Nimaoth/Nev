type Reading = object
  sensor: string
  temperature: float

proc describe(reading: Reading): string =
  reading.sensor & ": " & $reading.temperature & " C"

echo describe(Reading(sensor: "North pier", temperature: 18.5))
