/*
    ------ Code for Libelium System at Adressaparken --------

    ==================================================================
    ==|
    ==| Code by Carlos Valente and Torbjørn Kvåle for Adressaparken
    ==| Release 01
    ==| 28th September 2017
    ==|
    ==================================================================

    Sensor list:
    - Plug & Sense! SCP WiFi
    - 9370-P  - Temperature, Humidity and Pressure Probe
    - NLS     - Noise Level Sensor
    - 9372-P  - Carbon Dioxide (CO2) [Calibrated] Probe
    - 9387-P  - Particle Matter (PM1 / PM2.5 / PM10) – Dust Probe
    - 9326-P  - Luminosity (luxes accuracy) Probe

    Strategy:
    - Assign static IP
    - Connect to Gateway at 192.168.1.1
    - Turn ON sensors
    - Get data from sensors, final data is average
    - Send all data to Gateway
    - Gateway sends data to server over MQTT
    - Sleep

    INFO:
    - Gateway IP: 192.168.1.100 Mac Adress (wifi-side): 0013A200409C788A address (network side): 00:0d:b9:31:1f:50
    - Configure Manager System (Meshlium)

    FRAME EXAMPLE
    Start - Frame Type - Num Fields # Serial ID # Waspmote ID # Sequence # Sensor 1 # Sensor n       #
    <=>        0x80        0x03     #  35690284 #   NODE_001  #   214    # BAT:35   # DATE:12-01- 01 #


    LINKS:
    http://www.libelium.com/developers/
    http://www.libelium.com/downloads/documentation/smart_cities_pro_sensor_board.pdf

*/

// Include libraries
///////////////////////////////////////
#include "Configuration.h"
#include <WaspWIFI_PRO.h>
#include <WaspFrame.h>
#include <WaspSensorCities_PRO.h>
#include <WaspOPC_N2.h>             // Particle Matter
#include <TSL2561.h>                // Luminosity
//#include <WaspSensorGas_Pro.h>      // Gases
#include <WaspOPC_N2.h>             // Particle Matter
///////////////////////////////////////


// Socket Allocation
///////////////////////////////////////
int NOISE_SOCKET        = SOCKET_A; // NLS       Noise Level Sensor                                dBA
int LUMINOSITY_SOCKET   = SOCKET_C; // 9375-P    Luminosity Probe                                  lux
int PARTICLE_SOCKET     = SOCKET_D; // 9387-P    Particle Matter (PM1 / PM2.5/ PM10) - Dust Probe  og/m3
int TEMPHUMPRES_SOCKET  = SOCKET_E; // 9370-P    Temperature, Humidity and Pressure Probe          ºC - %RH - Pa
// int CO2_SOCKET          = SOCKET_F; // 9372-P    Carbon Dioxide Probe                              ppm
///////////////////////////////////////


// Network Settings
///////////////////////////////////////
char type[] = "http";
char host[] = "192.168.1.1";
char port[] = "80";
///////////////////////////////////////


// AUX
///////////////////////////////////////
//Gas gas_PRO_sensor(CO2_SOCKET);     // Gases object
bmeGasesSensor bme;
///////////////////////////////////////

void setup() {

  // Initialize aux
  ///////////////////////////////////////
  frame.setID(WASPMOTE_ID);        // Set node ID
  USB.ON();
  setupWIFI();
  ///////////////////////////////////////


  // Set restart watchdog
  ///////////////////////////////////////
  RTC.setWatchdog(720); //restart box every 12 hours
  ///////////////////////////////////////

  USB.println(F("Libelium Awake"));
}


void loop(){

  // Create Frame
  ///////////////////////////////////////
  USB.println(F("Reading Sensor Values"));
  frame.createFrame(ASCII);
  ///////////////////////////////////////


  // Turn on sensors
  ///////////////////////////////////////
  // CO2 sensor needs temp, humidity and pressure in addition to its own measurement
  //SensorCitiesPRO.ON(CO2_SOCKET);
  SensorCitiesPRO.ON(TEMPHUMPRES_SOCKET);
  bme.ON();
  //gas_PRO_sensor.ON();
  delay(60000); //Allow sensors to heat
  ///////////////////////////////////////


  // Get read from sensors: CO2
  ///////////////////////////////////////
  //float co2;
  //co2 = gas_PRO_sensor.getConc();
  //if (co2 < 0) PWR.reboot();
  //frame.addSensor(SENSOR_CITIES_PRO_CO2, co2);
  ///////////////////////////////////////


  // Get read from sensors: Temperature
  ///////////////////////////////////////
  float temperature;
  temperature = bme.getTemperature();
  if (temperature < -100) PWR.reboot();
  frame.addSensor(SENSOR_CITIES_PRO_TC, temperature);
  ///////////////////////////////////////


  // Get read from sensors: Humidity
  ///////////////////////////////////////
  float humidity;
  humidity = bme.getHumidity();
  if (humidity < 0) PWR.reboot();
  frame.addSensor(SENSOR_CITIES_PRO_HUM, humidity);
  ///////////////////////////////////////


  // Get read from sensors: Pressure
  ///////////////////////////////////////
  float pressure;
  pressure += bme.getPressure();  //gas_PRO_sensor.getPressure();
  frame.addSensor(SENSOR_CITIES_PRO_PRES, pressure);
  ///////////////////////////////////////


  // Turn Off Sensors
  ///////////////////////////////////////
  //SensorCitiesPRO.OFF(CO2_SOCKET);
  SensorCitiesPRO.OFF(TEMPHUMPRES_SOCKET);


  // Turn on and get data from sensor: Noise Level
  ///////////////////////////////////////
  SensorCitiesPRO.ON(NOISE_SOCKET);
  noise.configure();
  if (noise.getSPLA(SLOW_MODE) != 0) {
    USB.println(F("[CITIES PRO] Communication error. No response from the audio sensor (SLOW)"));
  }
  frame.addSensor(SENSOR_CITIES_PRO_NOISE, noise.SPLA);
  SensorCitiesPRO.OFF(NOISE_SOCKET);
  ///////////////////////////////////////


  // Send frame and create new
  ///////////////////////////////////////
  sendFrame(frame);
  frame.createFrame(ASCII);
  ///////////////////////////////////////


  // Turn on and get read from sensors: PM
  ///////////////////////////////////////
  SensorCitiesPRO.ON(PARTICLE_SOCKET);
  if (OPC_N2.ON()) {
    if (!OPC_N2.getPM(5000, 5000))
    {
      USB.println(F("Error reading values from the particle sensor"));
    }
  } else {
    USB.println(F("Error starting the particle sensor"));
  }
  frame.addSensor(SENSOR_CITIES_PRO_PM1,   OPC_N2._PM1);    // Add PM1 value
  frame.addSensor(SENSOR_CITIES_PRO_PM2_5, OPC_N2._PM2_5);  // Add PM2.5 value
  frame.addSensor(SENSOR_CITIES_PRO_PM10,  OPC_N2._PM10);   // Add PM10 value
  OPC_N2.OFF();
  SensorCitiesPRO.OFF(PARTICLE_SOCKET);
  ///////////////////////////////////////


  // Turn on and get read from sensors: Luminosity
  ///////////////////////////////////////
  SensorCitiesPRO.ON(LUMINOSITY_SOCKET);
  float luminosity;
  TSL.ON();
  TSL.getLuminosity();
  luminosity = TSL.lux;
  frame.addSensor(SENSOR_CITIES_PRO_LUXES, luminosity);
  SensorCitiesPRO.OFF(LUMINOSITY_SOCKET);
  ///////////////////////////////////////


  // Get current battery level
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());
  // Get amount of free memory (DEBUG)
  frame.addSensor(SENSOR_STR, freeMemory());
  ///////////////////////////////////////


  // Send frame and sleep
  ///////////////////////////////////////
  sendFrame(frame);


  // Sleep Cycle
  USB.println(F("\nSystem Sleep"));
  WIFI_PRO.OFF(SOCKET0);
  PWR.deepSleep("00:00:05:00", RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
  USB.ON();                             // Restart USB after sleep
  checkWIFI();                          // Restart WIFI after sleep
  ///////////////////////////////////////
}


/**
  * Sends wasp frame over WIFI
  * @param frame - WaspFrame object to send.
  * @return void.
*/
void sendFrame(WaspFrame frame) {

  frame.showFrame(); // Print frame in buffer

  if (WIFI_PRO.isConnected() == true) {
    USB.println(F("[connected]"));
    if (WIFI_PRO.sendFrameToMeshlium(type, host, port, frame.buffer, frame.length) == 0) {
      USB.println(F("HTTP query OK."));
    } else {
      USB.println(F("HTTP query ERROR"));
      WIFI_PRO.printErrorCode();
    }
  } else {
    USB.print(F("WIFI is not connected ERROR"));
    WIFI_PRO.printErrorCode();
  }
}


/**
  * Setup WIFI
  * @param none.
  * @return void.
*/
void setupWIFI() {

  USB.print(F("Turning on WIFI: "));
  USB.println(WIFI_PRO.ON(SOCKET0) == 0 ? F("[OK]") : F("[ERROR]"));

  USB.print(F("Resetting WIFI settings: "));
  USB.println(WIFI_PRO.resetValues() == 0 ? F("[OK]") : F("[ERROR]"));

  USB.print(F("Setting SSID: "));
  USB.println(WIFI_PRO.setESSID(SSID) == 0 ? F("[OK]") : F("[ERROR]"));

  USB.print(F("Configuring security: "));
  USB.println(WIFI_PRO.setPassword(SECURITY, WIFI_PASSWORD) == 0 ? F("[OK]") : F("[ERROR]"));

  USB.print(F("Restarting WIFI"));
  USB.println(WIFI_PRO.softReset() == 0 ? F("[OK]") : F("[ERROR]"));
}

/**
  * Check WIFI Status
  * @param none.
  * @return void.
*/
void checkWIFI() {
  USB.print(F("Checking WIFI: "));
  USB.println(WIFI_PRO.ON(SOCKET0) == 0 ? F("[OK]") : F("[ERROR]"));
}
