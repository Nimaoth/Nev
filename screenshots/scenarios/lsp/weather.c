typedef struct {
    float temperature;
    float humidity;
} Reading;

/// Estimate perceived temperature from the current weather.
float heat_index(float temperature, float humidity) {
    return temperature + humidity * 0.05f;
}

int main(void) {
    Reading reading = {18.5f, 72.0f};

    return (int)heat_index(reading.temperature, reading.humidity);
}
