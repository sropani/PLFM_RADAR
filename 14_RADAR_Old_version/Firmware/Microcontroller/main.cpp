/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "si5351.h"
#include "parameters.h"
#include "adf4382.h"
#include "adar1000.h"
#include "hardware_config.h"
#include "no_os_delay.h"
#include "no_os_alloc.h"
#include "no_os_print_log.h"
#include "no_os_error.h"
#include "no_os_units.h"
#include "no_os_dma.h"
#include "no_os_spi.h"
#include "no_os_uart.h"
#include "no_os_util.h"
#include <stdint.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <iostream>
#include <vector>
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
#define debug_uart	1
#define BUFFER_SIZE 16 //ADAR
#define Delay_scan 1 //Delay between each TX,RX scan// 1 corresponds to 15.6 ns// check delay_15ns() function
#define Delay_scan_rx 1 //Delay between each TX,RX scan// 1 corresponds to 15.6 ns// check delay_15ns() function

 Si5351 si5351;

 ////////////////////////////////////////////////////////////////////////////////
 ///////////////////////////////ADF4382//////////////////////////////////////////
 ////////////////////////////////////////////////////////////////////////////////

 struct no_os_uart_init_param adf4382_uart_ip = {
 	.device_id = UART_DEVICE_ID,
 	.irq_id = UART_IRQ_ID,
 	.asynchronous_rx = true,
 	.baud_rate = UART_BAUDRATE,
 	.size = NO_OS_UART_CS_8,
 	.parity = NO_OS_UART_PAR_NO,
 	.stop = NO_OS_UART_STOP_1_BIT,
 	.platform_ops = UART_OPS,
 	.extra = UART_EXTRA,
 };


 struct no_os_spi_init_param adf4382_spi_ip = {
 	.device_id = SPI_DEVICE_ID,
 	.max_speed_hz = 4000000,
	.chip_select = SPI_CS,
 	.mode = NO_OS_SPI_MODE_0,
 	.bit_order = NO_OS_SPI_BIT_ORDER_MSB_FIRST,
 	.platform_ops = SPI_OPS,
 	.extra = SPI_EXTRA,
 };


 struct adf4382_init_param adf4382_ip = {
 	.spi_init = &adf4382_spi_ip,
 	.spi_3wire_en = false,
 	.cmos_3v3 = false,
 	.ref_freq_hz = 100000000,
 	.freq = 10500000000ULL,
 	.ref_doubler_en = 1,
 	.ref_div = 1,
 	.cp_i = 15,
 	.bleed_word = 4903,
 	.ld_count = 10,
 	.id = ID_ADF4382A,
 };

 struct adf4382_dev *adf4382_device = NULL; // Pointer to device


 ////////////////////////////////////////////////////////////////////////////////
 //////////////////////////////ADAR1000//////////////////////////////////////////
 ////////////////////////////////////////////////////////////////////////////////

 uint8_t txBuffer[BUFFER_SIZE] = {0xA1, 0xB2, 0xC3, 0xD4};  // Example data
 uint8_t rxBuffer1[BUFFER_SIZE] = {0};  // Receive buffer
 uint8_t rxBuffer2[BUFFER_SIZE] = {0};  // Receive buffer
 uint8_t rxBuffer3[BUFFER_SIZE] = {0};  // Receive buffer
 uint8_t rxBuffer4[BUFFER_SIZE] = {0};  // Receive buffer

 uint32_t SpiTransferFunction(uint8_t *p_txData, uint8_t *p_rxData, uint32_t size) {
 	HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_1, GPIO_PIN_RESET);
 	HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_2, GPIO_PIN_RESET);
 	HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_3, GPIO_PIN_RESET);
 	HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_4, GPIO_PIN_RESET);
 	HAL_StatusTypeDef status = HAL_SPI_TransmitReceive(&hspi1, p_txData, p_rxData, size, HAL_MAX_DELAY);
    HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_1, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_2, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_3, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIO_ADAR, CS_ADAR_4, GPIO_PIN_SET);
    return (status == HAL_OK) ? 0 : 1;  // Return 0 on success, 1 on failure
 }

 /// Generic ADAR device that contains a hardware address, SPI transfer function
 /// and a pointer to a buffer to receive data into.

 // Define the ADAR1000 device instance
 const AdarDevice ADAR1 = {
     .dev_addr = 0x00,               // Example hardware address
     .Transfer = SpiTransferFunction, // Assign SPI function pointer
     .p_rx_buffer = rxBuffer1         // Assign receive buffer
 };
 const AdarDevice ADAR2 = {
     .dev_addr = 0x01,               // Example hardware address
     .Transfer = SpiTransferFunction, // Assign SPI function pointer
     .p_rx_buffer = rxBuffer2         // Assign receive buffer
 };
 const AdarDevice ADAR3 = {
     .dev_addr = 0x10,               // Example hardware address
     .Transfer = SpiTransferFunction, // Assign SPI function pointer
     .p_rx_buffer = rxBuffer3         // Assign receive buffer
 };
 const AdarDevice ADAR4 = {
     .dev_addr = 0x11,               // Example hardware address
     .Transfer = SpiTransferFunction, // Assign SPI function pointer
     .p_rx_buffer = rxBuffer4         // Assign receive buffer
 };

 AdarBiasCurrents ADAR_BC ={ //bias current
	.rx_lna = 8,		///< nominal:  8, low power: 5
	.rx_vm = 5,			///< nominal:  5, low power: 2
	.rx_vga = 10,		///< nominal: 10, low power: 3
	.tx_vm = 5,			///< nominal:  5, low power: 2
	.tx_vga = 5,		///< nominal:  5, low power: 5
	.tx_drv	= 6			///< nominal:  6, low power: 3
 };
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

I2C_HandleTypeDef hi2c1;

SPI_HandleTypeDef hspi1;

TIM_HandleTypeDef htim1;

UART_HandleTypeDef huart2;

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_I2C1_Init(void);
static void MX_SPI1_Init(void);
static void MX_TIM1_Init(void);
static void MX_USART2_UART_Init(void);
/* USER CODE BEGIN PFP */

void delay_15ns(volatile long unsigned int ns){
__HAL_TIM_SET_COUNTER(&htim1,0);  // set the counter value a
while (__HAL_TIM_GET_COUNTER(&htim1) < ns);  // //Clock TIMx -> AHB/APB1 is set to 64MHz/presc+1   presc = 0
//delay_15ns(1) would perform a delay of 15.6ns
}

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_I2C1_Init();
  MX_SPI1_Init();
  MX_TIM1_Init();
  MX_USART2_UART_Init();
  /* USER CODE BEGIN 2 */

  HAL_TIM_Base_Start(&htim1);
  //////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////Votage Enable////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////

  //3.3V to ADAR should be set before -5V
  HAL_GPIO_WritePin(GPIO_VR, EN_32, GPIO_PIN_SET);//active high
  HAL_GPIO_WritePin(GPIO_VR, EN_42, GPIO_PIN_SET);//active High


  //////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////SI5351///////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////
  si5351.init(SI5351_CRYSTAL_LOAD_8PF, 0, 0);
  HAL_GPIO_WritePin(GPIO_si5351, SI5351_CLK_EN, GPIO_PIN_RESET);//active low
  HAL_GPIO_WritePin(GPIO_si5351, SI5351_SS_EN, GPIO_PIN_SET);//active High (Spread Spectrum)
  //each unity on set_freq(unityULL, SI5351_CLK4) represents 0.01Hz
  si5351.set_freq(10000000000ULL, SI5351_CLK4);//set FPGA main clock to 100MHz
  si5351.set_freq(10000000000ULL, SI5351_CLK6);//ADF4382 clock
  si5351.update_status();
  HAL_Delay(500);
  if(debug_uart)
  {	  //When the synthesizers are locked and the Si5351 is working correctly, you'll see an output similar to this one (the REVID may be different):
      //SYS_INIT: 0  LOL_A: 0  LOL_B: 0  LOS: 0  REVID: 3
	  char buffer[10];
	  HAL_UART_Transmit(&huart2, (uint8_t*)"PLLA: " , strlen("PLLA: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%llu", si5351.plla_freq/100), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  PLLB: " , strlen("  PLLB: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%llu", si5351.pllb_freq/100), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  SYS_INIT: " , strlen("  SYS_INIT: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", si5351.dev_status.SYS_INIT), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  LOL_A: " , strlen("  LOL_A: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", si5351.dev_status.LOL_A), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  LOL_B: " , strlen("  LOL_B ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", si5351.dev_status.LOL_B), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  LOS: " , strlen("  LOS: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", si5351.dev_status.LOS), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  REVID: " , strlen("  REVID: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", si5351.dev_status.REVID), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"\r\n" , strlen("\r\n" ) , 10);
  }

  //////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////ADF4382//////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////

  int status = adf4382_init(&adf4382_device ,&adf4382_ip);
  if (status != 0) {
      // Handle initialization error
  }


  status = adf4382_set_freq(adf4382_device);
  if (status != 0) {
      // Handle frequency setting error
  }

  adf4382_set_en_chan(adf4382_device, 0, true);
  adf4382_set_en_chan(adf4382_device, 1, true);
  HAL_GPIO_WritePin(GPIO_ADF, ADF_CE, GPIO_PIN_SET);//active High

  //HAL_GPIO_WritePin(GPIO_ADF, ADF_DELSTR, GPIO_PIN_SET);
  //HAL_GPIO_WritePin(GPIO_ADF, ADF_DELADJ, GPIO_PIN_SET);

  //////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////LTC5552 Mixers///////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////

  HAL_GPIO_WritePin(GPIO_DIG, DIG_2, GPIO_PIN_SET); //Enable RX Mixer
  HAL_GPIO_WritePin(GPIO_DIG, DIG_3, GPIO_PIN_SET); //Enable TX Mixer


  //////////////////////////////////////////////////////////////////////////////////////
  /////////////////////////////////////ADAR1000/////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////

	 //phase_step = 0 => phase = 0°
	 //phase_step = 127 => phase = 360°
	 //steering angle (rad)= arcsin(phase_dif/Pi)

  uint8_t matrix1[22][16];
  uint8_t vector_0[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
  uint8_t matrix2[22][16];
  for(int j=0; j<15;j++){
	  for(int i=0; i<21;i++){
		  matrix1[i][j]=(2*(i+1)*(15-j))%127;
		  matrix2[i][j]=matrix1[i][15-j];
		  i++;
	  }
	  j++;
  }
  Adar_AdcInit(&ADAR1, BROADCAST_OFF);//init. ADC
  Adar_AdcInit(&ADAR2, BROADCAST_OFF);//init. ADC
  Adar_AdcInit(&ADAR3, BROADCAST_OFF);//init. ADC
  Adar_AdcInit(&ADAR4, BROADCAST_OFF);//init. ADC
  uint8_t Temp1 = Adar_AdcRead(&ADAR1,BROADCAST_OFF);//Read ADC from single ADAR
  uint8_t Temp2 = Adar_AdcRead(&ADAR2,BROADCAST_OFF);
  uint8_t Temp3 = Adar_AdcRead(&ADAR3,BROADCAST_OFF);
  uint8_t Temp4 = Adar_AdcRead(&ADAR4,BROADCAST_OFF);

  if(debug_uart){
	  char buffer[10];
	  HAL_UART_Transmit(&huart2, (uint8_t*)"Temp1: " , strlen("Temp1: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", Temp1), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  Temp2: " , strlen("  Temp2: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", Temp2), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  Temp3: " , strlen("  Temp3: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", Temp3), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"  Temp4: " , strlen("  Temp4: ") , 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)buffer, sprintf(buffer, "%u", Temp4), 10);
	  HAL_UART_Transmit(&huart2, (uint8_t*)"\r\n" , strlen("\r\n" ) , 10);
  }

  Adar_SetBiasCurrents(&ADAR1,&ADAR_BC,BROADCAST_OFF);
  Adar_SetBiasCurrents(&ADAR2,&ADAR_BC,BROADCAST_OFF);
  Adar_SetBiasCurrents(&ADAR3,&ADAR_BC,BROADCAST_OFF);
  Adar_SetBiasCurrents(&ADAR4,&ADAR_BC,BROADCAST_OFF);

  uint8_t bias_on_voltage [5] = {0x39, 0x39, 0x39, 0x39, 0x00};//V_PA = -1.1V; V_LNA = 0V
  uint8_t bias_off_voltage [5] = {0x85, 0x85, 0x85, 0x85, 0x68};//V_PA = -2.5V; V_LNA = -2V

  HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_RESET);//reset TR pin on FPGA for RX mode
  Adar_SetBiasVoltages(&ADAR1, bias_on_voltage, bias_off_voltage);
  Adar_SetBiasVoltages(&ADAR2, bias_on_voltage, bias_off_voltage);
  Adar_SetBiasVoltages(&ADAR3, bias_on_voltage, bias_off_voltage);
  Adar_SetBiasVoltages(&ADAR4, bias_on_voltage, bias_off_voltage);

  Adar_SetRxVgaGain(&ADAR1, 1, 16, BROADCAST_OFF);//16dB is the max
  Adar_SetRxVgaGain(&ADAR1, 2, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR1, 3, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR1, 4, 16, BROADCAST_OFF);

  Adar_SetRxVgaGain(&ADAR2, 1, 16, BROADCAST_OFF);//16dB is the max
  Adar_SetRxVgaGain(&ADAR2, 2, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR2, 3, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR2, 4, 16, BROADCAST_OFF);

  Adar_SetRxVgaGain(&ADAR3, 1, 16, BROADCAST_OFF);//16dB is the max
  Adar_SetRxVgaGain(&ADAR3, 2, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR3, 3, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR3, 4, 16, BROADCAST_OFF);

  Adar_SetRxVgaGain(&ADAR4, 1, 16, BROADCAST_OFF);//16dB is the max
  Adar_SetRxVgaGain(&ADAR4, 2, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR4, 3, 16, BROADCAST_OFF);
  Adar_SetRxVgaGain(&ADAR4, 4, 16, BROADCAST_OFF);

  Adar_SetTxBias(&ADAR1, BROADCAST_OFF);//set to nominal...check adar1000.c
  Adar_SetTxBias(&ADAR2, BROADCAST_OFF);
  Adar_SetTxBias(&ADAR3, BROADCAST_OFF);
  Adar_SetTxBias(&ADAR4, BROADCAST_OFF);

  Adar_SetTxVgaGain(&ADAR1, 1, 0x7D, BROADCAST_OFF);//0xFF = max
  Adar_SetTxVgaGain(&ADAR1, 2, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR1, 3, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR1, 4, 0x7D, BROADCAST_OFF);

  Adar_SetTxVgaGain(&ADAR2, 1, 0x7D, BROADCAST_OFF);//0xFF = max
  Adar_SetTxVgaGain(&ADAR2, 2, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR2, 3, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR2, 4, 0x7D, BROADCAST_OFF);

  Adar_SetTxVgaGain(&ADAR3, 1, 0x7D, BROADCAST_OFF);//0xFF = max
  Adar_SetTxVgaGain(&ADAR3, 2, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR3, 3, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR3, 4, 0x7D, BROADCAST_OFF);

  Adar_SetTxVgaGain(&ADAR4, 1, 0x7D, BROADCAST_OFF);//0xFF = max
  Adar_SetTxVgaGain(&ADAR4, 2, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR4, 3, 0x7D, BROADCAST_OFF);
  Adar_SetTxVgaGain(&ADAR4, 4, 0x7D, BROADCAST_OFF);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
	  //////////////////////////////////////////////////////////////////////////////////////
	  /////////////////////////////////////ADAR1000/////////////////////////////////////////
	  //////////////////////////////////////////////////////////////////////////////////////

	 //phase_step = 0 => phase = 0°
	 //phase_step = 127 => phase = 360°
	 //steering angle (rad)= arcsin(phase_dif/Pi)
	  HAL_GPIO_WritePin(GPIO_DIG, DIG_1, GPIO_PIN_SET); // Send to FPGA_FT2232HQ start frame from ADC Matrix
	  HAL_Delay(1);
	  HAL_GPIO_WritePin(GPIO_DIG, DIG_1, GPIO_PIN_RESET); // Send to FPGA_FT2232HQ start frame from ADC Matrix

	for(int i = 0; i<21; i++){

		    Adar_SetTxPhase(&ADAR1,1 ,matrix1[i][0] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,2 ,matrix1[i][1] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,3 ,matrix1[i][2] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,4 ,matrix1[i][3] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR2,1 ,matrix1[i][4] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,2 ,matrix1[i][5] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,3 ,matrix1[i][6] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,4 ,matrix1[i][7] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR3,1 ,matrix1[i][8] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,2 ,matrix1[i][9] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,3 ,matrix1[i][10] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,4 ,matrix1[i][11] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR4,1 ,matrix1[i][12] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,2 ,matrix1[i][13] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,3 ,matrix1[i][14] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,4 ,matrix1[i][15] , BROADCAST_OFF);
		    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_SET);//set TR pin on FPGA for TX mode
		    HAL_GPIO_TogglePin(GPIO_LED, LED_1);
		    delay_15ns(Delay_scan);

		    Adar_SetRxPhase(&ADAR1,1 ,matrix1[i][0] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,2 ,matrix1[i][1] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,3 ,matrix1[i][2] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,4 ,matrix1[i][3] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR2,1 ,matrix1[i][4] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,2 ,matrix1[i][5] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,3 ,matrix1[i][6] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,4 ,matrix1[i][7] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR3,1 ,matrix1[i][8] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,2 ,matrix1[i][9] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,3 ,matrix1[i][10] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,4 ,matrix1[i][11] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR4,1 ,matrix1[i][12] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,2 ,matrix1[i][13] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,3 ,matrix1[i][14] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,4 ,matrix1[i][15] , BROADCAST_OFF);
		    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_RESET);//reset TR pin on FPGA for RX mode
		    HAL_GPIO_TogglePin(GPIO_LED, LED_2);
		    delay_15ns(Delay_scan_rx);
		}
	for(int i = 0; i<15; i++){

			    Adar_SetTxPhase(&ADAR1,1 ,vector_0[0] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR1,2 ,vector_0[1] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR1,3 ,vector_0[2] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR1,4 ,vector_0[3] , BROADCAST_OFF);

			    Adar_SetTxPhase(&ADAR2,1 ,vector_0[4] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR2,2 ,vector_0[5] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR2,3 ,vector_0[6] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR2,4 ,vector_0[7] , BROADCAST_OFF);

			    Adar_SetTxPhase(&ADAR3,1 ,vector_0[8] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR3,2 ,vector_0[9] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR3,3 ,vector_0[10] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR3,4 ,vector_0[11] , BROADCAST_OFF);

			    Adar_SetTxPhase(&ADAR4,1 ,vector_0[12] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR4,2 ,vector_0[13] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR4,3 ,vector_0[14] , BROADCAST_OFF);
			    Adar_SetTxPhase(&ADAR4,4 ,vector_0[15] , BROADCAST_OFF);
			    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_SET);//set TR pin on FPGA for TX mode
			    HAL_GPIO_TogglePin(GPIO_LED, LED_1);
			    delay_15ns(Delay_scan);

			    Adar_SetRxPhase(&ADAR1,1 ,vector_0[0] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR1,2 ,vector_0[1] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR1,3 ,vector_0[2] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR1,4 ,vector_0[3] , BROADCAST_OFF);

				Adar_SetRxPhase(&ADAR2,1 ,vector_0[4] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR2,2 ,vector_0[5] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR2,3 ,vector_0[6] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR2,4 ,vector_0[7] , BROADCAST_OFF);

				Adar_SetRxPhase(&ADAR3,1 ,vector_0[8] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR3,2 ,vector_0[9] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR3,3 ,vector_0[10] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR3,4 ,vector_0[11] , BROADCAST_OFF);

				Adar_SetRxPhase(&ADAR4,1 ,vector_0[12] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR4,2 ,vector_0[13] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR4,3 ,vector_0[14] , BROADCAST_OFF);
				Adar_SetRxPhase(&ADAR4,4 ,vector_0[15] , BROADCAST_OFF);
			    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_RESET);//reset TR pin on FPGA for RX mode
			    HAL_GPIO_TogglePin(GPIO_LED, LED_2);
			    delay_15ns(Delay_scan_rx);
			}

	for(int i = 0; i<21; i++){

		    Adar_SetTxPhase(&ADAR1,1 ,matrix2[i][0] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,2 ,matrix2[i][1] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,3 ,matrix2[i][2] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR1,4 ,matrix2[i][3] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR2,1 ,matrix2[i][4] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,2 ,matrix2[i][5] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,3 ,matrix2[i][6] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR2,4 ,matrix2[i][7] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR3,1 ,matrix2[i][8] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,2 ,matrix2[i][9] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,3 ,matrix2[i][10] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR3,4 ,matrix2[i][11] , BROADCAST_OFF);

		    Adar_SetTxPhase(&ADAR4,1 ,matrix2[i][12] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,2 ,matrix2[i][13] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,3 ,matrix2[i][14] , BROADCAST_OFF);
		    Adar_SetTxPhase(&ADAR4,4 ,matrix2[i][15] , BROADCAST_OFF);
		    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_SET);//set TR pin on FPGA for TX mode
		    HAL_GPIO_TogglePin(GPIO_LED, LED_1);
		    delay_15ns(Delay_scan);

		    Adar_SetRxPhase(&ADAR1,1 ,matrix2[i][0] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,2 ,matrix2[i][1] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,3 ,matrix2[i][2] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR1,4 ,matrix2[i][3] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR2,1 ,matrix2[i][4] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,2 ,matrix2[i][5] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,3 ,matrix2[i][6] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR2,4 ,matrix2[i][7] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR3,1 ,matrix2[i][8] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,2 ,matrix2[i][9] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,3 ,matrix2[i][10] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR3,4 ,matrix2[i][11] , BROADCAST_OFF);

			Adar_SetRxPhase(&ADAR4,1 ,matrix2[i][12] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,2 ,matrix2[i][13] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,3 ,matrix2[i][14] , BROADCAST_OFF);
			Adar_SetRxPhase(&ADAR4,4 ,matrix2[i][15] , BROADCAST_OFF);
		    HAL_GPIO_WritePin(GPIO_DIG, DIG_0, GPIO_PIN_RESET);//reset TR pin on FPGA for RX mode
		    HAL_GPIO_TogglePin(GPIO_LED, LED_2);
		    delay_15ns(Delay_scan_rx);
		}
	//Send commands to the auxilliary board to set motor position and get GPS data

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure LSE Drive Capability
  */
  HAL_PWR_EnableBkUpAccess();

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE3);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 4;
  RCC_OscInitStruct.PLL.PLLN = 64;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief I2C1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C1_Init(void)
{

  /* USER CODE BEGIN I2C1_Init 0 */

  /* USER CODE END I2C1_Init 0 */

  /* USER CODE BEGIN I2C1_Init 1 */

  /* USER CODE END I2C1_Init 1 */
  hi2c1.Instance = I2C1;
  hi2c1.Init.Timing = 0x00707CBB;
  hi2c1.Init.OwnAddress1 = 0;
  hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2 = 0;
  hi2c1.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c1, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Digital filter
  */
  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c1, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C1_Init 2 */

  /* USER CODE END I2C1_Init 2 */

}

/**
  * @brief SPI1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_SPI1_Init(void)
{

  /* USER CODE BEGIN SPI1_Init 0 */

  /* USER CODE END SPI1_Init 0 */

  /* USER CODE BEGIN SPI1_Init 1 */

  /* USER CODE END SPI1_Init 1 */
  /* SPI1 parameter configuration*/
  hspi1.Instance = SPI1;
  hspi1.Init.Mode = SPI_MODE_MASTER;
  hspi1.Init.Direction = SPI_DIRECTION_2LINES;
  hspi1.Init.DataSize = SPI_DATASIZE_8BIT;
  hspi1.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi1.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi1.Init.NSS = SPI_NSS_SOFT;
  hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_16;
  hspi1.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi1.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi1.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi1.Init.CRCPolynomial = 7;
  hspi1.Init.CRCLength = SPI_CRC_LENGTH_DATASIZE;
  hspi1.Init.NSSPMode = SPI_NSS_PULSE_ENABLE;
  if (HAL_SPI_Init(&hspi1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN SPI1_Init 2 */

  /* USER CODE END SPI1_Init 2 */

}

/**
  * @brief TIM1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM1_Init(void)
{

  /* USER CODE BEGIN TIM1_Init 0 */

  /* USER CODE END TIM1_Init 0 */

  TIM_ClockConfigTypeDef sClockSourceConfig = {0};
  TIM_MasterConfigTypeDef sMasterConfig = {0};

  /* USER CODE BEGIN TIM1_Init 1 */

  /* USER CODE END TIM1_Init 1 */
  htim1.Instance = TIM1;
  htim1.Init.Prescaler = 0;
  htim1.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim1.Init.Period = 65535;
  htim1.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
  htim1.Init.RepetitionCounter = 0;
  htim1.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim1) != HAL_OK)
  {
    Error_Handler();
  }
  sClockSourceConfig.ClockSource = TIM_CLOCKSOURCE_INTERNAL;
  if (HAL_TIM_ConfigClockSource(&htim1, &sClockSourceConfig) != HAL_OK)
  {
    Error_Handler();
  }
  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;
  sMasterConfig.MasterOutputTrigger2 = TIM_TRGO2_RESET;
  sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
  if (HAL_TIMEx_MasterConfigSynchronization(&htim1, &sMasterConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM1_Init 2 */

  /* USER CODE END TIM1_Init 2 */

}

/**
  * @brief USART2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART2_UART_Init(void)
{

  /* USER CODE BEGIN USART2_Init 0 */

  /* USER CODE END USART2_Init 0 */

  /* USER CODE BEGIN USART2_Init 1 */

  /* USER CODE END USART2_Init 1 */
  huart2.Instance = USART2;
  huart2.Init.BaudRate = 115200;
  huart2.Init.WordLength = UART_WORDLENGTH_8B;
  huart2.Init.StopBits = UART_STOPBITS_1;
  huart2.Init.Parity = UART_PARITY_NONE;
  huart2.Init.Mode = UART_MODE_TX_RX;
  huart2.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart2.Init.OverSampling = UART_OVERSAMPLING_16;
  huart2.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
  huart2.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
  if (HAL_UART_Init(&huart2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART2_Init 2 */

  /* USER CODE END USART2_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
/* USER CODE BEGIN MX_GPIO_Init_1 */
/* USER CODE END MX_GPIO_Init_1 */

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOD_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOC, GPIO_PIN_4|GPIO_PIN_5|GPIO_PIN_6|GPIO_PIN_7, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_14|GPIO_PIN_15|GPIO_PIN_4|GPIO_PIN_5, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOD, GPIO_PIN_10|GPIO_PIN_11|GPIO_PIN_12|GPIO_PIN_13
                          |GPIO_PIN_0|GPIO_PIN_1|GPIO_PIN_2|GPIO_PIN_3, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_8|GPIO_PIN_9|GPIO_PIN_10|GPIO_PIN_11, GPIO_PIN_RESET);

  /*Configure GPIO pins : PC4 PC5 PC6 PC7 */
  GPIO_InitStruct.Pin  = GPIO_PIN_4|GPIO_PIN_5|GPIO_PIN_6|GPIO_PIN_7;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pins : PC0 PC1 PC2 PC3 */
  GPIO_InitStruct.Pin = GPIO_PIN_0|GPIO_PIN_1|GPIO_PIN_2|GPIO_PIN_3;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pins : PB14 PB15 PB4 PB5 */
  GPIO_InitStruct.Pin = GPIO_PIN_14|GPIO_PIN_15|GPIO_PIN_4|GPIO_PIN_5;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /*Configure GPIO pins : PD10 PD11 PD12 PD13
                           PD0 PD1 PD2 PD3 */
  GPIO_InitStruct.Pin = GPIO_PIN_10|GPIO_PIN_11|GPIO_PIN_12|GPIO_PIN_13
                          |GPIO_PIN_0|GPIO_PIN_1|GPIO_PIN_2|GPIO_PIN_3;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

  /*Configure GPIO pins : PA8 PA9 PA10 PA11 */
  GPIO_InitStruct.Pin = GPIO_PIN_8|GPIO_PIN_9|GPIO_PIN_10|GPIO_PIN_11;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

/* USER CODE BEGIN MX_GPIO_Init_2 */
/* USER CODE END MX_GPIO_Init_2 */
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
