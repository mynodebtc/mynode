#!/usr/local/bin/python3
from time import sleep

current_fan_speed=0

def get_temp():
    with open('/sys/class/thermal/thermal_zone0/temp') as f:
        results = f.read()
    device_temp = int(int(results) / 1000)
    print("Current temp: {}C".format(device_temp))
    return device_temp

def set_fan_speed(percent):
    global current_fan_speed

    if percent != current_fan_speed:
        print("Setting fan speed: {}%".format(percent))
        fan_speed=int(float(percent) * 2.55)
        current_fan_speed = percent
        with open('/sys/class/hwmon/hwmon0/pwm1', 'w') as f:
            f.write("{}".format(fan_speed))

    
def calculate_fan_setting(temp):
    if temp <= 50:
        set_fan_speed(0)
    elif temp >= 65 and temp < 70:
        set_fan_speed(30)
    elif temp >= 70 and temp < 75:
        set_fan_speed(60)
    elif temp >= 75:
        set_fan_speed(100)

def main_loop():
    # On start run fan for a bit
    try:
        set_fan_speed(60)
        sleep(20)
        set_fan_speed(0)
    except:
        pass

    while True:
        try:
            temp = get_temp()
            calculate_fan_setting(temp)
        except Exception as e:
            print("Exception: {}".format(str(e)))
            set_fan_speed(80)
        finally:
            sleep(10)

# This is the main entry point for the program
if __name__ == "__main__":
    main_loop()