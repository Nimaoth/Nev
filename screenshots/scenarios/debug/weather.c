typedef struct {
    int temperature;
    int humidity;
} Reading;

int heat_index(int temperature, int humidity) {
    int adjustment = humidity / 20;
    int result = temperature + adjustment;
    return result;
}

int main(void) {
    Reading reading = {18, 72};
    int comfort = heat_index(reading.temperature, reading.humidity);
    reading.temperature += 2;
    return comfort;
}
