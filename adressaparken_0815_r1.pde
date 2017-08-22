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
    - 9370-P    Temperature, Humidity and Pressure Probe          ºC - %RH - Pa
    - NLS       Noise Level Sensor                                dBA
    - 9372-P    Carbon Dioxide Probe                              ppm
    - 9387-P    Particle Matter (PM1 / PM2.5/ PM10) - Dust Probe  og/m3
    - 9375-P    Luminosity Probe                                  lux

    Strategy:
    - Assign static IP
    - Connect to Gateway at 192.168.1.1
    - Turn ON sensors
    - Get data from sensors, final data is average
    - - DO THIS x SEND_EVERY_N_LOOPS - 10
    - Send all data to Gateway
    - - Gateway sends data to server over MQTT
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

//=========| INCLUDE LIBRARIES, speculative at this time
#include <WaspFrame.h>
#include <WaspSensorCities_PRO.h>
#include <WaspOPC_N2.h>             // Particle Matter
#include <TSL2561.h>                // Luuminosity
#include <WaspSensorGas_Pro.h>      // Gases
#include <WaspOPC_N2.h>             // Particle Matter


//=========| DEFINE SENSOR DATA GLOBALS,

int SEND_EVERY_N_LOOPS = 10;
int SNAPSHOTS =  10;

Gas gas_PRO_sensor(SOCKET_1);

int frameCounter;
int loopCounter;

float temperature;
float humidity;
float pressure;
float ambNoise;
float co2;
float luminosity;

//=========| DEFINE AUXILIARY GLOBALS
char MOTE_ID[]     = "Waspmote_AP";
char MAC_ADDRESS[] = "0013A200409C788A"; // Destination MAC address
char AES_KEY[]     = "testeencription";

void setup() {
  /* Setup Waspmote */
  frame.setID(MOTE_ID); // store Waspmote ID in EEPROM memory (16-byte max)

  /* Opening UART to show messages using 'Serial Monitor' (Debug) */
  USB.ON();
  USB.println(F("Libelium Awake"));

  Gas gas_PRO_sensor(SOCKET_1);

  /* Configure noise sensor for UART communication */
  noise.configure();

  /* Initialize Variables */
  frameCounter = 0;
  loopCounter  = 0;
  
}


void loop(){

  /* GAS Sensors have warming up time, turn on and sleep */
  USB.println("Turning on GAS Sensors");
  SensorCitiesPRO.ON(SOCKET_1);   // SOCKET 1 is gas
  SensorCitiesPRO.ON(SOCKET_2);   // SOCKET 2 is temperature
  SensorCitiesPRO.ON(SOCKET_B);   // SOCKET B is
  SensorCitiesPRO.ON(SOCKET_C);   // SOCKET C is
  SensorCitiesPRO.ON(SOCKET_E);   // SOCKET E is
  gas_PRO_sensor.ON();


  /* ??? SHOULD SLEEP TIME BE HIGHER? */
  PWR.deepSleep("00:00:01:00", RTC_OFFSET, RTC_ALM1_MODE1, ALL_ON);

  //=========| READ VALUES
  USB.ON();                             // Restart USB after sleep
  USB.println("Reading Sensor Values");
  
  /* === Get snapshots from sensors temperature === */
  float t = 0.0f;                                   // INITIALIZE AUX
  for (int i = 0; i < SNAPSHOTS; i++) {
    t += gas_PRO_sensor.getTemp();                  // READ VALUES
    }
  t /= SNAPSHOTS;                                   // CALCULATE AVERAGE
  temperature = t;                                  // UPDATE VARIABLE
  //========================================================================

  /* === Get snapshots from sensors humidity === */
  float h = 0.0f;                                   // AUX
  for (int i = 0; i < SNAPSHOTS; i++) {
    h += gas_PRO_sensor.getHumidity();              // READ VALUES
  }
  h /= SNAPSHOTS;                                   // CALCULATE AVERAGE
  humidity = h;                                     // UPDATE VARIABLE
  //========================================================================

  /* === Get snapshots from sensors pressure === */
  float p = 0.0f;
  for (int i = 0; i < SNAPSHOTS; i++) {
    p += gas_PRO_sensor.getPressure();              // READ VALUES
  }
  p /= SNAPSHOTS;                                   // CALCULATE AVERAGE
  pressure = p;                                     // UPDATE VARIABLE
 //========================================================================

  /* === Get  snapshots from sensors CO2 === */
  float c = 0.0f;                                   // AUX
  for (int i = 0; i < SNAPSHOTS; i++) {
    c += gas_PRO_sensor.getConc();                  // READ VALUES
  }
  c /= SNAPSHOTS;                                   // CALCULATE AVERAGE
  co2 = c;                                          // UPDATE VARIABLE
  //========================================================================
    
  /* === Get snapshots from sensors noise === */
  int status = noise.getSPLA(SLOW_MODE);

  if (status == 0) {
    ambNoise = noise.SPLA;
  } else {
   ambNoise = -1;
   USB.println(F("[CITIES PRO] Communication error. No response from the audio sensor (SLOW)"));
  }

  //========================================================================

  /* === Get  snapshots from sensors PM === */
  boolean OPC_status = OPC_N2.ON();           // Turn on the particle matter sensor
  if (OPC_status == 1) {
    int OPC_measure = OPC_N2.getPM(5000, 5000);
  } else {
    USB.println(F("Error starting the particle sensor"));
  }
 //========================================================================

  /* === Get  snapshots from sensors luminosity === */
  SensorCitiesPRO.ON(SOCKET_2);                   // SENSOR ON SOCKET 2
  TSL.ON();                                       // POWER ON SENSOR
  float l = 0.0f;                                 // AUX
  for (int i = 0; i < SNAPSHOTS; i++) {
    l += TSL.getLuminosity();                     // READ VALUES
  }
  SensorCitiesPRO.OFF(SOCKET_2);                  // POWER OFF SOCKET 2
  l /= SNAPSHOTS;                                 // CALCULATE AVERAGE
  luminosity = l;                                // UPDATE ARRAY
  //========================================================================}
  /* Get current time */
  RTC.ON();
  RTC.getTime();

  /* Build and send packets */
  frame.createFrame(ASCII);                  // Create new ASCII frame

  frame.addSensor(SENSOR_CITIES_PRO_TC, temperature);      // Add temperature“  frame.addSensor(SENSOR_CITIES_PRO_HUM, fHumidity);        // Add humidity
  frame.addSensor(SENSOR_CITIES_PRO_PRES, pressure);       // Add pressure value
  frame.addSensor(SENSOR_CITIES_PRO_PM1, OPC_N2._PM1);      // Add PM1 value
  frame.addSensor(SENSOR_CITIES_PRO_PM2_5, OPC_N2._PM2_5);  // Add PM2.5 value
  frame.addSensor(SENSOR_CITIES_PRO_PM10, OPC_N2._PM10);    // Add PM10 value
  frame.addSensor(SENSOR_CITIES_PRO_CO2, co2);             // Add CO2 ¨

  frame.addSensor(TSL.lux, luminosity);      // ????? IS THIS THE RIGHT KEYWORD
  frame.addSensor(SENSOR_TIME, RTC.hour, RTC.minute, RTC.second); // ADD TIME

  frame.showFrame();                      // Print frame in buffer
  //frame.encryptFrame(AES_128, AES_KEY);   // Encrypt frame

  frameCounter++; // increase frame counter

  //=========| POWER OFF SENSORS
  SensorCitiesPRO.ON(SOCKET_B);
  SensorCitiesPRO.ON(SOCKET_C);
  SensorCitiesPRO.ON(SOCKET_E);

  OPC_N2.OFF();

  /* Sleep Cycle */
  USB.println(F("\nSystem Sleep"));  // Call off
  PWR.deepSleep("00:00:00:30", RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);

  USB.ON();                          // Restart USB
  USB.println(F("\nAwake"));         // Call on

}
