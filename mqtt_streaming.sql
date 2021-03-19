open schema retail;

--/
CREATE or replace PYTHON3 SCALAR SCRIPT "STREAMTEST" ("DB_CONNECTION" VARCHAR(2000) UTF8, "MQTT_CONNECTION" VARCHAR(2000000)) EMITS (MESSAGE VARCHAR(2000000)) AS

'''
This SQL is meant to be part of a tutorial.
name: mqtt_streaming.sql
desc: Create and run the STREAMTEST script
      to demonstrate cool things with exasol
      like using BucketFS to hold python modules,
      connecting to the database using python,
      extracting hidden credentials, and
      streaming data
'''

import glob
import sys
'''
# We do the syspath first, 
so python can see the import pyexasol
'''
sys.path.extend(glob.glob('/buckets/bucketfs1/jars/*'))
import pyexasol
from paho.mqtt import client as mqtt
#======================================
# Variables
#======================================
metric_cpu = float(0.0)
metric_swap = float(0.0)
information_level = "Informational"
warning_cpu = int(88)
critical_cpu = int(99)
#======================================
def send_message(mqtt_user, mqtt_password, information_level, my_message):
#======================================
    client = mqtt.Client()
    client.username_pw_set(username=mqtt_user,password=mqtt_password)
    client.connect("96.80.44.170",8883,60)
    client.publish( ("myTopic/To/" + information_level), my_message);
    client.disconnect();

#======================================
def prep_message(metric_cpu, metric_swap):
#======================================
    if float(metric_cpu) > critical_cpu:
        information_level = "Critical"
    elif float(metric_cpu) > warning_cpu:
        information_level = "Warning"
    else:
        information_level = "Informational"
    if float(metric_swap) > 0:
        information_level = "Critical"
    my_message = ('{"message":"' + str(information_level) + '","cpu":"' + str(metric_cpu) + '"swap":"' + str(metric_swap) + '"}')
    return information_level, my_message
    
#======================================
def run(ctx):
#======================================
    c = pyexasol.connect(dsn=exa.get_connection(ctx.DB_CONNECTION).address,
         user=exa.get_connection(ctx.DB_CONNECTION).user,
         password=exa.get_connection(ctx.DB_CONNECTION).password)
    metrics_stmt = c.execute("select cpu_max , swap_max from exa_monitor_hourly where interval_start = (select max(interval_start) from exa_monitor_hourly);")
    metrics_val = metrics_stmt.fetchall()
    for row in metrics_val:
        metric_cpu = row[0]
        assert float(metric_cpu) >= 0.0, ctx.emit("cpu_max not read from query")
        metric_swap = row[1]
        assert float(metric_swap) >= 0.0, ctx.emit("swap_max not read from query")
        #ctx.emit(metric_cpu + " " + metric_swap);
        mqtt_user = exa.get_connection(ctx.MQTT_CONNECTION).user
        mqtt_password = exa.get_connection(ctx.MQTT_CONNECTION).password
        #DEBUG ctx.emit(mqtt_user + " " + mqtt_password)
        my_info_level, my_message = prep_message(metric_cpu, metric_swap)
        send_message(mqtt_user, mqtt_password, my_info_level, my_message)
    c.close()
/
select STREAMTEST('exasol_conn', 'mqtt_conn');
