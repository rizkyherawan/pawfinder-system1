/*
  PawFinder Collar - firmware Arduino Uno (kabel USB -> server PawFinder)

  Perangkat keras:
    - Arduino Uno
    - Modul GPS NEO-6M (atau kompatibel NMEA 9600 baud)
        GPS TX  -> Arduino pin 4   (GPS_RX_PIN)
        GPS RX  -> Arduino pin 3   (GPS_TX_PIN)   (boleh tidak disambung)
        GPS VCC -> 5V, GND -> GND
    - Buzzer aktif ke pin 8 (+) dan GND (-)         (opsional)
    - Baterai: pembagi tegangan ke A0                (opsional, lihat BATTERY_SENSE)
    - Sensor suhu LM35 ke A1                         (opsional, lihat HAS_LM35)

  Library (Arduino IDE > Tools > Manage Libraries):
    - TinyGPSPlus oleh Mikal Hart
    (SoftwareSerial sudah bawaan Arduino)

  Protokol (satu baris per paket lewat USB serial, 9600 baud):
    Alat -> server :  PF,<ID>,<lat>,<lng>,<baterai%>,<fix 0/1>,<detak>,<suhu>,<satelit>
                      PF,HELLO,<ID>,<versi>        (saat menyala / diminta WHO)
                      PF,ACK,<PERINTAH>            (setelah menjalankan perintah)
    Server -> alat :  PING | INTERVAL <detik> | WHO

  Kolom yang tidak tersedia dikosongkan (mis. koordinat saat GPS belum fix).
  Dokumentasi lengkap: README.md bagian "Koneksi alat".
*/

#include <SoftwareSerial.h>
#include <TinyGPSPlus.h>

// ===================== KONFIGURASI (ubah di sini) =====================
const char DEVICE_ID[]  = "PF-ABC-123456";  // WAJIB sama dengan nomor seri yang dipasangkan di aplikasi
const char FW_VERSION[] = "1.0.0";
const long USB_BAUD     = 9600;             // harus sama dengan USB_BAUD di backend/.env

const uint8_t GPS_RX_PIN = 4;
const uint8_t GPS_TX_PIN = 3;
const long    GPS_BAUD   = 9600;

const uint8_t BUZZER_PIN  = 8;
const uint8_t LED_PIN     = LED_BUILTIN;

#define BATTERY_SENSE 0          // 1 bila A0 membaca baterai lewat pembagi tegangan
const float ADC_REF_VOLT   = 5.0;
const float DIVIDER_RATIO  = 2.0;   // mis. dua resistor sama besar => tegangan baterai = A0 x 2
const float BATT_EMPTY_V   = 3.3;   // 0%  (LiPo 1S)
const float BATT_FULL_V    = 4.2;   // 100%

#define HAS_LM35 0               // 1 bila sensor suhu LM35 dipasang di A1 (10 mV per derajat C)

// 0 = ikuti interval yang diatur di aplikasi. Isi detik (mis. 2) agar data lebih cepat saat demo di lab.
#define FORCE_INTERVAL_SEC 0
// ======================================================================

SoftwareSerial gpsSerial(GPS_RX_PIN, GPS_TX_PIN);
TinyGPSPlus gps;

unsigned long sendEveryMs = 5000;   // diganti oleh perintah INTERVAL dari server
unsigned long lastSend = 0;
unsigned long lastGpsChars = 0;

char cmdBuf[24];
uint8_t cmdLen = 0;

// ---------------------------------------------------------------- util
void beep(uint16_t ms) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(ms);
  digitalWrite(BUZZER_PIN, LOW);
}

void sendHello() {
  Serial.print(F("PF,HELLO,"));
  Serial.print(DEVICE_ID);
  Serial.print(',');
  Serial.println(FW_VERSION);
}

void sendAck(const char* cmd) {
  Serial.print(F("PF,ACK,"));
  Serial.println(cmd);
}

int readBatteryPercent() {
#if BATTERY_SENSE
  float v = analogRead(A0) * (ADC_REF_VOLT / 1023.0) * DIVIDER_RATIO;
  float pct = (v - BATT_EMPTY_V) / (BATT_FULL_V - BATT_EMPTY_V) * 100.0;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return (int)(pct + 0.5);
#else
  return -1;  // tidak tersedia: kolom dikosongkan
#endif
}

// ---------------------------------------------------------------- kirim data
void sendTelemetry() {
  bool fix = gps.location.isValid() && gps.location.age() < 5000;

  Serial.print(F("PF,"));
  Serial.print(DEVICE_ID);
  Serial.print(',');
  if (fix) Serial.print(gps.location.lat(), 6);
  Serial.print(',');
  if (fix) Serial.print(gps.location.lng(), 6);
  Serial.print(',');
  int bat = readBatteryPercent();
  if (bat >= 0) Serial.print(bat);
  Serial.print(',');
  Serial.print(fix ? 1 : 0);
  Serial.print(',');
  // kolom detak jantung dikosongkan (belum ada sensor)
  Serial.print(',');
#if HAS_LM35
  Serial.print(analogRead(A1) * (ADC_REF_VOLT / 1023.0) * 100.0, 1);
#endif
  Serial.print(',');
  if (gps.satellites.isValid()) Serial.print(gps.satellites.value());
  Serial.println();

  digitalWrite(LED_PIN, fix ? HIGH : LOW);  // LED menyala = GPS sudah fix
}

// ---------------------------------------------------------------- perintah dari server
void handleCommand(char* line) {
  if (strcmp(line, "PING") == 0) {
    beep(200); delay(120); beep(200); delay(120); beep(500);
    sendAck("PING");
  } else if (strcmp(line, "WHO") == 0) {
    sendHello();
  } else if (strncmp(line, "INTERVAL ", 9) == 0) {
    long sec = atol(line + 9);
    if (sec >= 1 && sec <= 3600 && FORCE_INTERVAL_SEC == 0) sendEveryMs = (unsigned long)sec * 1000UL;
    sendAck("INTERVAL");
  }
  // perintah lain diabaikan
}

void readCommands() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (cmdLen > 0) {
        cmdBuf[cmdLen] = '\0';
        handleCommand(cmdBuf);
        cmdLen = 0;
      }
    } else if (cmdLen < sizeof(cmdBuf) - 1) {
      cmdBuf[cmdLen++] = c;
    } else {
      cmdLen = 0;  // baris terlalu panjang: buang
    }
  }
}

// ---------------------------------------------------------------- setup & loop
void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(LED_PIN, OUTPUT);
  Serial.begin(USB_BAUD);
  gpsSerial.begin(GPS_BAUD);
  if (FORCE_INTERVAL_SEC > 0) sendEveryMs = (unsigned long)FORCE_INTERVAL_SEC * 1000UL;
  delay(300);
  Serial.println(F("# PawFinder collar siap"));  // baris berawalan '#' = komentar, diabaikan server
  sendHello();
  beep(80);
}

void loop() {
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
    lastGpsChars++;
  }
  readCommands();

  unsigned long now = millis();
  if (now - lastSend >= sendEveryMs) {
    lastSend = now;
    sendTelemetry();
    if (lastGpsChars < 10 && now > 5000) {
      Serial.println(F("# peringatan: tidak ada data dari modul GPS (cek kabel TX/RX)"));
    }
    lastGpsChars = 0;
  }
}
