#ifndef HARDWARE_CONFIG_H

#define HARDWARE_CONFIG_H

#include "stm32f7xx_hal.h"

#define GPIO_VR GPIOB
#define EN_32 GPIO_PIN_14 //Active High
#define EN_42 GPIO_PIN_15 //Active High

#define GPIO_si5351 GPIOB
#define SI5351_CLK_EN GPIO_PIN_4 //Active Low
#define SI5351_SS_EN GPIO_PIN_5 //Active High (Spread Spectrum)

#define GPIO_ADF GPIOD
#define ADF_CS GPIO_PIN_0 //Active Low
#define ADF_CE GPIO_PIN_1 //Active High (Chip Enable)
#define ADF_DELSTR GPIO_PIN_2 //Delay Strobe/ 1=adjustment needed/ adjustment is made after GPIO_PIN_ssing from 1 to 0
#define ADF_DELADJ GPIO_PIN_3 // Delay Adjustment/ 0=ensures that delay of RF is reduced when ADF_DELSTR is asserted/ 0!=1

#define GPIO_LED GPIOD
#define LED_1 GPIO_PIN_10
#define LED_2 GPIO_PIN_11
#define LED_3 GPIO_PIN_12
#define LED_4 GPIO_PIN_13

#define GPIO_ADAR GPIOA
#define CS_ADAR_1 GPIO_PIN_8
#define CS_ADAR_2 GPIO_PIN_9
#define CS_ADAR_3 GPIO_PIN_10
#define CS_ADAR_4 GPIO_PIN_11

#define GPIO_DIG GPIOC
#define DIG_0 GPIO_PIN_0 // 0 = RX mode, 1 = TX mode
#define DIG_1 GPIO_PIN_1 // Send RX ADC start frame of (83x83) to FT2232HQ_FPGA
#define DIG_2 GPIO_PIN_2 // Enable = 1 / Disable = 0 RX mixer
#define DIG_3 GPIO_PIN_3 // Enable = 1 / Disable = 0 RX mixer
#define DIG_4 GPIO_PIN_4 //
#define DIG_5 GPIO_PIN_5
#define DIG_6 GPIO_PIN_6
#define DIG_7 GPIO_PIN_7

#endif  // HARDWARE_CONFIG_H
