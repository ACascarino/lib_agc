// Copyright (c) 2016-2017, XMOS Ltd, All rights reserved

#include <platform.h>
#include <xs1.h>
#include <xclib.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <print.h>
#include <xscope.h>
#include <math.h>
#include "agc.h"
#include "output.h"

#define AGC_WINDOW_LENGTH 512

int sineWave[16] = {
    8432740,
    829553294,
    1524381879,
    1987137141,
    2147368787,
    1980683001,
    1512456183,
    813971621,
    -8432740,
    -829553294,
    -1524381879,
    -1987137141,
    -2147368787,
    -1980683001,
    -1512456183,
    -813971621,
};

int32_t compare_data[AGC_WINDOW_LENGTH];
int32_t input_data[AGC_WINDOW_LENGTH];

static void prepare_compare_data() {
    for(int i =0 ; i < AGC_WINDOW_LENGTH; i++) {
        compare_data[i] = 0 ? i & 0 ? 0x80000000 : 0x7fffffff : sineWave[i&15];
    }
}

static void prepare_input_data() {
    for(int i =0 ; i < AGC_WINDOW_LENGTH; i++) {
        input_data[i] = compare_data[i];
    }
}

static double dBSignal(int32_t x, int32_t ref) {
    return log(x/(float)0x7fffffff)/log(10.0)*20.0;    // *8.6858896381
}

static void down_test() {
    agc_state_t a;
    int errors = 0;
    const int start_signal = 0;
    const int desired_energy = -20;
    int cliptest = 0;
    agc_init_state(a, start_signal, desired_energy, AGC_WINDOW_LENGTH, 0, 0);
    agc_set_wait_for_up_ms(a, 100);

    const int down_rate = -128;
    agc_set_rate_down_dbps(a, down_rate);
    agc_set_rate_up_dbps(a, 64);

    for(int i = 0; i < 10; i++) {
        prepare_input_data();
        agc_block(a, input_data, 0, null, null);
        double signal = dBSignal(input_data[4], 0x7fffffff);
        double desired_signal = start_signal + i*AGC_WINDOW_LENGTH/16000.0 * down_rate;
        if (desired_signal < desired_energy + 3) {
            desired_signal = desired_energy + 3;
            cliptest = 1;
        }
        if (fabs(desired_signal - signal) > 0.05) {
            printf("Error down_test: Signal level %f not %f\n", signal, desired_signal);
            errors++;
        }
        output_block((input_data, unsigned char[]), AGC_WINDOW_LENGTH * 4);
    }

    agc_set_gain_min_db(a, -3);
    agc_set_desired_db(a, desired_energy - 10);
    prepare_input_data();
    agc_block(a, input_data, 0, null, null);
    double signal = dBSignal(input_data[4], 0x7fffffff);
    double desired_signal = start_signal - 3;
    if (fabs(desired_signal - signal) > 0.05) {
        printf("Error down_test - gain_min: Signal level %f not %f\n", signal, desired_signal);
        errors++;
    }
    output_block((input_data, unsigned char[]), AGC_WINDOW_LENGTH * 4);

    if (!cliptest) {
        printf("down_test: missed out on clipping\n");
        errors++;
    }
    if (errors == 0) {
        printf("Down test passed\n");
    }
}

static void up_test() {
    agc_state_t a;
    const int start_signal = 0;
    const int desired_energy = -20;
    for(int start_delay_frames = 2; start_delay_frames < 16; start_delay_frames*=2) {
        int errors = 0;
        int cliptest = 0;
        agc_init_state(a, start_signal, desired_energy, AGC_WINDOW_LENGTH, 0, 0);
        int msdelay = start_delay_frames * AGC_WINDOW_LENGTH/16;
        agc_set_wait_for_up_ms(a, msdelay);

        const int up_rate = 64;
        agc_set_rate_down_dbps(a, -128);
        agc_set_rate_up_dbps(a, up_rate);

        for(int i = 0; i < 5+start_delay_frames; i++) {
            prepare_input_data();
            agc_block(a, input_data, 4, null, null);
            double signal = dBSignal(input_data[4], 0x7fffffff);
            double desired_signal = start_signal - 24.0823996531;
            if (i > start_delay_frames) {
                desired_signal += (i-start_delay_frames)*AGC_WINDOW_LENGTH/16000.0 * up_rate;
            }
            if (desired_signal > desired_energy + 3) {
                desired_signal = desired_energy + 3;
                cliptest = 1;
            }
            if (fabs(desired_signal - signal) > 0.05) {
                printf("Error up_test: Signal level %f not %f\n", signal, desired_signal);
                errors++;
            }
            output_block((input_data, unsigned char[]), AGC_WINDOW_LENGTH * 4);
        }

        agc_set_gain_max_db(a, -30);
        agc_set_desired_db(a, desired_energy + 10);
        prepare_input_data();
        agc_block(a, input_data, 0, null, null);
        double signal = dBSignal(input_data[4], 0x7fffffff);
        double desired_signal = start_signal - 30;
        if (fabs(desired_signal - signal) > 0.05) {
            printf("Error up_test - gain_min: Signal level %f not %f\n", signal, desired_signal);
            errors++;
        }
        output_block((input_data, unsigned char[]), AGC_WINDOW_LENGTH * 4);

        if (!cliptest) {
            printf("up_test(%d ms): missed out on clipping\n", msdelay);
            errors++;
        }
        if (errors == 0) {
            printf("Up test passed for msdelay %d\n", msdelay);
        }
    }
}

int main(void) {
    prepare_compare_data();
    output_init();

    down_test();
    up_test();

    return 0;
}
