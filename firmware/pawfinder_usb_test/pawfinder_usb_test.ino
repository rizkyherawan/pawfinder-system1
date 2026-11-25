/*
  PawFinder USB Test - TANPA modul GPS atau sensor apa pun.

  Gunanya: membuktikan rantai  Arduino -> kabel USB -> server -> aplikasi  bekerja,
  sebelum modul GPS dirakit. Sketsa ini mengirim titik yang berputar kecil di sekitar
  koordinat awal (sehingga geofence & riwayat juga bisa diuji), dan membunyikan LED saat PING.

  Cara pakai:
    1) Ubah DEVICE_ID di bawah, lalu Upload ke Arduino Uno.
    2) Tutup Serial Monitor (satu port tidak boleh dipakai dua program).
    3) Jalankan backend: npm run start:usb, pasangkan ID itu di aplikasi (tab Kabel USB).
*/

const char DEVICE_ID[] = "PF-TST-000001";   // WAJIB sama dengan yang dipasangkan di aplikasi
const char FW_VERSION[] = "test-1.0";
const long USB_BAUD = 9600;

const float START_LAT = -7.71556;           // titik awal (Sleman). Ganti dengan lokasi Anda.
const float START_LNG = 110.35547;
const float RADIUS_DEG = 0.0005;            // kira-kira 55 meter

unsigned long sendEveryMs = 2000;
unsigned long lastSend = 0;
float angle = 0;
int battery = 100;
char cmdBuf[24];
uint8_t cmdLen = 0;

void sendHello() {
  Serial.print(F("PF,HELLO,"));
  Serial.print(DEVICE_ID);
  Serial.print(',');
  Serial.println(FW_VERSION);
}

void handleCommand(char* line) {
  if (strcmp(line, "PING") == 0) {
    for (int i = 0; i < 4; i++) { digitalWrite(LED_BUILTIN, HIGH); delay(150); digitalWrite(LED_BUILTIN, LOW); delay(150); }
    Serial.println(F("PF,ACK,PING"));
  } else if (strcmp(line, "WHO") == 0) {
    sendHello();
  } else if (strncmp(line, "INTERVAL ", 9) == 0) {
    long sec = atol(line + 9);
    if (sec >= 1 && sec <= 3600) sendEveryMs = (unsigned long)sec * 1000UL;
    Serial.println(F("PF,ACK,INTERVAL"));
  }
}

void readCommands() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (cmdLen > 0) { cmdBuf[cmdLen] = '\0'; handleCommand(cmdBuf); cmdLen = 0; }
    } else if (cmdLen < sizeof(cmdBuf) - 1) {
      cmdBuf[cmdLen++] = c;
    } else {
      cmdLen = 0;
    }
  }
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(USB_BAUD);
  delay(300);
  sendHello();
}

void loop() {
  readCommands();
  unsigned long now = millis();
  if (now - lastSend >= sendEveryMs) {
    lastSend = now;
    angle += 0.25;
    if (angle > 6.28318) angle -= 6.28318;
    if (battery > 20 && (now / 60000UL) % 2 == 0 && now % 7 == 0) battery--;  // turun pelan-pelan
    Serial.print(F("PF,"));
    Serial.print(DEVICE_ID);
    Serial.print(',');
    Serial.print(START_LAT + RADIUS_DEG * sin(angle), 6);
    Serial.print(',');
    Serial.print(START_LNG + RADIUS_DEG * cos(angle), 6);
    Serial.print(',');
    Serial.print(battery);
    Serial.println(F(",1,,,7"));
  }
}
