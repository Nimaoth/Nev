type Sensor = object
  name: string
  reading: float

proc display(sensor: Sensor): string =
  sensor.name & ": " & $sensor.reading

let sensor = Sensor(name: "North pier", reading: 18.5)
echo display(sensor)
