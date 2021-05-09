#!/bin/bash
set +e

source activate rapids

BROKER="localhost:9092"
GROUP_ID="streamz"
ENV_TEST_SCRIPT="/python/check_env.py"
INPUT_TOPIC="input"
OUTPUT_TOPIC="output"

#If sample data filepath is not passed as a parameter, use sample.csv data.
if [ -n "$1" ]; then
  SAMPLE_DATA=$1
else
  SAMPLE_DATA="/data/sample.csv"
fi

# Start Zookeeper
$KAFKA_HOME/bin/zookeeper-server-start.sh -daemon $KAFKA_HOME/config/zookeeper.properties
sleep 3

# Configure Kafka
sed -i '/#listeners=PLAINTEXT:\/\/:9092/c\listeners=PLAINTEXT:\/\/localhost:9092' $KAFKA_HOME/config/server.properties
sed -i '/#advertised.listeners=PLAINTEXT:\/\/your.host.name:9092/c\advertised.listeners=PLAINTEXT:\/\/localhost:9092' $KAFKA_HOME/config/server.properties

# Run Kafka
$KAFKA_HOME/bin/kafka-server-start.sh -daemon $KAFKA_HOME/config/server.properties
sleep 3

# Create kafka topic
$KAFKA_HOME/bin/kafka-topics.sh --create --bootstrap-server $BROKER --replication-factor 1 --partitions 1 --topic $INPUT_TOPIC
$KAFKA_HOME/bin/kafka-topics.sh --create --bootstrap-server $BROKER --replication-factor 1 --partitions 1 --topic $OUTPUT_TOPIC

# Read sample data into the kafka topic
$KAFKA_HOME/bin/kafka-console-producer.sh --broker-list $BROKER --topic $INPUT_TOPIC < $SAMPLE_DATA

# Check the environment.
python $ENV_TEST_SCRIPT

# Run cybert
python -i /python/cybert.py --broker $BROKER --input_topic $INPUT_TOPIC --group_id $GROUP_ID
