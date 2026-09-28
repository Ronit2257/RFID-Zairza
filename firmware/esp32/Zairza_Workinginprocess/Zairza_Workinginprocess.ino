#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <SPI.h>
#include <MFRC522.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "RTClib.h"
#include "FS.h"
#include "LittleFS.h"
#include "SD.h"
#include "time.h"

// --- Audio Playback Libraries ---
#include "AudioFileSourceSD.h"
#include "AudioOutputI2S.h"
#include "AudioGeneratorWAV.h"

// ============================================================
// CONFIGURATION: WI-FI, GOOGLE SCRIPT & NTP
// ============================================================
const char* ssid            = "Galaxy F16 5G (Ronit)";
const char* password        = "12345678";
const char* googleScriptUrl = "https://script.google.com/macros/s/AKfycbwMbokNhb1rbfScg0QPO1rkfw0Z1PDnkgBRjM4Z4thqiUID_KQnX-SbqMC4jeNa8p0c/exec";

// NTP Server Configuration (India Standard Time: UTC + 5:30)
const char* ntpServer       = "pool.ntp.org";
const long  gmtOffset_sec   = 19800; // 5 hours 30 mins = 19800 sec
const int   daylightOffset_sec = 0;

// ============================================================
// HARDWARE PIN ASSIGNMENTS: DUAL DEDICATED SPI BUSES
// ============================================================
// 1. VSPI Bus dedicated to RC522 RFID Reader
#define RFID_CS_PIN   5
#define RFID_RST_PIN  4
#define VSPI_SCK      18
#define VSPI_MISO     19
#define VSPI_MOSI     23

// 2. HSPI Bus dedicated to HW-125 MicroSD Module
#define SD_CS_PIN     27
#define HSPI_SCK      14
#define HSPI_MISO     33
#define HSPI_MOSI     13

// 3. MAX98357A I2S Amplifier Pins
#define I2S_BCLK_PIN  26
#define I2S_LRC_PIN   25
#define I2S_DOUT_PIN  32

// ============================================================
// PERIPHERALS, BUSES & AUDIO OBJECTS
// ============================================================
SPIClass spiHSPI(HSPI);
MFRC522 rfid(RFID_CS_PIN, RFID_RST_PIN);
LiquidCrystal_I2C lcd(0x27, 16, 2);
RTC_DS3231 rtc;

AudioGeneratorWAV *wav  = nullptr;
AudioFileSourceSD *file = nullptr;
AudioOutputI2S *out     = nullptr;

// ============================================================
// DATA STRUCTURES & CACHING PIPELINE
// ============================================================
struct Student {
  String name;
  String regNo;
  String branch;
  String uid;
  unsigned long lastTapTime;
  int tapCount;
};

const int MAX_STUDENTS = 200;
Student database[MAX_STUDENTS];
int studentCount = 0;

// Memory Cache Structure
struct AttendanceLog {
  String id;       // Unique per event -> makes uploads idempotent, prevents duplicate rows
  String dateStr;
  String timeStr;
  String regNo;
  String name;
  String branch;
  String action;
  String uid;
};

AttendanceLog logCache; // Active in-memory buffer before dispatch

const char* OFFLINE_LOG_FILE = "/offline_logs.csv";
unsigned long screenResetTime = 0;
bool screenNeedsReset = false;
bool sdAvailable = false;
unsigned long lastSyncCheck = 0;

// ============================================================
// AUDIO PLAYBACK ROUTINE
// ============================================================
void playWAV(const char *filename) {
  if (!sdAvailable) return;

  if (!SD.exists(filename)) {
    Serial.printf("[AUDIO] File not found: %s\n", filename);
    return;
  }

  file = new AudioFileSourceSD(filename);
  wav  = new AudioGeneratorWAV();

  if (wav->begin(file, out)) {
    while (wav->isRunning()) {
      if (!wav->loop()) {
        wav->stop();
      }
    }
  }

  delete file;
  delete wav;
  file = nullptr;
  wav  = nullptr;
}

// ============================================================
// HELPERS & DATABASE
// ============================================================
String getFirstName(String fullName) {
  fullName.trim();
  int spaceIndex = fullName.indexOf(' ');
  return (spaceIndex != -1) ? fullName.substring(0, spaceIndex) : fullName;
}

void showIdleScreen() {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Zairza Club");
  lcd.setCursor(0, 1);
  if (WiFi.status() == WL_CONNECTED) {
    lcd.print("Scan Card...    ");
  } else {
    lcd.print("Scan (Offline)  ");
  }
  screenNeedsReset = false;
}

void loadDatabaseFromFS() {
  if (!LittleFS.begin(true)) {
    Serial.println("[ERROR] LittleFS Mount Failed!");
    return;
  }

  File csvFile = LittleFS.open("/students.csv", "r");
  if (!csvFile) {
    Serial.println("[ERROR] /students.csv not found on LittleFS!");
    return;
  }

  studentCount = 0;
  while (csvFile.available() && studentCount < MAX_STUDENTS) {
    String line = csvFile.readStringUntil('\n');
    line.trim();

    if (line.length() == 0 || line.startsWith("S.No") || line.startsWith("Name")) continue;

    int commaCount = 0;
    for (size_t i = 0; i < line.length(); i++) {
      if (line.charAt(i) == ',') commaCount++;
    }

    String nameVal = "", regVal = "", branchVal = "", uidVal = "";

    if (commaCount >= 4) {
      int c1 = line.indexOf(',');
      int c2 = line.indexOf(',', c1 + 1);
      int c3 = line.indexOf(',', c2 + 1);
      int c4 = line.indexOf(',', c3 + 1);

      nameVal   = line.substring(c1 + 1, c2);
      regVal    = line.substring(c2 + 1, c3);
      branchVal = line.substring(c3 + 1, c4);
      uidVal    = line.substring(c4 + 1);
    } else if (commaCount == 3) {
      int c1 = line.indexOf(',');
      int c2 = line.indexOf(',', c1 + 1);
      int c3 = line.indexOf(',', c2 + 1);

      nameVal   = line.substring(0, c1);
      regVal    = line.substring(c1 + 1, c2);
      branchVal = line.substring(c2 + 1, c3);
      uidVal    = line.substring(c3 + 1);
    }

    nameVal.trim();
    regVal.trim();
    branchVal.trim();
    uidVal.toUpperCase();
    uidVal.trim();

    if (uidVal.length() > 0) {
      database[studentCount].name        = nameVal;
      database[studentCount].regNo       = regVal;
      database[studentCount].branch      = branchVal;
      database[studentCount].uid         = uidVal;
      database[studentCount].lastTapTime = 0;
      database[studentCount].tapCount    = 0;
      studentCount++;
    }
  }
  csvFile.close();
  Serial.printf("[DB] Database Loaded: %d Students\n", studentCount);
}

int findStudentByUID(const String& scannedUID) {
  for (int i = 0; i < studentCount; i++) {
    if (database[i].uid.equalsIgnoreCase(scannedUID)) return i;
  }
  return -1;
}

// ============================================================
// RTC AUTO-CALIBRATION VIA NTP
// ============================================================
void syncRTCWithNTP() {
  if (WiFi.status() != WL_CONNECTED) return;

  Serial.println("[NTP] Fetching precise network time...");
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);

  struct tm timeinfo;
  int retry = 0;
  while (!getLocalTime(&timeinfo) && retry < 10) {
    delay(300);
    retry++;
  }

  if (retry < 10) {
    // Update the physical DS3231 hardware registers
    rtc.adjust(DateTime(timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
                        timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec));
    Serial.println("[RTC SUCCESS] DS3231 recalibrated to exact network time!");
  } else {
    Serial.println("[NTP ERROR] Failed to obtain time from server.");
  }
}

// ============================================================
// CACHE & STORAGE PIPELINE (ONLINE & OFFLINE)
// ============================================================
// Helper function to encode spaces and symbols for URL-encoded payloads
String urlEncode(String str) {
  String encoded = "";
  char c;
  char code0;
  char code1;
  for (int i = 0; i < str.length(); i++) {
    c = str.charAt(i);
    if (c == ' ') {
      encoded += '+'; // Spaces turn into '+' in form-urlencoded
    } else if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      encoded += c;
    } else {
      code1 = (c & 0xf) + '0';
      if ((c & 0xf) > 9) {
        code1 = (c & 0xf) - 10 + 'A';
      }
      c = (c >> 4) & 0xf;
      code0 = c + '0';
      if (c > 9) {
        code0 = c - 10 + 'A';
      }
      encoded += '%';
      encoded += code0;
      encoded += code1;
    }
  }
  return encoded;
}

bool postToGoogleSheets(const AttendanceLog& log) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[HTTP] WiFi is not connected.");
    return false;
  }

  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(20); // widened from 12s: Apps Script can be slow on cold-start / lock contention

  HTTPClient http;
  http.setTimeout(20000); // widened from 12000ms for the same reason

  if (!http.begin(client, googleScriptUrl)) {
    Serial.println("[HTTP ERROR] Failed to connect to URL endpoint.");
    return false;
  }

  // Do NOT auto-follow the redirect. Apps Script's doPost() finishes running
  // (and writes the row) BEFORE it responds with a 302 to a
  // script.googleusercontent.com content URL. ESP32's HTTPClient produces a
  // malformed follow-up request when it tries to auto-follow that chain,
  // which is what generic www.google.com "Error 400" robot page you saw
  // actually is. Since the sheet write already happened by the time the 302
  // arrives, we don't need to follow it at all -- we just treat 302 as success.
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  http.addHeader("Content-Type", "application/x-www-form-urlencoded");

  auto clean = [](String s) -> String {
    s.replace("\r", "");
    s.replace("\n", "");
    s.trim();
    return s;
  };

  // URL-encode all fields so spaces and colons don't crash HTTP parsing
  // "id" is included so the Apps Script backend can dedupe on retry (idempotent upload)
  String postData = "id="      + urlEncode(clean(log.id)) +
                    "&date="   + urlEncode(clean(log.dateStr)) +
                    "&time="   + urlEncode(clean(log.timeStr)) +
                    "&regNo="  + urlEncode(clean(log.regNo)) +
                    "&name="   + urlEncode(clean(log.name)) +
                    "&branch=" + urlEncode(clean(log.branch)) +
                    "&action=" + urlEncode(clean(log.action)) +
                    "&uid="    + urlEncode(clean(log.uid));

  Serial.println("[HTTP] Sending POST data...");
  int httpCode = http.POST(postData);
  String response = "";

  if (httpCode > 0) {
    Serial.printf("[HTTP] Result Code: %d\n", httpCode);
    if (httpCode == 302 || httpCode == 301) {
      // Expected: doPost() already ran and wrote the row. This is just
      // Google handing us a pointer to the rendered output, which we don't
      // need to fetch. Fetching it is what triggered the malformed-request
      // 400 from www.google.com, so skip http.getString() entirely here.
      Serial.println("[HTTP] Got redirect (expected) -- write already happened, treating as success.");
    } else {
      response = http.getString();
      Serial.println("[HTTP] Response body:");
      Serial.println(response);
    }
  } else {
    Serial.printf("[HTTP ERROR] Request failed: %s\n", http.errorToString(httpCode).c_str());
  }

  http.end();

  // Treat a server-reported duplicate as success too, so a false-negative retry
  // (e.g. our timeout fired but the row already landed) doesn't loop forever.
  bool isSuccess = httpCode == 302 || httpCode == 301 ||
                    (httpCode >= 200 && httpCode < 300) ||
                    response.indexOf("SUCCESS") != -1 ||
                    response.indexOf("DUPLICATE_SKIPPED") != -1;
  return isSuccess;
}

void appendToSDOffline(const AttendanceLog& log) {
  if (!sdAvailable) {
    Serial.println("[STORAGE ERROR] SD card offline! Data cannot be saved.");
    return;
  }

  File f = SD.open(OFFLINE_LOG_FILE, FILE_APPEND);
  if (!f) {
    Serial.println("[STORAGE ERROR] Failed to open /offline_logs.csv for append!");
    return;
  }

  // Format: ID,Date,Time,RegNo,Name,Branch,Action,UID
  f.printf("%s,%s,%s,%s,%s,%s,%s,%s\n",
           log.id.c_str(), log.dateStr.c_str(), log.timeStr.c_str(), log.regNo.c_str(),
           log.name.c_str(), log.branch.c_str(), log.action.c_str(), log.uid.c_str());
  f.close();
  Serial.println("[STORAGE] Record saved to SD card cache (/offline_logs.csv).");
}

void processAttendanceRecord(const AttendanceLog& log) {
  // Step 1: Push directly if Wi-Fi is connected
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("[PIPELINE] Cache -> Google Sheets (Live)...");
    if (postToGoogleSheets(log)) {
      Serial.println("[PIPELINE SUCCESS] Uploaded directly.");
      return;
    }
    Serial.println("[PIPELINE WARN] POST failed. Fallback to SD card cache.");
  } else {
    Serial.println("[PIPELINE] Wi-Fi offline. Routing Cache -> SD Card.");
  }

  // Step 2: Fallback to SD card storage
  appendToSDOffline(log);
}

// Background auto-sync when Wi-Fi becomes available
void syncOfflineLogsToCloud() {
  if (WiFi.status() != WL_CONNECTED || !sdAvailable) return;
  if (!SD.exists(OFFLINE_LOG_FILE)) return;

  File readFile = SD.open(OFFLINE_LOG_FILE, FILE_READ);
  if (!readFile || readFile.size() == 0) {
    if (readFile) readFile.close();
    SD.remove(OFFLINE_LOG_FILE);
    return;
  }

  Serial.println("\n[AUTO-SYNC] Unsynced logs detected on SD card. Initiating sync...");
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Syncing Cloud...");

  // Read all lines into memory first to avoid file lock conflicts
  std::vector<String> lines;
  while (readFile.available()) {
    String l = readFile.readStringUntil('\n');
    l.trim();
    if (l.length() > 0) {
      lines.push_back(l);
    }
  }
  readFile.close();

  // If file had only empty spaces, remove it
  if (lines.empty()) {
    SD.remove(OFFLINE_LOG_FILE);
    showIdleScreen();
    return;
  }

  std::vector<String> failedLines;

  for (size_t i = 0; i < lines.size(); i++) {
    String line = lines[i];

    // 8 fields now: ID,Date,Time,RegNo,Name,Branch,Action,UID -> 7 commas
    int c[7];
    c[0] = line.indexOf(',');
    for (int j = 1; j < 7; j++) {
      c[j] = line.indexOf(',', c[j - 1] + 1);
    }

    if (c[6] != -1) {
      AttendanceLog item;
      item.id      = line.substring(0, c[0]);
      item.dateStr = line.substring(c[0] + 1, c[1]);
      item.timeStr = line.substring(c[1] + 1, c[2]);
      item.regNo   = line.substring(c[2] + 1, c[3]);
      item.name    = line.substring(c[3] + 1, c[4]);
      item.branch  = line.substring(c[4] + 1, c[5]);
      item.action  = line.substring(c[5] + 1, c[6]);
      item.uid     = line.substring(c[6] + 1);

      if (postToGoogleSheets(item)) {
        Serial.printf("[AUTO-SYNC OK] Uploaded: %s (%s)\n", item.name.c_str(), item.action.c_str());
      } else {
        Serial.printf("[AUTO-SYNC FAIL] Keep in cache: %s\n", item.name.c_str());
        failedLines.push_back(line);
      }
      delay(500); // Give TLS socket and Google Apps Script time to complete cleanly
    }
  }

  // Remove the old processed file
  SD.remove(OFFLINE_LOG_FILE);

  // If any individual uploads genuinely failed, write ONLY those back to the SD card
  if (!failedLines.empty()) {
    File rewriteFile = SD.open(OFFLINE_LOG_FILE, FILE_WRITE);
    if (rewriteFile) {
      for (const String& fl : failedLines) {
        rewriteFile.println(fl);
      }
      rewriteFile.close();
      Serial.printf("[AUTO-SYNC] %d record(s) remained offline.\n", failedLines.size());
    }
  } else {
    Serial.println("[AUTO-SYNC COMPLETE] All offline records synchronized successfully!\n");
  }

  showIdleScreen();
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1500);
  Serial.println("\n\n========================================");
  Serial.println("   ESP32 ATTENDANCE SYSTEM STARTING     ");
  Serial.println("========================================");

  Wire.begin(21, 22);

  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Starting");

  // MAX98357A I2S Setup
  out = new AudioOutputI2S();
  out->SetPinout(I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DOUT_PIN);
  out->SetGain(2.5); // Boosted software volume gain

  // DS3231 RTC Setup
  if (!rtc.begin()) {
    Serial.println("[RTC ERROR] DS3231 Not Detected!");
  } else {
    Serial.println("[RTC] DS3231 Ready.");
  }

  loadDatabaseFromFS();

  // 1. Initialize MicroSD on HSPI (14, 33, 13)
  pinMode(SD_CS_PIN, OUTPUT);
  digitalWrite(SD_CS_PIN, HIGH);
  spiHSPI.begin(HSPI_SCK, HSPI_MISO, HSPI_MOSI, SD_CS_PIN);

  if (!SD.begin(SD_CS_PIN, spiHSPI, 4000000)) {
    Serial.println("[SD ERROR] HW-125 MicroSD Mount Failed! Audio & Offline storage disabled.");
    sdAvailable = false;
  } else {
    Serial.println("[SD SUCCESS] MicroSD Card Mounted on HSPI.");
    sdAvailable = true;
    // NOTE: the old queue-wipe line that used to sit here was removed.
    // Wiping /offline_logs.csv on every boot silently discarded any records
    // that hadn't synced yet. syncOfflineLogsToCloud() (called below, after
    // Wi-Fi connects) now drains the real queue instead of us nuking it.
  }

  // 2. Initialize RC522 on VSPI (18, 19, 23)
  pinMode(RFID_CS_PIN, OUTPUT);
  digitalWrite(RFID_CS_PIN, HIGH);
  SPI.begin(VSPI_SCK, VSPI_MISO, VSPI_MOSI, RFID_CS_PIN);

  rfid.PCD_Init();
  delay(50);
  rfid.PCD_SetAntennaGain(rfid.RxGain_max);

  byte v = rfid.PCD_ReadRegister(rfid.VersionReg);
  Serial.printf("[RFID] Firmware Version: 0x%02X\n", v);

  // 3. Wi-Fi Setup & Time Sync
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Connecting WiFi");
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 20) {
    delay(500);
    Serial.print(".");
    tries++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WIFI SUCCESS] Connected! IP: ");
    Serial.println(WiFi.localIP());
    // Recalibrate RTC from Internet NTP
    syncRTCWithNTP();
    // Flush any pending logs left from prior offline sessions
    syncOfflineLogsToCloud();
  } else {
    Serial.println("[WIFI] Operating in Offline Mode.");
  }

  showIdleScreen();
  Serial.println("[READY] Awaiting RFID cards...\n");
}

// ============================================================
// MAIN LOOP
// ============================================================
void loop() {
  // Revert screen back to idle after message timeout
  if (screenNeedsReset && (millis() > screenResetTime)) {
    showIdleScreen();
  }

  // Background check: attempt auto-sync every 30 seconds if Wi-Fi is active
  if (millis() - lastSyncCheck > 30000) {
    lastSyncCheck = millis();
    if (WiFi.status() == WL_CONNECTED) {
      syncOfflineLogsToCloud();
    }
  }

  // RFID Scan
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    delay(40);
    return;
  }

  String uidStr = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uidStr += "0";
    uidStr += String(rfid.uid.uidByte[i], HEX);
  }
  uidStr.toUpperCase();

  Serial.println("----------------------------------------");
  Serial.printf("[CARD DETECTED] UID: %s\n", uidStr.c_str());

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();

  int idx = findStudentByUID(uidStr);

  if (idx != -1) {
    unsigned long currentTime = millis();
    unsigned long timePassed  = currentTime - database[idx].lastTapTime;

    // 30-Second Cooldown
    if (database[idx].lastTapTime != 0 && timePassed < 30000) {
      int remainingSecs = (30000 - timePassed) / 1000;
      if (remainingSecs < 1) remainingSecs = 1;

      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Please Wait...");
      lcd.setCursor(0, 1);
      lcd.print("Wait: " + String(remainingSecs) + "s left");

      playWAV("/wait.wav");

      screenResetTime = millis() + 1500;
      screenNeedsReset = true;
      return;
    }

    database[idx].lastTapTime = currentTime;
    database[idx].tapCount++;

    String action    = (database[idx].tapCount % 2 != 0) ? "CHECK-IN" : "CHECK-OUT";
    String fullName  = database[idx].name;
    String firstName = getFirstName(fullName);
    String regNo     = database[idx].regNo;
    String branch    = database[idx].branch;

    DateTime now = rtc.now();
    int hour12 = now.hour();
    const char* meridiem = (hour12 >= 12) ? "PM" : "AM";
    if (hour12 == 0) hour12 = 12;
    else if (hour12 > 12) hour12 -= 12;

    char timeBuf[16];
    snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d %s", hour12, now.minute(), meridiem);

    char dateBuf[16];
    snprintf(dateBuf, sizeof(dateBuf), "%04d-%02d-%02d", now.year(), now.month(), now.day());

    // Update 16x2 LCD
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(firstName);
    lcd.setCursor(0, 1);
    lcd.print(action + " " + String(timeBuf));

    // Fill in-memory cache
    // Unique ID = UID + unix timestamp (hex). Lets the backend dedupe if a
    // request times out on our side but actually succeeded on the server.
    char idBuf[48];
    snprintf(idBuf, sizeof(idBuf), "%s-%08lX", uidStr.c_str(), (unsigned long)now.unixtime());
    logCache.id       = String(idBuf);
    logCache.dateStr  = String(dateBuf);
    logCache.timeStr  = String(timeBuf);
    logCache.regNo    = regNo;
    logCache.name     = fullName;
    logCache.branch   = branch;
    logCache.action   = action;
    logCache.uid      = uidStr;

    // Execute transmission pipeline (Cache -> Sheets or Cache -> SD)
    processAttendanceRecord(logCache);

    // Audio Playback
    String studentVoicePath = "/names/" + firstName + ".wav";
    studentVoicePath.toLowerCase();

    if (action == "CHECK-IN") {
      playWAV("/hello.wav");
      playWAV(studentVoicePath.c_str());
      playWAV("/welcome.wav");
    } else {
      playWAV("/bye.wav");
      playWAV(studentVoicePath.c_str());
      playWAV("/see_you.wav");
    }

    screenResetTime = millis() + 1500;
    screenNeedsReset = true;

  } else {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Imposter Ahead");
    lcd.setCursor(0, 1);
    lcd.print("Access Denied");

    playWAV("/denied.wav");

    screenResetTime = millis() + 1800;
    screenNeedsReset = true;
  }
}
