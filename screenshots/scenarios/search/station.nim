type Sensor = object
  name: string
  reading: float

proc calibrate(sensor: var Sensor, offset: float) =
  sensor.reading += offset

proc report(sensor: Sensor): string =
  sensor.name & ": " & $sensor.reading

var sensor = Sensor(name: "North pier", reading: 18.5)
sensor.calibrate(0.2)
echo sensor.report()
