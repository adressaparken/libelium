/*


    ------ Code for Libelium System at Adressaparken --------

    ==================================================
    ==|
    ==| Code by Carlos Valente for Adressaparken
    ==| Release 01
    ==| 15th August 2017
    ==|
    ==| . Read sensor data
    ==| . Build frames
    ==| . Sleep implemented
    ==================================================

    Sensor list:
    - Plug & Sense! SCP WiFi

    A - NLS       Noise Level Sensor                                dBA
    B - 9372-P    Carbon Dioxide Probe                              ppm
    C - 9375-P    Luminosity Probe                                  lux
    D - 9387-P    Particle Matter (PM1 / PM2.5/ PM10) - Dust Probe  og/m3
    F - 9370-P    Temperature, Humidity and Pressure Probe          ºC - %RH - Pa

    Strategy:
    - Assign static IP
    - Connect to Gateway at 192.168.1.1
    - Turn ON sensors
    - Get data from sensors, final data is average
    - Send all data to Gateway
    - Gateway sends data to server over MQTT
    - Sleep

    TODO:
    - Assign sensors to the right slots
    - Improve sleep times WaspPWR.h
    - - Check battery level, adjust sleep times accordingly
    - - save values and send information for period of time (hour?)
    - - Waspmote: On - 17mA, Sleep 30 uA - Deep Sleep 33 uA
    - - WIFI    : On - 33mA, Sleep 04 uA - Off 0uA - Send 38mA - Receive 38mA
    - Use OTA to update Waspmote
    - Encrypt data to gateway (link layer AES)
    - Send data to DB
    - Sensor is an average of readings?

    INFO:
    !!!!!! CANNOT REACH GATEWAY AT GIVEN IP
    - Gateway IP: 192.168.1.100 Mac Adress: 0013A200409C788A
    - Configure Manager System (Meshlium)

    FRAME EXAMPLE
    Start - Frame Type - Num Fields # Serial ID # Waspmote ID # Sequence # Sensor 1 # Sensor n       #
    <=>        0x80        0x03     #  35690284 #   NODE_001  #   214    # BAT:35   # DATE:12-01- 01 #


    LINKS:
    http://www.libelium.com/developers/
    http://www.hivemq.com/blog/mqtt-essentials-part-6-mqtt-quality-of-service-levels

*/
#include "Configuration.h"
#include <WaspWIFI_PRO.h>
#include <WaspFrame.h>
#include <WaspSensorCities_PRO.h>
#include <WaspOPC_N2.h>             // Particle Matter
#include <TSL2561.h>                // Luuminosity
#include <WaspSensorGas_Pro.h>      // Gases
#include <WaspOPC_N2.h>             // Particle Matter



int SNAPSHOTS =  10;

Gas gas_PRO_sensor(SOCKET_F);

char type[] = "http";
char host[] = "10.10.10.1";
char port[] = "80";


void setup() {
  frame.setID(MOTE_ID);

  USB.println(F("Libelium Awake"));

  USB.println(F("Wifi on"));
  USB.println(WIFI_PRO.ON(SOCKET0) == 0 ? F("[OK]") : F("[ERROR]"));
  USB.println(F("Reset wifi settings"));
  USB.println(WIFI_PRO.resetValues() == 0 ? F("[OK]") : F("[ERROR]"));
  USB.println(F("Set SSID"));
  USB.println(WIFI_PRO.setESSID(SSID) == 0 ? F("[OK]") : F("[ERROR]"));
  USB.println(F("Configure security"));
  USB.println(WIFI_PRO.setPassword(OPEN, WIFI_PASSWORD) == 0 ? F("[OK]") : F("[ERROR]"));//Alt: OPEN, WEP64, WEP128, WPA (WPA-PSK with TKIP encryption), WPA2 (WPA2-PSK with TKIP or AES encryption)
  USB.println(F("Restart wifi"));
  USB.println(WIFI_PRO.softReset() == 0 ? F("[OK]") : F("[ERROR]"));
  
}


void loop(){
  //PWR.deepSleep("00:00:01:00", RTC_OFFSET, RTC_ALM1_MODE1, ALL_ON);
  
  USB.println(F("Wifi on"));
  USB.println(WIFI_PRO.ON(SOCKET0) == 0 ? F("[OK]") : F("[ERROR]"));
  frame.createFrame(ASCII);                  // Create new ASCII frame

  USB.ON();                             // Restart USB after sleep
  USB.println("Reading Sensor Values");


  // CO2 sensor needs temp, humidity and pressure in addition to its own measurement
  SensorCitiesPRO.ON(SOCKET_F);
  SensorCitiesPRO.ON(SOCKET_E);
  gas_PRO_sensor.ON();

  delay(60000);//Allow CO2 sensor to heat
  // Get  snapshots from sensors CO2
  float co2 = 0.0f;
  for (int i = 0; i < SNAPSHOTS; i++) {
    co2 += gas_PRO_sensor.getConc();
  }
  co2 /= SNAPSHOTS;
  frame.addSensor(SENSOR_CITIES_PRO_CO2, co2);

  // Get snapshots from sensors temperature
  float temperature = 0.0f;
  for (int i = 0; i < SNAPSHOTS; i++) {
    temperature += SensorCitiesPRO.getTemperature();//gas_PRO_sensor.getTemp();
    }
  temperature /= SNAPSHOTS;
  frame.addSensor(SENSOR_CITIES_PRO_TC, temperature);

  // Get snapshots from sensors humidity
  float humidity = 0.0f;
  for (int i = 0; i < SNAPSHOTS; i++) {
    humidity += SensorCitiesPRO.getHumidity();//gas_PRO_sensor.getHumidity();
  }
  humidity /= SNAPSHOTS;
  frame.addSensor(SENSOR_CITIES_PRO_HUM, humidity);

  // Get snapshots from sensors pressure 
  float pressure = 0.0f;
  for (int i = 0; i < SNAPSHOTS; i++) {
    pressure += SensorCitiesPRO.getPressure();//gas_PRO_sensor.getPressure();
  }
  pressure /= SNAPSHOTS;
  frame.addSensor(SENSOR_CITIES_PRO_PRES, pressure);

  SensorCitiesPRO.OFF(SOCKET_F);
  SensorCitiesPRO.OFF(SOCKET_E);


  
  // Get snapshots from sensors noise
  SensorCitiesPRO.ON(SOCKET_A);
  noise.configure();
  if (noise.getSPLA(SLOW_MODE) != 0) {
    USB.println(F("[CITIES PRO] Communication error. No response from the audio sensor (SLOW)"));
  }
  frame.addSensor(SENSOR_CITIES_PRO_NOISE, noise.SPLA);
  SensorCitiesPRO.OFF(SOCKET_A);


  sendFrame(frame);
  frame.createFrame(ASCII);

  // Get  snapshots from sensors PM 
  SensorCitiesPRO.OFF(SOCKET_D);
  if (OPC_N2.ON()) {
    if (!OPC_N2.getPM(5000, 5000))
    {
      USB.println(F("Error reading values from the particle sensor"));
    }
  } else {
    USB.println(F("Error starting the particle sensor"));
  }
  frame.addSensor(SENSOR_CITIES_PRO_PM1, OPC_N2._PM1);      // Add PM1 value
  frame.addSensor(SENSOR_CITIES_PRO_PM2_5, OPC_N2._PM2_5);  // Add PM2.5 value
  frame.addSensor(SENSOR_CITIES_PRO_PM10, OPC_N2._PM10);    // Add PM10 value
  OPC_N2.OFF();
  SensorCitiesPRO.OFF(SOCKET_D);



  // Get  snapshots from sensors luminosity
  SensorCitiesPRO.ON(SOCKET_C);
  float luminosity = 0.0f;
  TSL.ON();
  for (int i = 0; i < SNAPSHOTS; i++) {
    TSL.getLuminosity(); 
    luminosity += TSL.lux;
  }
  luminosity /= SNAPSHOTS;
  SensorCitiesPRO.OFF(SOCKET_C);
  frame.addSensor(SENSOR_CITIES_PRO_LUXES, luminosity);



  // Get current time and bat
  RTC.ON();
  RTC.getTime();
  frame.addSensor(SENSOR_TIME, RTC.hour, RTC.minute, RTC.second);
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());

  sendFrame(frame);

  // Sleep Cycle 
  USB.println(F("\nSystem Sleep"));
  WIFI_PRO.OFF(SOCKET0);
  PWR.deepSleep("00:00:00:30", RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
}

void sendFrame(WaspFrame frame)
{
  frame.showFrame(); // Print frame in buffer
  
  if (WIFI_PRO.isConnected() == true)
  {
    USB.println(F("[connected]"));
    if (WIFI_PRO.sendFrameToMeshlium(type, host, port, frame.buffer, frame.length) == 0)
    {
      USB.println(F("HTTP query OK."));
    }
    else
    {
      USB.println(F("HTTP query ERROR"));
      WIFI_PRO.printErrorCode();
    }
  }
  else
  {
    USB.print(F("WiFi is not connected ERROR")); 
    WIFI_PRO.printErrorCode();
  }
}


