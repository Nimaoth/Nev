type Station = object
  name: string
  temperature: float

proc publish(station: Station) =
  echo station.name, ": ", station.temperature, " C"

publish(Station(name: "North pier", temperature: 18.5))
