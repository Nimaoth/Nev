typedef struct {
    float temperature;
    float humidity;
} Reading;

typedef struct {
    const char *name;
    Reading current;
} Station;

float heat_index(float temperature, float humidity) {
    return temperature + humidity * 0.05f;
}

int needs_inspection(Station station) {
    return station.current.humidity > 95.0f;
}

float station_comfort(Station station) {
    return heat_index(station.current.temperature, station.current.humidity);
}

int main(void) {
    Station station = {"North pier", {18.5f, 72.0f}};
    return needs_inspection(station);
}
