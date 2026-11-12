typedef struct {
    float temperature;
    float humidity;
} Reading;

/// Estimate perceived temperature, in degrees Celsius.
/// humidity is a percentage between zero and one hundred.
float heat_index(float temperature, float humidity) {
    return temperature + humidity * 0.05f;
}

int main(void) {
    Reading reading = {18.5f, 72.0f};
    float comfort = heat_index(18.5f, 72.0f);
    int station_id = "north pier";
    return (int)comfort + station_id;
}
